import Foundation
import XCTest

@MainActor
final class NotchLocalChatTests: XCTestCase {

    // MARK: - Deterministic Fake Engine (never invokes FoundationModels)

    @MainActor
    private final class FakeLocalChatEngine: LocalChatEngine {
        var availability: NotchLocalChatRules.Availability = .available
        private(set) var availabilityCheckCount = 0
        private(set) var respondCalls: [(prompt: String, instructions: String)] = []
        private(set) var resetSessionCount = 0

        var responder: ((String, String) async throws -> String)?

        func checkAvailability() -> NotchLocalChatRules.Availability {
            availabilityCheckCount += 1
            return availability
        }

        func respond(to prompt: String, instructions: String) async throws -> String {
            respondCalls.append((prompt, instructions))
            if let responder {
                return try await responder(prompt, instructions)
            }
            return "Echo: \(prompt)"
        }

        func resetSession() {
            resetSessionCount += 1
        }
    }

    // MARK: - Tests

    func testInitNeverChecksAvailabilityOrInvokesModel() {
        let engine = FakeLocalChatEngine()
        let model = NotchLocalChatModel(engine: engine)

        XCTAssertEqual(model.availability, .unchecked)
        XCTAssertEqual(engine.availabilityCheckCount, 0)
        XCTAssertTrue(engine.respondCalls.isEmpty)
        XCTAssertEqual(model.sendBlockReason, .availabilityUnchecked)
    }

    func testDistinctUnavailableReasonsAndRetryRecovery() {
        let engine = FakeLocalChatEngine()
        let model = NotchLocalChatModel(engine: engine)
        model.draft = "Hello"

        let reasons: [NotchLocalChatRules.UnavailableReason] = [
            .unsupportedOS,
            .deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .sdkUnavailable,
            .unknown,
        ]

        for reason in reasons {
            engine.availability = .unavailable(reason)
            model.checkAvailability()
            XCTAssertEqual(model.availability, .unavailable(reason))
            XCTAssertEqual(model.sendBlockReason, .unavailable(reason))
            XCTAssertFalse(model.sendPrompt())
        }

        XCTAssertTrue(engine.respondCalls.isEmpty)

        // Retry after user enables Apple Intelligence
        engine.availability = .available
        model.retryAvailability()
        XCTAssertEqual(model.availability, .available)
        XCTAssertNil(model.sendBlockReason)
    }

    func testEmptyAndOverLimitPromptsBlocked() {
        let engine = FakeLocalChatEngine()
        let model = NotchLocalChatModel(engine: engine, maxPromptCharacters: 10, maxContextCharacters: 100)
        model.checkAvailability()

        model.draft = "   \n\t  "
        XCTAssertEqual(model.sendBlockReason, .emptyPrompt)
        XCTAssertFalse(model.sendPrompt())

        model.draft = String(repeating: "a", count: 11)
        XCTAssertEqual(model.sendBlockReason, .promptTooLong(count: 11, limit: 10))
        XCTAssertFalse(model.sendPrompt())
        XCTAssertTrue(engine.respondCalls.isEmpty)
    }

    func testContextLimitBlocksAndResetClearsIt() async {
        let engine = FakeLocalChatEngine()
        let model = NotchLocalChatModel(engine: engine, maxPromptCharacters: 50, maxContextCharacters: 25)
        model.checkAvailability()

        model.draft = "1234567890" // 10 chars; reply "Echo: 1234567890" = 16 chars -> total 26 > 25
        XCTAssertTrue(model.sendPrompt())
        await waitUntil { !model.isGenerating }

        XCTAssertEqual(model.messages.count, 2)
        model.draft = "hi"
        XCTAssertEqual(model.sendBlockReason, .contextLimitReached)
        XCTAssertFalse(model.sendPrompt())

        model.resetConversation()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(engine.resetSessionCount, 1)
        XCTAssertNil(model.sendBlockReason)
    }

