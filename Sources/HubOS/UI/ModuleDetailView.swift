import SwiftUI

/// Routes an open module to its detail UI. Feature modules replace their case
/// here as they come online.
struct ModuleDetailView: View {
    let id: ModuleID

    var body: some View {
        switch id {
        case .clipboard:
            ClipboardView()
        case .brightness:
            BrightnessView()
        case .notch:
            NotchInfoView()
        case .shelf:
            ShelfInfoView()
        case .caffeine:
            CaffeineView()
        case .battery:
            BatteryView()
        case .audio:
            AudioView()
        case .focus:
            FocusView()
        case .timer:
            TimerView()
        case .cleaner:
            CleanerView()
        default:
            ComingSoonDetail(info: ModuleInfo.info(for: id))
        }
    }
}

/// Placeholder shown for modules that aren't wired up yet.
struct ComingSoonDetail: View {
    let info: ModuleInfo

    var body: some View {
        VStack(spacing: 16) {
            IconBadge(symbol: info.symbol, tint: info.tint, size: 64)
                .padding(.top, 8)
            Text(info.title)
                .font(.system(size: 18, weight: .bold))
            Text(info.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Ce module arrive bientôt.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .frame(height: 280)
    }
}
