import AppKit
import CoreText
import PDFKit
import XCTest
@testable import FreeScore

@MainActor
private final class NoteSoundSpy: NoteSoundPlaying {
    var pitches: [Int] = []
    var countInClicks = 0

    func playNote(pitch: Int, velocity: Int) { pitches.append(pitch) }
    func playCountInClick() { countInClicks += 1 }
}

private final class FlippedScrollTestView: NSView {
    override var isFlipped: Bool { true }
}

final class ScoreFeatureTests: XCTestCase {
    func testLegacyProjectLoadsIntoPageModel() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/edited-scale.mscore")
        let legacy = try JSONDecoder().decode(ScoreDocument.self, from: Data(contentsOf: file))
        XCTAssertEqual(legacy.page.title, "scale")
        XCTAssertEqual(legacy.page.measuresPerLine, 8)
        XCTAssertEqual(legacy.page.noteSpacing, 29)
        XCTAssertEqual(legacy.page.measureWidthRatio, 1)
        XCTAssertEqual(legacy.page.rowGap, 15)
        XCTAssertEqual(legacy.page.lyricFontName, "")
        XCTAssertEqual(legacy.page.lyricFontSize, 15)
        XCTAssertEqual(legacy.page.keySignature, .d)
        XCTAssertEqual(legacy.tracks[0].clef, .treble)
        XCTAssertEqual(legacy.tracks[0].notes[0].lyric, "")
        XCTAssertTrue(legacy.chordEvents.isEmpty)

