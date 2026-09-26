import Foundation
import Testing
@testable import AtticCore

// MARK: fixtures

let t0 = Date(timeIntervalSince1970: 1_750_000_000)

func vec(_ angle: Double, dims: Int = 8) -> [Float] {
    // Unit vectors on a circle: distance between angles a and b is 2 sin(|a-b|/2).
    var v = [Float](repeating: 0, count: dims)
    v[0] = Float(cos(angle)); v[1] = Float(sin(angle))
    return v
}

/// Angle giving a feature-print distance of `d`.
func angle(for d: Double) -> Double { 2 * asin(d / 2) }

func photo(_ id: String, _ angle: Double, at: TimeInterval = 0, w: Int = 4032, h: Int = 3024,
           hash: UInt64? = nil, fav: Bool = false, faces: Int = 0, faceMin: Double? = nil,
           aesthetic: Double? = 0.1, sharp: Double = 100, clipped: Double = 0.01,
           lat: Double? = nil, lon: Double? = nil, labels: [String: Double] = [:],
           screenshot: Bool = false, utility: Bool = false) -> Photo {
    Photo(asset: Asset(id: id, date: t0.addingTimeInterval(at), width: w, height: h, favorite: fav,
                       screenshot: screenshot, latitude: lat, longitude: lon),
          features: Features(print: vec(angle), dhash: hash ?? UInt64(truncatingIfNeeded: id.hashValue),
                             faces: faces, faceMin: faceMin, aesthetic: aesthetic, utility: utility,
                             sharpness: sharp, clipped: clipped, labels: labels))
}

// MARK: similarity and clustering

@Suite struct SimilarityRules {
    @Test func nearPairsFindsExactlyThePairsUnderTheLimit() {
        let prints = [vec(0), vec(angle(for: 0.3)), vec(angle(for: 1.2))]
        let pairs = Similarity.nearPairs(prints, limit: 0.5)
        #expect(pairs.count == 1)
        #expect(pairs[0].0 == 0 && pairs[0].1 == 1)
        #expect(abs(pairs[0].2 - 0.3) < 0.001)
    }

    @Test func nearPairsWorksAcrossBlocks() {
        // 600 photos in 300 identical pairs: blocks of 256 must not drop any.
        let prints = (0..<600).map { vec(Double($0 / 2) * 0.05) }
        let exact = Similarity.nearPairs(prints, limit: 0.01).filter { $0.2 < 0.001 }
        #expect(exact.count == 300)
    }

