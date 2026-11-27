import SwiftUI

// MARK: - Tab 2: Sound & Display (retains observers ONLY while visible)

struct AudioDisplayPanelTabView: View {
    @State private var volumeObserver = VolumeObserver.shared
    @State private var audioOutputs = AudioOutputDevices.shared
    @State private var brightness = ScreenBrightness.shared
    @State private var brightnessSlider: Double = 0.5
    @State private var brightnessDragging = false
    @State private var brightDenied = false

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        volumeObserver.toggleMute()
                    } label: {
                        Image(systemName: volumeObserver.isMuted || volumeObserver.volume == 0
                              ? "speaker.slash.fill"
                              : volumeObserver.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                            .font(.system(size: 13))
                            .foregroundColor(volumeObserver.isMuted ? .red : .accentColor)
                            .frame(width: 22)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Tắt tiếng"))

                    Slider(value: Binding(
                        get: { volumeObserver.volume },
                        set: { volumeObserver.setVolume($0) }
                    ), in: 0...1)
                    .tint(.blue)

                    Text("\(Int(volumeObserver.volume * 100))%")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                Divider().opacity(0.35)

                HStack(spacing: 8) {
                    Image(systemName: audioOutputs.current?.symbol ?? "speaker.wave.2")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text(L10n.t("Âm thanh ra"))
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 4)
                    if audioOutputs.devices.count > 1 {
                        Picker("", selection: Binding(
                            get: { audioOutputs.currentID },
                            set: { id in
                                if let d = audioOutputs.devices.first(where: { $0.id == id }) {
                                    audioOutputs.select(d)
                                }
                            }
                        )) {
                            ForEach(audioOutputs.devices) { d in
                                Label(d.name, systemImage: d.symbol).tag(d.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 165)
                    } else {
                        Text(audioOutputs.current?.name ?? "—")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if audioOutputs.devices.count <= 1 {
                    Text(L10n.t("Chỉ có một thiết bị âm thanh ra — cắm tai nghe hoặc kết nối loa để chọn thiết bị khác."))
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                if let err = audioOutputs.lastError {
                    Text("\(L10n.t("Không đổi được thiết bị âm thanh ra: "))\(err)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.red)
                }
            }
            .menubarPanelCard(padding: 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .frame(width: 22)
                    Text(L10n.t("Độ sáng màn hình"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(brightness.level == nil ? "—" : "\(Int(brightnessSlider * 100))%")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                }

                Slider(value: $brightnessSlider, in: 0...1) { editing in
                    brightnessDragging = editing
                    if !editing {
                        brightness.setLevel(brightnessSlider)
                    }
                }
                .tint(.orange)
                .disabled(brightDenied || brightness.level == nil)
                .onChange(of: brightness.level) { _, newValue in
                    if !brightnessDragging, let v = newValue {
                        brightnessSlider = v
                    }
                }

                if brightDenied {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Chưa có quyền Trợ năng — kéo thanh trượt sẽ không đổi được độ sáng."))
                            .font(.system(size: 10.5))
                            .foregroundColor(.orange)
                        Button(L10n.t("Cấp quyền Trợ năng…")) {
                            if !WindowManager.requestAccessibilityTrust() {
                                WindowManager.openAccessibilityPane()
                            }
                        }
                        .controlSize(.small)
                    }
                } else if brightness.level == nil {
                    Text(L10n.t("Không đọc được độ sáng — máy này có thể chỉ dùng màn hình ngoài."))
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .menubarPanelCard(padding: 12)
        }
        .onAppear {
            brightDenied = !WindowManager.isTrusted
            brightnessSlider = brightness.level ?? 0.5
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
}

// MARK: - Tab 3: System (retains SystemMonitorManager ONLY while visible)

struct SystemPanelTabView: View {
    let onOpenFull: () -> Void
    @State private var monitor = SystemMonitorManager.shared
    @State private var hasBattery = PowerManager.hasBattery()
    @State private var batteryInfo: BatteryInfo?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                tempCard(title: L10n.t("Nhiệt độ SoC"), celsius: monitor.currentMetrics.socTempAverage)
                tempCard(title: L10n.t("Nóng nhất"), celsius: monitor.currentMetrics.socTempMax)
                if hasBattery {
                    tempCard(title: L10n.t("Pin"), celsius: batteryInfo?.temperatureC)
                }
            }

            VStack(spacing: 10) {
                metricBar(label: "CPU", value: monitor.currentMetrics.cpuUsage, tint: .blue)
                if !monitor.metricsHistory.isEmpty {
                    SparklineView(values: monitor.metricsHistory.map(\.cpuUsage), yMax: 100, tint: .blue, height: 22)
                }
                if let gpu = monitor.currentMetrics.gpuUsage {
                    metricBar(label: "GPU", value: gpu, tint: .cyan)
                    if monitor.metricsHistory.contains(where: { $0.gpuUsage != nil }) {
                        SparklineView(values: monitor.metricsHistory.map { $0.gpuUsage ?? 0 }, yMax: 100, tint: .cyan, height: 22)
                    }
                } else {
                    HStack {
                        Text("GPU").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(L10n.t("Không khả dụng"))
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                }
                if hasBattery {
                    let level = monitor.currentMetrics.batteryLevel
                    metricBar(label: L10n.t("Pin"), value: level, tint: level < 20 ? .red : .green)
                }
                HStack(spacing: 6) {
                    Text("RAM").font(.system(size: 12, weight: .medium))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(thermalDotColor(monitor.currentMetrics.thermalState))
                            .frame(width: 6, height: 6)
                        Text(monitor.currentMetrics.thermalState.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    Spacer()
                    Text("\(monitor.currentMetrics.memoryUsedString) / \(monitor.currentMetrics.memoryTotalString)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                if !monitor.metricsHistory.isEmpty {
                    SparklineView(values: monitor.metricsHistory.map(\.memoryPercentage), yMax: 100, tint: .purple, height: 22)
                }
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(monitor.currentMetrics.uptimeString)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .menubarPanelCard(padding: 12)

            MenubarOpenDetailButton(title: L10n.t("Theo dõi hệ thống"), action: onOpenFull)
        }
        .onAppear {
            monitor.retain()
            hasBattery = PowerManager.hasBattery()
            batteryInfo = hasBattery ? PowerManager.read() : nil
        }
        .onDisappear { monitor.release() }
    }

    private func thermalDotColor(_ state: SystemThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }

    private func tempCard(title: String, celsius: Double?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            if let text = MenubarPanelRules.formatTemp(celsius) {
                Text(text)
                    .font(.system(size: 13.5, weight: .bold))
                    .monospacedDigit()
            } else {
                Text(L10n.t("Không khả dụng"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func metricBar(label: String, value: Double, tint: Color) -> some View {
        let clamped = min(max(value, 0), 100)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", clamped))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            ProgressView(value: clamped, total: 100)
                .tint(tint)
        }
    }
}

// MARK: - Tab 4: Network

struct NetworkPanelTabView: View {
    let onOpenFull: () -> Void
    @State private var monitor = SystemMonitorManager.shared

    var body: some View {
        let measuring = monitor.metricsHistory.isEmpty
        return VStack(spacing: 8) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(
                            measuring ? L10n.t("Đang đo…") : MenubarPanelRules.formatRateKBs(monitor.currentMetrics.networkDownload),
                            systemImage: "arrow.down"
                        )
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                        .monospacedDigit()
                        Text(L10n.t("Tải xuống"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(
                            measuring ? L10n.t("Đang đo…") : MenubarPanelRules.formatRateKBs(monitor.currentMetrics.networkUpload),
                            systemImage: "arrow.up"
                        )
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                        .monospacedDigit()
                        Text(L10n.t("Tải lên"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !monitor.metricsHistory.isEmpty {
                    ZStack {
                        SparklineView(values: monitor.metricsHistory.map(\.networkDownload), tint: .blue, height: 24)
                        SparklineView(values: monitor.metricsHistory.map(\.networkUpload), tint: .green, height: 24)
                            .opacity(0.75)
                    }
                }

                Divider().opacity(0.35)

                HStack {
                    Text(L10n.t("Phiên này"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("↓\(MenubarPanelRules.formatBytes(Int64(clamping: monitor.sessionBytesRX)))  ↑\(MenubarPanelRules.formatBytes(Int64(clamping: monitor.sessionBytesTX)))")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                }
            }
            .menubarPanelCard(padding: 12)

            MenubarOpenDetailButton(title: L10n.t("Mạng"), action: onOpenFull)
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }
}

// MARK: - Tab 5: Storage

struct StoragePanelTabView: View {
    let onOpenFull: () -> Void
    @State private var monitor = SystemMonitorManager.shared

    var body: some View {
        let total = max(monitor.currentMetrics.diskTotal, 1)
        let used = min(max(monitor.currentMetrics.diskUsed, 0), total)
        let free = max(total - used, 0)
        let pct = Double(used) / Double(total) * 100.0

        return VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("Ổ đĩa")).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("\(MenubarPanelRules.formatBytes(used)) / \(MenubarPanelRules.formatBytes(total))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                ProgressView(value: pct, total: 100)
                    .tint(pct > 85 ? .orange : .blue)
                Text("\(L10n.t("Còn trống: "))\(MenubarPanelRules.formatBytes(free))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .menubarPanelCard(padding: 12)

            MenubarOpenDetailButton(title: L10n.t("Ổ đĩa"), action: onOpenFull)
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }
}

// MARK: - Tab 6: Battery

struct BatteryPanelTabView: View {
    let onOpenFull: () -> Void
    @State private var monitor = SystemMonitorManager.shared
    @State private var hasBattery = PowerManager.hasBattery()
    @State private var info: BatteryInfo?

    var body: some View {
        let level = min(max(monitor.currentMetrics.batteryLevel, 0), 100)
        let charging = monitor.currentMetrics.isCharging

        return VStack(spacing: 8) {
            if !hasBattery {
                VStack(spacing: 6) {
                    Image(systemName: "battery.0")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                    Text(L10n.t("Không có pin"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(L10n.t("Thiết bị này không có pin tích hợp."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .menubarPanelCard(padding: 14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L10n.t("Pin"), systemImage: charging ? "bolt.batteryblock.fill" : "battery.100")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text(String(format: "%.0f%%", level))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                    }
                    ProgressView(value: level, total: 100)
                        .tint(level < 20 ? .red : .green)
                    HStack {
                        Text(charging ? L10n.t("Đang sạc") : L10n.t("Đang dùng pin"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let rem = MenubarPanelRules.formatBatteryRemaining(minutes: monitor.currentMetrics.batteryTimeRemaining) {
                            Text("\(L10n.t("Còn lại: "))\(rem)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .menubarPanelCard(padding: 12)

                if let info {
                    VStack(spacing: 6) {
                        statRow(label: L10n.t("Công suất"), value: info.watts.map { String(format: "%.1f W", $0) } ?? "—")
                        statRow(label: L10n.t("Sức khỏe"), value: info.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                        statRow(label: L10n.t("Số chu kỳ"), value: info.cycleCount.map(String.init) ?? "—")
                        statRow(label: L10n.t("Nhiệt độ pin"), value: info.temperatureC.map { String(format: "%.1f °C", $0) } ?? "—")
                    }
                    .menubarPanelCard(padding: 12)
                }
            }

            MenubarOpenDetailButton(title: L10n.t("Pin"), action: onOpenFull)
        }
        .onAppear {
            monitor.retain()
            hasBattery = PowerManager.hasBattery()
            info = hasBattery ? PowerManager.read() : nil
        }
        .onDisappear { monitor.release() }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
        }
    }
}

private struct MenubarOpenDetailButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .menubarPanelCard()
        }
        .buttonStyle(.plain)
    }
}
