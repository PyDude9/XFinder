import SwiftUI

public struct CircularProgressRing: View {
    public let percent: Int
    public var strokeWidth: CGFloat = 4

    public var isLow: Bool { percent < 20 }

    public init(percent: Int, strokeWidth: CGFloat = 4) {
        self.percent = percent
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, percent))) / 100.0)
                .stroke(
                    isLow ? Color.red : Color.green,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percent)
        }
    }
}

/// Mini native battery capsule pill with charge bolt, matching Apple and AirBattery style
public struct AirBatteryPillView: View {
    public let percent: Int
    public let isCharging: Bool

    public init(percent: Int, isCharging: Bool) {
        self.percent = percent
        self.isCharging = isCharging
    }

    public var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                // Outer capsule border
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 25, height: 13)

                // Fill level
                let fillWidth = max(2.0, CGFloat(max(0, min(100, percent))) / 100.0 * 21.0)
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .fill(isCharging ? Color.green : (percent < 20 ? Color.red : Color.green))
                    .frame(width: fillWidth, height: 9)
                    .padding(.leading, 2)

                // Bolt icon when charging
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 25, height: 13, alignment: .center)
                }
            }

            // Positive terminal knob
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.35))
                .frame(width: 1.5, height: 5)
        }
    }
}

/// A clean device row matching AirBattery: [Icon] [Name + sub] ... [%] [Pill]
public struct AirBatteryDeviceRow: View {
    public let device: ConnectedDeviceBattery

    public init(device: ConnectedDeviceBattery) {
        self.device = device
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.kind.iconName)
                .font(.system(size: 15))
                .frame(width: 22, height: 22)
                .foregroundColor(device.isLowBattery ? .red : .primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if device.hasMultiBattery {
                    Text(device.multiBatterySubtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if device.percent >= 0 {
                Text("\(device.percent)%")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(device.isLowBattery ? .red : .secondary)

                AirBatteryPillView(percent: device.percent, isCharging: device.isCharging)
            } else if device.isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(L10n.t("Đã kết nối"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                Text(L10n.t("Đã ngắt kết nối"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

public struct LargeBatteryCardView: View {
    public let device: ConnectedDeviceBattery

    public init(device: ConnectedDeviceBattery) {
        self.device = device
    }

    public var body: some View {
        AirBatteryDeviceRow(device: device)
    }
}

public struct GridBatteryCardView: View {
    public let device: ConnectedDeviceBattery

    public init(device: ConnectedDeviceBattery) {
        self.device = device
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: device.kind.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(device.isLowBattery ? .red : .primary)
                Spacer()
                HStack(spacing: 2) {
                    if device.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                    if device.percent >= 0 {
                        Text("\(device.percent)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(device.isLowBattery ? .red : .primary)
                    } else if device.isConnected {
                        Text(L10n.t("Đã kết nối"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text(L10n.t("Đã ngắt kết nối"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if device.percent >= 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(device.isLowBattery ? Color.red : Color.green)
                            .frame(width: max(0, CGFloat(device.percent) / 100.0 * geo.size.width))
                    }
                }
                .frame(height: 4)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if device.hasMultiBattery {
                    Text(device.multiBatterySubtitle)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(device.isConnected ? L10n.t("Đã kết nối") : L10n.t("Đã ngắt kết nối"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

public struct ConnectedDevicesSectionView: View {
    @ObservedObject private var store = BatteryStore.shared
    @AppStorage("batteryHub.layoutMode") private var layoutMode: String = "list"
    @State private var isRefreshing = false

    public init() {}

    public var body: some View {
        let externalDevices = store.connectedDevices.filter { $0.kind != .mac }
        if externalDevices.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("Thiết bị đã kết nối"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        Task {
                            isRefreshing = true
                            await store.refresh()
                            isRefreshing = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Làm mới pin"))
                    .accessibilityLabel(L10n.t("Làm mới pin"))

                    HStack(spacing: 2) {
                        Button {
                            layoutMode = "list"
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 10))
                                .padding(3)
                                .background(layoutMode == "list" ? Color.primary.opacity(0.12) : Color.clear)
                                .cornerRadius(4)
                                .foregroundColor(layoutMode == "list" ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Chế độ danh sách"))
                        .accessibilityLabel(L10n.t("Chế độ danh sách"))

                        Button {
                            layoutMode = "grid"
                        } label: {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 10))
                                .padding(3)
                                .background(layoutMode == "grid" ? Color.primary.opacity(0.12) : Color.clear)
                                .cornerRadius(4)
                                .foregroundColor(layoutMode == "grid" ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Chế độ lưới"))
                        .accessibilityLabel(L10n.t("Chế độ lưới"))
                    }
                }

                if layoutMode == "list" {
                    VStack(spacing: 6) {
                        ForEach(externalDevices) { dev in
                            AirBatteryDeviceRow(device: dev)
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ],
                        spacing: 6
                    ) {
                        ForEach(externalDevices) { dev in
                            GridBatteryCardView(device: dev)
                        }
                    }
                }
            }
        }
    }
}
