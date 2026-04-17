import SwiftUI
import AppKit
import TrackieClient

struct MainWindowView: View {
    @ObservedObject var store: QueueStore
    @State private var newTitle: String = ""
    @State private var newProject: String = ""
    @State private var selection: UUID?
    @State private var showScratched = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(WindowAccessor().ignoresSafeArea())
    }

    // MARK: - Sidebar (the queue)

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pendingItems.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: $selection) {
                Section {
                    ForEach(pendingItems) { item in
                        row(item: item)
                            .tag(item.id)
                    }
                    .onMove { src, dest in
                        store.onMove(from: src, to: dest)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            let item = pendingItems[idx]
                            _ = store.remove(id: item.id)
                        }
                    }
                }

                if !doneItems.isEmpty {
                    Section("Done") {
                        ForEach(doneItems) { item in
                            row(item: item)
                                .tag(item.id)
                        }
                    }
                }

                if showScratched && !scratchedItems.isEmpty {
                    Section("Scratched") {
                        ForEach(scratchedItems) { item in
                            row(item: item)
                                .tag(item.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            addRow
        }
        .frame(minWidth: 300, idealWidth: 340)
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

    private func row(item: TrackieItem) -> some View {
        HStack(spacing: 8) {
            Button {
                _ = store.setStatus(id: item.id, item.status == .done ? .pending : .done)
            } label: {
                Image(systemName: item.status == .done ? "checkmark.circle.fill"
                                 : item.status == .scratched ? "xmark.circle.fill"
                                 : "circle")
                    .foregroundStyle(item.status == .done ? .green
                                     : item.status == .scratched ? .orange
                                     : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .strikethrough(item.status != .pending, color: .secondary)
                    .foregroundStyle(item.status == .pending ? .primary : .secondary)
                    .lineLimit(1)

                if let project = item.project, !project.isEmpty {
                    Text(project)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contextMenu {
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
            Button("Delete", role: .destructive) { _ = store.remove(id: item.id) }
        }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("Add to queue", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { submitNew() }
            TextField("project", text: $newProject)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 80)
            Button("Add") { submitNew() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
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
            if let id = selection, let item = store.item(id: id) {
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
        .frame(minWidth: 380)
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Theme.subtleBackground)
                    )
            }

            HStack(spacing: 8) {
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
                    _ = store.remove(id: item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
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

    private func commitAll() {
        commitTitle()
        commitProject()
        let newNote: String? = note.isEmpty ? nil : note
        if newNote != item.note {
            _ = store.update(id: item.id, note: .some(newNote))
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch item.status {
            case .pending: return ("PENDING", .secondary)
            case .done: return ("DONE", .green)
            case .scratched: return ("SCRATCHED", .orange)
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
                window.isMovableByWindowBackground = true
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