    func testNormalMultiTurnAndDoubleSendRejected() async {
        let engine = FakeLocalChatEngine()
        var pendingContinuation: CheckedContinuation<String, Error>?
        engine.responder = { _, _ in
            try await withCheckedThrowingContinuation { cont in
                pendingContinuation = cont
            }
        }

        let model = NotchLocalChatModel(engine: engine)
        model.checkAvailability()

        model.draft = "First question"
        XCTAssertTrue(model.sendPrompt())
        XCTAssertTrue(model.isGenerating)
        XCTAssertEqual(model.draft, "")
        XCTAssertEqual(model.messages.count, 1)

        // Rapid second send while still generating must be blocked.
        model.draft = "Second question"
        XCTAssertEqual(model.sendBlockReason, .generating)
        XCTAssertFalse(model.sendPrompt())

        await waitUntil { pendingContinuation != nil }
        XCTAssertEqual(engine.respondCalls.count, 1)
        pendingContinuation?.resume(returning: "First answer")
        await waitUntil { !model.isGenerating }

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[0].role, .user)
        XCTAssertEqual(model.messages[0].text, "First question")
        XCTAssertEqual(model.messages[1].role, .assistant)
        XCTAssertEqual(model.messages[1].text, "First answer")
        XCTAssertNil(model.lastError)
    }

    func testStopDiscardsLateReply() async {
        let engine = FakeLocalChatEngine()
        var pendingContinuation: CheckedContinuation<String, Error>?
        engine.responder = { _, _ in
            try await withCheckedThrowingContinuation { cont in
                pendingContinuation = cont
            }
        }

        let model = NotchLocalChatModel(engine: engine)
        model.checkAvailability()
        model.draft = "Slow prompt"
        XCTAssertTrue(model.sendPrompt())

        await waitUntil { pendingContinuation != nil }
        model.stopGeneration()
        XCTAssertFalse(model.isGenerating)

        // Late response arrives after Stop: must be ignored.
        pendingContinuation?.resume(returning: "Late stale reply")
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(model.messages.count, 1)
        XCTAssertNil(model.lastError)
    }

    func testResetDuringGenerationDiscardsLateReplyAndError() async {
        let engine = FakeLocalChatEngine()
        var pendingContinuation: CheckedContinuation<String, Error>?
        engine.responder = { _, _ in
            try await withCheckedThrowingContinuation { cont in
                pendingContinuation = cont
            }
        }

        let model = NotchLocalChatModel(engine: engine)
        model.checkAvailability()
        model.draft = "Old conversation"
        XCTAssertTrue(model.sendPrompt())

        await waitUntil { pendingContinuation != nil }
        model.resetConversation()

        XCTAssertFalse(model.isGenerating)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(engine.resetSessionCount, 1)

        // Late error arrives from old epoch: must not surface in fresh conversation.
        pendingContinuation?.resume(throwing: NotchLocalChatRules.ChatError.refused)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNil(model.lastError)
    }

    func testTabDisableAndShutdownCancelWithoutDroppingHistoryOnDisable() async {
        let engine = FakeLocalChatEngine()
        var pendingContinuation: CheckedContinuation<String, Error>?
        engine.responder = { _, _ in
            try await withCheckedThrowingContinuation { cont in
                pendingContinuation = cont
            }
        }

        let model = NotchLocalChatModel(engine: engine)
        model.checkAvailability()
        model.draft = "Question before disabling tab"
        XCTAssertTrue(model.sendPrompt())

        await waitUntil { pendingContinuation != nil }
        model.handleTabDisabled()
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.messages.count, 1)

        pendingContinuation?.resume(returning: "Late after tab disabled")
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(model.messages.count, 1)

        // Shutdown resets underlying adapter session cleanly.
        model.shutdown()
        XCTAssertEqual(engine.resetSessionCount, 1)
    }

    func testRefusalGuardrailContextWindowAndAssetsUnavailableErrors() async {
        let engine = FakeLocalChatEngine()
        let model = NotchLocalChatModel(engine: engine)
        model.checkAvailability()

        // Refusal
        engine.responder = { _, _ in throw NotchLocalChatRules.ChatError.refused }
        model.draft = "refuse me"
        XCTAssertTrue(model.sendPrompt())
        await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.lastError, .refused)

        // Guardrail violation
        engine.responder = { _, _ in throw NotchLocalChatRules.ChatError.guardrailViolation }
        model.draft = "guardrail"
        XCTAssertTrue(model.sendPrompt())
        await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.lastError, .guardrailViolation)

        // Context window exceeded -> blocks further sends until New Conversation
        engine.responder = { _, _ in throw NotchLocalChatRules.ChatError.contextWindowExceeded }
        model.draft = "overflow"
        XCTAssertTrue(model.sendPrompt())
        await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.lastError, .contextWindowExceeded)
        XCTAssertTrue(model.isContextWindowFull)
        model.draft = "another"
        XCTAssertEqual(model.sendBlockReason, .contextLimitReached)

        model.resetConversation()
        XCTAssertFalse(model.isContextWindowFull)

        // Assets unavailable -> marks availability as .modelNotReady
        engine.responder = { _, _ in throw NotchLocalChatRules.ChatError.assetsUnavailable }
        model.draft = "assets gone"
        XCTAssertTrue(model.sendPrompt())
        await waitUntil { !model.isGenerating }
        XCTAssertEqual(model.lastError, .assetsUnavailable)
        XCTAssertEqual(model.availability, .unavailable(.modelNotReady))
    }

    // MARK: - Async Wait Helper

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                XCTFail("Timed out waiting for condition")
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
