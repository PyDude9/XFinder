import SwiftUI

struct AntiSleepDetailView: View {
    @State private var caffeine = CaffeineController.shared
    @State private var selectedMinutes: Int? = nil

    private let presets: [(label: String, minutes: Int?)] = [
        ("Vô hạn", nil), ("15 phút", 15), ("1 giờ", 60), ("2 giờ", 120),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Chống ngủ")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                SettingsCard {
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(caffeine.isActive ? "Đang ngăn chế độ ngủ" : "Cho phép ngủ bình thường")
                                    .font(.system(size: 14, weight: .semibold))
                                if let r = caffeine.remainingSeconds {
                                    Text(String(format: "Còn %02d:%02d", r / 60, r % 60))
                                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                                        .foregroundColor(.orange)
                                } else if caffeine.isActive {
                                    Text("∞ Vô hạn").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(.orange)
                                }
                            }
                            Spacer()
                            Button(caffeine.isActive ? "Tắt" : "Bật") {
                                if caffeine.isActive { caffeine.deactivate() }
                                else {
                                    if let m = selectedMinutes { caffeine.activate(duration: .minutes(m)) }
                                    else { caffeine.activate(duration: .indefinite) }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(caffeine.isActive ? Color.red : Color.orange)
                            .controlSize(.large)
                        }

                        Picker("Thời lượng", selection: $selectedMinutes) {
                            ForEach(presets, id: \.label) { p in Text(p.label).tag(p.minutes) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(caffeine.isActive)
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Lưu ý") {
                    Text("Khi bật, hệ thống sẽ không tự động ngủ hay tắt màn hình cho đến khi bạn tắt hoặc hết thời lượng đã chọn. Kiểm tra bằng `pmset -g assertions` trong Terminal.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}
