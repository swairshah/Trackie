import SwiftUI
import AppKit
import TrackieClient

struct MenuBarContentView: View {
    @ObservedObject var store: QueueStore
    @State private var newTitle: String = ""
    @State private var filter: Filter = .recent
    @State private var expanded: Bool = false
    @AppStorage("persistDockIcon") private var persistDockIcon: Bool = false
    @FocusState private var inputFocused: Bool

    enum Filter: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case pending = "Pending"
        case done = "Done"
        case all = "All"
        case trashed = "Trash"
        var id: String { rawValue }
        /// Cases shown as text segments in the header picker. Trash gets its
        /// own icon button instead of crowding the segmented control.
        static var segmentCases: [Filter] { [.recent, .pending, .done, .all] }
    }

    /// How many items to show in the "Recent" view — a compact glance at
    /// the newest open items without scrolling through the whole queue.
    private static let recentLimit = 5

    private var filteredItems: [TrackieItem] {
        switch filter {
        case .recent:
            // When the list is expanded we drop the 5-item cap — the
            // chevron's job is to *show more*, so it also lifts the Recent
            // slice from a compact glance to the full stream of open items.
            let pending = store.items
                .filter { $0.status == .pending }
                .sorted { $0.createdAt > $1.createdAt }
            return expanded ? pending : Array(pending.prefix(Self.recentLimit))
        case .pending:
            return store.items.filter { $0.status == .pending }
        case .done:
            return store.items.filter { $0.status == .done }
        case .all:
            return store.items.filter { $0.status != .trashed }
        case .trashed:
            return store.items.filter { $0.status == .trashed }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            inputRow
            Divider().opacity(0.5)
            list
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Theme.menubarWidth)
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Trackie")
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            Picker("", selection: $filter) {
                ForEach(Filter.segmentCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .controlSize(.small)

            Button {
                filter = (filter == .trashed) ? .recent : .trashed
            } label: {
                Image(systemName: filter == .trashed ? "trash.fill" : "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(filter == .trashed ? .primary : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(filter == .trashed ? Color.primary.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(filter == .trashed ? "Back to Recent" : "Show Trash")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("Add an item…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($inputFocused)
                .onSubmit { submit() }
            if !newTitle.isEmpty {
                Button(action: submit) {
                    Text("Add")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func submit() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = store.add(title: trimmed, sourceApp: "Trackie.app")
        newTitle = ""
    }

    private var emptyMessage: String {
        switch filter {
        case .recent, .pending: return "No open items"
        case .done: return "Nothing marked done yet"
        case .all: return "Nothing here"
        case .trashed: return "Trash is empty"
        }
    }

    // MARK: - List

    private var list: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Use an explicit `height:` (not `maxHeight`) so SwiftUI
                // reliably re-lays out the MenuBarExtra popover when the
                // toggle flips. MenuBarExtra's NSPanel measures its host
                // view once at content-size, and `maxHeight` alone is not
                // enough to force a resize between states.
                ScrollView {
                    // Plain VStack instead of LazyVStack — the menubar list is
                    // small (≤ few dozen items), and Lazy adds cell-recycling
                    // lag on removal that makes the trash click feel sluggish.
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        ForEach(filteredItems) { item in
                            MenuItemRow(item: item, store: store)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .animation(nil, value: filteredItems.map(\.id))
                }
                .frame(height: expanded ? 560 : 320)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(countSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Expand / collapse the list area. `>` when collapsed, `v` when
            // expanded — familiar chevron affordance.
            Button {
                expanded.toggle()
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .help(expanded ? "Show less" : "Show more")

            // Toggle whether Trackie keeps its dock icon on. Flipping it ON
            // also opens the main window — without a window the dock icon
            // has nothing to click to, so pairing the two matches the
            // standard "this is a regular app now" expectation.
            Button {
                persistDockIcon.toggle()
                DockIconManager.apply(persistDockIcon: persistDockIcon)
                if persistDockIcon {
                    MainWindowController.shared.show()
                }
            } label: {
                Image(systemName: persistDockIcon ? "dock.rectangle" : "menubar.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(persistDockIcon ? Color.accentColor : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .help(persistDockIcon ? "Dock icon: visible (click to hide)" : "Dock icon: hidden (click to show)")

            Spacer()

            Button {
                MainWindowController.shared.show()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)

            Menu {
                Button("Clear Completed") {
                    _ = store.clearCompleted()
                }
                .disabled(!store.items.contains { $0.status != .pending })

                Button("Clear All", role: .destructive) {
                    _ = store.clearAll()
                }
                .disabled(store.items.isEmpty)

                Divider()

                Button("Quit Trackie") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countSummary: String {
        let pending = store.items.filter { $0.status == .pending }.count
        let done = store.items.filter { $0.status == .done }.count
        if done > 0 {
            return "\(pending) pending · \(done) done"
        }
        return "\(pending) pending"
    }
}

// MARK: - Row

private struct MenuItemRow: View {
    let item: TrackieItem
    @ObservedObject var store: QueueStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: toggleDone) {
                Image(systemName: checkSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(checkColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .strikethrough(item.status != .pending, color: .secondary)
                    .foregroundStyle(item.status == .pending ? .primary : .secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if let project = item.project, !project.isEmpty {
                        pill(project)
                    }
                    if let src = item.sourceApp, !src.isEmpty, src != "Trackie.app" {
                        pill(src)
                    }
                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                HStack(spacing: 2) {
                    if item.status == .trashed {
                        iconButton("arrow.uturn.left") { _ = store.setStatus(id: item.id, .pending) }
                        HoldToConfirmButton(symbol: "trash.slash", duration: 2.0) {
                            _ = store.remove(id: item.id)
                        }
                    } else {
                        iconButton("arrow.up") { _ = store.move(id: item.id, direction: "up") }
                        iconButton("arrow.down") { _ = store.move(id: item.id, direction: "down") }
                        iconButton("trash") { _ = store.setStatus(id: item.id, .trashed) }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(hovering ? Theme.hoverBackground : Theme.subtleBackground)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Double-click opens the full window and focuses this item. We
        // attach tapCount:2 before tapCount:1 so the single-tap handler
        // (nothing yet, but room to grow) doesn't swallow the double.
        .onTapGesture(count: 2) {
            MainWindowController.shared.show(select: item.id)
        }
    }

    private var checkSymbol: String {
        switch item.status {
        case .pending: return "circle"
        case .done: return "checkmark.circle.fill"
        case .scratched: return "xmark.circle.fill"
        case .trashed: return "trash.circle.fill"
        }
    }

    private var checkColor: Color {
        switch item.status {
        case .pending: return .secondary
        case .done: return .green
        case .scratched: return .orange
        case .trashed: return .red.opacity(0.7)
        }
    }

    private func toggleDone() {
        _ = store.setStatus(id: item.id, item.status == .done ? .pending : .done)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

