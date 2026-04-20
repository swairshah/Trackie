import SwiftUI
import AppKit

/// Two-pane horizontal split with a draggable divider.
///
/// Why not HSplitView:
///   - HSplitView's current width is part of the AppKit view's internal
///     state, not SwiftUI's state graph. Any time SwiftUI rebuilds the
///     subtree (e.g. a List selection change), the split resets to its
///     default, which the user perceives as a bug.
///   - There's no built-in hook to persist the width across launches.
///
/// This view keeps the sidebar's width in @AppStorage, clamps it to a
/// configurable range, and drives the drag through a simple gesture on a
/// thin divider handle.
struct ResizableSplit<Sidebar: View, Detail: View>: View {
    let storageKey: String
    let defaultWidth: CGFloat
    let minSidebar: CGFloat
    let maxSidebar: CGFloat
    let minDetail: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        // Read/write AppStorage through a computed wrapper so we can back
        // it by a dynamic key. Using a small inner view with its own
        // @AppStorage avoids SwiftUI re-initialising storage on every call.
        SplitContent(
            storageKey: storageKey,
            defaultWidth: defaultWidth,
            minSidebar: minSidebar,
            maxSidebar: maxSidebar,
            minDetail: minDetail,
            sidebar: sidebar,
            detail: detail
        )
    }
}

private struct SplitContent<Sidebar: View, Detail: View>: View {
    let storageKey: String
    let defaultWidth: CGFloat
    let minSidebar: CGFloat
    let maxSidebar: CGFloat
    let minDetail: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    @AppStorage private var sidebarWidth: Double
    @State private var dragStartWidth: CGFloat?

    init(
        storageKey: String,
        defaultWidth: CGFloat,
        minSidebar: CGFloat,
        maxSidebar: CGFloat,
        minDetail: CGFloat,
        sidebar: @escaping () -> Sidebar,
        detail: @escaping () -> Detail
    ) {
        self.storageKey = storageKey
        self.defaultWidth = defaultWidth
        self.minSidebar = minSidebar
        self.maxSidebar = maxSidebar
        self.minDetail = minDetail
        self.sidebar = sidebar
        self.detail = detail
        self._sidebarWidth = AppStorage(wrappedValue: Double(defaultWidth), storageKey)
    }

    var body: some View {
        GeometryReader { geo in
            let allowedUpper = max(minSidebar, min(maxSidebar, geo.size.width - minDetail))
            let clamped = min(max(CGFloat(sidebarWidth), minSidebar), allowedUpper)
            HStack(spacing: 0) {
                sidebar()
                    .frame(width: clamped)
                    .frame(maxHeight: .infinity)

                DividerHandle()
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = clamped
                                }
                                let proposed = (dragStartWidth ?? clamped) + value.translation.width
                                let bounded = min(max(proposed, minSidebar), allowedUpper)
                                sidebarWidth = Double(bounded)
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )

                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Thin visible divider + wider invisible hit-target so the drag affordance
/// is easy to grab. Shows the standard macOS horizontal-resize cursor on
/// hover.
private struct DividerHandle: View {
    var body: some View {
        ZStack {
            // Wider invisible hit area for easier grabbing.
            Color.clear
                .frame(width: 10)
                .contentShape(Rectangle())
            // Thin visible hairline.
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
