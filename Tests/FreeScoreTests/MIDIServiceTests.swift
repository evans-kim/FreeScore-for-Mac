import AVFAudio
import PDFKit
import XCTest
@testable import FreeScore

final class MIDIServiceTests: XCTestCase {
    func testMIDIExportCanBeImportedAgain() throws {
        let note = ScoreNote(pitch: 64, startBeat: 1.25, durationBeats: 0.5,
                             originalStartBeat: 1.25, originalDurationBeats: 0.5)
        let document = ScoreDocument(title: "Roundtrip", tempo: 96,
                                     numerator: 3, denominator: 4,
                                     tracks: [ScoreTrack(name: "Piano", notes: [note])],
                                     sourceMIDI: nil)
        let data = try MIDIService.midiData(document: document, trackIndex: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let imported = try MIDIService.importFile(url)

        XCTAssertEqual(imported.tracks.count, 1)
        XCTAssertEqual(imported.tracks[0].notes.count, 1)
        XCTAssertEqual(imported.tracks[0].notes[0].pitch, 64)
        XCTAssertEqual(imported.tracks[0].notes[0].startBeat, 1.25, accuracy: 0.01)
        XCTAssertEqual(imported.tracks[0].notes[0].durationBeats, 0.5, accuracy: 0.01)
        XCTAssertEqual(imported.numerator, 3)
        XCTAssertEqual(imported.denominator, 4)
        XCTAssertEqual(imported.tempo, 96, accuracy: 0.1)
    }

    func testQuantizationKeepsPositiveDuration() {
        let note = ScoreNote(pitch: 60, startBeat: 0.11, durationBeats: 0.08,
                             originalStartBeat: 0.11, originalDurationBeats: 0.08)
        let result = ScoreGrid.sixteenth.quantize(note)
        XCTAssertEqual(result.startBeat, 0)
        XCTAssertEqual(result.durationBeats, 0.25)
        XCTAssertEqual(result.originalStartBeat, 0.11)
    }

    func testPlaybackMIDIKeepsSilentEndingMeasures() throws {
        let note = ScoreNote(pitch: 60, startBeat: 0, durationBeats: 1,
                             originalStartBeat: 0, originalDurationBeats: 1)
        let document = ScoreDocument(page: Page(), tempo: 120,
            tracks: [ScoreTrack(name: "Piano", notes: [note])], sourceMIDI: nil)
        let data = try MIDIService.midiData(document: document, trackIndex: 0,
                                            minimumDurationBeats: 12)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let sequencer = AVAudioSequencer()
        try sequencer.load(from: url)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sequencer.tracks.first).lengthInBeats, 12)
    }

    func testNavigationPlaybackPlanRendersInMIDIOrder() throws {
        let notes = (0..<5).map { bar in
            ScoreNote(pitch: 60 + bar, startBeat: Double(bar * 4), durationBeats: 1,
                      originalStartBeat: Double(bar * 4), originalDurationBeats: 1)
        }
        let marks = [NavigationMark(measure: 1, kind: .segno),
                     NavigationMark(measure: 2, kind: .fine),
                     NavigationMark(measure: 3, kind: .dalSegnoAlFine)]
        let page = Page()
        let plan = try RepeatPlaybackPlan(page: page, notes: notes, navigation: marks)
        let document = ScoreDocument(page: page, tempo: 120,
            tracks: [ScoreTrack(name: "Piano", notes: plan.expandedNotes(notes))], sourceMIDI: nil)
        let data = try MIDIService.midiData(document: document, trackIndex: 0,
                                            minimumDurationBeats: plan.totalBeats)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let imported = try MIDIService.importFile(url)
        XCTAssertEqual(imported.tracks[0].notes.map(\.pitch), [60, 61, 62, 63, 61, 62])
        XCTAssertEqual(imported.tracks[0].notes.map(\.startBeat), [0, 4, 8, 12, 16, 20])
    }

    @MainActor
    func testProvidedMIDIImportsAtAllGridResolutions() throws {
        guard let path = ProcessInfo.processInfo.environment["MIDI_TEST_FILE"] else {
            throw XCTSkip("MIDI_TEST_FILE 경로를 지정하면 제공된 MIDI로 가져오기를 확인합니다.")
        }
        let url = URL(fileURLWithPath: path)
        let source = try Data(contentsOf: url)
        XCTAssertFalse(source.isEmpty)
        for grid in ScoreGrid.allCases {
            let document = try MIDIService.importFile(url, grid: grid)
            XCTAssertFalse(document.tracks.isEmpty)
            XCTAssertGreaterThan(document.tracks.flatMap(\.notes).count, 0)
            XCTAssertEqual(document.sourceMIDI, source)
            for note in document.tracks.flatMap(\.notes) {
                XCTAssertEqual(grid.quantize(note.startBeat), note.startBeat, accuracy: 0.000001)
                XCTAssertGreaterThanOrEqual(note.durationBeats, grid.rawValue)
            }
        }
        let document = try MIDIService.importFile(url)
        let printSettings = [
            ScorePrintSettings(orientation: .landscape, sizing: .fitWidth),
            ScorePrintSettings(orientation: .portrait, sizing: .fitPage),
            ScorePrintSettings(orientation: .portrait, sizing: .custom, scalePercent: 150)
        ]
        for settings in printSettings {
            let printData = try ScorePrintRenderer.makePDF(document: document, trackIndex: 0,
                                                           settings: settings)
            let pdf = try XCTUnwrap(PDFDocument(data: printData))
            XCTAssertGreaterThan(pdf.pageCount, 0)
            XCTAssertEqual(try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox).size,
                           settings.paperSize)
        }
    }
}
