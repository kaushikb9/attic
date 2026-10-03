import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AtticCore
@testable import AtticKit

/// The app's flows, driven through AppModel exactly as the buttons drive it,
/// on the synthetic fixture library. No real photos, no Photos access.
@MainActor
struct Harness {
    let dir: URL
    let source: FolderSource
    let model: AppModel
    let best: URL

    init() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("attic-test-\(UUID().uuidString)")
        let lib = try Fixture.make(at: dir.appendingPathComponent("library"))
        source = FolderSource(dir: lib)
        best = dir.appendingPathComponent("best-of")
        model = AppModel(source: source, store: StateStore(url: dir.appendingPathComponent("home/state.json")),
                         analyzer: Analyzer(cacheURL: nil), exporter: Exporter(root: best),
                         summaryURL: dir.appendingPathComponent("home/last-run.json"))
        await model.start()
    }

    /// A second launch over the same state file.
    func relaunch() async -> AppModel {
        let m = AppModel(source: source, store: StateStore(url: dir.appendingPathComponent("home/state.json")),
                         analyzer: Analyzer(cacheURL: nil), exporter: Exporter(root: best))
        await m.start()
        return m
    }

    func files() -> [String] {
        (FileManager.default.enumerator(atPath: best.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".jpg") }.sorted()
    }
}

@MainActor @Suite struct ReviewFlows {
    @Test func theFixtureOpensWithOneDuplicateOneRetakeGroupAndABeachTrip() async throws {
        let h = try await Harness()
        #expect(h.model.phase == .ready)
        #expect(h.model.visibleGroups(.duplicates).count == 1)
        #expect(h.model.visibleGroups(.retakes).count == 1)
        #expect(h.model.visibleGroups(.retakes)[0].photos.count == 5)
        #expect(h.model.events.count == 1)
        #expect(h.model.events[0].autoName.hasPrefix("Beach · "))
    }

    @Test func theBlurredShotIsNotTheKeeperAndSaysWhy() async throws {
        let h = try await Harness()
        let g = h.model.visibleGroups(.retakes)[0]
        #expect(g.keeper != "RET3/L0/001")
        #expect(g.flaws["RET3/L0/001"]?.contains("face") == true)
    }

    @Test func confirmMarksTheRestAndTheGroupLeaves() async throws {
        let h = try await Harness()
        let g = h.model.visibleGroups(.retakes)[0]
        h.model.confirm(g)
        #expect(h.model.visibleGroups(.retakes).isEmpty)
        #expect(h.model.marked.count == 4)
        #expect(!h.model.marked.map(\.id).contains(g.keeper))
    }

    @Test func untickingEveryShotMarksTheWholeGroup() async throws {
        let h = try await Harness()
        let g = h.model.visibleGroups(.duplicates)[0]
        for p in g.photos where h.model.keepSet(g).contains(p.id) { h.model.toggle(g, p.id) }
        #expect(h.model.keepSet(g).isEmpty)
        h.model.confirm(g)
        #expect(h.model.marked.count == 2)
    }

    @Test func undoPutsTheGroupBack() async throws {
        let h = try await Harness()
        h.model.confirm(h.model.visibleGroups(.retakes)[0])
        #expect(h.model.canUndo)
        h.model.undo()
        #expect(h.model.visibleGroups(.retakes).count == 1)
        #expect(h.model.marked.isEmpty)
    }

    @Test func skipIsOneUndoAway() async throws {
        let h = try await Harness()
        h.model.skip(h.model.visibleGroups(.duplicates)[0])
        #expect(h.model.visibleGroups(.duplicates).isEmpty)
        #expect(h.model.message?.contains("⌘Z") == true)
        h.model.undo()
        #expect(h.model.visibleGroups(.duplicates).count == 1)
        #expect(h.model.message == nil)
    }

    @Test func aGroupLeavingTheViewSaysWhatHappened() async throws {
        let h = try await Harness()
        h.model.keepAll(h.model.visibleGroups(.duplicates)[0])
        #expect(h.model.message == "Kept all 2 · ⌘Z undoes")
        h.model.confirm(h.model.visibleGroups(.retakes)[0])
        #expect(h.model.message == "Marked 4 for deletion · ⌘Z undoes")
    }

    @Test func decisionsSurviveARelaunchButSkipDoesNot() async throws {
        let h = try await Harness()
        h.model.notRetakes(h.model.visibleGroups(.retakes)[0])
        h.model.skip(h.model.visibleGroups(.duplicates)[0])
        let again = await h.relaunch()
        #expect(again.visibleGroups(.retakes).isEmpty)
        #expect(again.visibleGroups(.duplicates).count == 1)
        #expect(again.state.decisions.values.contains { $0.source == .notRetakes })
    }

    @Test func deleteSendsOneBatchAndThePhotosAreGone() async throws {
        let h = try await Harness()
        h.model.confirm(h.model.visibleGroups(.retakes)[0])
        h.model.confirm(h.model.visibleGroups(.duplicates)[0])
        await h.model.deleteMarked()
        #expect(h.source.deleteCalls.count == 1)
        #expect(h.source.deleteCalls[0].count == 5)
        #expect(h.model.marked.isEmpty)
        #expect(h.model.message?.contains("Recently Deleted") == true)
        let again = await h.relaunch()
        #expect(again.photos.count == h.model.photos.count)
    }

