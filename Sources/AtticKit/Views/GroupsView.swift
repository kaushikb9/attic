import AtticCore
import SwiftUI

/// Duplicates and Retakes: one card per group, keeper suggested, you decide.
/// Keys: j/k or ↓/↑ group, ←/→ shot, space keep/delete, return confirm,
/// a keep all, n not retakes, s skip, ⌘Z undo.
struct GroupsView: View {
    let kind: PhotoGroup.Kind
    @Bindable var model: AppModel
    @State private var current = 0
    @State private var shot = 0
    @State private var zoom: String?
    @FocusState private var focused: Bool

    var groups: [PhotoGroup] { model.visibleGroups(kind) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GroupsContent(kind: kind, model: model, current: current, shot: shot, zoom: $zoom, lazy: true,
                              select: { current = $0 })
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(characters: .init(charactersIn: "jkans "), phases: .down) { press in
                key(press.characters, proxy: proxy)
            }
            .onKeyPress(keys: [.downArrow, .upArrow, .leftArrow, .rightArrow, .return]) { press in
                switch press.key {
                case .downArrow: return key("j", proxy: proxy)
                case .upArrow: return key("k", proxy: proxy)
                case .leftArrow: shot = max(0, shot - 1); return .handled
                case .rightArrow: shot = min((current(of: groups)?.photos.count ?? 1) - 1, shot + 1); return .handled
                default: if let g = current(of: groups) { model.confirm(g) }; return .handled
                }
            }
        }
        .background(Theme.bg)
        .sheet(item: Binding(get: { zoom.map(ZoomID.init) }, set: { zoom = $0?.id })) { z in
            Zoomed(id: z.id).frame(minWidth: 800, minHeight: 600)
                .onTapGesture { zoom = nil }
        }
    }

    func current(of gs: [PhotoGroup]) -> PhotoGroup? { gs.indices.contains(current) ? gs[current] : nil }

    func key(_ c: String, proxy: ScrollViewProxy) -> KeyPress.Result {
        let gs = groups
        guard let g = current(of: gs) else { return .ignored }
        switch c {
        case "j": current = min(current + 1, gs.count - 1); shot = 0
        case "k": current = max(current - 1, 0); shot = 0
        case " ": if g.photos.indices.contains(shot) { model.toggle(g, g.photos[shot].id) }
        case "a": model.keepAll(g)
        case "n": if kind == .retakes { model.notRetakes(g) }
        case "s": model.skip(g)
        default: return .ignored
        }
        current = min(current, max(model.visibleGroups(kind).count - 1, 0))
        if let target = current(of: model.visibleGroups(kind)) { withAnimation(.snappy) { proxy.scrollTo(target.id, anchor: .center) } }
        return .handled
    }
}

/// The list itself, without scrolling or keys: the window wraps it in a
/// ScrollView, the snapshot renderer draws it whole.
struct GroupsContent: View {
    let kind: PhotoGroup.Kind
    @Bindable var model: AppModel
    var current = 0
    var shot = 0
    @Binding var zoom: String?
    var lazy = false
    var select: (Int) -> Void = { _ in }

    init(kind: PhotoGroup.Kind, model: AppModel, current: Int = 0, shot: Int = 0,
         zoom: Binding<String?> = .constant(nil), lazy: Bool = false, select: @escaping (Int) -> Void = { _ in }) {
        self.kind = kind; self.model = model; self.current = current; self.shot = shot
        _zoom = zoom; self.lazy = lazy; self.select = select
    }

    var groups: [PhotoGroup] { model.visibleGroups(kind) }

    var body: some View {
        Group {
            if lazy { LazyVStack(alignment: .leading, spacing: 0) { rows } } else { VStack(alignment: .leading, spacing: 0) { rows } }
        }
        .padding(.horizontal, 24).padding(.bottom, 60)
    }

