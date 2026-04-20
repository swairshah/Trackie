import SwiftUI
import AppKit
import TrackieClient

struct MainWindowView: View {
    @ObservedObject var store: QueueStore
    @ObservedObject var controller: MainWindowController
    @State private var newTitle: String = ""
    @State private var newProject: String = ""
    @State private var showScratched = false

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { controller.selection },
            set: { controller.selection = $0 }
        )
    }

    var body: some View {
        // Custom resizable split instead of HSplitView: HSplitView's internal
        // state is not preserved across SwiftUI body invalidations, so
        // selection changes would reset the width. Keeping the width in
        // @AppStorage also lets it persist across launches.
        ResizableSplit(
            storageKey: "sidebarWidth",
            defaultWidth: 340,
            minSidebar: 240,
            maxSidebar: 520,
            minDetail: 360,
            sidebar: { sidebar },
            detail: { detail }
        )
        .frame(minWidth: 760, minHeight: 460)
        .background(WindowAccessor().ignoresSafeArea())
    }

    // MARK: - Sidebar (the queue)

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                Section {
                    ForEach(pendingItems) { item in
                        row(item: item)
                            .tag(item.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    }
                    .onMove { src, dest in
                        store.onMove(from: src, to: dest)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            let item = pendingItems[idx]
                            _ = store.setStatus(id: item.id, .trashed)
                        }
                    }
                } header: {
                    sectionHeader("QUEUE", count: pendingItems.count)
                }

                if !doneItems.isEmpty {
                    Section {
                        ForEach(doneItems) { item in
                            row(item: item)
                                .tag(item.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        }
                    } header: {
                        sectionHeader("DONE", count: doneItems.count)
                    }
                }

                if !scratchedItems.isEmpty {
                    Section {
                        ForEach(scratchedItems) { item in
                            row(item: item)
                                .tag(item.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        }
                    } header: {
                        sectionHeader("SCRATCHED", count: scratchedItems.count)
                    }
                }

                if !trashedItems.isEmpty {
                    Section {
                        ForEach(trashedItems) { item in
                            row(item: item)
                                .tag(item.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        }
                    } header: {
                        trashHeader
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 30)

            Divider().opacity(0.4)

            addRow
        }
    }

    /// Clearly-style small-caps section header with a subtle trailing count.
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .textCase(nil)
    }

    private var pendingItems: [TrackieItem] {
        store.items.filter { $0.status == .pending }
    }
    private var doneItems: [TrackieItem] {
        store.items.filter { $0.status == .done }
    }
    private var scratchedItems: [TrackieItem] {
        store.items.filter { $0.status == .scratched }
    }
    private var trashedItems: [TrackieItem] {
        store.items.filter { $0.status == .trashed }
    }

    private var trashHeader: some View {
        HStack {
            Text("TRASH")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Spacer()
            HoldToConfirmButton(text: "Empty") {
                let trashedSelection = controller.selection.flatMap { sel in
                    trashedItems.contains(where: { $0.id == sel }) ? sel : nil
                }
                _ = store.purgeTrashed()
                if trashedSelection != nil { controller.selection = nil }
            }
            Text("\(trashedItems.count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .textCase(nil)
    }

    private func row(item: TrackieItem) -> some View {
        HStack(spacing: 8) {
            // Leading status/type icon. Tapping it cycles pending ⇄ done
            // (disabled for trashed items — restore via context menu instead).
            Button {
                if item.status == .trashed { return }
                _ = store.setStatus(id: item.id, item.status == .done ? .pending : .done)
            } label: {
                Image(systemName: rowIcon(for: item))
                    .font(.system(size: 13))
                    .foregroundStyle(rowIconColor(for: item))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .disabled(item.status == .trashed)

            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.status != .pending, color: .secondary)
                .foregroundStyle(item.status == .pending ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // Trailing secondary — either the project tag or the source
            // app. Clearly's sidebar uses this slot for file-type hints
            // like "Excalid…"; we use it for project/source.
            if let trailing = rowTrailingText(item), !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contextMenu {
            if item.status == .trashed {
                Button("Restore") { _ = store.setStatus(id: item.id, .pending) }
                Divider()
                Button("Delete Forever", role: .destructive) { _ = store.remove(id: item.id) }
            } else {
                Button("Mark Done") { _ = store.setStatus(id: item.id, .done) }
                    .disabled(item.status == .done)
                Button("Reopen") { _ = store.setStatus(id: item.id, .pending) }
                    .disabled(item.status == .pending)
                Button("Scratch") { _ = store.setStatus(id: item.id, .scratched) }
                    .disabled(item.status == .scratched)
                Divider()
                Button("Move to Top") { _ = store.move(id: item.id, direction: "top") }
                Button("Move to Bottom") { _ = store.move(id: item.id, direction: "bottom") }
                Divider()
                Button("Move to Trash", role: .destructive) { _ = store.setStatus(id: item.id, .trashed) }
            }
        }
    }

    private func rowIcon(for item: TrackieItem) -> String {
        switch item.status {
        case .pending:   return "circle"
        case .done:      return "checkmark"
        case .scratched: return "xmark"
        case .trashed:   return "trash"
        }
    }

    private func rowIconColor(for item: TrackieItem) -> Color {
        switch item.status {
        case .pending:   return .secondary
        case .done:      return .green
        case .scratched: return .orange
        case .trashed:   return .red.opacity(0.7)
        }
    }

    private func rowTrailingText(_ item: TrackieItem) -> String? {
        if let project = item.project, !project.isEmpty { return project }
        if let src = item.sourceApp, !src.isEmpty, src != "Trackie.app" { return src }
        return nil
    }

    private var addRow: some View {
        // Wrap the TextFields in a visible pill-styled container — plain
        // text fields without a background are easy to miss and hard to
        // hit reliably inside a List-dominated sidebar.
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Add to queue", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { submitNew() }
            TextField("project", text: $newProject)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 70)
                .onSubmit { submitNew() }
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add") { submitNew() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func submitNew() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let project = newProject.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = store.add(title: trimmed, project: project.isEmpty ? nil : project, sourceApp: "Trackie.app")
        newTitle = ""
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let id = controller.selection, let item = store.item(id: id) {
                DetailEditor(item: item, store: store)
                    .id(id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select an item")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Any agent can push items via the `trackie` CLI.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Detail editor

private struct DetailEditor: View {
    let item: TrackieItem
    @ObservedObject var store: QueueStore

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var project: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statusBadge
                Text(item.shortId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            TextField("Title", text: $title)
                .font(.system(size: 20, weight: .semibold))
                .textFieldStyle(.plain)
                .onSubmit { commitTitle() }

            HStack(spacing: 6) {
                Text("Project")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("(none)", text: $project)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { commitProject() }
            }

            NoteEditor(itemId: item.id, text: $note, onCommit: commitNote)

            HStack(spacing: 8) {
                if item.status == .trashed {
                    Button {
                        _ = store.setStatus(id: item.id, .pending)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.left")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        _ = store.remove(id: item.id)
                    } label: {
                        Label("Delete Forever", systemImage: "trash.slash")
                    }
                } else {
                    Button {
                        _ = store.setStatus(id: item.id, item.status == .done ? .pending : .done)
                    } label: {
                        Label(item.status == .done ? "Reopen" : "Mark Done",
                              systemImage: item.status == .done ? "arrow.uturn.left" : "checkmark")
                    }

                    Button {
                        _ = store.setStatus(id: item.id, .scratched)
                    } label: {
                        Label("Scratch", systemImage: "xmark")
                    }
                    .disabled(item.status == .scratched)

                    Spacer()

                    Button(role: .destructive) {
                        commitAll()
                        _ = store.setStatus(id: item.id, .trashed)
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear { hydrate() }
        .onChange(of: item.id) { _ in hydrate() }
        .onDisappear { commitAll() }
    }

    private func hydrate() {
        title = item.title
        note = item.note ?? ""
        project = item.project ?? ""
        loaded = true
    }

    private func commitTitle() {
        guard loaded else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != item.title else { return }
        _ = store.update(id: item.id, title: t)
    }

    private func commitProject() {
        guard loaded else { return }
        let p = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue: String? = p.isEmpty ? nil : p
        guard newValue != item.project else { return }
        _ = store.update(id: item.id, project: .some(newValue))
    }

    private func commitNote() {
        guard loaded else { return }
        let newNote: String? = note.isEmpty ? nil : note
        guard newNote != item.note else { return }
        _ = store.update(id: item.id, note: .some(newNote))
    }

    private func commitAll() {
        commitTitle()
        commitProject()
        commitNote()
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch item.status {
            case .pending: return ("PENDING", .secondary)
            case .done: return ("DONE", .green)
            case .scratched: return ("SCRATCHED", .orange)
            case .trashed: return ("TRASH", .red)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Window styling

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let window = v.window {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                // Intentionally NOT setting isMovableByWindowBackground — with
                // it on, any non-titlebar drag (including dragging our split
                // divider) was moving the whole window. The titlebar is
                // still draggable for repositioning the window.
                window.isMovableByWindowBackground = false
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
