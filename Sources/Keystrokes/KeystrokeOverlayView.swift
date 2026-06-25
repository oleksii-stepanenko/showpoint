import SwiftUI

/// The content of the overlay window: a row of key capsules pinned to the
/// configured corner, animating in/out as keys are pressed.
struct KeystrokeOverlayView: View {
    @ObservedObject var controller: KeystrokeController
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ZStack(alignment: settings.position.alignment) {
            Color.clear
            HStack(spacing: 10) {
                ForEach(controller.items) { item in
                    KeyCapsule(item: item, settings: settings)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal: .opacity))
                }
            }
            .padding(40)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: controller.items)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A single rounded "key cap" showing the modifier(s) + key.
private struct KeyCapsule: View {
    let item: KeyPressItem
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Text(item.text)
            .font(.system(size: settings.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, settings.fontSize * 0.6)
            .padding(.vertical, settings.fontSize * 0.32)
            .background(
                RoundedRectangle(cornerRadius: settings.fontSize * 0.45, style: .continuous)
                    .fill(.black.opacity(settings.overlayOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: settings.fontSize * 0.45, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .fixedSize()
    }
}
