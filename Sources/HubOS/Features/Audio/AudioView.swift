import SwiftUI
import CoreAudio

/// In-hub audio device switcher: pick the default output/input and set the
/// master output volume, without opening System Settings.
struct AudioView: View {
    @Bindable private var audio = AudioManager.shared

    var body: some View {
        VStack(spacing: 14) {
            if audio.volumeAvailable { volumeCard }
            section(L(fr: "Sortie", en: "Output"), symbol: "speaker.wave.2.fill", devices: audio.outputs,
                    selected: audio.defaultOutputID) { audio.selectOutput($0) }
            if !audio.inputs.isEmpty {
                section(L(fr: "Entrée", en: "Input"), symbol: "mic.fill", devices: audio.inputs,
                        selected: audio.defaultInputID) { audio.selectInput($0) }
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .onAppear { if !PreviewConfig.isPreview { audio.refresh() } }
    }

    // MARK: Volume

    private var volumeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(audio.volume) },
                                  set: { audio.volume = Float($0) }), in: 0...1)
                .tint(Theme.teal)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 14)).foregroundStyle(Theme.teal)
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    // MARK: Device section

    private func section(_ title: String, symbol: String, devices: [AudioManager.Device],
                         selected: AudioDeviceID, action: @escaping (AudioManager.Device) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(devices) { device in
                    deviceRow(device, isSelected: device.id == selected) { action(device) }
                    if device.id != devices.last?.id {
                        Divider().opacity(0.1).padding(.leading, 46)
                    }
                }
            }
            .padding(.vertical, 4)
            .glassCard(radius: 16)
        }
    }

    private func deviceRow(_ device: AudioManager.Device, isSelected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: device.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Theme.teal : .secondary)
                    .frame(width: 26)
                Text(device.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Theme.teal)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
