import SwiftUI

struct QuickControlsDetailView: View {
    @State private var volumeObserver = VolumeObserver.shared
    @State private var appearance: SystemControls.AppearanceMode = SystemControls.currentAppearance()
    @State private var appearanceError: String? = nil
    @State private var appearanceBusy = false
    @State private var brightDenied = false
    @AppStorage("windowPreview.hoverEnabled") private var hoverEnabled = true
    @State private var caffeine = CaffeineController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Điều khiển nhanh")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                SettingsCard(title: "Âm lượng", subtitle: volumeObserver.isMuted ? "Đang tắt tiếng" : "\(Int(volumeObserver.volume * 100))%") {
                    HStack(spacing: 12) {
                        Button(action: { volumeObserver.toggleMute() }) {
                            Image(systemName: volumeObserver.isMuted || volumeObserver.volume == 0
                                  ? "speaker.slash.fill"
                                  : volumeObserver.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                                .foregroundColor(volumeObserver.isMuted ? .red : .secondary)
                                .frame(width: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Bật / tắt tiếng")
                        Slider(value: Binding(get: { volumeObserver.volume },
                                              set: { volumeObserver.setVolume($0) }),
                               in: 0...1)
                            .tint(.blue)
                        Text("\(Int(volumeObserver.volume * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Độ sáng màn hình") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Image(systemName: "sun.min.fill").foregroundColor(.secondary).frame(width: 22)
                            Text("Tăng / Giảm độ sáng")
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: { stepBrightness(up: false) }) {
                                Image(systemName: "minus.circle.fill").imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .help("Giảm độ sáng")
                            Button(action: { stepBrightness(up: true) }) {
                                Image(systemName: "plus.circle.fill").imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .help("Tăng độ sáng")
                            Image(systemName: "sun.max.fill").foregroundColor(.secondary).frame(width: 22)
                        }
                        Text("Dùng phím độ sáng hệ thống (cần quyền Trợ năng). macOS không có API công khai để đọc % độ sáng nên không hiển thị số.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        if brightDenied {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Chưa có quyền Trợ năng — phím độ sáng sẽ không có tác dụng.")
                                    .font(.system(size: 11)).foregroundColor(.red)
                                Button("Mở Cài đặt quyền Trợ năng") { WindowManager.openAccessibilityPane() }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Giao diện", subtitle: "Áp dụng cho toàn hệ thống") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $appearance) {
                            ForEach(SystemControls.AppearanceMode.allCases) { mode in
                                Label(mode.titleVI, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(appearanceBusy)
                        .onChange(of: appearance) { applyAppearance($0) }

                        Text("“Hệ thống” để macOS tự chuyển Sáng/Tối theo thời gian trong ngày.")
                            .font(.system(size: 11)).foregroundColor(.secondary)

                        if let err = appearanceError {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(err).font(.system(size: 11)).foregroundColor(.red)
                                Button("Mở Cài đặt Tự động hóa") { SystemControls.openAutomationPane() }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Xem trước cửa sổ") {
                    ToggleRow(title: "Xem trước khi di chuột", subtitle: "Hover icon trên Dock để xem các cửa sổ của app", isOn: $hoverEnabled)
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Chống ngủ (nhanh)") {
                    ToggleRow(title: "Ngăn màn hình tắt", subtitle: caffeine.isActive ? "Đang bật\(caffeine.remainingSeconds.map { " · \($0 / 60):\($0 % 60 < 10 ? "0" : "")\($0 % 60)" } ?? "")" : "Đang tắt", isOn: Binding(get: { caffeine.isActive }, set: { on in
                        if on { caffeine.activate(duration: .indefinite) } else { caffeine.deactivate() }
                    }))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            appearance = SystemControls.currentAppearance()
            volumeObserver.retain()
        }
        .onDisappear { volumeObserver.release() }
    }

    private func applyAppearance(_ mode: SystemControls.AppearanceMode) {
        guard !appearanceBusy else { return }
        appearanceError = nil
        appearanceBusy = true
        Task {
            let result = await SystemControls.setAppearance(mode)
            appearanceBusy = false
            switch result {
            case .ok:
                appearance = SystemControls.currentAppearance()
            case .notPermitted:
                appearance = SystemControls.currentAppearance()
                appearanceError = "Chưa được cấp quyền Tự động hóa cho System Events. Mở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Tự động hóa → XFinder → bật System Events."
            case .failed(let msg):
                appearance = SystemControls.currentAppearance()
                appearanceError = "Không đổi được giao diện: \(msg)"
            }
        }
    }

    private func stepBrightness(up: Bool) {
        brightDenied = !WindowManager.isTrusted
        SystemControls.adjustBrightness(up: up)
    }
}