    @Test func aChainOfLookalikesDoesNotCollapseIntoOneGroup() {
        let prints = (0..<10).map { vec(Double($0) * 0.12) }
        let pairs = Similarity.nearPairs(prints, limit: 0.5)
        let d = { (i: Int, j: Int) in Similarity.distance(prints[i], prints[j]) }
        let groups = Clustering.averageLinkage(n: 10, edges: pairs, cut: 0.45, spread: 0.72, distance: d)
        #expect(groups.count > 1)
        for g in groups { for i in g { for j in g { #expect(d(i, j) < 0.72) } } }
    }
}

// MARK: grouping

@Suite struct GroupingRules {
    @Test func aResaveIsADuplicateEvenYearsApart() {
        let a = photo("orig", 0, hash: 0xFF00)
        let b = photo("resave", angle(for: 0.08), at: 86400 * 400, w: 1600, h: 1200, hash: 0xFF01)
        let r = Grouping.build([a, b], state: AtticState())
        #expect(r.duplicates.count == 1)
        #expect(r.duplicates[0].keeper == "orig")
        #expect(r.duplicates[0].reason.contains("full-size original"))
        #expect(r.retakes.isEmpty)
    }

    @Test func lookingAlikeWithoutMatchingPixelsIsNotADuplicate() {
        let a = photo("a", 0, hash: 0)
        let b = photo("b", angle(for: 0.1), at: 30, hash: ~0)
        let r = Grouping.build([a, b], state: AtticState())
        #expect(r.duplicates.isEmpty)
        #expect(r.retakes.count == 1)
    }

    @Test func closeInTimeLowersTheBarButDoesNotGate() {
        let a = photo("a", 0, hash: 0), b = photo("b", angle(for: 0.5), at: 60, hash: ~0)
        #expect(Grouping.build([a, b], state: AtticState()).retakes.count == 1)
        let c = photo("c", angle(for: 0.5), at: 86400 * 30, hash: ~0)
        #expect(Grouping.build([a, c], state: AtticState()).retakes.isEmpty)
        let d = photo("d", angle(for: 0.3), at: 86400 * 30, hash: ~0)
        #expect(Grouping.build([a, d], state: AtticState()).retakes.count == 1)
    }

    @Test func aGroupYouAlreadyDecidedIsNotShownAgain() {
        let a = photo("a", 0, hash: 0), b = photo("b", angle(for: 0.3), at: 20, hash: ~0)
        var s = AtticState()
        s.decisions = ["a": Decision(.keep, .keepAll), "b": Decision(.keep, .keepAll)]
        #expect(Grouping.build([a, b], state: s).retakes.isEmpty)
    }

    @Test func aNewShotJoiningKeptOnesIsShownWithThemMarked() {
        let a = photo("a", 0, hash: 0), b = photo("b", angle(for: 0.2), at: 20, hash: 1 << 40)
        let c = photo("c", angle(for: 0.25), at: 40, hash: ~0)
        var s = AtticState()
        s.decisions = ["a": Decision(.keep, .keepAll), "b": Decision(.keep, .keepAll)]
        let g = Grouping.build([a, b, c], state: s).retakes
        #expect(g.count == 1)
        #expect(g[0].reviewed == ["a", "b"])
    }

    @Test func shotsMarkedForDeletionDropOut() {
        let a = photo("a", 0, hash: 0), b = photo("b", angle(for: 0.3), at: 20, hash: ~0)
        var s = AtticState()
        s.decisions = ["b": Decision(.delete, .confirm)]
        #expect(Grouping.build([a, b], state: s).retakes.isEmpty)
    }

    @Test func duplicateLosersNeverReachTheRetakePass() {
        let a = photo("a", 0, hash: 0)
        let copy = photo("copy", angle(for: 0.05), at: 999_999, w: 800, h: 600, hash: 1)
        let retake = photo("r", angle(for: 0.3), at: 30, hash: ~0)
        let r = Grouping.build([a, copy, retake], state: AtticState())
        #expect(r.duplicates.count == 1)
        #expect(r.retakes.count == 1)
        #expect(!r.retakes[0].photos.map(\.id).contains("copy"))
    }
}

// MARK: ranking

@Suite struct RankingRules {
    @Test func theOriginalBeatsItsWhatsAppResave() {
        let r = Ranking.rank([photo("resave", 0, w: 1600, h: 1200, sharp: 140), photo("orig", 0)])
        #expect(r.keeper == "orig")
        #expect(r.reason.contains("full-size original"))
    }

    @Test func aFavouriteAlwaysWins() {
        let r = Ranking.rank([photo("a", 0, aesthetic: 0.9), photo("b", 0, fav: true, aesthetic: -0.5)])
        #expect(r.keeper == "b")
    }

    @Test func aBlinkLosesToOpenEyes() {
        let r = Ranking.rank([photo("blink", 0, faces: 2, faceMin: 0.1), photo("open", 0, faces: 2, faceMin: 0.8)])
        #expect(r.keeper == "open")
        #expect(r.flaws["blink"]?.contains("face") == true)
    }

    @Test func someoneMissingFromTheFrameCountsAgainstIt() {
        let r = Ranking.rank([photo("two", 0, faces: 2, faceMin: 0.6), photo("one", 0, faces: 1, faceMin: 0.7)])
        #expect(r.keeper == "two")
    }

    @Test func aTinyDifferenceIsACloseCallNotAWin() {
        let r = Ranking.rank([photo("a", 0), photo("b", 0, sharp: 101)])
        #expect(r.closeCall)
    }

    @Test func reasonsStayUnderFortyWordsWithoutEmDashes() {
        let r = Ranking.rank([photo("a", 0, w: 800, h: 600, faces: 1, faceMin: 0.2, clipped: 0.3),
                              photo("b", 0, faces: 1, faceMin: 0.9, sharp: 400)])
        #expect(r.reason.split(separator: " ").count < 40)
        #expect(!r.reason.contains("\u{2014}"))
    }
}

// MARK: events

@Suite struct EventRules {
    let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    func run(_ prefix: String, day: Int, n: Int = 3, lat: Double? = nil, lon: Double? = nil,
             labels: [String: Double] = [:]) -> [Photo] {
        (0..<n).map { photo("\(prefix)\($0)", Double($0), at: Double(day) * 86400 + Double($0) * 60,
                            hash: UInt64($0 + 1) << UInt64(abs(day) % 50), lat: lat, lon: lon, labels: labels) }
    }

    @Test func aLongGapStartsANewEvent() {
        let ps = run("a", day: 0) + run("b", day: 2)
        #expect(Events.split(ps, home: nil).count == 2)
    }

    @Test func daysAwayInOneRegionMergeIntoOneTrip() {
        let home = run("h", day: -30, n: 20, lat: 48.86, lon: 2.35)
        let trip = run("d1", day: 0, lat: 43.70, lon: 7.26) + run("d2", day: 1, lat: 43.71, lon: 7.27)
        let ps = (home + trip).sorted { $0.asset.date < $1.asset.date }
        let runs = Events.split(ps, home: Events.homeCell(ps))
        #expect(runs.count == 2)
        #expect(runs.last?.count == 6)
    }

    @Test func daysAtHomeDoNotMerge() {
        let ps = run("a", day: 0, lat: 48.86, lon: 2.35) + run("b", day: 1, lat: 48.86, lon: 2.35)
        #expect(Events.split(ps, home: Events.homeCell(ps)).count == 2)
    }

    @Test func anEventIsNamedByItsActivityAndDates() {
        let ps = run("b", day: 0, labels: ["beach": 0.8])
        let e = Events.build(ps, groups: .init(), state: AtticState(), calendar: utc)
        #expect(e.count == 1)
        #expect(e[0].activity == .beach)
        #expect(e[0].autoName.hasPrefix("Beach · "))
    }

    @Test func withoutAClearActivityTheNameIsTheDates() {
        let ps = run("x", day: 0)
        let e = Events.build(ps, groups: .init(), state: AtticState(), calendar: utc)
        #expect(e[0].activity == nil)
        #expect(!e[0].autoName.contains("·"))
    }

    @Test func placeNamesAreUsedOnlyWhenTurnedOn() {
        let ps = run("x", day: 0, labels: ["beach": 0.9])
        var s = AtticState()
        let id = Events.build(ps, groups: .init(), state: s, calendar: utc)[0].id
        s.placeNames[id] = "Nice"
        #expect(!Events.build(ps, groups: .init(), state: s, calendar: utc)[0].autoName.contains("Nice"))
        s.namePlaces = true
        #expect(Events.build(ps, groups: .init(), state: s, calendar: utc)[0].autoName.hasPrefix("Nice · "))
    }

    @Test func screenshotsDocumentsAndMarkedPhotosAreNeverCandidates() {
        let ok = run("ok", day: 0, n: 3)
        let bad = [photo("shot", 9, at: 100, screenshot: true), photo("doc", 9, at: 110, utility: true),
                   photo("gone", 9, at: 120)]
        var s = AtticState()
        s.decisions["gone"] = Decision(.delete, .confirm)
        let got = Events.eligible(ok + bad, groups: .init(), state: s).map(\.id)
        #expect(Set(got) == Set(ok.map(\.id)))
    }

    @Test func threeAreSuggestedAndAFavouriteIsAmongThem() {
        var ps = run("p", day: 0, n: 6)
        ps[5] = photo("fav", 5, at: 400, fav: true, aesthetic: -0.9)
        let e = Events.build(ps, groups: .init(), state: AtticState(), calendar: utc)[0]
        #expect(e.suggested.count == 3)
        #expect(e.suggested.contains("fav"))
    }

    @Test func datesReadNaturally() {
        let a = Date(timeIntervalSince1970: 1_775_174_400) // 3 Apr 2026 00:00 UTC
        #expect(Events.dates(a, a.addingTimeInterval(5 * 86400), calendar: utc) == "3–8 Apr 2026")
        #expect(Events.dates(a, a.addingTimeInterval(3600), calendar: utc) == "3 Apr 2026")
        #expect(Events.dates(a, a.addingTimeInterval(30 * 86400), calendar: utc) == "3 Apr – 3 May 2026")
    }
}

// MARK: export naming and state

@Suite struct ExportAndStateRules {
    @Test func nothingIsWrittenOutsideTheBestOfFolder() {
        let root = URL(fileURLWithPath: "/tmp/best-of")
        #expect(throws: ExportNaming.Outside.self) { try ExportNaming.inside(root, root.appendingPathComponent("../escape.jpg")) }
        #expect(throws: ExportNaming.Outside.self) { try ExportNaming.inside(root, URL(fileURLWithPath: "/tmp/best-offset/x.jpg")) }
        #expect((try? ExportNaming.inside(root, root.appendingPathComponent("2026-04-beach/x.jpg"))) != nil)
    }

    @Test func folderNamesAreReadableSlugs() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 1_775_174_400)
        #expect(ExportNaming.folder(start: d, name: "Nice · 3–8 Apr 2026", calendar: c) == "2026-04-nice-3-8-apr-2026")
        #expect(ExportNaming.slug("Weekend in Goa!") == "weekend-in-goa")
        #expect(!ExportNaming.file(date: d, id: "AB/L0/001", calendar: c).contains("/"))
    }

    @Test func stateSurvivesARoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/state.json")
        let store = StateStore(url: url)
        try store.update { $0.decisions["x/L0/001"] = Decision(.delete, .confirm); $0.namePlaces = true }
        let again = StateStore(url: url)
        #expect(again.state == store.state)
        #expect(again.state.marked == ["x/L0/001"])
    }

}