    @ViewBuilder var rows: some View {
        header
        if groups.isEmpty {
            Text(kind == .duplicates ? "No duplicates left to review." : "No retakes left to review.")
                .font(Theme.second).foregroundStyle(Theme.muted).padding(.vertical, 40)
        }
        ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
            GroupCard(group: g, index: i, model: model, current: i == current,
                      focusedShot: i == current ? shot : nil, zoom: $zoom)
                .id(g.id)
                .onTapGesture { select(i) }
        }
    }

    var header: some View {
        let toDelete = groups.reduce(0) { $0 + $1.photos.count - model.keepSet($1).count }
        return HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(kind == .duplicates ? "Duplicates" : "Retakes").font(Theme.title).foregroundStyle(Theme.ink)
            Text("\(plural(groups.count, "group")) · \(toDelete) suggested to delete")
                .font(Theme.second).foregroundStyle(Theme.muted).monospacedDigit()
            Spacer()
            Text(kind == .retakes ? "j k group · ← → shot · space keep/delete · return confirm · a keep all · n not retakes · s skip"
                                  : "j k group · ← → shot · space keep/delete · return confirm · a keep all · s skip")
                .font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.head)
        }
        .padding(.vertical, 16)
    }
}


struct ZoomID: Identifiable { let id: String }

struct GroupCard: View {
    let group: PhotoGroup
    let index: Int
    @Bindable var model: AppModel
    let current: Bool
    let focusedShot: Int?
    @Binding var zoom: String?

    static let when: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy · HH:mm"; return f
    }()

    var span: String {
        let s = group.timeSpan
        if s < 60 { return "" }
        if s < 3600 { return " · over \(Int((s / 60).rounded())) min" }
        if s < 86400 * 2 { return " · over \(Int((s / 3600).rounded())) h" }
        return " · over \(Int((s / 86400).rounded())) days"
    }

    var body: some View {
        let keep = model.keepSet(group)
        let n = group.photos.count, del = n - keep.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(group.kind == .duplicates ? plural(n, "copy", "copies") : plural(n, "shot")).font(Theme.item).foregroundStyle(Theme.ink)
                Text(Self.when.string(from: group.photos[0].asset.date) + span)
                    .font(Theme.caption).foregroundStyle(Theme.muted).monospacedDigit()
                if group.kind == .retakes && group.datesDisagree {
                    Text("look match · dates disagree").font(Theme.caption).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).overlay(Capsule().stroke(Theme.line))
                }
            }
            Text(group.reason).font(Theme.second).foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(Array(group.photos.enumerated()), id: \.element.id) { i, p in
                    tile(p, i, keep.contains(p.id))
                }
            }
            HStack(spacing: 10) {
                Button(del == n ? "Mark all \(n) for deletion" : del == 0 ? "Keep all" : "Mark \(del) for deletion") {
                    model.confirm(group)
                }
                .buttonStyle(ActionButton(kind: del == n ? .danger : .primary))
                if del > 0 { Button("Keep all") { model.keepAll(group) }.buttonStyle(ActionButton()) }
                if group.kind == .retakes { Button("Not retakes") { model.notRetakes(group) }.buttonStyle(ActionButton()) }
                Button("Skip") { model.skip(group) }.buttonStyle(ActionButton())
            }
        }
        .padding(.vertical, 18).padding(.leading, 14)
        .overlay(alignment: .leading) { if current { Rectangle().fill(Theme.gold).frame(width: 3) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }

    func tile(_ p: Photo, _ i: Int, _ k: Bool) -> some View {
        let note = group.reviewed.contains(p.id) ? "kept before" : k ? nil : group.flaws[p.id]
        return VStack(alignment: .leading, spacing: 5) {
            Thumb(id: p.id)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .opacity(k ? 1 : 0.5)
                .onTapGesture { zoom = p.id }
                .accessibilityLabel("Shot \(i + 1)")
            HStack {
                Text("#\(i + 1)").font(Theme.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button(k ? "Keep" : "Delete") { model.toggle(group, p.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 1)
                    .foregroundStyle(k ? Theme.card : Theme.del)
                    .background(Capsule().fill(k ? Theme.gold : Theme.delSoft))
                    .accessibilityLabel(k ? "Keeping shot \(i + 1). Switch to delete" : "Deleting shot \(i + 1). Switch to keep")
            }
            if let note { Text(note).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(2) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(k ? Theme.goldSoft : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(k ? Theme.gold : .clear, lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focusedShot == i ? Theme.muted : .clear, lineWidth: 3).padding(-3))
    }
}
