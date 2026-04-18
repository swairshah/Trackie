import SwiftUI
import AppKit
import TrackieClient

struct MenuBarContentView: View {
    @ObservedObject var store: QueueStore
    @State private var newTitle: String = ""
    @State private var filter: Filter = .pending
    @FocusState private var inputFocused: Bool

    enum Filter: String, CaseIterable, Identifiable {
        case pending = "Pending"
        case done = "Done"
        case all = "All"
        var id: String { rawValue }
    }

    private var filteredItems: [TrackieItem] {
        switch filter {
        case .pending:
            return store.items.filter { $0.status == .pending }
        case .done:
            return store.items.filter { $0.status == .done }
        case .all:
            return store.items
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
        .frame(maxHeight: Theme.menubarMaxHeight, alignment: .top)
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Trackie")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .controlSize(.small)
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

    // MARK: - List

    private var list: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(filter == .pending ? "No pending items" : "Nothing here")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        ForEach(filteredItems) { item in
                            MenuItemRow(item: item, store: store)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 340)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(countSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
                    iconButton("arrow.up") { _ = store.move(id: item.id, direction: "up") }
                    iconButton("arrow.down") { _ = store.move(id: item.id, direction: "down") }
                    iconButton("xmark") { _ = store.remove(id: item.id) }
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
        }
    }

    private var checkColor: Color {
        switch item.status {
        case .pending: return .secondary
        case .done: return .green
        case .scratched: return .orange
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
