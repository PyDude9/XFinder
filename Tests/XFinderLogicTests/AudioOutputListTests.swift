import XCTest
import AppKit
import Foundation

final class AudioOutputListTests: XCTestCase {

    private func dev(_ id: UInt32, _ name: String, uid: String? = nil, out: Int = 2,
                     hidden: Bool = false, alive: Bool = true, transport: String = "bltn") -> RawAudioDevice {
        RawAudioDevice(id: id, uid: uid ?? "uid-\(id)", name: name, outputChannels: out,
                       isHidden: hidden, isAlive: alive, transport: transport)
    }

    // MARK: - What may appear

    /// The exact shape measured on this Mac: three devices, only one of them an output. The two
    /// microphones (one a Continuity "Wifi Microphone") must not be offered as somewhere to play sound.
    func testMeasuredMachineShapeOffersOnlyTheSpeakers() {
        let raw = [
            dev(83, "Gomu Gomu No Wifi Microphone", out: 0, transport: "ccwd"),
            dev(78, "MacBook Pro Microphone", out: 0, transport: "bltn"),
            dev(71, "MacBook Pro Speakers", out: 2, transport: "bltn"),
        ]
        let list = AudioOutputList.build(from: raw)
        XCTAssertEqual(list.map(\.name), ["MacBook Pro Speakers"])
        XCTAssertEqual(list.first?.id, 71)
    }

    func testHiddenDeadAndNamelessDevicesAreNotChoices() {
        let raw = [
            dev(1, "Real", out: 2),
            dev(2, "Hidden aggregate", out: 2, hidden: true),
            dev(3, "Unplugged but still listed", out: 2, alive: false),
            dev(4, "   ", out: 2),
            dev(5, "", out: 2),
        ]
        XCTAssertEqual(AudioOutputList.build(from: raw).map(\.id), [1])
    }

    func testADeviceListedTwiceAppearsOnceByUID() {
        let raw = [dev(10, "Speakers", uid: "same"), dev(11, "Speakers", uid: "same")]
        let list = AudioOutputList.build(from: raw)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, 10, "the first one wins; identity is the UID")
    }

    func testVirtualAndAggregateOutputsAreKept() {
        // Multi-Output / BlackHole / Loopback devices are legitimate choices for the people who made them.
        let raw = [dev(1, "BlackHole 2ch", transport: "virt"), dev(2, "Multi-Output Device", transport: "grup")]
        XCTAssertEqual(AudioOutputList.build(from: raw).count, 2)
    }

    // MARK: - Order

    func testOrderIsAlphabeticalCaseInsensitiveAndStable() {
        let raw = [dev(3, "zeta"), dev(1, "Alpha"), dev(2, "beta"), dev(9, "Beta", uid: "b2")]
        let names = AudioOutputList.build(from: raw).map(\.name)
        XCTAssertEqual(names, ["Alpha", "beta", "Beta", "zeta"], "case-insensitive; equal names ordered by id")
        // Stable under reshuffling of the input — the list must not jump when the selection changes.
        XCTAssertEqual(AudioOutputList.build(from: raw.reversed()).map(\.name), names)
    }

    // MARK: - Icons

    func testEveryTransportMapsToASymbolThatReallyExists() {
        let transports = ["bltn", "blue", "bleL", "usb", "hdmi", "dprt", "airp", "virt", "grup", "", "weird"]
        for t in transports {
            let name = AudioOutputList.symbol(forTransport: t)
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "SF Symbol '\(name)' for transport '\(t)' does not exist — Image(systemName:) fails silently")
            XCTAssertTrue(AudioOutputList.allSymbols.contains(name), "'\(name)' is not in allSymbols")
        }
        for name in AudioOutputList.allSymbols {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "allSymbols has a bad name: \(name)")
        }
        XCTAssertGreaterThanOrEqual(AudioOutputList.allSymbols.count, 8)
    }

    func testFourCharacterTransportCodesWithTrailingSpaceAreRecognised() {
        // CoreAudio's USB code is 'usb ' (with a space); a naive compare would miss it.
        XCTAssertEqual(AudioOutputList.symbol(forTransport: "usb "), "cable.connector")
        XCTAssertEqual(AudioOutputList.symbol(forTransport: "usb"), "cable.connector")
    }

    // MARK: - Which defaults move

    func testSystemOutputFollowsOnlyWhenTheUserLeftItUnified() {
        XCTAssertTrue(AudioOutputList.shouldMoveSystemOutput(previousDefault: 71, previousSystem: 71),
                      "unified ⇒ move both, or the alert beeps from the old speaker")
        XCTAssertFalse(AudioOutputList.shouldMoveSystemOutput(previousDefault: 71, previousSystem: 55),
                       "a deliberately split alert device is a choice the switcher must not undo")
    }
}
