import AppKit
import SwiftUI
import UserNotifications

/// First-run wizard: welcome, notification permission, pairing, test.
struct OnboardingView: View {
    @ObservedObject var model = AppModel.shared
    @State private var step: Int

    init(step: Int = 0) { _step = State(initialValue: step) }

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 18) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                content
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 32)
            Spacer(minLength: 24)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.connected) { connected in
            if connected && step == 2 { withAnimation { step = 3 } }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            page(L("NotifyBridge’e hoş geldin"),
                 L("Telefonundaki bildirimleri Mac’inde gör, yanıtla ve yönet. Kurulum yaklaşık bir dakika sürer.")) {
                Button { withAnimation { step = 1 } } label: { Label(L("Başla"), systemImage: "arrow.right") }
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
        case 1:
            page(L("Bildirimlere izin ver"),
                 L("Telefondan gelen bildirimlerin Mac’te görünmesi için macOS’tan izin gerekir.")) {
                permissionControls
            }
        case 2:
            page(L("Telefonu eşleştir"), nil) {
                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 22) {
                        Group {
                            if let img = QR.pairingImage(), !model.pairingKey.isEmpty {
                                Image(nsImage: img).interpolation(.none).resizable().scaledToFit()
                            } else { Color.clear }
                        }
                        .frame(width: 150, height: 150).padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        VStack(alignment: .leading, spacing: 10) {
                            numbered(1, L("Telefonda NotifyBridge’i aç"))
                            numbered(2, L("Kurulum bölümünde “QR oku”ya bas"))
                            numbered(3, L("Bu kodu telefona okut"))
                        }
                    }
                    if model.connected {
                        Label(model.deviceName.isEmpty ? L("Telefon bağlı") : String(format: L("Telefon bağlı · %@"), model.deviceName), systemImage: "checkmark.circle.fill")
                            .foregroundColor(nbGreen).font(.headline)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Telefon bekleniyor…")).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        default:
            page(L("Hazırsın"), L("Telefondan gelen bildirimler artık Mac’inde. İstersen şimdi bir test bildirimi gönderip nasıl göründüğüne bakabilirsin.")) {
                HStack(spacing: 10) {
                    Button { AppDelegate.shared.sendTest() } label: { Label(L("Test bildirimi gönder"), systemImage: "bell") }
                        .buttonStyle(PillButtonStyle())
                    Button { model.onboarded = true } label: { Label(L("Bitir"), systemImage: "checkmark") }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                }
            }
        }
    }

    @ViewBuilder private var permissionControls: some View {
        switch model.notifStatus {
        case .authorized, .provisional, .ephemeral:
            VStack(spacing: 14) {
                Label(L("İzin verildi"), systemImage: "checkmark.circle.fill").foregroundColor(nbGreen).font(.headline)
                Button { withAnimation { step = 2 } } label: { Label(L("Devam"), systemImage: "arrow.right") }
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
        case .denied:
            VStack(spacing: 14) {
                Text(L("Bildirimler macOS’ta kapalı. Sistem Ayarları’ndan NotifyBridge için açman gerekiyor."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { AppDelegate.shared.openNotificationSettings() } label: { Label(L("Sistem Ayarları’nı aç"), systemImage: "gearshape") }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                    Button { withAnimation { step = 2 } } label: { Text(L("Sonra")) }.buttonStyle(PillButtonStyle())
                }
            }
        default:
            Button { AppDelegate.shared.requestNotificationPermission() } label: { Label(L("İzin ver"), systemImage: "bell.badge") }
                .buttonStyle(PillButtonStyle(kind: .primary))
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle().fill(i == step ? nbTeal : Color.primary.opacity(0.18)).frame(width: 8, height: 8)
                }
            }
            Spacer()
            Button(L("Atla")) { model.onboarded = true }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28).padding(.bottom, 22)
    }

    private func page<Controls: View>(_ title: String, _ text: String?, @ViewBuilder controls: () -> Controls) -> some View {
        VStack(spacing: 14) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            if let text { Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            controls().padding(.top, 6)
        }
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundColor(.white)
                .frame(width: 22, height: 22).background(Circle().fill(nbTeal))
            Text(text)
        }
    }
}
