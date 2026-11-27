import SwiftUI

/// Inline Audio Output, Master Volume & Display Brightness deck inside the expanded Dynamic Island
/// (`extraModule == .audio`). Demand-driven: retains observers ONLY while visible on screen.
struct NotchAudioPage: View {
    @State private var volumeObserver = VolumeObserver.shared
    @State private var audioOutputs = AudioOutputDevices.shared
    @State private var brightness = ScreenBrightness.shared
    @State private var brightnessDragging = false
    @State private var brightnessDraft: Double = 0.5
    @State private var trusted = WindowManager.isTrusted

    var body: some View {
        HStack(spacing: 8) {
            // Left card: Master Volume + Output Devices
            card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button { volumeObserver.toggleMute() } label: {
                            Image(systemName: volumeSymbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(volumeObserver.isMuted ? .red : .blue)
                                .frame(width: 20)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Tắt tiếng"))

                        Text(L10n.t("Âm lượng"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Text("\(Int((volumeObserver.volume * 100).rounded()))%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                    }

                    NotchGlassSlider(
                        value: volumeObserver.volume,
                        tint: volumeObserver.isMuted ? .gray : .blue,
                        enabled: true
                    ) { v in
                        volumeObserver.setVolume(v)
                    }

                    Divider().overlay(Color.white.opacity(0.10))

                    HStack {
                        Text(L10n.t("Âm thanh ra"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        if let err = audioOutputs.lastError {
                            Text(err).font(.system(size: 9.5)).foregroundStyle(.red).lineLimit(1)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(audioOutputs.devices) { device in
                                let selected = device.id == audioOutputs.currentID
                                Button {
                                    audioOutputs.select(device)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: device.symbol).font(.system(size: 10))
                                        Text(device.name).font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(selected ? .black : .white.opacity(0.85))
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.10)))
                                }
                                .buttonStyle(.plain)
                                .help(L10n.t("Chọn đầu ra âm thanh"))
                            }
                        }
                    }
                    .frame(height: 26)
                }
            }

            // Right card: Brightness + Settings jump
            card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        Text(L10n.t("Độ sáng"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Text(brightness.level == nil ? "—" : "\(Int((brightnessDraft * 100).rounded()))%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                    }

                    NotchGlassSlider(
                        value: brightness.level ?? 0.5,
                        tint: .orange,
                        enabled: trusted && brightness.level != nil,
                        onDragChanged: { v in
                            brightnessDragging = true
                            brightnessDraft = v
                        },
                        onCommit: { v in
                            brightnessDraft = v
                            brightness.setLevel(v)
                            brightnessDragging = false
                        }
                    )

                    if !trusted {
                        Button(L10n.t("Cấp quyền Trợ năng…")) {
                            if !WindowManager.requestAccessibilityTrust() {
                                WindowManager.openAccessibilityPane()
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .buttonStyle(.plain)
                    } else if brightness.level == nil {
                        Text(L10n.t("Không đọc được độ sáng — máy này có thể chỉ dùng màn hình ngoài."))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Button {
                            NotchSurfaceController.shared.dismiss()
                            AppState.shared.navigate(to: .system)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape").font(.system(size: 10.5))
                                Text(L10n.t("Cài đặt")).font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Mở Cài đặt hệ thống"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 140)
        .onChange(of: brightness.level) { _, newValue in
            if !brightnessDragging, let v = newValue {
                brightnessDraft = v
            }
        }
        .onAppear {
            trusted = WindowManager.isTrusted
            brightnessDraft = brightness.level ?? 0.5
            volumeObserver.retain()
            audioOutputs.retain()
            brightness.retain()
        }
        .onDisappear {
            volumeObserver.release()
            audioOutputs.release()
            brightness.release()
        }
    }

    private var volumeSymbol: String {
        if volumeObserver.isMuted || volumeObserver.volume == 0 { return "speaker.slash.fill" }
        return volumeObserver.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}

private struct NotchGlassSlider: View {
    let value: Double
    let tint: Color
    let enabled: Bool
    var onDragChanged: ((Double) -> Void)? = nil
    let onCommit: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { g in
            let current = min(max(dragValue ?? value, 0), 1)
            let fillWidth = max(12, g.size.width * current)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 8)
                Capsule().fill(tint.opacity(enabled ? 0.92 : 0.35)).frame(width: fillWidth, height: 8)
                Circle()
                    .fill(Color.white.opacity(enabled ? 1 : 0.45))
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: max(0, min(g.size.width - 14, g.size.width * current - 7)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled, g.size.width > 0 else { return }
                        let next = Double(min(max(v.location.x / g.size.width, 0), 1))
                        dragValue = next
                        onDragChanged?(next)
                        if onDragChanged == nil { onCommit(next) }
                    }
                    .onEnded { v in
                        guard enabled, g.size.width > 0 else { dragValue = nil; return }
                        let next = Double(min(max(v.location.x / g.size.width, 0), 1))
                        dragValue = nil
                        onCommit(next)
                    }
            )
        }
        .frame(height: 18)
        .opacity(enabled ? 1 : 0.55)
    }
}