        let encoded = try JSONEncoder().encode(legacy)
        let reloaded = try JSONDecoder().decode(ScoreDocument.self, from: encoded)
        XCTAssertEqual(reloaded, legacy)
    }

    @MainActor
    func testBeatChordsFollowKeyChangesAndPersistWithProject() throws {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        XCTAssertTrue(store.setChord(at: 0, text: "Cmaj7", followsKey: true))
        XCTAssertTrue(store.setChord(at: 480, text: "Fm", followsKey: true))
        XCTAssertTrue(store.setChord(at: 1920, text: "G7/B", followsKey: false))
        XCTAssertEqual(store.chord(at: 0)?.chord.symbol(in: .c), "Cmaj7")
        XCTAssertEqual(store.chord(at: 480)?.chord.symbol(in: .c), "Fm")
        XCTAssertEqual(store.chord(at: 1920)?.chord.symbol(in: .c), "G7/B")

        store.updatePage { $0.keySignature = .g }
        XCTAssertEqual(store.chord(at: 0)?.chord.symbol(in: .g), "Gmaj7")
        XCTAssertEqual(store.chord(at: 480)?.chord.symbol(in: .g), "Cm")
        XCTAssertEqual(store.chord(at: 1920)?.chord.symbol(in: .g), "G7/B")
        XCTAssertEqual(ScoreLayout(page: store.document.page, notes: [],
                                   chords: store.document.chordEvents).measureCount, 2)

        let decoded = try JSONDecoder().decode(ScoreDocument.self,
                                               from: JSONEncoder().encode(store.document))
        XCTAssertEqual(decoded.chordEvents, store.document.chordEvents)
        store.removeChord(at: 480)
        XCTAssertNil(store.chord(at: 480))
        store.undo()
        XCTAssertEqual(store.chord(at: 480)?.chord.symbol(in: .g), "Cm")
    }

    func testLegacyMeasureChordsMoveToFirstBeatOfTheirMeasures() throws {
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ScoreDocument(page: Page(keySignature: .g), tempo: 120,
                          tracks: [ScoreTrack(name: "피아노", notes: [])], sourceMIDI: nil)
        )) as? [String: Any])
        encoded.removeValue(forKey: "chordEvents")
        encoded["measureChords"] = ["0": ["tonicOffset": 0, "quality": "major"],
                                     "2": ["tonicOffset": 7, "quality": "dominantSeventh"]]
        let loaded = try JSONDecoder().decode(ScoreDocument.self,
                                              from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(loaded.chordEvents.map(\.positionTick), [0, 3840])
        XCTAssertEqual(loaded.chordEvents.map { $0.chord.symbol(in: .g) }, ["G", "D7"])
    }

    func testChordSuggestionsAndFreeTextSupport() throws {
        XCTAssertEqual(ChordSuggestions.diatonicTriads(in: .g),
                       ["G", "Am", "Bm", "C", "D", "Em", "F♯dim"])
        XCTAssertEqual(ChordSuggestions.matching("F#", in: .g), ["F♯dim"])
        XCTAssertEqual(ChordSymbol(text: "F#m", key: .g)?.symbol(in: .g), "F#m")
        XCTAssertEqual(ChordSymbol(text: "D/F#", key: .g)?.symbol(in: .g), "D/F#")
        XCTAssertEqual(ChordSymbol(text: "Cadd9", key: .g)?.symbol(in: .g), "Cadd9")
        XCTAssertNil(ChordSymbol(text: "G/H", key: .g))
        XCTAssertNil(ChordSymbol(text: "Hello", key: .g))
    }

    func testChordGridAdvancesByMeterBeatRatherThanNoteGrid() {
        let fourFour = Page(numerator: 4, denominator: 4)
        XCTAssertEqual((0..<5).map { ChordGrid.tick(measure: $0 / 4, slot: $0 % 4,
                                                   page: fourFour) },
                       [0, 480, 960, 1440, 1920])
        XCTAssertEqual(ChordGrid.snappedTick(beat: 2.1, measure: 0, page: fourFour), 960)
        XCTAssertEqual(ChordGrid.snappedTick(beat: 2.9, measure: 0, page: fourFour), 960)
        let sixEight = Page(numerator: 6, denominator: 8)
        XCTAssertEqual(ChordGrid.ticksPerSlot(sixEight), 240)
        XCTAssertEqual(ChordGrid.tick(measure: 1, slot: 0, page: sixEight), 1440)
        XCTAssertEqual(ChordGrid.slot(for: 1200, page: sixEight), 5)
        XCTAssertEqual(ChordGrid.next(1200, page: sixEight), 1440)
    }

    func testChordLaneHitTestingAndPageSpacing() {
        let compact = ScoreLayout(page: Page(measureWidthRatio: 1), notes: [])
        let spacious = ScoreLayout(page: Page(measureWidthRatio: 3), notes: [])
        XCTAssertGreaterThan(spacious.measureWidth(0), compact.measureWidth(0) * 2.9)
        let top = spacious.staffTop(row: 0)
        for slot in 0..<4 {
            let tick = ChordGrid.tick(measure: 0, slot: slot, page: spacious.page)
            let point = CGPoint(x: spacious.x(for: ChordGrid.beat(for: tick)) + 1,
                                y: top - 40)
            XCTAssertEqual(spacious.chordTick(at: point), tick)
            let rect = spacious.chordRect(for: tick)
            XCTAssertGreaterThan(rect.width, 50)
            XCTAssertEqual(spacious.chordTick(at: CGPoint(x: rect.maxX - 5,
                                                          y: top - 40)), tick)
        }
    }

    @MainActor
    func testMultipleBeatChordsRenderInPrintPDF() throws {
        let page = Page(measureWidthRatio: 2.5)
        let symbols = ["G", "Am", "D/F#", "Cadd9"]
        let events = try symbols.enumerated().map { index, symbol in
            ChordEvent(positionTick: index * 480,
                       chord: try XCTUnwrap(ChordSymbol(text: symbol, key: .g)))
        }
        var gPage = page
        gPage.keySignature = .g
        let document = ScoreDocument(page: gPage, tempo: 120,
                                     tracks: [ScoreTrack(name: "피아노", notes: [])],
                                     sourceMIDI: nil, chordEvents: events)
        let pdf = try XCTUnwrap(PDFDocument(data: ScorePrintRenderer.makePDF(
            document: document, trackIndex: 0)))
        let rendered = try XCTUnwrap(pdf.page(at: 0)?.string)
        for symbol in symbols { XCTAssertTrue(rendered.contains(symbol), symbol) }
    }

    @MainActor
    func testChordLabelsRemainCompleteWhenFirstNoteStartsLateInMeasure() throws {
        var page = Page(measuresPerLine: 2)
        page.keySignature = .g
        let notes = [2.0, 6.0].map { beat in
            ScoreNote(pitch: 67, startBeat: beat, durationBeats: 1,
                      originalStartBeat: beat, originalDurationBeats: 1)
        }
        let symbols = ["Bm7", "Dsus4"]
        let events = try symbols.enumerated().map { index, symbol in
            ChordEvent(positionTick: index * ChordGrid.ticksPerMeasure(page),
                       chord: try XCTUnwrap(ChordSymbol(text: symbol, key: .g)))
        }
        let document = ScoreDocument(page: page, tempo: 120,
                                     tracks: [ScoreTrack(name: "멜로디", notes: notes)],
                                     sourceMIDI: nil, chordEvents: events)
        let pdf = try XCTUnwrap(PDFDocument(data: ScorePrintRenderer.makePDF(
            document: document, trackIndex: 0)))
        let rendered = try XCTUnwrap(pdf.page(at: 0)?.string)
        for symbol in symbols { XCTAssertTrue(rendered.contains(symbol), rendered) }
    }

    func testChordSpellingFollowsDifficultKeySignatures() {
        XCTAssertEqual(MeasureChord.rootName(for: 5, in: .cSharp), "E♯")
        XCTAssertEqual(MeasureChord.rootName(for: 4, in: .cFlat), "F♭")
        XCTAssertEqual(MeasureChord.rootName(for: 10, in: .c), "B♭")
    }

    @MainActor
    func testPrintPDFUsesLandscapePagesAndKeepsRowsTogether() throws {
        let page = Page(title: "인쇄 확인", measuresPerLine: 2)
        let notes = (0..<8).map { index in
            let beat = Double(index) * 4
            return ScoreNote(pitch: 60, startBeat: beat, durationBeats: 1,
                             originalStartBeat: beat, originalDurationBeats: 1)
        }
        let document = ScoreDocument(
            page: page, tempo: 120,
            tracks: [ScoreTrack(name: "피아노", notes: notes)], sourceMIDI: nil,
            chordEvents: [ChordEvent(positionTick: 0,
                                     chord: try XCTUnwrap(ChordSymbol(text: "Cmaj7", key: .c)))]
        )
        let score = ScoreLayout(page: page, notes: notes, chords: document.chordEvents)
        let settings = ScorePrintSettings(orientation: .landscape, sizing: .custom,
                                          scalePercent: 100)
        let pagination = ScorePrintLayout(score: score, settings: settings)
        XCTAssertEqual(pagination.pageStarts.count, 2)
        XCTAssertEqual(pagination.pageStarts[0], 0)
        XCTAssertEqual(pagination.pageStarts[1], score.staffTop(row: 2) - 52)

        let data = try ScorePrintRenderer.makePDF(document: document, trackIndex: 0,
                                                   settings: settings)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, pagination.pageStarts.count)
        for index in 0..<pdf.pageCount {
            let size = try XCTUnwrap(pdf.page(at: index)).bounds(for: .mediaBox).size
            XCTAssertEqual(size.width, pagination.paperSize.width, accuracy: 1)
            XCTAssertEqual(size.height, pagination.paperSize.height, accuracy: 1)
        }
        if let path = ProcessInfo.processInfo.environment["MIDI_PRINT_PREVIEW_OUT"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    func testPrintOrientationAndScaleControlPagination() throws {
        let notes = (0..<8).map { index in
            let beat = Double(index) * 4
            return ScoreNote(pitch: 60, startBeat: beat, durationBeats: 1,
                             originalStartBeat: beat, originalDurationBeats: 1)
        }
        let document = ScoreDocument(page: Page(measuresPerLine: 2), tempo: 120,
                                     tracks: [ScoreTrack(name: "피아노", notes: notes)],
                                     sourceMIDI: nil)
        let score = ScoreLayout(page: document.page, notes: notes)
        let onePage = ScorePrintSettings(orientation: .portrait, sizing: .fitPage)
        let onePageLayout = ScorePrintLayout(score: score, settings: onePage)
        XCTAssertEqual(onePageLayout.pageCount, 1)
        let onePageData = try ScorePrintRenderer.makePDF(document: document, trackIndex: 0,
                                                       settings: onePage)
        let onePagePDF = try XCTUnwrap(PDFDocument(data: onePageData))
        XCTAssertEqual(onePagePDF.pageCount, 1)
        XCTAssertEqual(try XCTUnwrap(onePagePDF.page(at: 0)).bounds(for: .mediaBox).size,
                       onePage.paperSize)

        let enlarged = ScorePrintSettings(orientation: .portrait, sizing: .custom,
                                          scalePercent: 180)
        let enlargedLayout = ScorePrintLayout(score: score, settings: enlarged)
        XCTAssertEqual(enlargedLayout.scale, 1.8, accuracy: 0.001)
        XCTAssertGreaterThan(enlargedLayout.horizontalStarts.count, 1)
        XCTAssertGreaterThan(enlargedLayout.pageCount, onePageLayout.pageCount)
        let enlargedData = try ScorePrintRenderer.makePDF(document: document, trackIndex: 0,
                                                        settings: enlarged)
        let enlargedPDF = try XCTUnwrap(PDFDocument(data: enlargedData))
        XCTAssertEqual(enlargedPDF.pageCount, enlargedLayout.pageCount)
        for index in 0..<enlargedPDF.pageCount {
            XCTAssertEqual(try XCTUnwrap(enlargedPDF.page(at: index)).bounds(for: .mediaBox).size,
                           enlarged.paperSize)
        }
        if let folder = ProcessInfo.processInfo.environment["MIDI_PRINT_SAMPLES_DIR"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try onePageData.write(to: url.appendingPathComponent("portrait-fit-page.pdf"))
            try enlargedData.write(to: url.appendingPathComponent("portrait-180.pdf"))
        }
    }

    @MainActor
    func testPrintUsesPageMeasureCountAndRowGap() throws {
        var notes = (0..<8).map { index in
            ScoreNote(pitch: 60, startBeat: Double(index) * 4, durationBeats: 1,
                      originalStartBeat: Double(index) * 4, originalDurationBeats: 1)
        }
        notes[0].lyric = "가사"
        var page = Page(measuresPerLine: 2, rowGap: 0,
                        lyricFontName: "Apple SD Gothic Neo", lyricFontSize: 22)
        let track = ScoreTrack(name: "피아노", notes: notes)
        let settings = ScorePrintSettings(orientation: .portrait, sizing: .fitWidth)
        let compact = ScoreLayout(page: page, notes: notes)
        let compactPages = ScorePrintLayout(score: compact, settings: settings)
        XCTAssertEqual(compact.rows, 4)

        page.rowGap = 160
        let spacious = ScoreLayout(page: page, notes: notes)
        XCTAssertEqual(spacious.staffTop(row: 1) - compact.staffTop(row: 1), 160)
        XCTAssertGreaterThan(ScorePrintLayout(score: spacious, settings: settings).pageCount,
                             compactPages.pageCount)

        page.measuresPerLine = 4
        let fewerRows = ScoreLayout(page: page, notes: notes)
        XCTAssertEqual(fewerRows.rows, 2)
        let document = ScoreDocument(page: page, tempo: 120, tracks: [track], sourceMIDI: nil)
        let printed = try XCTUnwrap(PDFDocument(data:
            ScorePrintRenderer.makePDF(document: document, trackIndex: 0, settings: settings)))
        XCTAssertEqual(printed.pageCount,
                       ScorePrintLayout(score: fewerRows, settings: settings).pageCount)
        XCTAssertTrue(printed.string?.contains("가사") == true)
    }

    @MainActor
    func testPrintSettingsSurviveModeChangesAndAppRelaunch() throws {
        let suite = "MidiScorePrintTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }

        let store = ScoreStore(noteSound: NoteSoundSpy(), preferences: preferences)
        store.printSettings.orientation = .portrait
        store.printSettings.sizing = .custom
        store.printSettings.scalePercent = 145
        store.editorMode = .score
        store.editorMode = .printPreview
        XCTAssertEqual(store.printSettings.scalePercent, 145)

        let relaunched = ScoreStore(noteSound: NoteSoundSpy(), preferences: preferences)
        XCTAssertEqual(relaunched.printSettings, store.printSettings)
    }

    @MainActor
    func testRecentProjectsKeepFiveUniqueFilesAndOpenFromMenuPath() throws {
        let suite = "MidiScoreTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MidiScoreRecent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        let store = ScoreStore(noteSound: NoteSoundSpy(), preferences: preferences)
        let files = (0..<6).map { folder.appendingPathComponent("project-\($0).mscore") }
        for (index, file) in files.enumerated() {
            store.updatePage { $0.title = "프로젝트 \(index)" }
            store.saveProject(to: file)
        }
        XCTAssertEqual(store.recentProjects, Array(files.reversed().prefix(5)))

        store.openProject(at: files[2])
        XCTAssertEqual(store.document.title, "프로젝트 2")
        XCTAssertEqual(store.recentProjects, [files[2], files[5], files[4], files[3], files[1]])

        let relaunched = ScoreStore(noteSound: NoteSoundSpy(), preferences: preferences)
        XCTAssertEqual(relaunched.recentProjects, store.recentProjects)
        try FileManager.default.removeItem(at: files[2])
        relaunched.openProject(at: files[2])
        XCTAssertEqual(relaunched.recentProjects.count, 4)
        XCTAssertNotNil(relaunched.errorMessage)
    }

    func testMeasuresPerLineChangesScoreRows() {
        let note = ScoreNote(pitch: 60, startBeat: 15, durationBeats: 1,
                             originalStartBeat: 15, originalDurationBeats: 1)
        var page = Page()
        page.measuresPerLine = 8
        XCTAssertEqual(ScoreLayout(page: page, notes: [note]).rows, 1)
        page.measuresPerLine = 2
        XCTAssertEqual(ScoreLayout(page: page, notes: [note]).rows, 2)
    }

    func testScoreHeaderSpacingGrowsOnlyWithKeySignatureSymbols() {
        let plain = ScoreLayout(page: Page(keySignature: .c), notes: [])
        let oneSharp = ScoreLayout(page: Page(keySignature: .g), notes: [])
        let sevenSharps = ScoreLayout(page: Page(keySignature: .cSharp), notes: [])

        XCTAssertEqual(plain.keySignatureX, 76)
        XCTAssertEqual(plain.meterX, 75)
        XCTAssertEqual(oneSharp.meterX - plain.meterX, 14)
        XCTAssertEqual(sevenSharps.meterX - oneSharp.meterX, 6 * 14)
        XCTAssertEqual(plain.musicStart - plain.meterX, 37)
        XCTAssertLessThan(plain.musicStart, 120)
        XCTAssertLessThan(sevenSharps.musicStart, 220)

        let context = CGContext(data: nil, width: 300, height: 100,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func inkX(_ symbol: String, x: CGFloat, width: CGFloat, size: CGFloat,
                  weight: NSFont.Weight = .regular) -> ClosedRange<CGFloat> {
            let text = NSAttributedString(string: symbol, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight)
            ])
            let line = CTLineCreateWithAttributedString(text)
            let bounds = CTLineGetImageBounds(line, context)
            let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let start = x + (width - advance) / 2
            return (start + bounds.minX)...(start + bounds.maxX)
        }
        for clef in Clef.allCases {
            for key in [KeySignature.c, .g, .f, .cSharp, .cFlat] {
                let layout = ScoreLayout(page: Page(keySignature: key), notes: [], clef: clef)
                let clefInk = inkX(clef.symbol, x: layout.clefX, width: 48,
                                   size: clef == .treble ? 62 : 50)
                let meterInk = inkX("4", x: layout.meterX, width: 28, size: 21,
                                    weight: .bold)
                if key.accidentalCount == 0 {
                    XCTAssertEqual(meterInk.lowerBound - clefInk.upperBound, 6,
                                   accuracy: 2, "\(clef.label), \(key.label)")
                } else {
                    let accidental = key.isFlat ? "♭" : "♯"
                    let first = inkX(accidental, x: layout.keySignatureX,
                                     width: 22, size: 25)
                    let last = inkX(accidental,
                                    x: layout.keySignatureX + CGFloat(key.accidentalCount - 1) * 14,
                                    width: 22, size: 25)
                    XCTAssertEqual(first.lowerBound - clefInk.upperBound, 6,
                                   accuracy: 2, "\(clef.label), \(key.label)")
                    XCTAssertEqual(meterInk.lowerBound - last.upperBound, 6,
                                   accuracy: 2, "\(clef.label), \(key.label)")
                }
            }
        }
    }

    func testScoreStopsAtLastOccupiedMeasureEvenWhenPlaybackMovesPastIt() {
        let note = ScoreNote(pitch: 60, startBeat: 4, durationBeats: 1,
                             originalStartBeat: 4, originalDurationBeats: 1)
        let layout = ScoreLayout(page: Page(measuresPerLine: 8), notes: [note],
                                 playbackBeat: 40)
        XCTAssertEqual(layout.measureCount, 2)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.barsInRow(0), 2)
        XCTAssertEqual(layout.rowWidth(0), layout.measureWidth(0) + layout.measureWidth(1))
        XCTAssertEqual(layout.row(for: 40), 0)
        XCTAssertNil(layout.measureIndex(at: CGPoint(x: layout.measureStartX(2) + 10,
                                                       y: layout.staffTop(row: 0) - 15)))
        XCTAssertEqual(ScoreLayout(page: Page(), notes: []).measureCount, 1)
    }

    func testPageNoteSpacingSeparatesCloseNotesAndSurvivesProjectSave() throws {
        let notes = (0..<3).map { index in
            ScoreNote(pitch: 60 + index, startBeat: Double(index) * 0.125,
                      durationBeats: 0.125, originalStartBeat: Double(index) * 0.125,
                      originalDurationBeats: 0.125)
        }
        let compact = ScoreLayout(page: Page(noteSpacing: 29), notes: notes)
        let spacious = ScoreLayout(page: Page(noteSpacing: 58), notes: notes)
        XCTAssertGreaterThanOrEqual(compact.x(for: 0.125) - compact.x(for: 0), 29)
        XCTAssertGreaterThanOrEqual(spacious.x(for: 0.125) - spacious.x(for: 0), 58)
        XCTAssertGreaterThan(spacious.x(for: 0.25) - spacious.x(for: 0),
                             compact.x(for: 0.25) - compact.x(for: 0))
        XCTAssertEqual(spacious.beat(at: CGPoint(x: spacious.x(for: 0.125),
                                                y: spacious.staffTop(row: 0))), 0.125,
                       accuracy: 0.0001)

        let document = ScoreDocument(page: Page(noteSpacing: 45, measureWidthRatio: 1.35),
                                     tempo: 120, tracks: [ScoreTrack(name: "피아노", notes: notes)],
                                     sourceMIDI: nil)
        let loaded = try JSONDecoder().decode(ScoreDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(loaded.page.noteSpacing, 45)
        XCTAssertEqual(loaded.page.measureWidthRatio, 1.35)
    }

    func testMeasureWidthRatioChangesBarWidthWithoutChangingNoteSpacing() {
        let notes = (0..<4).map { index in
            ScoreNote(pitch: 60, startBeat: Double(index), durationBeats: 1,
                      originalStartBeat: Double(index), originalDurationBeats: 1)
        }
        let tight = ScoreLayout(page: Page(noteSpacing: 18, measureWidthRatio: 0.75), notes: notes)
        let loose = ScoreLayout(page: Page(noteSpacing: 18, measureWidthRatio: 1.5), notes: notes)
        XCTAssertGreaterThan(loose.measureWidth(0), tight.measureWidth(0))
        XCTAssertGreaterThan(loose.x(for: 3) - loose.x(for: 0),
                             tight.x(for: 3) - tight.x(for: 0))
        XCTAssertGreaterThanOrEqual(tight.x(for: 1) - tight.x(for: 0), 18)
    }

    func testRowsShareMidpointWidthWhileCrowdedMeasureKeepsItsProportion() {
        let page = Page(measuresPerLine: 2)
        let notes = (0..<8).map { index in
            ScoreNote(pitch: 60, startBeat: Double(index) * 0.5, durationBeats: 0.5,
                      originalStartBeat: Double(index) * 0.5, originalDurationBeats: 0.5)
        } + [ScoreNote(pitch: 60, startBeat: 8, durationBeats: 1,
                       originalStartBeat: 8, originalDurationBeats: 1)]
        let layout = ScoreLayout(page: page, notes: notes)
        XCTAssertEqual(layout.measureCount, 3)
        XCTAssertEqual(layout.barsInRow(1), 1)
        XCTAssertGreaterThan(layout.naturalRowWidth(0), layout.naturalRowWidth(1))
        XCTAssertEqual(layout.alignedRowWidth,
                       (layout.naturalRowWidth(0) + layout.naturalRowWidth(1)) / 2)
        XCTAssertEqual(layout.rowWidth(0), layout.rowWidth(1))
        XCTAssertEqual(layout.rowWidth(0), layout.measureWidth(0) + layout.measureWidth(1),
                       accuracy: 0.0001)
        XCTAssertEqual(layout.rowWidth(1), layout.measureWidth(2))
        XCTAssertGreaterThan(layout.measureWidth(0), layout.measureWidth(1))
        XCTAssertLessThan(layout.measureWidth(0), 256)
        XCTAssertGreaterThan(layout.measureWidth(2), 112)
        XCTAssertEqual(layout.measureStartX(2), layout.musicStart)
        XCTAssertEqual(layout.measureStartX(3), layout.musicStart + layout.alignedRowWidth)
    }

    func testAlignedRowsScalePageSpacingAndPreserveBeatHitTesting() {
        let page = Page(measuresPerLine: 2, noteSpacing: 45, measureWidthRatio: 1.4)
        let starts: [Double] = [0, 0.125, 0.25, 1, 4, 5, 8, 12]
        let notes = starts.map { beat in
            ScoreNote(pitch: 60, startBeat: beat, durationBeats: 0.125,
                      originalStartBeat: beat, originalDurationBeats: 0.125)
        }
        let layout = ScoreLayout(page: page, notes: notes)
        let firstRow = ScoreLayout(page: page, notes: notes.filter { $0.startBeat < 8 })
        let scale = layout.alignedRowWidth / layout.naturalRowWidth(0)

        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.rowWidth(0), layout.rowWidth(1), accuracy: 0.0001)
        XCTAssertEqual(layout.measureWidth(0), firstRow.measureWidth(0) * scale,
                       accuracy: 0.0001)
        XCTAssertEqual(layout.x(for: 0.125) - layout.x(for: 0),
                       (firstRow.x(for: 0.125) - firstRow.x(for: 0)) * scale,
                       accuracy: 0.0001)
        for beat in starts {
            let point = CGPoint(x: layout.x(for: beat),
                                y: layout.staffTop(row: layout.row(for: beat)))
            XCTAssertEqual(layout.beat(at: point), beat, accuracy: 0.0001)
        }
    }

    func testKeySignatureSpellingAndAccidentalReset() {
        let notes = [
            ScoreNote(pitch: 66, startBeat: 0, durationBeats: 1, originalStartBeat: 0, originalDurationBeats: 1),
            ScoreNote(pitch: 65, startBeat: 1, durationBeats: 1, originalStartBeat: 1, originalDurationBeats: 1),
            ScoreNote(pitch: 65, startBeat: 2, durationBeats: 1, originalStartBeat: 2, originalDurationBeats: 1),
            ScoreNote(pitch: 65, startBeat: 4, durationBeats: 1, originalStartBeat: 4, originalDurationBeats: 1)
        ]
        let marks = ScoreNotation.accidentals(for: notes, page: Page(keySignature: .d))
        XCTAssertNil(marks[notes[0].id])
        XCTAssertEqual(marks[notes[1].id], "♮")
        XCTAssertNil(marks[notes[2].id])
        XCTAssertEqual(marks[notes[3].id], "♮")
        XCTAssertEqual(NotatedPitch.spell(70, in: .bFlat).letter, 6)
        XCTAssertEqual(NotatedPitch.spell(65, in: .cSharp).letter, 2)
        XCTAssertEqual(NotatedPitch.spell(70, in: .bFlat).name, "B♭4")
    }

    func testBeamGroupsFollowSimpleAndCompoundBeats() {
        let notes = (0..<6).map { index in
            ScoreNote(pitch: 60 + index, startBeat: Double(index) * 0.5, durationBeats: 0.5,
                      originalStartBeat: Double(index) * 0.5, originalDurationBeats: 0.5)
        }
        let simple = ScoreNotation.beamGroups(for: notes, page: Page())
        XCTAssertEqual(simple.map(\.count), [2, 2, 2])
        let compound = ScoreNotation.beamGroups(for: notes, page: Page(numerator: 6, denominator: 8))
        XCTAssertEqual(compound.map(\.count), [3, 3])
        XCTAssertEqual(ScoreNotation.beamLevel(for: 0.375), 2)
        XCTAssertEqual(ScoreNotation.beamLevel(for: 0.125), 3)
    }

    func testNotesCrossingBarsBecomeTiedDisplaySegmentsWithoutChangingSource() {
        let source = ScoreNote(pitch: 61, startBeat: 3, durationBeats: 6,
                               originalStartBeat: 3, originalDurationBeats: 6,
                               lyric: "가")
        let segments = ScoreNotation.displayNotes(for: [source], page: Page())
        XCTAssertEqual(segments.map { $0.note.startBeat }, [3, 4, 8])
        XCTAssertEqual(segments.map { $0.note.durationBeats }, [1, 4, 1])
        XCTAssertEqual(segments.map(\.tiedFromPrevious), [false, true, true])
        XCTAssertEqual(segments.map(\.tiedToNext), [true, true, false])
        XCTAssertEqual(segments.map(\.showsLyric), [true, false, false])
        XCTAssertTrue(segments.allSatisfy { $0.sourceID == source.id })
        XCTAssertEqual(source.durationBeats, 6)
    }

    func testHyphenLyricConnectsToPreviousOnsetAndHandlesSplitNotes() {
        let first = ScoreNote(pitch: 60, startBeat: 3, durationBeats: 4,
                              originalStartBeat: 3, originalDurationBeats: 4, lyric: "가")
        let second = ScoreNote(pitch: 64, startBeat: 5, durationBeats: 1,
                               originalStartBeat: 5, originalDurationBeats: 1, lyric: " - ")
        let third = ScoreNote(pitch: 67, startBeat: 6, durationBeats: 1,
                              originalStartBeat: 6, originalDurationBeats: 1, lyric: "나")
        let segments = ScoreNotation.displayNotes(for: [third, second, first], page: Page())
        let slurs = ScoreNotation.lyricSlurs(for: segments)
        XCTAssertEqual(slurs.count, 1)
        XCTAssertEqual(slurs[0].fromID, first.id)
        XCTAssertEqual(slurs[0].toID, second.id)
        XCTAssertEqual(slurs[0].from.startBeat, 4)
        XCTAssertEqual(slurs[0].to.startBeat, 5)
        XCTAssertEqual(slurs[0].from.pitch, 60)
        XCTAssertEqual(slurs[0].to.pitch, 64)
        XCTAssertTrue(ScoreNotation.lyricSlurs(for: ScoreNotation.displayNotes(
            for: [second], page: Page())).isEmpty)
    }

    func testRestsCoverOnlySilentTimeAndUseWholeMeasureForEmptyBars() {
        let notes = [
            ScoreNote(pitch: 60, startBeat: 0, durationBeats: 1,
                      originalStartBeat: 0, originalDurationBeats: 1),
            ScoreNote(pitch: 64, startBeat: 0.5, durationBeats: 1,
                      originalStartBeat: 0.5, originalDurationBeats: 1),
            ScoreNote(pitch: 67, startBeat: 2.5, durationBeats: 2,
                      originalStartBeat: 2.5, originalDurationBeats: 2)
        ]
        let rests = ScoreNotation.rests(for: notes, page: Page(), measureCount: 3)
        XCTAssertEqual(rests, [
            ScoreRest(startBeat: 1.5, durationBeats: 0.5, wholeMeasure: false),
            ScoreRest(startBeat: 2, durationBeats: 0.5, wholeMeasure: false),
            ScoreRest(startBeat: 4.5, durationBeats: 0.5, wholeMeasure: false),
            ScoreRest(startBeat: 5, durationBeats: 1, wholeMeasure: false),
            ScoreRest(startBeat: 6, durationBeats: 2, wholeMeasure: false),
            ScoreRest(startBeat: 8, durationBeats: 4, wholeMeasure: true)
        ])
    }

    func testThreeFourEmptyMeasureUsesOneWholeMeasureRest() {
        let rests = ScoreNotation.rests(for: [], page: Page(numerator: 3, denominator: 4),
                                        measureCount: 1)
        XCTAssertEqual(rests, [ScoreRest(startBeat: 0, durationBeats: 3,
                                         wholeMeasure: true)])
    }

    func testSixEightGapUsesDottedQuarterRestAtPulseBoundary() {
        let note = ScoreNote(pitch: 60, startBeat: 1.5, durationBeats: 1.5,
                             originalStartBeat: 1.5, originalDurationBeats: 1.5)
        let rests = ScoreNotation.rests(for: [note],
                                        page: Page(numerator: 6, denominator: 8), measureCount: 1)
        XCTAssertEqual(rests, [ScoreRest(startBeat: 0, durationBeats: 1.5,
                                         wholeMeasure: false)])
    }

    func testMeasureNumberMapsToPlaybackStart() {
        let page = Page(measuresPerLine: 2, numerator: 3, denominator: 4)
        let note = ScoreNote(pitch: 60, startBeat: 9, durationBeats: 1,
                             originalStartBeat: 9, originalDurationBeats: 1)
        let layout = ScoreLayout(page: page, notes: [note])
        let number = CGPoint(x: layout.measureStartX(3) + 10,
                             y: layout.staffTop(row: 1) - 15)
        XCTAssertEqual(layout.measureIndex(at: number), 3)
        XCTAssertEqual(layout.playbackX(for: 9), layout.measureStartX(3))
        XCTAssertNil(layout.measureIndex(at: CGPoint(x: number.x, y: number.y + 30)))
    }

    @MainActor
    func testPlaybackCueUsesCurrentMeter() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.seekToMeasure(2)
        XCTAssertEqual(store.playbackStartBeat, 8)
        XCTAssertEqual(store.visiblePlaybackBeat, 8)
        store.updatePage { $0.numerator = 3 }
        XCTAssertEqual(store.playbackStartBeat, 6)
    }

    @MainActor
    func testEmptyTrackPlaybackMovesGuideWithoutMIDIPlayerError() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.seekToBeat(2.25)
        store.play()
        XCTAssertTrue(store.isPlaying)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.playbackBeat, 2.25)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertGreaterThan(store.playbackBeat ?? 0, 2.25)
        store.seekToBeat(4)
        XCTAssertEqual(store.playbackBeat, 4)
        store.play()
        XCTAssertFalse(store.isPlaying)
        XCTAssertNil(store.playbackBeat)
        XCTAssertGreaterThanOrEqual(store.visiblePlaybackBeat ?? 0, 4)
        XCTAssertEqual(store.playbackStartBeat, store.visiblePlaybackBeat)
    }

    @MainActor
    func testPlaybackResumesAtStoppedPosition() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.seekToBeat(1)
        store.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        store.stop()
        let pausedBeat = store.visiblePlaybackBeat!
        XCTAssertGreaterThan(pausedBeat, 1)
        XCTAssertNil(store.playbackBeat)

        store.play()
        XCTAssertEqual(store.playbackBeat!, pausedBeat, accuracy: 0.000001)
        store.stop()
    }

    @MainActor
    func testPlaybackScrollFollowerCentersBothAxesAndMovesSmoothly() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = FlippedScrollTestView(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        scrollView.documentView = canvas
        let focus = CGPoint(x: 600, y: 500)
        XCTAssertTrue(PlaybackScrollFollower.center(focus, in: canvas, smoothly: false))
        let viewport = scrollView.contentView.bounds.size
        XCTAssertEqual(scrollView.contentView.bounds.origin.x,
                       focus.x - viewport.width / 2, accuracy: 1)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y,
                       focus.y - viewport.height / 2, accuracy: 1)

        scrollView.contentView.scroll(to: .zero)
        XCTAssertTrue(PlaybackScrollFollower.center(focus, in: canvas, smoothly: true))
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
        XCTAssertLessThan(scrollView.contentView.bounds.origin.x,
                          focus.x - viewport.width / 2)
    }

    @MainActor
    func testPlaybackScrollFollowerKeepsVerticalBoundaryWithoutExtraPadding() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = FlippedScrollTestView(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        scrollView.documentView = canvas
        XCTAssertTrue(PlaybackScrollFollower.center(
            CGPoint(x: 600, y: 20), in: canvas, smoothly: false))
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 0, accuracy: 0.001)

        let bottom = canvas.bounds.maxY - scrollView.contentView.bounds.height
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: bottom))
        XCTAssertTrue(PlaybackScrollFollower.center(
            CGPoint(x: 700, y: 880), in: canvas, smoothly: false))
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, bottom, accuracy: 0.001)
    }

    @MainActor
    func testPlaybackScrollFollowerKeepsHorizontalBoundaryWithoutExtraPadding() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = FlippedScrollTestView(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        scrollView.documentView = canvas
        XCTAssertTrue(PlaybackScrollFollower.center(
            CGPoint(x: 20, y: 500), in: canvas, smoothly: false))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.001)

        let right = canvas.bounds.maxX - scrollView.contentView.bounds.width
        scrollView.contentView.scroll(to: CGPoint(x: right, y: 400))
        XCTAssertTrue(PlaybackScrollFollower.center(
            CGPoint(x: 980, y: 500), in: canvas, smoothly: false))
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, right, accuracy: 0.001)
    }

    @MainActor
    func testPianoRollPlaybackFollowerKeepsVerticalScrollPosition() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = FlippedScrollTestView(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        scrollView.documentView = canvas
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 300))
        let originalY = scrollView.contentView.bounds.origin.y

        XCTAssertTrue(PlaybackScrollFollower.center(
            CGPoint(x: 600, y: 800), in: canvas, smoothly: true, axes: .horizontal
        ))
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, originalY, accuracy: 0.001)

        XCTAssertTrue(PlaybackScrollFollower.center(
            CGPoint(x: 700, y: 0), in: canvas, smoothly: false, axes: .horizontal
        ))
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, originalY, accuracy: 0.001)
    }

    @MainActor
    func testEnteringPianoRollCentersGuideOnceWithoutChangingVerticalScroll() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = PianoRollView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        canvas.playbackBeat = 10
        scrollView.documentView = canvas
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 250))
        canvas.centerGuideOnEntryIfNeeded()
        XCTAssertEqual(scrollView.contentView.bounds.origin.x,
                       PianoRollLayout(notes: [], page: Page()).x(10) - 110, accuracy: 1)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 250, accuracy: 1)

        let centeredX = scrollView.contentView.bounds.origin.x
        canvas.playbackBeat = 12
        canvas.centerGuideOnEntryIfNeeded()
        canvas.followPlaybackGuide()
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, centeredX, accuracy: 0.001)
    }

    @MainActor
    func testEnteringScoreCentersGuideOnBothAxes() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = StaffView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        let note = ScoreNote(pitch: 60, startBeat: 16, durationBeats: 1,
                             originalStartBeat: 16, originalDurationBeats: 1)
        canvas.notes = [note]
        canvas.playbackBeat = 16
        scrollView.documentView = canvas
        canvas.centerGuideOnEntryIfNeeded()

        let layout = ScoreLayout(page: canvas.page, notes: canvas.notes, playbackBeat: 16)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x,
                       layout.playbackX(for: 16) - 110, accuracy: 1)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y,
                       layout.staffTop(row: layout.row(for: 16)) + 44 - 90, accuracy: 1)
    }

    @MainActor
    func testPianoRollSeekDoesNotScrollUntilPlaybackStarts() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        let canvas = PianoRollView(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        scrollView.documentView = canvas
        canvas.centerGuideOnEntryIfNeeded()
        scrollView.contentView.scroll(to: CGPoint(x: 100, y: 250))
        let original = scrollView.contentView.bounds.origin

        canvas.playbackBeat = 10
        canvas.followPlaybackGuide()
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, original.x, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, original.y, accuracy: 0.001)

        canvas.isPlaying = true
        canvas.followPlaybackGuide()
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, original.x)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, original.y, accuracy: 0.001)
    }

    func testProjectPersistsPageClefAndLyrics() throws {
        var page = Page(title: "노래", composer: "작곡", arranger: "편곡", keySignature: .aFlat,
                        measuresPerLine: 6, numerator: 6, denominator: 8,
                        rowGap: 64, lyricFontName: "Apple SD Gothic Neo", lyricFontSize: 22)
        page.measuresPerLine = 6
        let note = ScoreNote(pitch: 60, startBeat: 0, durationBeats: 1,
                             originalStartBeat: 0, originalDurationBeats: 1,
                             lyric: "안녕하세요")
        let document = ScoreDocument(page: page, tempo: 88,
                                     tracks: [ScoreTrack(name: "보컬", notes: [note], clef: .bass)],
                                     sourceMIDI: nil)
        let loaded = try JSONDecoder().decode(ScoreDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(loaded, document)
        XCTAssertEqual(loaded.tracks[0].notes[0].lyric, "안녕하세요")
        XCTAssertEqual(loaded.page.keySignature, .aFlat)
        XCTAssertEqual(loaded.page.rowGap, 64)
        XCTAssertEqual(loaded.page.lyricFontName, "Apple SD Gothic Neo")
        XCTAssertEqual(loaded.page.lyricFontSize, 22)
    }

    @MainActor
    func testLyricEntryAdvancesOneNote() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.addNote(at: 0, pitch: 60)
        let first = store.selectedNoteID
        store.addNote(at: 1, pitch: 62)
        let second = store.selectedNoteID
        store.selectedNoteID = first
        store.assignLyricAndAdvance("가")
        XCTAssertEqual(store.selectedTrack?.notes.first?.lyric, "가")
        XCTAssertEqual(store.selectedNoteID, second)
    }

    @MainActor
    func testMultiSelectionEditsAndNotePlaybackCue() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.addNote(at: 0, pitch: 60)
        let first = store.selectedNoteID!
        store.addNote(at: 1, pitch: 62)
        let second = store.selectedNoteID!
        store.selectNotes([first, second])
        store.nudgeSelection(.right, shift: false)
        XCTAssertEqual(store.selectedTrack?.notes.map(\.startBeat), [0.25, 1.25])
        store.nudgeSelection(.up, shift: true)
        store.nudgeSelection(.left, shift: true)
        XCTAssertEqual(store.selectedTrack?.notes.map(\.startBeat), [0, 1])
        XCTAssertEqual(store.selectedTrack?.notes.map(\.durationBeats), [1.25, 1.25])
        store.seekToNote(second)
        XCTAssertEqual(store.playbackStartBeat, 1)
        store.deleteSelected()
        XCTAssertTrue(store.selectedTrack?.notes.isEmpty ?? false)
    }

    @MainActor
    func testPasteOffsetsCopiedNotesFromPlaybackGuide() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = ScoreStore(pasteboard: pasteboard, noteSound: NoteSoundSpy())
        store.addNote(at: 0, pitch: 60)
        let first = store.selectedNoteID!
        store.addNote(at: 1, pitch: 62)
        let second = store.selectedNoteID!
        store.selectNotes([first, second])
        store.copySelectedNotes()
        store.seekToMeasure(1)
        store.pasteNotes()
        XCTAssertEqual(store.selectedTrack?.notes.count, 4)
        XCTAssertEqual(store.selectedTrack?.notes.filter { store.selectedNoteIDs.contains($0.id) }
            .map(\.startBeat), [4, 5])
        XCTAssertFalse(store.selectedNoteIDs.contains(first))
        XCTAssertFalse(store.selectedNoteIDs.contains(second))
    }

    @MainActor
    func testPianoRollClickCueUsesGridAndPastePosition() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = ScoreStore(pasteboard: pasteboard, noteSound: NoteSoundSpy())
        store.grid = .thirtySecond
        store.addNote(at: 0, pitch: 60)
        store.copySelectedNotes()
        store.seekToBeat(2.19)
        XCTAssertEqual(store.playbackStartBeat, 2.25)
        XCTAssertEqual(store.visiblePlaybackBeat, 2.25)
        store.pasteNotes()
        XCTAssertEqual(store.selectedNote?.startBeat, 2.25)
        store.seekToMeasure(1)
        XCTAssertEqual(store.playbackStartBeat, 4)
    }

    @MainActor
    func testPianoRollCuePrecedesNoteOnsetWithoutMovingPasteGrid() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = ScoreStore(pasteboard: pasteboard, noteSound: NoteSoundSpy())
        store.grid = .thirtySecond
        store.addNote(at: 2.25, pitch: 60)
        let noteID = store.selectedNoteID!
        store.copySelectedNotes()

        store.seekToPianoRollBeat(2.19)
        XCTAssertEqual(try XCTUnwrap(store.playbackStartBeat), 2.23, accuracy: 0.000_001)
        XCTAssertEqual(store.visiblePlaybackBeat, store.playbackStartBeat)
        store.pasteNotes()
        XCTAssertEqual(store.selectedNote?.startBeat, 2.25)

        store.seekToPianoRollNote(noteID)
        XCTAssertEqual(try XCTUnwrap(store.playbackStartBeat), 2.23, accuracy: 0.000_001)
        store.seekToPianoRollBeat(0)
        XCTAssertEqual(store.playbackStartBeat, 0)
    }

    @MainActor
    func testMergeAndSplitSelectedSamePitchNotes() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.addNote(at: 0, pitch: 60)
        let first = store.selectedNoteID!
        store.addNote(at: 1, pitch: 60)
        let second = store.selectedNoteID!
        store.addNote(at: 2, pitch: 62)
        store.selectNotes([first, second])
        store.seekToNote(second)
        store.mergeSelectedNotes()
        XCTAssertEqual(store.selectedTrack?.notes.count, 2)
        XCTAssertEqual(store.selectedTrack?.notes.first?.id, first)
        XCTAssertEqual(store.selectedTrack?.notes.first?.durationBeats, 2)
        XCTAssertEqual(store.playbackStartBeat, 0)
        store.splitSelectedNotes()
        let parts = store.selectedTrack!.notes.filter { $0.pitch == 60 }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.map(\.startBeat), [0, 1])
        XCTAssertEqual(parts.map(\.durationBeats), [1, 1])
        XCTAssertEqual(store.selectedNoteIDs.count, 2)
        store.undo()
        XCTAssertEqual(store.selectedTrack?.notes.count, 2)
    }

    func testFourQuantizationChoices() {
        let note = ScoreNote(pitch: 60, startBeat: 0.38, durationBeats: 0.72,
                             originalStartBeat: 0.38, originalDurationBeats: 0.72)
        XCTAssertEqual(ScoreGrid.allCases.count, 4)
        XCTAssertEqual(ScoreGrid.quarter.quantize(note).startBeat, 0)
        XCTAssertEqual(ScoreGrid.eighth.quantize(note).startBeat, 0.5)
        XCTAssertEqual(ScoreGrid.sixteenth.quantize(note).startBeat, 0.5)
        XCTAssertEqual(ScoreGrid.thirtySecond.quantize(note).startBeat, 0.375)
    }

    @MainActor
    func testQuantizationChangesOnlySelectedNotes() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.grid = .thirtySecond
        store.addNote(at: 0.375, pitch: 60, duration: 0.72)
        let selectedID = store.selectedNoteID!
        store.addNote(at: 1.375, pitch: 62, duration: 0.72)
        let untouchedID = store.selectedNoteID!
        let untouchedBefore = store.selectedTrack!.notes.first { $0.id == untouchedID }!
        store.selectNotes([selectedID])

        store.grid = .quarter
        store.quantizeTrack()

        let selected = store.selectedTrack!.notes.first { $0.id == selectedID }!
        XCTAssertEqual(selected.startBeat, 0)
        XCTAssertEqual(selected.durationBeats, 1)
        XCTAssertEqual(store.selectedTrack!.notes.first { $0.id == untouchedID }, untouchedBefore)
        XCTAssertEqual(store.selectedNoteIDs, [selectedID])
        store.undo()
        XCTAssertEqual(store.selectedTrack!.notes.first { $0.id == selectedID }?.startBeat, 0.375)
        XCTAssertEqual(store.selectedTrack!.notes.first { $0.id == untouchedID }, untouchedBefore)
    }

    @MainActor
    func testSelectedMelodyQuantizationUsesButDoesNotEditUnselectedNeighbor() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.grid = .thirtySecond
        store.addNote(at: 0.375, pitch: 60, duration: 0.5)
        let firstID = store.selectedNoteID!
        store.addNote(at: 1.375, pitch: 62, duration: 0.7)
        let middleID = store.selectedNoteID!
        store.addNote(at: 2.375, pitch: 64, duration: 0.5)
        let lastID = store.selectedNoteID!
        let middleBefore = store.selectedTrack!.notes.first { $0.id == middleID }!
        store.selectNotes([firstID, lastID])

        store.grid = .quarter
        store.melodyMode = true
        store.quantizeTrack()

        let notes = store.selectedTrack!.notes
        let first = notes.first { $0.id == firstID }!
        let last = notes.first { $0.id == lastID }!
        XCTAssertEqual(first.startBeat, 0)
        XCTAssertEqual(first.durationBeats, middleBefore.startBeat)
        XCTAssertEqual(last.startBeat, 2)
        XCTAssertEqual(last.durationBeats, 1)
        XCTAssertEqual(notes.first { $0.id == middleID }, middleBefore)
    }

    @MainActor
    func testPianoRollSelectAllIncludesEveryNote() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.addNote(at: 0, pitch: 60)
        store.addNote(at: 1, pitch: 62)
        store.selectNotes([])
        store.selectAllNotes()
        XCTAssertTrue(store.selectedNoteIDs.isEmpty)
        store.editorMode = .pianoRoll
        store.selectAllNotes()
        XCTAssertEqual(store.selectedNoteIDs, Set(store.selectedTrack!.notes.map(\.id)))
        XCTAssertEqual(store.selectedNoteIDs.count, 2)
    }

    @MainActor
    func testMelodyQuantizationFillsGapsAndTrimsOverlapsAtNextStart() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.grid = .eighth
        store.addNote(at: 0, pitch: 60, duration: 2)
        store.addNote(at: 0, pitch: 64, duration: 1.5)
        store.addNote(at: 1, pitch: 62, duration: 0.5)
        store.addNote(at: 2, pitch: 65, duration: 0.5)
        store.selectNotes([])
        store.melodyMode = true
        store.quantizeTrack()
        let notes = store.selectedTrack!.notes
        XCTAssertEqual(notes.filter { $0.startBeat == 0 }.map(\.durationBeats), [1, 1])
        XCTAssertEqual(notes.first(where: { $0.startBeat == 1 })?.durationBeats, 1)
        XCTAssertEqual(notes.first(where: { $0.startBeat == 2 })?.durationBeats, 0.5)
        store.undo()
        XCTAssertEqual(store.selectedTrack!.notes.first(where: { $0.pitch == 60 })?.durationBeats, 2)
    }

    @MainActor
    func testRecordedC4NoteShowsPreviewAndCommitsOnRelease() {
        let store = ScoreStore(noteSound: NoteSoundSpy())
        store.beginRecordedNote(at: 0.37)
        XCTAssertEqual(store.recordingPreview?.pitch, 60)
        XCTAssertEqual(store.displayedNotes.count, 1)
        store.finishRecordedNote(at: 1.13)
        XCTAssertNil(store.recordingPreview)
        XCTAssertEqual(store.selectedTrack?.notes.count, 1)
        XCTAssertEqual(store.selectedNote?.pitch, 60)
        XCTAssertEqual(store.selectedNote!.startBeat, 0.37, accuracy: 0.000001)
        XCTAssertEqual(store.selectedNote!.durationBeats, 0.76, accuracy: 0.000001)
        store.undo()
        XCTAssertTrue(store.selectedTrack?.notes.isEmpty ?? false)
    }

    @MainActor
    func testRecordingStartsPlaybackAndFinishesHeldNoteWhenStopped() {
        let sound = NoteSoundSpy()
        let store = ScoreStore(noteSound: sound)
        store.toggleRecording()
        XCTAssertTrue(store.isCountingIn)
        XCTAssertFalse(store.isRecording)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.countInDuration, 2)
        XCTAssertEqual(sound.countInClicks, 1)
        store.beginRecordedNote()
        XCTAssertNil(store.recordingPreview)
        for expectedClick in 2...4 {
            store.advanceMetronomeTick()
            XCTAssertTrue(store.isCountingIn)
            XCTAssertEqual(sound.countInClicks, expectedClick)
        }
        store.advanceMetronomeTick()
        XCTAssertFalse(store.isCountingIn)
        XCTAssertTrue(store.isRecording)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(sound.countInClicks, 5)
        store.advanceMetronomeTick()
        XCTAssertEqual(sound.countInClicks, 6)
        XCTAssertEqual(store.editorMode, .pianoRoll)
        store.beginRecordedNote()
        XCTAssertNotNil(store.recordingPreview)
        store.toggleRecording()
        XCTAssertFalse(store.isRecording)
        XCTAssertFalse(store.isPlaying)
        XCTAssertNil(store.recordingPreview)
        XCTAssertEqual(store.selectedTrack?.notes.count, 1)
        store.advanceMetronomeTick()
        XCTAssertEqual(sound.countInClicks, 6)
    }

    @MainActor
    func testCountInUsesCurrentTempoAndCanBeCancelled() {
        let sound = NoteSoundSpy()
        let store = ScoreStore(noteSound: sound)
        store.setTempo(60)
        store.updatePage { $0.numerator = 3 }
        XCTAssertEqual(store.metronomeInterval, 1)
        XCTAssertEqual(store.countInDuration, 3)
        store.toggleRecording()
        XCTAssertTrue(store.isCountingIn)
        XCTAssertEqual(sound.countInClicks, 1)
        store.toggleRecording()
        XCTAssertFalse(store.isCountingIn)
        XCTAssertFalse(store.isRecording)
        XCTAssertFalse(store.isPlaying)
        store.completeCountIn()
        XCTAssertFalse(store.isRecording)
    }

    @MainActor
    func testSixEightCountInUsesSixEighthNotes() {
        let sound = NoteSoundSpy()
        let store = ScoreStore(noteSound: sound)
        store.updatePage {
            $0.numerator = 6
            $0.denominator = 8
        }
        XCTAssertEqual(store.metronomeInterval, 0.25)
        XCTAssertEqual(store.countInDuration, 1.5)
        store.toggleRecording()
        for _ in 0..<5 { store.advanceMetronomeTick() }
        XCTAssertEqual(sound.countInClicks, 6)
        XCTAssertTrue(store.isCountingIn)
        store.advanceMetronomeTick()
        XCTAssertTrue(store.isRecording)
        XCTAssertEqual(sound.countInClicks, 7)
        store.stop()
    }

    @MainActor
    func testAddingAndMovingNotesPlaysTheirPitch() {
        let sound = NoteSoundSpy()
        let store = ScoreStore(noteSound: sound)
        store.addNote(at: 0, pitch: 60)
        XCTAssertEqual(sound.pitches, [60])
        store.updateSelected { $0.pitch = 62 }
        XCTAssertEqual(sound.pitches, [60, 62])
        store.nudgeSelection(.right, shift: false)
        XCTAssertEqual(sound.pitches, [60, 62, 62])
        store.updateSelected { $0.durationBeats = 2 }
        XCTAssertEqual(sound.pitches, [60, 62, 62])
        store.addNote(at: 2, pitch: 65)
        XCTAssertEqual(sound.pitches.last, 65)
    }

    func testFourLyricVersesRoundTripAndLegacyDefault() throws {
        var note = ScoreNote(pitch: 60, startBeat: 0, durationBeats: 1,
                             originalStartBeat: 0, originalDurationBeats: 1, lyric: "첫")
        note.setLyric("넷", for: 4)
        XCTAssertEqual((1...4).map { note.lyric(for: $0) }, ["첫", "", "", "넷"])
        let decoded = try JSONDecoder().decode(ScoreNote.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(decoded, note)
        note.setLyric("", for: 4)
        XCTAssertTrue(note.additionalLyrics.isEmpty)

        let legacyURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/edited-scale.mscore")
        let legacy = try JSONDecoder().decode(ScoreDocument.self, from: Data(contentsOf: legacyURL))
        XCTAssertTrue(legacy.repeatSections.isEmpty)
        XCTAssertEqual(legacy.tracks[0].notes[0].lyric(for: 4), "")
    }

    func testRepeatPlaybackWithFirstAndSecondEndings() throws {
        let page = Page()
        let notes = (0..<4).map { bar in
            ScoreNote(pitch: 60 + bar, startBeat: Double(bar * 4), durationBeats: 1,
                      originalStartBeat: Double(bar * 4), originalDurationBeats: 1)
        }
        let repeatSection = RepeatSection(startMeasure: 0, endMeasure: 2,
            firstEndingStartMeasure: 2, secondEndingEndMeasure: 3)
        let plan = try RepeatPlaybackPlan(page: page, notes: notes, repeats: [repeatSection])
        XCTAssertEqual(plan.scoreMeasures, [0, 1, 2, 0, 1, 3])
        XCTAssertEqual((0..<6).map { plan.scoreBeat(at: Double($0 * 4)) },
                       [0, 4, 8, 0, 4, 12])
        XCTAssertEqual(plan.expandedNotes(notes).map(\.pitch), [60, 61, 62, 60, 61, 63])
        XCTAssertEqual(plan.expandedNotes(notes).map(\.startBeat), [0, 4, 8, 12, 16, 20])
        XCTAssertEqual(plan.performanceBeat(for: 12), 20)
        let document = ScoreDocument(page: page, tempo: 120,
            tracks: [ScoreTrack(name: "노래", notes: notes)], sourceMIDI: nil,
            repeatSections: [repeatSection])
        XCTAssertEqual(try JSONDecoder().decode(ScoreDocument.self,
            from: JSONEncoder().encode(document)).repeatSections, [repeatSection])
    }

    func testRepeatValidationAndPrintBrackets() throws {
        let page = Page(measuresPerLine: 2)
        let section = RepeatSection(startMeasure: 0, endMeasure: 2,
            firstEndingStartMeasure: 2, secondEndingEndMeasure: 3)
        XCTAssertThrowsError(try RepeatPlaybackPlan.validate([
            section, RepeatSection(startMeasure: 3, endMeasure: 4,
                firstEndingStartMeasure: nil, secondEndingEndMeasure: nil)]))
        let layout = ScoreLayout(page: page, notes: [], repeats: [section])
        XCTAssertEqual(layout.measureCount, 4)
        let document = ScoreDocument(page: page, tempo: 120,
            tracks: [ScoreTrack(name: "노래", notes: [])], sourceMIDI: nil,
            repeatSections: [section])
        let pdf = try XCTUnwrap(PDFDocument(data: ScorePrintRenderer.makePDF(
            document: document, trackIndex: 0)))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("1."))
        XCTAssertTrue(text.contains("2."))
    }

    func testRepeatTrimsNotesAtJumpAndSimpleRepeatPlaysTwice() throws {
        let crossing = ScoreNote(pitch: 60, startBeat: 3, durationBeats: 3,
                                 originalStartBeat: 3, originalDurationBeats: 3)
        let next = ScoreNote(pitch: 62, startBeat: 8, durationBeats: 1,
                             originalStartBeat: 8, originalDurationBeats: 1)
        let section = RepeatSection(startMeasure: 0, endMeasure: 0,
            firstEndingStartMeasure: nil, secondEndingEndMeasure: nil)
        let plan = try RepeatPlaybackPlan(page: Page(), notes: [crossing, next],
            repeats: [section])
        XCTAssertEqual(plan.scoreMeasures, [0, 0, 1, 2])
        let expanded = plan.expandedNotes([crossing, next])
        XCTAssertEqual(expanded.map(\.startBeat), [3, 7, 12])
        XCTAssertEqual(expanded.map(\.durationBeats), [1, 3, 1])
    }

    func testDaCapoAndDalSegnoPlaybackRoutes() throws {
        let notes = (0..<8).map { bar in
            ScoreNote(pitch: 60 + bar, startBeat: Double(bar * 4), durationBeats: 1,
                      originalStartBeat: Double(bar * 4), originalDurationBeats: 1)
        }
        func route(_ marks: [NavigationMark]) throws -> [Int] {
            try RepeatPlaybackPlan(page: Page(), notes: notes, navigation: marks).scoreMeasures
        }
        XCTAssertEqual(try route([NavigationMark(measure: 5, kind: .daCapo)]),
                       [0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(try route([NavigationMark(measure: 1, kind: .segno),
                                  NavigationMark(measure: 5, kind: .dalSegno)]),
                       [0, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(try route([NavigationMark(measure: 2, kind: .fine),
                                  NavigationMark(measure: 5, kind: .daCapoAlFine)]),
                       [0, 1, 2, 3, 4, 5, 0, 1, 2])
        XCTAssertEqual(try route([NavigationMark(measure: 1, kind: .segno),
                                  NavigationMark(measure: 3, kind: .fine),
                                  NavigationMark(measure: 5, kind: .dalSegnoAlFine)]),
                       [0, 1, 2, 3, 4, 5, 1, 2, 3])
        let codaMarks = [NavigationMark(measure: 1, kind: .segno),
                         NavigationMark(measure: 3, kind: .toCoda),
                         NavigationMark(measure: 5, kind: .dalSegnoAlCoda),
                         NavigationMark(measure: 6, kind: .coda)]
        XCTAssertEqual(try route(codaMarks), [0, 1, 2, 3, 4, 5, 1, 2, 3, 6, 7])
        XCTAssertEqual(try route([NavigationMark(measure: 2, kind: .toCoda),
                                  NavigationMark(measure: 5, kind: .daCapoAlCoda),
                                  NavigationMark(measure: 6, kind: .coda)]),
                       [0, 1, 2, 3, 4, 5, 0, 1, 2, 6, 7])
        let plan = try RepeatPlaybackPlan(page: Page(), notes: notes, navigation: codaMarks)
        XCTAssertEqual(plan.expandedNotes(notes).map(\.pitch),
                       [60, 61, 62, 63, 64, 65, 61, 62, 63, 66, 67])
        XCTAssertEqual(plan.scoreBeat(at: 9 * 4), 6 * 4)
        XCTAssertEqual(plan.performanceBeat(for: 6 * 4), 9 * 4)
        let linear = try RepeatPlaybackPlan(page: Page(), notes: notes,
            navigation: codaMarks, playRepeats: false)
        XCTAssertEqual(linear.scoreMeasures, Array(0..<8))
    }

    func testNavigationAfterVoltasSkipsFirstEndingOnReturn() throws {
        let section = RepeatSection(startMeasure: 0, endMeasure: 2,
            firstEndingStartMeasure: 2, secondEndingEndMeasure: 3)
        let marks = [NavigationMark(measure: 4, kind: .daCapo)]
        let plan = try RepeatPlaybackPlan(page: Page(), notes: [], repeats: [section],
                                           navigation: marks)
        XCTAssertEqual(plan.scoreMeasures, [0, 1, 2, 0, 1, 3, 4, 0, 1, 3, 4])
        XCTAssertEqual(ScoreLayout(page: Page(), notes: [], repeats: [section],
                                   navigation: marks).measureCount, 5)
    }

    func testNavigationValidationAndLegacyProjectMigration() throws {
        XCTAssertThrowsError(try RepeatPlaybackPlan.validate(repeats: [],
            navigation: [NavigationMark(measure: 3, kind: .dalSegno)]))
        XCTAssertThrowsError(try RepeatPlaybackPlan.validate(repeats: [],
            navigation: [NavigationMark(measure: 3, kind: .daCapoAlFine)]))
        XCTAssertThrowsError(try RepeatPlaybackPlan.validate(repeats: [],
            navigation: [NavigationMark(measure: 3, kind: .daCapoAlCoda)]))
        XCTAssertThrowsError(try RepeatPlaybackPlan.validate(repeats: [],
            navigation: [NavigationMark(measure: 0, kind: .segno),
                         NavigationMark(measure: 2, kind: .toCoda),
                         NavigationMark(measure: 3, kind: .dalSegnoAlCoda),
                         NavigationMark(measure: 1, kind: .coda)]))
        XCTAssertThrowsError(try RepeatPlaybackPlan.validate(repeats: [],
            navigation: [NavigationMark(measure: 3, kind: .daCapo),
                         NavigationMark(measure: 4, kind: .dalSegno)]))
        let document = ScoreDocument(page: Page(), tempo: 120,
            tracks: [ScoreTrack(name: "노래", notes: [])], sourceMIDI: nil,
            navigationMarks: [NavigationMark(measure: 1, kind: .segno)])
        XCTAssertEqual(try JSONDecoder().decode(ScoreDocument.self,
            from: JSONEncoder().encode(document)).navigationMarks, document.navigationMarks)
        let oldURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/edited-scale.mscore")
        XCTAssertTrue(try JSONDecoder().decode(ScoreDocument.self,
            from: Data(contentsOf: oldURL)).navigationMarks.isEmpty)
    }

    @MainActor
    func testNavigationMarksAppearInPrintedScore() throws {
        let marks = [NavigationMark(measure: 0, kind: .segno),
                     NavigationMark(measure: 1, kind: .toCoda),
                     NavigationMark(measure: 2, kind: .dalSegnoAlCoda),
                     NavigationMark(measure: 3, kind: .coda)]
        let document = ScoreDocument(page: Page(measuresPerLine: 2), tempo: 120,
            tracks: [ScoreTrack(name: "노래", notes: [])], sourceMIDI: nil,
            navigationMarks: marks)
        let pdf = try XCTUnwrap(PDFDocument(data: ScorePrintRenderer.makePDF(
            document: document, trackIndex: 0)))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        for label in ["Segno", "To Coda", "D.S. al Coda", "Coda"] {
            XCTAssertTrue(text.contains(label), label)
        }
    }

    @MainActor
    func testAllFourVersesAppearInPrint() throws {
        var note = ScoreNote(pitch: 60, startBeat: 0, durationBeats: 1,
                             originalStartBeat: 0, originalDurationBeats: 1, lyric: "첫째")
        note.setLyric("둘째", for: 2)
        note.setLyric("셋째", for: 3)
        note.setLyric("넷째", for: 4)
        let document = ScoreDocument(page: Page(), tempo: 120,
            tracks: [ScoreTrack(name: "노래", notes: [note])], sourceMIDI: nil)
        let pdf = try XCTUnwrap(PDFDocument(data: ScorePrintRenderer.makePDF(
            document: document, trackIndex: 0)))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        for lyric in ["첫째", "둘째", "셋째", "넷째"] {
            XCTAssertTrue(text.contains(lyric), lyric)
        }
    }
}
