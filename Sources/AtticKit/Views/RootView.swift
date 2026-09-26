import AppKit
import AtticCore
import SwiftUI

public struct RootView: View {
    @Bindable var model: AppModel
    let thumbs: ThumbnailStoreBox

    public init(model: AppModel, thumbs: ThumbnailStoreBox) { self.model = model; self.thumbs = thumbs }

    public var body: some View {
        Group {
            switch model.phase {
            case .starting:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied:
                AccessView()
            case let .analyzing(done, total):
                VStack(spacing: 12) {
                    ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 320)
                    Text("Looking at \(done) of \(total) photos on this Mac")
                        .font(Theme.second).foregroundStyle(Theme.muted).monospacedDigit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                NavigationSplitView {
                    Sidebar(model: model).navigationSplitViewColumnWidth(min: 200, ideal: 220)
                } detail: {
                    // The banner is an inset, not a sibling in a VStack: inserting a
                    // view above the section blanked the whole split view on macOS 26
                    // (sidebar included) the moment a message appeared.
                    SectionView(model: model)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if let m = model.message { Banner(text: m) { model.message = nil } }
                        }
                }
            }
        }
        .background(Theme.bg)
        .environment(thumbs)
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct SectionView: View {
    @Bindable var model: AppModel
    var body: some View {
        switch model.section {
        case .duplicates: GroupsView(kind: .duplicates, model: model).id("dup")
        case .retakes: GroupsView(kind: .retakes, model: model).id("ret")
        case .bestOf: BestOfView(model: model)
        case .marked: MarkedView(model: model)
        }
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel

    func count(_ s: AppModel.Section) -> Int {
        switch s {
        case .duplicates: model.visibleGroups(.duplicates).count
        case .retakes: model.visibleGroups(.retakes).count
        case .bestOf: model.visibleEvents(.todo).count
        case .marked: model.marked.count
        }
    }

    var body: some View {
        List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
            Section("Clean up") {
                row(.duplicates, "square.on.square")
                row(.retakes, "square.stack.3d.down.right")
            }
            Section("Curate") { row(.bestOf, "star") }
            Section { row(.marked, "trash") }
        }
        .safeAreaInset(edge: .bottom) {
            if model.unavailable > 0 {
                Text("\(model.unavailable) photos are only in iCloud and were not looked at.")
                    .font(Theme.caption).foregroundStyle(Theme.muted).padding(12)
            }
        }
    }

    func row(_ s: AppModel.Section, _ icon: String) -> some View {
        Label {
            HStack {
                Text(s.title)
                Spacer()
                let n = count(s)
                if n > 0 {
                    Text("\(n)").monospacedDigit().foregroundStyle(s == .marked ? Theme.del : Theme.muted)
                }
            }
        } icon: { Image(systemName: icon) }
        .tag(s)
    }
}

struct MarkedView: View {
    @Bindable var model: AppModel
    var body: some View { ScrollView { MarkedContent(model: model) }.background(Theme.bg) }
}

struct MarkedContent: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("Marked for deletion").font(Theme.title).foregroundStyle(Theme.ink)
                Spacer()
                if !model.marked.isEmpty || model.working.contains("delete") {
                    Button(model.working.contains("delete") ? "Deleting…" : "Delete \(model.marked.count) from Photos…") {
                        Task { await model.deleteMarked() }
                    }
                    .buttonStyle(ActionButton(kind: .danger))
                    .disabled(model.working.contains("delete"))
                }
            }
            .padding(.top, 16)
            if model.marked.isEmpty {
                Text("Nothing marked. Mark shots in Duplicates or Retakes, then delete them here in one go.")
                    .font(Theme.second).foregroundStyle(Theme.muted)
            } else {
                Text("Photos asks you to confirm. Deleted photos stay in Recently Deleted for 30 days.")
                    .font(Theme.caption).foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(model.marked) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Thumb(id: p.id).clipShape(RoundedRectangle(cornerRadius: 5))
                            Button("Keep instead") { model.unmark(p.id) }
                                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 60)
    }
}

struct Banner: View {
    let text: String
    let close: () -> Void
    // No fixedSize and no Spacer: that pairing sent AppKit into a layout loop
    // ("layoutSubtreeIfNeeded on a view which is already being laid out") and
    // the whole window drew blank after a delete (2026-09-26).
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.goldSoft)
    }
}

struct AccessView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(Theme.muted)
            Text("Attic needs access to your photo library").font(Theme.title)
            Text("It looks at your photos on this Mac only. Turn on Attic under Privacy & Security › Photos, then reopen it.")
                .font(Theme.second).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
            }
            .buttonStyle(ActionButton(kind: .primary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

public struct AtticApp: App {
    @State private var model: AppModel
    private let thumbs: ThumbnailStoreBox

    public init() {
        let m = AppModel.live()
        _model = State(initialValue: m)
        thumbs = ThumbnailStoreBox(ThumbnailStore(source: m.source))
    }

    public var body: some Scene {
        WindowGroup("Attic") {
            RootView(model: model, thumbs: thumbs)
                .task { await model.start(); await Script.run(model) }
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }.keyboardShortcut("z").disabled(!model.canUndo)
            }
            CommandGroup(after: .newItem) {
                Button("Rescan Library") { Task { await model.rescan() } }.keyboardShortcut("r")
            }
            CommandMenu("Go") {
                ForEach(Array(AppModel.Section.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { model.section = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
        }
    }
}
