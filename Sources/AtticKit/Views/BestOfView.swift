import AtticCore
import SwiftUI

/// Best of: events by time, place and activity, three picks suggested each.
/// Nothing leaves Photos until you press Export on an event.
struct BestOfView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView { BestOfContent(model: model, lazy: true) }.background(Theme.bg)
    }
}

struct BestOfContent: View {
    @Bindable var model: AppModel
    var lazy = false

    var body: some View {
        Group {
            if lazy { LazyVStack(alignment: .leading, spacing: 0) { rows } } else { VStack(alignment: .leading, spacing: 0) { rows } }
        }
        .padding(.horizontal, 24).padding(.bottom, 60)
    }

    @ViewBuilder var rows: some View {
        header
        let evs = model.visibleEvents(model.eventFilter)
        if evs.isEmpty {
            Text(model.eventFilter == .todo ? "Every event is exported or skipped." : "Nothing here yet.")
                .font(Theme.second).foregroundStyle(Theme.muted).padding(.vertical, 40)
        }
        ForEach(evs) { e in EventCard(event: e, model: model) }
    }

    var header: some View {
        let exported = model.events.filter { model.status($0) == .exported }
        let files = exported.reduce(0) { $0 + (model.state.best[$1.id]?.files.count ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("Best of").font(Theme.title).foregroundStyle(Theme.ink)
                Text("\(plural(model.visibleEvents(.todo).count, "event")) to do · \(exported.count) exported · \(plural(files, "photo")) in \(model.exporter.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .font(Theme.second).foregroundStyle(Theme.muted).monospacedDigit()
                Spacer()
                Picker("Show", selection: $model.eventFilter) {
                    Text("To do").tag(AppModel.EventFilter.todo)
                    Text("Exported").tag(AppModel.EventFilter.exported)
                    Text("Skipped").tag(AppModel.EventFilter.skipped)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Toggle(isOn: Binding(get: { model.state.namePlaces },
                                 set: { on in Task { await model.setNamePlaces(on) } })) {
                Text("Name places with Apple Maps").font(Theme.second).foregroundStyle(Theme.ink)
                + Text("  sends each event's approximate location to Apple").font(Theme.caption).foregroundStyle(Theme.muted)
            }
            .toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 16)
    }
}

struct EventCard: View {
    let event: Event
    @Bindable var model: AppModel
    @State private var more = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let st = model.status(event)
        let on = model.picked(event)
        let busy = model.working.contains(event.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if editing {
                    TextField("Event name", text: $draft)
                        .textFieldStyle(.roundedBorder).font(Theme.item).frame(maxWidth: 340)
                        .focused($nameFocused)
                        .onSubmit { commit() }
                        .onExitCommand { editing = false }
                        .onChange(of: nameFocused) { _, f in if !f { commit() } }
                } else {
                    Button(model.name(event)) { draft = model.name(event); editing = true; nameFocused = true }
                        .buttonStyle(.plain).font(Theme.item).foregroundStyle(Theme.ink)
                        .help("Rename")
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).offset(y: 2) }
                }
                Text(meta).font(Theme.caption).foregroundStyle(Theme.muted)
            }
            if st == .skipped {
                HStack { Text("Skipped").font(Theme.second).foregroundStyle(Theme.muted)
                    Button("Reopen") { model.reopenEvent(event) }.buttonStyle(.plain).foregroundStyle(Theme.gold) }
            } else {
                if st == .exported, let b = model.state.best[event.id], let f = b.folder {
                    Text("Exported \(b.files.count) to \(f)").font(Theme.second).foregroundStyle(Theme.muted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                    ForEach(Array((more ? event.candidates : Array(event.candidates.prefix(6))).enumerated()), id: \.element.id) { i, p in
                        pick(p, i, on.contains(p.id))
                    }
                }
                HStack(spacing: 10) {
                    Button(busy ? "Exporting…" : st == .exported ? "Update export · \(on.count)" : "Export \(on.count) to best-of") {
                        Task { await model.export(event) }
                    }
                    .buttonStyle(ActionButton(kind: .primary)).disabled(on.isEmpty || busy)
                    if st == .todo { Button("Skip event") { model.skipEvent(event) }.buttonStyle(ActionButton()) }
                    if event.candidates.count > 6 {
                        Button(more ? "Show fewer" : "Show \(event.candidates.count - 6) more") { more.toggle() }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    var meta: String {
        [event.activity.map { $0.name }, plural(event.count, "photo"), event.away ? "away" : nil]
            .compactMap { $0 }.filter { !model.name(event).hasPrefix($0) }.joined(separator: " · ")
    }

    func commit() {
        guard editing else { return }
        editing = false
        Task { await model.rename(event, to: draft) }
    }

    func pick(_ p: Photo, _ i: Int, _ on: Bool) -> some View {
        Button { model.togglePick(event, p.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Thumb(id: p.id).clipShape(RoundedRectangle(cornerRadius: 5))
                    .opacity(on ? 1 : 0.55)
                HStack {
                    Text(p.asset.date.formatted(.dateTime.day().month(.abbreviated)) + (p.asset.favorite ? " · ♥" : ""))
                    Spacer()
                    if on { Text("✓").fontWeight(.semibold).foregroundStyle(Theme.gold) }
                }
                .font(Theme.caption).foregroundStyle(Theme.muted).padding(.horizontal, 2)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.goldSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Theme.gold : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo \(i + 1), \(on ? "picked" : "not picked")")
    }
}