    @Test func cancellingPhotosPromptDeletesNothingAndKeepsTheMarks() async throws {
        let h = try await Harness()
        h.model.confirm(h.model.visibleGroups(.retakes)[0])
        h.source.cancelNextDelete = true
        await h.model.deleteMarked()
        #expect(h.source.deleteCalls.isEmpty)
        #expect(h.model.marked.count == 4)
        #expect(h.model.message == nil)
    }

    @Test func keepInsteadUnmarksOnePhoto() async throws {
        let h = try await Harness()
        h.model.confirm(h.model.visibleGroups(.retakes)[0])
        h.model.unmark(h.model.marked[0].id)
        #expect(h.model.marked.count == 3)
    }

    @Test func theSummaryForAgentsHoldsCountsOnly() async throws {
        let h = try await Harness()
        let data = try Data(contentsOf: h.dir.appendingPathComponent("home/last-run.json"))
        let s = try JSONDecoder().decode([String: Int].self, from: data)
        #expect(s["photos"] == Fixture.specs.count)
        #expect(s["duplicate_groups"] == 1 && s["retake_groups"] == 1)
    }
}

@MainActor @Suite struct BestOfFlows {
    @Test func exportWritesOnlyTheTickedPhotosKeepingGPSButNotTheCamera() async throws {
        let h = try await Harness()
        let e = h.model.events[0]
        await h.model.export(e)
        #expect(h.model.message == nil)
        let files = h.files()
        #expect(files.count == 3)
        for f in files {
            let url = h.best.appendingPathComponent(f)
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
            let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
            #expect(gps[kCGImagePropertyGPSLatitude] != nil && gps[kCGImagePropertyGPSLongitude] != nil, "\(f) lost its GPS")
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            #expect(tiff[kCGImagePropertyTIFFMake] == nil && tiff[kCGImagePropertyTIFFModel] == nil, "\(f) kept camera")
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            #expect(exif[kCGImagePropertyExifDateTimeOriginal] != nil)
            #expect(exif[kCGImagePropertyExifLensModel] == nil && exif[kCGImagePropertyExifBodySerialNumber] == nil)
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, hgt = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            #expect(max(w, hgt) <= 2400 && max(w, hgt) > 0)
        }
        #expect(h.model.status(e) == .exported)
        #expect(FileManager.default.fileExists(atPath: h.best.appendingPathComponent("manifest.json").path))
    }

    @Test func theManifestNamesEventsAndLeavesCoordinatesToTheFiles() async throws {
        let h = try await Harness()
        await h.model.export(h.model.events[0])
        let m = try String(contentsOf: h.best.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(m.contains("Beach"))
        for word in ["latitude", "longitude", "gps", "7.26", "43.7"] { #expect(!m.lowercased().contains(word)) }
    }

    @Test func exportingAgainAddsNoDuplicatesAndUntickedPhotosLeave() async throws {
        let h = try await Harness()
        let e = h.model.events[0]
        await h.model.export(e)
        await h.model.export(e)
        #expect(h.files().count == 3)
        h.model.togglePick(e, e.suggested[0])
        await h.model.export(e)
        #expect(h.files().count == 2)
    }

    @Test func renamingAnExportedEventMovesItsFolder() async throws {
        let h = try await Harness()
        let e = h.model.events[0]
        await h.model.export(e)
        await h.model.rename(e, to: "Beach week with friends")
        #expect(Set(h.files().map { String($0.split(separator: "/")[0]) }) == ["2026-04-beach-week-with-friends"])
        #expect(h.model.name(e) == "Beach week with friends")
    }

    @Test func anEventNeedsATickedPhotoToExport() async throws {
        let h = try await Harness()
        let e = h.model.events[0]
        for id in h.model.picked(e) { h.model.togglePick(e, id) }
        await h.model.export(e)
        #expect(h.files().isEmpty)
        #expect(h.model.message?.contains("Tick at least one") == true)
    }

    @Test func skipAndReopen() async throws {
        let h = try await Harness()
        let e = h.model.events[0]
        h.model.skipEvent(e)
        #expect(h.model.visibleEvents(.skipped).count == 1)
        h.model.reopenEvent(e)
        #expect(h.model.visibleEvents(.todo).count == 1)
    }
}

@Suite struct OnDeviceAnalysis {
    @Test func visionRunsOnAPictureAndBlurLowersSharpness() throws {
        let sharp = Fixture.draw(scene: 7, shift: 0, w: 600, h: 450, blur: false)
        let blurred = Fixture.draw(scene: 7, shift: 0, w: 600, h: 450, blur: true)
        let a = try Analyzer.features(of: sharp), b = try Analyzer.features(of: blurred)
        #expect(a.print.count > 100)
        #expect(abs(a.print.reduce(0) { $0 + $1 * $1 } - 1) < 0.01)  // unit length
        #expect(a.sharpness > b.sharpness * 2)
        #expect(a.aesthetic != nil)
    }

    @Test func theSamePictureHasTheSameHashAndPrint() throws {
        let img = Fixture.draw(scene: 3, shift: 0, w: 400, h: 300, blur: false)
        let a = try Analyzer.features(of: img), b = try Analyzer.features(of: img)
        #expect(a.dhash == b.dhash)
        #expect(Similarity.distance(a.print, b.print) < 0.01)
    }

}
