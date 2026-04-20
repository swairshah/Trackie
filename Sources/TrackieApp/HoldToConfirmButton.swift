import SwiftUI

/// Press-and-hold confirmation button. Fires `action` only after the
/// user has held for `duration` seconds. While held, a progress
/// indicator fills; releasing early cancels.
///
/// Two flavors:
/// - `HoldToConfirmButton(symbol:)` — 18×18 icon square with a
///   circular ring overlay. Used by the menubar row's "delete forever".
/// - `HoldToConfirmButton(text:)` — pill-shaped text label with a
///   horizontal progress bar sweeping left-to-right. Used by the main
///   window's "Empty" trash action, which is too wide for a ring.
struct HoldToConfirmButton<Label: View>: View {
    let duration: Double
    let action: () -> Void
    /// Closure receives the current [0, 1] progress value so the label
    /// can draw its own shape of progress indicator.
    @ViewBuilder let label: (CGFloat) -> Label

    @State private var progress: CGFloat = 0

    var body: some View {
        label(progress)
            .contentShape(Rectangle())
            .help("Hold to confirm")
            .onLongPressGesture(
                minimumDuration: duration,
                maximumDistance: 100,
                perform: {
                    action()
                    progress = 0
                },
                onPressingChanged: { isDown in
                    if isDown {
                        withAnimation(.linear(duration: duration)) { progress = 1 }
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
                    }
                }
            )
    }
}

// MARK: - Convenience initializers

extension HoldToConfirmButton where Label == HoldIconLabel {
    /// Icon-only hold button. Matches the 18×18 rounded-rect iconButton
    /// style with a circular progress ring overlay.
    init(symbol: String, duration: Double = 2.0, action: @escaping () -> Void) {
        self.duration = duration
        self.action = action
        self.label = { progress in HoldIconLabel(symbol: symbol, progress: progress) }
    }
}

extension HoldToConfirmButton where Label == HoldTextLabel {
    /// Text hold button — pill label with a horizontal fill that
    /// sweeps left-to-right as the user holds.
    init(text: String, duration: Double = 2.0, action: @escaping () -> Void) {
        self.duration = duration
        self.action = action
        self.label = { progress in HoldTextLabel(text: text, progress: progress) }
    }
}

// MARK: - Default labels

struct HoldIconLabel: View {
    let symbol: String
    let progress: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(progress > 0 ? Color.red.opacity(0.15) : Color.primary.opacity(0.08))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)

            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(progress > 0 ? Color.red : .secondary)
        }
        .frame(width: 18, height: 18)
    }
}

struct HoldTextLabel: View {
    let text: String
    let progress: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                // Full-width base fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                // Progress bar: red, sweeps left-to-right
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red.opacity(0.28))
                    .frame(width: geo.size.width * progress)
            }

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(progress > 0 ? Color.red : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .fixedSize()
    }
}
