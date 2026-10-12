import AppKit
import AVFAudio
import SwiftUI
import UniformTypeIdentifiers

enum EditorMode: String, CaseIterable, Identifiable {
    case score = "악보"
    case pianoRoll = "피아노 롤"
    case printPreview = "인쇄"
    var id: String { rawValue }
}

enum LyricMode: String {
    case single = "한 글자"
    case multiple = "여러 글자"
}

enum NoteEditEdge: String {
    case start = "앞단"
    case end = "뒷단"
}

enum NoteKeyDirection: Equatable {
    case left, right, up, down
}

@MainActor
final class ScoreStore: ObservableObject {
    private static let pianoRollSeekLeadBeats = 0.02
    private static let recentProjectPathsKey = "MidiScore.recentProjectPaths"
    private static let printSettingsKey = "MidiScore.printSettings"
    @Published private(set) var document = ScoreDocument.empty
    @Published var selectedTrackIndex = 0
    @Published private(set) var selectedNoteIDs: Set<UUID> = []
    @Published private(set) var primarySelectedNoteID: UUID?
    @Published var grid: ScoreGrid = .sixteenth
    @Published var melodyMode = false
    @Published var isPlaying = false
    @Published private(set) var isCountingIn = false
    @Published private(set) var countInClicksPlayed = 0
    @Published private(set) var isRecording = false
    @Published private(set) var recordingPreview: ScoreNote?
    @Published var playbackBeat: Double?
    @Published var chordEditingTick: Int?
    @Published private(set) var playbackStartMeasureIndex: Int?
    @Published private(set) var playbackStartNoteID: UUID?
    @Published private(set) var playbackStartPositionBeat: Double?
    @Published private(set) var resizeEdge: NoteEditEdge = .end
    @Published var editorMode: EditorMode = .score
    @Published var printSettings = ScorePrintSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(printSettings) {
                preferences.set(data, forKey: Self.printSettingsKey)
            }
        }
    }
    @Published var lyricMode: LyricMode = .single
    @Published var selectedLyricVerse = 1
    @Published var errorMessage: String?
    @Published var status = "MIDI 파일을 열거나 음표를 추가하세요."
    @Published private(set) var recentProjects: [URL] = []

    private var projectURL: URL?
    private var savedDocument: ScoreDocument? = .empty
    private var undoStack: [ScoreDocument] = []
    private var redoStack: [ScoreDocument] = []
    private var player: AVMIDIPlayer?
    private var playbackTimer: Timer?
    private var metronomeTimer: Timer?
    private var recordingStartedAt: TimeInterval?
    private var recordingStartBeat = 0.0
    private var silentPlaybackStartedAt: TimeInterval?
    private var silentPlaybackStartBeat = 0.0
    private var activePlaybackPlan: RepeatPlaybackPlan?
    private var playbackStartPerformanceBeat: Double?
    private let pasteboard: NSPasteboard
    private let noteSound: NoteSoundPlaying
    private let preferences: UserDefaults
    private let notesPasteboardType = NSPasteboard.PasteboardType("com.evanskim.midiscore.notes")

    init(pasteboard: NSPasteboard = .general, noteSound: NoteSoundPlaying? = nil,
         preferences: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.noteSound = noteSound ?? NoteAuditioner()
        self.preferences = preferences
        if let data = preferences.data(forKey: Self.printSettingsKey),
           let saved = try? JSONDecoder().decode(ScorePrintSettings.self, from: data) {
            printSettings = saved
        }
        var seen = Set<String>()
        recentProjects = Array((preferences.stringArray(forKey: Self.recentProjectPathsKey) ?? [])
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0.path).inserted }
            .prefix(5))
    }

    var selectedNoteID: UUID? {
        get { primarySelectedNoteID }
        set { selectNotes(newValue.map { Set([$0]) } ?? []) }
    }

    var selectedTrack: ScoreTrack? {
        document.tracks.indices.contains(selectedTrackIndex) ? document.tracks[selectedTrackIndex] : nil
    }

    var displayedNotes: [ScoreNote] {
        let notes = selectedTrack?.notes ?? []
        return recordingPreview.map { notes + [$0] } ?? notes
    }

    var selectedNote: ScoreNote? {
        selectedTrack?.notes.first(where: { $0.id == selectedNoteID })
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canPasteNotes: Bool { pasteboard.data(forType: notesPasteboardType) != nil }
    var hasUnsavedChanges: Bool { savedDocument != document }
    var playbackStartBeat: Double? {
        if let playbackStartPositionBeat { return playbackStartPositionBeat }
        if let playbackStartNoteID,
           let note = selectedTrack?.notes.first(where: { $0.id == playbackStartNoteID }) {
            return note.startBeat
        }
        return playbackStartMeasureIndex.map { Double($0) * document.beatsPerMeasure }
    }
    var visiblePlaybackBeat: Double? { playbackBeat ?? playbackStartBeat }

    func selectNotes(_ ids: Set<UUID>, additive: Bool = false) {
        let valid = Set(selectedTrack?.notes.map(\.id) ?? [])
        let selected = (additive ? selectedNoteIDs.union(ids) : ids).intersection(valid)
        selectedNoteIDs = selected
        primarySelectedNoteID = selectedTrack?.notes.first(where: { selected.contains($0.id) })?.id
    }

    func selectNote(_ id: UUID?, additive: Bool = false) {
        guard let id else {
            if !additive { selectNotes([]) }
            return
        }
        if additive {
            var next = selectedNoteIDs
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            selectNotes(next)
        } else if !(selectedNoteIDs.contains(id) && selectedNoteIDs.count > 1) {
            selectNotes([id])
        }
    }

    func selectTrack(_ index: Int) {
        guard document.tracks.indices.contains(index) else { return }
        if isRecording || isCountingIn { stop() }
        selectedTrackIndex = index
        selectNotes([])
        playbackStartNoteID = nil
        playbackStartPerformanceBeat = nil
    }

    private func confirmDiscardChanges() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 변경 사항이 있습니다."
        alert.informativeText = "계속하면 현재 악보의 변경 사항이 사라집니다."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "저장하지 않음")
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn
    }

    func newDocument() {
        guard confirmDiscardChanges() else { return }
        stop()
        playbackStartMeasureIndex = nil
        playbackStartNoteID = nil
        playbackStartPositionBeat = nil
        playbackStartPerformanceBeat = nil
        chordEditingTick = nil
        document = .empty
        selectedTrackIndex = 0
        selectedNoteID = nil
        projectURL = nil
        savedDocument = .empty
        undoStack.removeAll()
        redoStack.removeAll()
        status = "새 악보"
    }

    func importMIDI() {
        guard confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.title = "MIDI 파일 열기"
        panel.allowedContentTypes = [UTType(filenameExtension: "mid")!, UTType(filenameExtension: "midi")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try MIDIService.importFile(url, grid: grid)
            stop()
            playbackStartMeasureIndex = nil
            playbackStartNoteID = nil
            playbackStartPositionBeat = nil
            playbackStartPerformanceBeat = nil
            chordEditingTick = nil
            document = loaded
            selectedTrackIndex = 0
            selectedNoteID = nil
            projectURL = nil
            savedDocument = nil
            undoStack.removeAll()
            redoStack.removeAll()
            status = "\(loaded.tracks.count)개 트랙을 가져왔습니다. 음표의 위치와 길이는 \(grid.label) 단위로 정렬했습니다."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "프로젝트 열기"
        panel.allowedContentTypes = [UTType(filenameExtension: "mscore")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            recentProjects.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
            preferences.set(recentProjects.map(\.path), forKey: Self.recentProjectPathsKey)
            errorMessage = "프로젝트 파일을 찾을 수 없습니다: \(url.lastPathComponent)"
            return
        }
        guard confirmDiscardChanges() else { return }
        do {
            let loaded = try JSONDecoder().decode(ScoreDocument.self, from: Data(contentsOf: url))
            guard !loaded.tracks.isEmpty else { throw MIDIService.MIDIError.invalidDocument }
            try RepeatPlaybackPlan.validate(repeats: loaded.repeatSections,
                                            navigation: loaded.navigationMarks)
            stop()
            playbackStartMeasureIndex = nil
            playbackStartNoteID = nil
            playbackStartPositionBeat = nil
            playbackStartPerformanceBeat = nil
            chordEditingTick = nil
            document = loaded
            selectedTrackIndex = 0
            selectedNoteID = nil
            projectURL = url
            savedDocument = loaded
            undoStack.removeAll()
            redoStack.removeAll()
            recordRecentProject(url)
            status = "\(url.lastPathComponent) 열기 완료"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProject(asNewFile: Bool = false) {
        var url = asNewFile ? nil : projectURL
        if url == nil {
            let panel = NSSavePanel()
            panel.title = "프로젝트 저장"
            panel.nameFieldStringValue = "\(document.title).mscore"
            panel.allowedContentTypes = [UTType(exportedAs: "com.evanskim.midiscore.project", conformingTo: .json)]
            guard panel.runModal() == .OK else { return }
            url = panel.url
        }
        guard let url else { return }
        saveProject(to: url)
    }

    func saveProject(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            projectURL = url
            savedDocument = document
            recordRecentProject(url)
            status = "\(url.lastPathComponent) 저장 완료"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordRecentProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentProjects = Array(([normalized] + recentProjects.filter { $0 != normalized }).prefix(5))
        preferences.set(recentProjects.map(\.path), forKey: Self.recentProjectPathsKey)
    }

    func exportMIDI() {
        let panel = NSSavePanel()
        panel.title = "선택 트랙 MIDI 내보내기"
        panel.nameFieldStringValue = "\(document.title)-\(selectedTrack?.name ?? "track").mid"
        panel.allowedContentTypes = [UTType(filenameExtension: "mid")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MIDIService.midiData(document: document, trackIndex: selectedTrackIndex)
                .write(to: url, options: .atomic)
            status = "선택 트랙을 \(url.lastPathComponent)(으)로 내보냈습니다."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mutate(_ change: (inout ScoreDocument) -> Void) {
        stop()
        playbackStartPerformanceBeat = nil
        let before = document
        change(&document)
        guard document != before else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func quantizeTrack() {
        guard document.tracks.indices.contains(selectedTrackIndex) else { return }
        let selectedIDs = selectedNoteIDs
        let quantizeAll = selectedIDs.isEmpty
        mutate { document in
            document.tracks[selectedTrackIndex].notes = ScoreOperations.quantizedNotes(
                document.tracks[selectedTrackIndex].notes, grid: grid,
                selectedIDs: selectedIDs, melodyMode: melodyMode)
        }
        let target = quantizeAll ? "선택 트랙" : "선택한 \(selectedIDs.count)개 음표"
        status = "\(target)를 \(grid.label) 단위로 정렬했습니다\(melodyMode ? " (멜로디 모드)" : "")."
    }

    func selectAllNotes() {
        guard editorMode == .pianoRoll else { return }
        selectNotes(Set(selectedTrack?.notes.map(\.id) ?? []))
        status = "\(selectedNoteIDs.count)개 음표 선택"
    }

    func setTempo(_ value: Double) {
        mutate { $0.tempo = max(20, min(300, value)) }
    }

    func updatePage(_ change: (inout Page) -> Void) {
        mutate { document in
            change(&document.page)
            document.page.measuresPerLine = max(1, min(16, document.page.measuresPerLine))
            document.page.noteSpacing = document.page.noteSpacing.isFinite
                ? max(18, min(60, document.page.noteSpacing)) : 29
            document.page.measureWidthRatio = document.page.measureWidthRatio.isFinite
                ? max(0.5, min(4, document.page.measureWidthRatio)) : 1
            document.page.rowGap = document.page.rowGap.isFinite
                ? max(0, min(160, document.page.rowGap)) : 15
            document.page.lyricFontSize = document.page.lyricFontSize.isFinite
                ? max(10, min(28, document.page.lyricFontSize)) : 15
            document.page.numerator = max(1, min(12, document.page.numerator))
            if ![2, 4, 8, 16].contains(document.page.denominator) {
                document.page.denominator = 4
            }
        }
    }

    func chord(at tick: Int) -> ChordEvent? {
        document.chordEvents.first { $0.positionTick == tick }
    }

    @discardableResult
    func setChord(at tick: Int, text: String, followsKey: Bool) -> Bool {
        guard tick >= 0,
              let chord = ChordSymbol(text: text, key: document.page.keySignature,
                                      followsKey: followsKey) else { return false }
        mutate { document in
            document.chordEvents.removeAll { $0.positionTick == tick }
            document.chordEvents.append(ChordEvent(positionTick: tick, chord: chord))
            document.chordEvents.sort { $0.positionTick < $1.positionTick }
        }
        let measure = ChordGrid.measure(for: tick, page: document.page) + 1
        let slot = ChordGrid.slot(for: tick, page: document.page) + 1
        status = "\(measure)마디 \(slot)박 코드: \(chord.symbol(in: document.page.keySignature))"
        return true
    }

    func removeChord(at tick: Int) {
        guard chord(at: tick) != nil else { return }
        mutate { $0.chordEvents.removeAll { $0.positionTick == tick } }
        status = "코드 삭제"
    }

    @discardableResult
    func upsertRepeatSection(_ section: RepeatSection, replacing index: Int? = nil) -> Bool {
        var sections = document.repeatSections
        if let index, sections.indices.contains(index) { sections.remove(at: index) }
        sections.append(section)
        do {
            try RepeatPlaybackPlan.validate(repeats: sections,
                                            navigation: document.navigationMarks)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        mutate { $0.repeatSections = sections.sorted { $0.startMeasure < $1.startMeasure } }
        status = "도돌이 구간 설정: \(section.description)"
        return true
    }

    func removeRepeatSection(at index: Int) {
        guard document.repeatSections.indices.contains(index) else { return }
        mutate { $0.repeatSections.remove(at: index) }
        status = "도돌이 구간 삭제"
    }

    @discardableResult
    func upsertNavigationMark(_ mark: NavigationMark, replacing index: Int? = nil) -> Bool {
        var marks = document.navigationMarks
        if let index, marks.indices.contains(index) { marks.remove(at: index) }
        marks.append(mark)
        do {
            try RepeatPlaybackPlan.validate(repeats: document.repeatSections,
                                            navigation: marks)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        mutate { $0.navigationMarks = marks.sorted {
            $0.measure == $1.measure ? $0.kind.rawValue < $1.kind.rawValue : $0.measure < $1.measure
        } }
        status = "이동 기호 설정: \(mark.description)"
        return true
    }

    func removeNavigationMark(at index: Int) {
        guard document.navigationMarks.indices.contains(index) else { return }
        var marks = document.navigationMarks
        marks.remove(at: index)
        do {
            try RepeatPlaybackPlan.validate(repeats: document.repeatSections,
                                            navigation: marks)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        mutate { $0.navigationMarks = marks }
        status = "이동 기호 삭제"
    }

    func setClef(_ clef: Clef) {
        guard document.tracks.indices.contains(selectedTrackIndex) else { return }
        mutate { $0.tracks[selectedTrackIndex].clef = clef }
    }

    func addTrack() {
        let index = document.tracks.count
        mutate { $0.tracks.append(ScoreTrack(name: "트랙 \(index + 1)", notes: [])) }
        selectedTrackIndex = index
        selectedNoteID = nil
    }

    func renameSelectedTrack() {
        guard let track = selectedTrack else { return }
        let alert = NSAlert()
        alert.messageText = "트랙 이름 변경"
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(string: track.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate { $0.tracks[selectedTrackIndex].name = name }
    }

    func deleteSelectedTrack() {
        guard document.tracks.count > 1 else {
            status = "마지막 트랙은 삭제할 수 없습니다."
            return
        }
        let alert = NSAlert()
        alert.messageText = "\(selectedTrack?.name ?? "트랙")을(를) 삭제할까요?"
        alert.informativeText = "트랙의 모든 음표와 가사가 삭제됩니다."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "삭제")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        mutate { $0.tracks.remove(at: selectedTrackIndex) }
        selectedTrackIndex = min(selectedTrackIndex, document.tracks.count - 1)
        selectedNoteID = nil
    }

    func toggleLyricMode() {
        lyricMode = lyricMode == .single ? .multiple : .single
        status = "가사 입력: \(lyricMode.rawValue) 모드"
    }

    func assignLyricAndAdvance(_ lyric: String) {
        guard let id = selectedNoteID,
              let notes = selectedTrack?.notes,
              let note = notes.first(where: { $0.id == id }) else { return }
        let next = notes.filter { $0.startBeat > note.startBeat + 0.0001 }
            .min(by: { $0.startBeat < $1.startBeat })?.id
        let verse = selectedLyricVerse
        updateSelected { $0.setLyric(lyric, for: verse) }
        selectedNoteID = next
    }

    func addNote(at beat: Double, pitch: Int, duration: Double? = nil) {
        guard document.tracks.indices.contains(selectedTrackIndex) else { return }
        let note = ScoreNote(pitch: max(0, min(127, pitch)), startBeat: max(0, grid.quantize(beat)),
                             durationBeats: duration ?? 1,
                             originalStartBeat: beat, originalDurationBeats: duration ?? 1)
        mutate { $0.tracks[selectedTrackIndex].notes.append(note) }
        selectedNoteID = note.id
        noteSound.playNote(pitch: note.pitch, velocity: note.velocity)
    }

    func editNote(id: UUID, pitch: Int, startBeat: Double, duration: Double) {
        guard let index = selectedTrack?.notes.firstIndex(where: { $0.id == id }) else { return }
        let before = document.tracks[selectedTrackIndex].notes[index]
        mutate { document in
            var note = document.tracks[selectedTrackIndex].notes[index]
            note.pitch = max(0, min(127, pitch))
            note.startBeat = max(0, grid.quantize(startBeat))
            note.durationBeats = max(grid.rawValue, grid.quantize(duration))
            document.tracks[selectedTrackIndex].notes[index] = note
            document.tracks[selectedTrackIndex].notes.sort { $0.startBeat < $1.startBeat }
        }
        selectedNoteID = id
        if let after = selectedNote, after.pitch != before.pitch || after.startBeat != before.startBeat {
            noteSound.playNote(pitch: after.pitch, velocity: after.velocity)
        }
    }

    func addNote() {
        guard let track = selectedTrack else { return }
        let last = track.notes.max(by: { $0.startBeat + $0.durationBeats < $1.startBeat + $1.durationBeats })
        let start = selectedNote.map { $0.startBeat + $0.durationBeats }
            ?? last.map { $0.startBeat + $0.durationBeats } ?? 0
        let pitch = selectedNote?.pitch ?? 60
        let note = ScoreNote(pitch: pitch, startBeat: start, durationBeats: 1,
                             originalStartBeat: start, originalDurationBeats: 1)
        mutate { $0.tracks[selectedTrackIndex].notes.append(note) }
        selectedNoteID = note.id
        noteSound.playNote(pitch: note.pitch, velocity: note.velocity)
    }

    func updateSelected(_ change: (inout ScoreNote) -> Void) {
        guard let id = selectedNoteID,
              let index = selectedTrack?.notes.firstIndex(where: { $0.id == id }) else { return }
        let before = document.tracks[selectedTrackIndex].notes[index]
        mutate { document in
            change(&document.tracks[selectedTrackIndex].notes[index])
            document.tracks[selectedTrackIndex].notes[index].pitch = max(0, min(127, document.tracks[selectedTrackIndex].notes[index].pitch))
            document.tracks[selectedTrackIndex].notes[index].startBeat = max(0, document.tracks[selectedTrackIndex].notes[index].startBeat)
            document.tracks[selectedTrackIndex].notes[index].durationBeats = max(grid.rawValue, document.tracks[selectedTrackIndex].notes[index].durationBeats)
            document.tracks[selectedTrackIndex].notes.sort { $0.startBeat < $1.startBeat }
        }
        if let after = selectedNote, after.pitch != before.pitch || after.startBeat != before.startBeat {
            noteSound.playNote(pitch: after.pitch, velocity: after.velocity)
        }
    }

    func deleteSelected() {
        guard !selectedNoteIDs.isEmpty else { return }
        let ids = selectedNoteIDs
        mutate { $0.tracks[selectedTrackIndex].notes.removeAll(where: { ids.contains($0.id) }) }
        selectNotes([])
    }

    func mergeSelectedNotes() {
        guard let track = selectedTrack else { return }
        let selected = track.notes.filter { selectedNoteIDs.contains($0.id) }
        let groups = Dictionary(grouping: selected) { "\($0.pitch):\($0.channel)" }
            .values.filter { $0.count > 1 }
        guard !groups.isEmpty else {
            status = "합칠 같은 높이의 음표를 2개 이상 선택하세요."
            return
        }
        var replacements: [UUID: ScoreNote] = [:]
        var removed: Set<UUID> = []
        var survivorByRemovedID: [UUID: UUID] = [:]
        for group in groups {
            let sorted = group.sorted { $0.startBeat < $1.startBeat }
            var merged = sorted[0]
            let end = sorted.map { $0.startBeat + $0.durationBeats }.max() ?? merged.startBeat
            merged.durationBeats = end - merged.startBeat
            replacements[merged.id] = merged
            removed.formUnion(sorted.dropFirst().map(\.id))
            for note in sorted.dropFirst() { survivorByRemovedID[note.id] = merged.id }
        }
        mutate { document in
            document.tracks[selectedTrackIndex].notes = document.tracks[selectedTrackIndex].notes
                .filter { !removed.contains($0.id) }
                .map { replacements[$0.id] ?? $0 }
                .sorted { $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat }
        }
        if let playbackStartNoteID, let survivor = survivorByRemovedID[playbackStartNoteID] {
            self.playbackStartNoteID = survivor
        }
        selectNotes(Set(replacements.keys))
        status = "\(removed.count + replacements.count)개 음표를 \(replacements.count)개로 합쳤습니다."
    }

    func splitSelectedNotes() {
        guard let track = selectedTrack else { return }
        let selected = track.notes.filter { selectedNoteIDs.contains($0.id) && $0.durationBeats >= 0.25 - 0.000001 }
        guard !selected.isEmpty else {
            status = "32분음표 2개 이상 길이의 음표를 선택하세요."
            return
        }
        let halves = Dictionary(uniqueKeysWithValues: selected.map { note -> (UUID, (ScoreNote, ScoreNote)) in
            var first = note
            first.durationBeats = note.durationBeats / 2
            var second = note
            second.id = UUID()
            second.startBeat = note.startBeat + first.durationBeats
            second.durationBeats = note.durationBeats - first.durationBeats
            second.originalStartBeat = second.startBeat
            second.originalDurationBeats = second.durationBeats
            second.lyric = ""
            second.additionalLyrics = []
            return (note.id, (first, second))
        })
        mutate { document in
            let existing = document.tracks[selectedTrackIndex].notes
            var result: [ScoreNote] = []
            for note in existing {
                if let pair = halves[note.id] {
                    result.append(pair.0)
                    result.append(pair.1)
                } else {
                    result.append(note)
                }
            }
            result.sort { $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat }
            document.tracks[selectedTrackIndex].notes = result
        }
        selectNotes(Set(halves.values.flatMap { [$0.0.id, $0.1.id] }))
        status = "\(halves.count)개 음표를 각각 반으로 나눴습니다."
        if let note = halves.values.first?.1 {
            noteSound.playNote(pitch: note.pitch, velocity: note.velocity)
        }
    }

    func applyNoteEdits(_ edits: [ScoreNote]) {
        guard !edits.isEmpty, selectedTrack != nil else { return }
        let before = Dictionary(uniqueKeysWithValues: (selectedTrack?.notes ?? []).map { ($0.id, $0) })
        let replacements = Dictionary(uniqueKeysWithValues: edits.map { ($0.id, $0) })
        mutate { document in
            document.tracks[selectedTrackIndex].notes = document.tracks[selectedTrackIndex].notes.map { old in
                guard var note = replacements[old.id] else { return old }
                note.pitch = max(0, min(127, note.pitch))
                note.startBeat = max(0, grid.quantize(note.startBeat))
                note.durationBeats = max(grid.rawValue, grid.quantize(note.durationBeats))
                return note
            }.sorted { $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat }
        }
        selectNotes(Set(edits.map(\.id)))
        if let changed = edits.first(where: { edit in
            guard let old = before[edit.id] else { return false }
            return edit.pitch != old.pitch || grid.quantize(edit.startBeat) != old.startBeat
        }), let note = selectedTrack?.notes.first(where: { $0.id == changed.id }) {
            noteSound.playNote(pitch: note.pitch, velocity: note.velocity)
        }
    }

    func nudgeSelection(_ direction: NoteKeyDirection, shift: Bool) {
        guard let notes = selectedTrack?.notes.filter({ selectedNoteIDs.contains($0.id) }),
              !notes.isEmpty else { return }
        if shift && (direction == .up || direction == .down) {
            resizeEdge = direction == .up ? .start : .end
            status = "길이 조절: \(resizeEdge.rawValue) (Shift + ←/→)"
            return
        }
        let amount = grid.rawValue
        let beatDelta = direction == .left ? -amount : amount
        let pitchDelta = direction == .up ? 1 : -1
        let minimumStart = notes.map(\.startBeat).min() ?? 0
        let earliestAllowed = max(beatDelta, -minimumStart)
        let edits = notes.map { original -> ScoreNote in
            var note = original
            if shift {
                if resizeEdge == .start {
                    let delta = max(-note.startBeat, min(beatDelta, note.durationBeats - amount))
                    note.startBeat += delta
                    note.durationBeats -= delta
                } else {
                    note.durationBeats = max(amount, note.durationBeats + beatDelta)
                }
            } else {
                switch direction {
                case .left, .right: note.startBeat += earliestAllowed
                case .up, .down: note.pitch = max(0, min(127, note.pitch + pitchDelta))
                }
            }
            return note
        }
        applyNoteEdits(edits)
    }

    func copySelectedNotes() {
        guard let notes = selectedTrack?.notes.filter({ selectedNoteIDs.contains($0.id) }),
              !notes.isEmpty, let data = try? JSONEncoder().encode(notes) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: notesPasteboardType)
        status = "\(notes.count)개 음표 복사"
    }

    func pasteNotes() {
        guard selectedTrack != nil,
              let data = pasteboard.data(forType: notesPasteboardType),
              let copied = try? JSONDecoder().decode([ScoreNote].self, from: data),
              !copied.isEmpty else { return }
        let anchor = max(0, grid.quantize(visiblePlaybackBeat ?? 0))
        let firstBeat = copied.map(\.startBeat).min() ?? 0
        let pasted = copied.map { source -> ScoreNote in
            var note = source
            note.id = UUID()
            note.startBeat = anchor + source.startBeat - firstBeat
            note.originalStartBeat = note.startBeat
            note.originalDurationBeats = note.durationBeats
            return note
        }
        mutate { document in
            document.tracks[selectedTrackIndex].notes.append(contentsOf: pasted)
            document.tracks[selectedTrackIndex].notes.sort {
                $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat
            }
        }
        selectNotes(Set(pasted.map(\.id)))
        status = "\(pasted.count)개 음표를 \(anchor.formatted())박에 붙여넣었습니다."
        if let note = pasted.first { noteSound.playNote(pitch: note.pitch, velocity: note.velocity) }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        stop()
        redoStack.append(document)
        document = previous
        playbackStartPerformanceBeat = nil
        selectedTrackIndex = min(selectedTrackIndex, max(0, document.tracks.count - 1))
        selectNotes(selectedNoteIDs)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        stop()
        undoStack.append(document)
        document = next
        playbackStartPerformanceBeat = nil
        selectedTrackIndex = min(selectedTrackIndex, max(0, document.tracks.count - 1))
        selectNotes(selectedNoteIDs)
    }

    func seekToMeasure(_ index: Int) {
        guard index >= 0 else { return }
        playbackStartMeasureIndex = index
        playbackStartNoteID = nil
        playbackStartPositionBeat = nil
        playbackStartPerformanceBeat = nil
        seekPlayer(to: Double(index) * document.beatsPerMeasure)
        status = "\(index + 1)마디부터 재생"
    }

    func seekToNote(_ id: UUID) {
        guard let note = selectedTrack?.notes.first(where: { $0.id == id }) else { return }
        playbackStartNoteID = id
        playbackStartMeasureIndex = nil
        playbackStartPositionBeat = nil
        playbackStartPerformanceBeat = nil
        seekPlayer(to: note.startBeat)
        status = "\(NotatedPitch.spell(note.pitch, in: document.page.keySignature).name) 음표부터 재생"
    }

    func seekToBeat(_ beat: Double) {
        guard beat.isFinite else { return }
        seekToPosition(max(0, grid.quantize(beat)))
    }

    func seekToPianoRollBeat(_ beat: Double) {
        guard beat.isFinite else { return }
        let gridBeat = max(0, grid.quantize(beat))
        seekToPosition(max(0, gridBeat - Self.pianoRollSeekLeadBeats))
    }

    func seekToPianoRollNote(_ id: UUID) {
        guard let note = selectedTrack?.notes.first(where: { $0.id == id }) else { return }
        seekToPosition(max(0, note.startBeat - Self.pianoRollSeekLeadBeats))
    }

    private func seekToPosition(_ position: Double) {
        if isRecording, recordingPreview != nil { finishRecordedNote(at: recordingBeatNow()) }
        playbackStartPositionBeat = position
        playbackStartPerformanceBeat = nil
        playbackStartMeasureIndex = nil
        playbackStartNoteID = nil
        seekPlayer(to: position)
        status = "\(position.formatted())박부터 재생"
    }

    private func seekPlayer(to beat: Double) {
        let performanceBeat = activePlaybackPlan?.performanceBeat(for: beat) ?? beat
        if isPlaying { playbackStartPerformanceBeat = performanceBeat }
        if let player, isPlaying {
            player.currentPosition = performanceBeat * 60.0 / max(20, document.tempo)
            playbackBeat = beat
        }
        if isRecording || isCountingIn {
            recordingStartBeat = beat
            if isRecording { recordingStartedAt = ProcessInfo.processInfo.systemUptime }
            playbackBeat = beat
        } else if isPlaying, player == nil {
            silentPlaybackStartBeat = performanceBeat
            silentPlaybackStartedAt = ProcessInfo.processInfo.systemUptime
            playbackBeat = beat
        }
    }

    private func recordingBeatNow() -> Double {
        guard let recordingStartedAt else { return playbackBeat ?? playbackStartBeat ?? 0 }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - recordingStartedAt)
        return recordingStartBeat + elapsed * document.tempo / 60.0
    }

    var metronomeInterval: TimeInterval {
        60.0 / max(20, document.tempo) * 4.0 / Double(max(1, document.denominator))
    }
    var countInTotalClicks: Int { max(1, document.numerator) }
    var countInDuration: TimeInterval { metronomeInterval * Double(countInTotalClicks) }

    func toggleRecording() {
        if isRecording || isCountingIn {
            let wasCountingIn = isCountingIn
            stop()
            status = wasCountingIn ? "녹음 카운트 취소" : "녹음 종료"
            return
        }
        if isPlaying {
            let position = playbackBeat ?? playbackStartBeat ?? 0
            stop()
            seekToBeat(position)
        }
        editorMode = .pianoRoll
        recordingStartBeat = playbackStartBeat ?? 0
        playbackStartPerformanceBeat = nil
        playbackBeat = recordingStartBeat
        isCountingIn = true
        countInClicksPlayed = 1
        noteSound.playCountInClick()
        let timer = Timer(timeInterval: metronomeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceMetronomeTick() }
        }
        metronomeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        status = "녹음 준비 · 메트로놈 \(countInClicksPlayed)/\(countInTotalClicks)"
    }

    func advanceMetronomeTick() {
        if isCountingIn {
            if countInClicksPlayed < countInTotalClicks {
                countInClicksPlayed += 1
                noteSound.playCountInClick()
                status = "녹음 준비 · 메트로놈 \(countInClicksPlayed)/\(countInTotalClicks)"
            } else {
                completeCountIn()
            }
        } else if isRecording {
            noteSound.playCountInClick()
        }
    }

    func completeCountIn() {
        guard isCountingIn else { return }
        isCountingIn = false
        isRecording = true
        if selectedTrack?.notes.isEmpty == false { play() }
        if !isPlaying {
            isPlaying = true
            playbackBeat = recordingStartBeat
            startPlaybackTimer()
        }
        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        noteSound.playCountInClick()
        status = "녹음 중 · I 키를 누르고 있으면 C4 음표가 기록됩니다."
    }

    func beginRecordedNote() {
        guard isRecording, recordingPreview == nil, selectedTrack != nil else { return }
        beginRecordedNote(at: recordingBeatNow())
    }

    func endRecordedNote() {
        guard isRecording, recordingPreview != nil else { return }
        finishRecordedNote(at: recordingBeatNow())
    }

    func beginRecordedNote(at beat: Double) {
        guard recordingPreview == nil, beat.isFinite, selectedTrack != nil else { return }
        let start = max(0, beat)
        recordingPreview = ScoreNote(pitch: 60, startBeat: start, durationBeats: 0.01,
                                     originalStartBeat: start, originalDurationBeats: 0.01)
        noteSound.playNote(pitch: 60, velocity: 90)
    }

    func finishRecordedNote(at beat: Double) {
        guard var note = recordingPreview, beat.isFinite,
              document.tracks.indices.contains(selectedTrackIndex) else { return }
        note.durationBeats = max(0.01, beat - note.startBeat)
        note.originalDurationBeats = note.durationBeats
        recordingPreview = nil
        let before = document
        document.tracks[selectedTrackIndex].notes.append(note)
        document.tracks[selectedTrackIndex].notes.sort {
            $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat
        }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        selectedNoteID = note.id
        status = "C4 음표 녹음: \(note.startBeat.formatted())박부터 \(note.durationBeats.formatted())박"
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isRecording {
                    let beat = self.recordingBeatNow()
                    self.playbackBeat = beat
                    if var preview = self.recordingPreview {
                        preview.durationBeats = max(0.01, beat - preview.startBeat)
                        self.recordingPreview = preview
                    }
                } else if let player = self.player {
                    let performanceBeat = player.currentPosition * self.document.tempo / 60.0
                    self.playbackBeat = self.activePlaybackPlan?.scoreBeat(at: performanceBeat)
                        ?? performanceBeat
                } else if let startedAt = self.silentPlaybackStartedAt {
                    let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
                    let performanceBeat = self.silentPlaybackStartBeat +
                        elapsed * self.document.tempo / 60.0
                    self.playbackBeat = self.activePlaybackPlan?.scoreBeat(at: performanceBeat)
                        ?? performanceBeat
                }
            }
        }
    }

    func play() {
        if isCountingIn {
            stop()
            status = "녹음 카운트 취소"
            return
        }
        guard !isPlaying else { stop(); return }
        let plan: RepeatPlaybackPlan
        do {
            plan = try RepeatPlaybackPlan(page: document.page,
                notes: selectedTrack?.notes ?? [], chords: document.chordEvents,
                repeats: document.repeatSections, navigation: document.navigationMarks,
                playRepeats: !isRecording)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        activePlaybackPlan = plan
        let startPerformance = playbackStartPerformanceBeat.map { min($0, plan.totalBeats) }
            ?? plan.performanceBeat(for: playbackStartBeat ?? 0)
        if selectedTrack?.notes.isEmpty != false {
            silentPlaybackStartBeat = startPerformance
            silentPlaybackStartedAt = ProcessInfo.processInfo.systemUptime
            isPlaying = true
            playbackBeat = plan.scoreBeat(at: startPerformance)
            startPlaybackTimer()
            status = "음표가 없어 재생선만 이동합니다."
            return
        }
        do {
            var performanceDocument = document
            performanceDocument.tracks[selectedTrackIndex].notes = plan.expandedNotes(
                document.tracks[selectedTrackIndex].notes)
            let data = try MIDIService.midiData(document: performanceDocument,
                                                trackIndex: selectedTrackIndex,
                                                minimumDurationBeats: plan.totalBeats)
            let player = try AVMIDIPlayer(data: data, soundBankURL: nil)
            player.prepareToPlay()
            player.currentPosition = startPerformance * 60.0 / max(20, document.tempo)
            self.player = player
            isPlaying = true
            playbackBeat = plan.scoreBeat(at: startPerformance)
            startPlaybackTimer()
            let playerID = ObjectIdentifier(player)
            player.play { [weak self] in
                DispatchQueue.main.async {
                    guard let self, let current = self.player,
                          ObjectIdentifier(current) == playerID else { return }
                    if self.isRecording {
                        self.player = nil
                        return
                    }
                    self.isPlaying = false
                    let performanceBeat = current.currentPosition * self.document.tempo / 60.0
                    self.rememberPlaybackPosition(performanceBeat)
                    self.player = nil
                    self.playbackTimer?.invalidate()
                    self.playbackTimer = nil
                    self.playbackBeat = nil
                    self.activePlaybackPlan = nil
                }
            }
        } catch {
            activePlaybackPlan = nil
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        let stoppedPerformanceBeat: Double? = (isPlaying || isRecording)
            ? currentPerformancePosition() : nil
        metronomeTimer?.invalidate()
        metronomeTimer = nil
        isCountingIn = false
        countInClicksPlayed = 0
        if isRecording, recordingPreview != nil {
            finishRecordedNote(at: recordingBeatNow())
        }
        isRecording = false
        recordingStartedAt = nil
        silentPlaybackStartedAt = nil
        if let stoppedPerformanceBeat { rememberPlaybackPosition(stoppedPerformanceBeat) }
        player?.stop()
        player = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackBeat = nil
        activePlaybackPlan = nil
    }

    private func currentPerformancePosition() -> Double? {
        if isRecording { return recordingBeatNow() }
        if let player {
            return player.currentPosition * document.tempo / 60.0
        }
        if let startedAt = silentPlaybackStartedAt {
            return silentPlaybackStartBeat +
                max(0, ProcessInfo.processInfo.systemUptime - startedAt) * document.tempo / 60.0
        }
        return playbackBeat.flatMap { activePlaybackPlan?.performanceBeat(for: $0) ?? $0 }
    }

    private func rememberPlaybackPosition(_ performanceBeat: Double) {
        guard performanceBeat.isFinite else { return }
        let position = max(0, performanceBeat)
        playbackStartPositionBeat = activePlaybackPlan?.scoreBeat(at: position) ?? position
        playbackStartPerformanceBeat = position
        playbackStartMeasureIndex = nil
        playbackStartNoteID = nil
    }
}
