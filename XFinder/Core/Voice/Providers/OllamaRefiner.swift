import Foundation

/// Refiner backed by a local Ollama daemon.
///
/// Ollama is the only tier that is free, offline and model-agnostic, which makes it the best
/// default for a user who does not want to send their dictation anywhere. Two endpoints are
/// used: `/api/chat` to rewrite, and `/api/tags` to list the models already pulled so the
/// settings page can offer a picker instead of asking the user to remember a tag.
///
/// Nothing here assumes the daemon is running. `isAvailable()` is a real probe, and the page
/// shows the connection result rather than a switch that appears on and does nothing.
public final class OllamaRefiner: TranscriptRefiner, @unchecked Sendable {
    public let id = "ollama"

    private let baseURL: String
    private let model: String
    private let session: URLSession

    public init(baseURL: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "http://localhost:11434"
            : baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model

        let configuration = URLSessionConfiguration.ephemeral
        // A local model can take a while to load the first time; that is a warm-up cost,
        // not a hang, so the timeout is generous. The request itself is cancellable.
        configuration.timeoutIntervalForRequest = 120
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func isAvailable() async -> Bool {
        guard !model.isEmpty else { return false }
        return await listModels() != nil
    }

    public func refine(_ request: RefineRequest) async throws -> String {
        guard !model.isEmpty else { throw RefinerError.notConfigured }
        guard let urlRequest = RefinerRequestBuilder.ollamaRequest(
            baseURL: baseURL,
            model: model,
            messages: request.messages
        ) else {
            throw RefinerError.notConfigured
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw RefinerError.badResponse }
            guard (200...299).contains(http.statusCode) else {
                let detail = RefinerResponseParser.errorMessage(from: data)
                    ?? String(data: data, encoding: .utf8)
                    ?? ""
                throw RefinerError.http(http.statusCode, detail)
            }
            guard let text = RefinerResponseParser.ollamaText(from: data) else {
                throw RefinerError.badResponse
            }
            return text
        } catch let error as RefinerError {
            throw error
        } catch is CancellationError {
            throw RefinerError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw RefinerError.cancelled
        } catch {
            throw RefinerError.transport(error.localizedDescription)
        }
    }

    /// The models the user has already pulled. `nil` means "could not reach the daemon",
    /// which is a different statement from "the daemon is running and has no models".
    public func listModels() async -> [String]? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tags") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return RefinerResponseParser.ollamaModelNames(from: data)
        } catch {
            return nil
        }
    }
}
