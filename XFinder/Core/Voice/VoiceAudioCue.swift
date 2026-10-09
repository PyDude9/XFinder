import AppKit

/// Optional, very quiet confirmation sounds.
///
/// Dictation is used without looking at the screen, so a sound is the only feedback that
/// arrives when the user's eyes are elsewhere. It is off by default: a system-wide feature
/// that beeps on every session is a feature people turn off.
///
/// `NSSound(named:)` returns nil when the user's system has the sound removed, so every call
/// is optional-chained — a missing sound must never be an error path.
public enum VoiceAudioCue {
    public static func start() { play("Tink") }
    public static func done() { play("Pop") }
    public static func failed() { play("Basso") }

    private static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
