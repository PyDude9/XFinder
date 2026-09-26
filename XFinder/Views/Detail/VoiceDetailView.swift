import SwiftUI
import Speech
import AVFoundation

/// Voice to Typing settings and live testing page in flat System-Settings style.
struct VoiceDetailView: View {
    @State private var voiceManager = VoiceManager.shared
    @State private var isTesting = false
    @State private var testRMS: Float = 0.0
    @State private var testText: String = ""

    @AppStorage("voice.enabled") private var voiceEnabled = true
    @AppStorage("voice.language") private var voiceLanguage = "vi-VN"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    icon: "mic.fill",
                    title: L10n.t("Nhập bằng giọng nói"),
                    subtitle: L10n.t("Giữ Option Phải để nói và tự động chèn chữ vào ứng dụng đang dùng.")
                )

                Divider()

                // Section 1: Activation & Hotkey
                SectionHeader(
                    icon: "keyboard",
                    title: L10n.t("Kích hoạt & Phím tắt"),
                    subtitle: L10n.t("Thiết lập phím tắt giữ để nói toàn hệ thống.")
                )

                VStack(spacing: 0) {
                    ToggleRow(
                        title: L10n.t("Bật nhập bằng giọng nói"),
                        subtitle: L10n.t("Giữ phím tắt để nói, thả phím để chèn văn bản."),
                        isOn: Binding(
                            get: { voiceEnabled },
                            set: {
                                voiceEnabled = $0
                                voiceManager.isEnabled = $0
                            }
                        )
                    )

                    Divider().padding(.vertical, 8)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Phím tắt kích hoạt"))
                                .font(.system(size: 13, weight: .medium))
                            Text(L10n.t("Phân biệt Option Phải và Option Trái"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Right Option (⌥)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Divider().padding(.vertical, 8)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Ngôn ngữ nhận dạng"))
                                .font(.system(size: 13, weight: .medium))
                            Text(L10n.t("Mô hình Apple Speech Recognizer tích hợp"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { voiceLanguage },
                            set: {
                                voiceLanguage = $0
                                voiceManager.selectedLanguage = $0
                            }
                        )) {
                            Text(L10n.t("Tiếng Việt (vi-VN)")).tag("vi-VN")
                            Text("English (en-US)").tag("en-US")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                .padding(.horizontal, 20)

                Divider()

                // Section 2: Permissions
                SectionHeader(
                    icon: "lock.shield",
                    title: L10n.t("Quyền hệ thống"),
                    subtitle: L10n.t("Yêu cầu Trợ năng, Micro và Nhận dạng giọng nói.")
                )

                VStack(spacing: 8) {
                    StatusChecklistRow(
                        state: WindowManager.isTrusted ? .ok : .warning,
                        title: L10n.t("Quyền Trợ năng (Accessibility)"),
                        status: WindowManager.isTrusted ? L10n.t("Đã cấp") : L10n.t("Cần cấp quyền"),
                        actionTitle: WindowManager.isTrusted ? nil : L10n.t("Cấp quyền"),
                        action: {
                            WindowManager.requestAccessibilityTrust()
                        }
                    )

                    StatusChecklistRow(
                        state: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .ok : .warning,
                        title: L10n.t("Quyền Micro (Microphone)"),
                        status: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? L10n.t("Đã cấp") : L10n.t("Cần cấp quyền"),
                        actionTitle: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? nil : L10n.t("Yêu cầu"),
                        action: {
                            Task {
                                _ = await voiceManager.checkAndRequestPermissions()
                            }
                        }
                    )

                    StatusChecklistRow(
                        state: SFSpeechRecognizer.authorizationStatus() == .authorized ? .ok : .warning,
                        title: L10n.t("Quyền Nhận dạng giọng nói"),
                        status: SFSpeechRecognizer.authorizationStatus() == .authorized ? L10n.t("Đã cấp") : L10n.t("Cần cấp quyền"),
                        actionTitle: SFSpeechRecognizer.authorizationStatus() == .authorized ? nil : L10n.t("Yêu cầu"),
                        action: {
                            Task {
                                _ = await voiceManager.checkAndRequestPermissions()
                            }
                        }
                    )
                }
                .padding(.horizontal, 20)

                Divider()

                // Section 3: Live Test & Microphone Monitor
                SectionHeader(
                    icon: "waveform",
                    title: L10n.t("Thử nghiệm trực tiếp"),
                    subtitle: L10n.t("Kiểm tra mức âm lượng micro và văn bản nhận dạng.")
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button(action: {
                            toggleTest()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isTesting ? "stop.fill" : "mic.fill")
                                    .foregroundColor(isTesting ? .red : .blue)
                                Text(isTesting ? L10n.t("Dừng thử nghiệm") : L10n.t("Thử micro & nhận dạng"))
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if isTesting {
                            // Sound level bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.12))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [.blue, .green, .red], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(4, geo.size.width * CGFloat(testRMS)))
                                }
                            }
                            .frame(height: 12)
                            .frame(maxWidth: 160)
                        }
                    }

                    if !testText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("Kết quả nhận dạng:"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(testText)
                                .font(.system(size: 13, weight: .medium))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .onDisappear {
            if isTesting {
                toggleTest()
            }
        }
    }

    private func toggleTest() {
        if isTesting {
            isTesting = false
            _ = AudioCapture.shared.stop()
        } else {
            isTesting = true
            testText = ""
            AudioCapture.shared.onRMSUpdate = { db, norm in
                Task { @MainActor in
                    self.testRMS = norm
                }
            }
            do {
                try AudioCapture.shared.start()
            } catch {
                testText = L10n.t("Không mở được Micro")
                isTesting = false
            }
        }
    }
}
