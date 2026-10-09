import Foundation

/// Which key starts a dictation session.
///
/// The default is **Right Option** because it is a modifier that produces no character of
/// its own, sits under the right thumb, and is the key RayMate and Whisper-style dictation
/// tools converge on. Left Option is offered separately because the two are distinct
/// keycodes (58 / 61) and a user may want one for dictation and one for their own use.
///
/// `fn`/Globe is offered but flagged: on some keyboards it is not delivered as a normal
/// keycode, so the page states that instead of silently doing nothing.
public enum VoiceTriggerKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case rightOption
    case leftOption
    case rightCommand
    case fnGlobe

    public var id: String { rawValue }

    /// Hardware keycode delivered in `CGEvent.keyboardEventKeycode`.
    public var keyCode: Int64 {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .fnGlobe: return 63
        }
    }

    /// The modifier bit that must be present in `CGEvent.flags` for the key to count as
    /// "held". Read from the event rather than inferred from the keycode alone, because a
    /// flagsChanged event carries the *resulting* flag state.
    public var modifierMask: UInt64 {
        switch self {
        case .rightOption, .leftOption: return 0x80000   // .maskAlternate
        case .rightCommand: return 0x100000              // .maskCommand
        case .fnGlobe: return 0x800000                   // .maskSecondaryFn
        }
    }

    public var labelKey: String {
        switch self {
        case .rightOption: return "Option Phải (⌥)"
        case .leftOption: return "Option Trái (⌥)"
        case .rightCommand: return "Command Phải (⌘)"
        case .fnGlobe: return "Phím Fn / Globe"
        }
    }

    public var hintKey: String? {
        switch self {
        case .fnGlobe: return "Một số bàn phím không gửi phím Fn dưới dạng mã phím thường — nếu giữ mà không thấy gì, hãy chọn Option Phải."
        default: return nil
        }
    }
}

/// Hold-to-talk or press-to-start/press-to-stop.
///
/// Hold is the default because it makes "am I recording?" unambiguous — the key is down or
/// it is not. Toggle exists for long dictation, where holding a key for a minute is painful.
public enum VoiceActivationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case hold
    case toggle

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .hold: return "Giữ để nói"
        case .toggle: return "Bấm bật / bấm tắt"
        }
    }

    public var detailKey: String {
        switch self {
        case .hold: return "Giữ phím để nói, thả ra là chèn văn bản."
        case .toggle: return "Bấm một lần để bắt đầu, bấm lần nữa để kết thúc — tiện cho đoạn dài."
        }
    }
}

/// Where the floating HUD appears. Both are offered because they suit different setups:
/// the caret anchor follows the text you are writing, the notch anchor stays in one place
/// and never covers the document.
public enum VoiceHUDAnchor: String, CaseIterable, Identifiable, Codable, Sendable {
    case caret
    case notch

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .caret: return "Cạnh con trỏ"
        case .notch: return "Mép trên màn hình"
        }
    }

    public var detailKey: String {
        switch self {
        case .caret: return "Nổi ngay cạnh vị trí bạn đang gõ."
        case .notch: return "Neo ở mép trên, không che tài liệu."
        }
    }
}

/// The model tier used to rewrite the transcription. Ordered the way the page presents
/// them: fully on-device first, then local, then bring-your-own-key.
public enum VoiceRefinerTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleOnDevice
    case ollama
    case customAPI
    case subscription

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .appleOnDevice: return "Apple Intelligence (trên máy)"
        case .ollama: return "Ollama (chạy trên máy)"
        case .customAPI: return "API riêng (dùng khoá của bạn)"
        case .subscription: return "Tài khoản ChatGPT / Claude"
        }
    }

    public var detailKey: String {
        switch self {
        case .appleOnDevice: return "Chạy hoàn toàn trên máy, miễn phí, không cần mạng."
        case .ollama: return "Kết nối tới Ollama tại localhost:11434."
        case .customAPI: return "OpenAI, Groq, Anthropic, Gemini, OpenRouter, DeepSeek hoặc một địa chỉ riêng."
        case .subscription: return "Chưa hỗ trợ đăng nhập trực tiếp — xem giải thích bên dưới."
        }
    }

    public var icon: String {
        switch self {
        case .appleOnDevice: return "apple.logo"
        case .ollama: return "desktopcomputer"
        case .customAPI: return "key.horizontal"
        case .subscription: return "person.crop.circle.badge.exclamationmark"
        }
    }
}
