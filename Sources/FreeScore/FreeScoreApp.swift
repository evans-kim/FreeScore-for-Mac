import AppKit
import SwiftUI

@main
struct FreeScoreApp: App {
    @StateObject private var store = ScoreStore()

    var body: some Scene {
        WindowGroup("FreeScore for Mac") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1160, height: 720)
        .commands {
            CommandMenu("악보") {
                Button("새 악보") { store.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("MIDI 가져오기…") { store.importMIDI() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("프로젝트 열기…") { store.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
                if !store.recentProjects.isEmpty {
                    Divider()
                    ForEach(Array(store.recentProjects.enumerated()), id: \.element) { index, url in
                        Button(url.lastPathComponent) { store.openProject(at: url) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))),
                                              modifiers: [.command, .option])
                            .help(url.path)
                    }
                }
                Divider()
                Button("프로젝트 저장…") { store.saveProject() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("선택 트랙 MIDI 내보내기…") { store.exportMIDI() }
                    .keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("인쇄 미리보기…") { store.editorMode = .printPreview }
                    .keyboardShortcut("p", modifiers: .command)
            }
            CommandMenu("음표") {
                Button("음표 추가") { store.addNote() }
                Button("피아노 롤 전체 선택") { store.selectAllNotes() }
                    .keyboardShortcut("a", modifiers: .command)
                    .disabled(store.editorMode != .pianoRoll)
                Button("선택 음표 삭제") { store.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(store.selectedNote == nil)
                Button("같은 음 병합") { store.mergeSelectedNotes() }
                    .keyboardShortcut("m", modifiers: .command)
                Button("선택 음표 반으로 나누기") { store.splitSelectedNotes() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("실행 취소") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("다시 실행") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
        }
    }
}

private struct ContentView: View {
    private static let lyricFontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    @ObservedObject var store: ScoreStore
    @State private var activeSheet: SettingsSheet?
    @State private var chordSession: ChordEditorSession?
    @State private var scoreView: StaffView?
    @State private var showingPageSettings = false
    @State private var pageDraft = Page()
    @State private var shiftMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var keyUpMonitor: Any?
    @State private var shiftWasDown = false
    @State private var shiftPressedAt: TimeInterval = 0
    @State private var shiftChordUsed = false
    @State private var lastShiftPress: TimeInterval = -10

    private enum SettingsSheet: String, Identifiable {
        case meter, clef, repeats, navigation
        var id: String { rawValue }
    }

    private var displayedPage: Page {
        guard showingPageSettings else { return store.document.page }
        var page = store.document.page
        page.title = pageDraft.title
        page.composer = pageDraft.composer
        page.arranger = pageDraft.arranger
        page.measuresPerLine = pageDraft.measuresPerLine
        page.noteSpacing = pageDraft.noteSpacing
        page.measureWidthRatio = pageDraft.measureWidthRatio
        page.rowGap = pageDraft.rowGap
        page.lyricFontName = pageDraft.lyricFontName
        page.lyricFontSize = pageDraft.lyricFontSize
        return page
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                if store.editorMode == .printPreview {
                    PrintModeView(store: store)
                } else {
                GeometryReader { geometry in
                    let horizontalPadding = store.editorMode == .pianoRoll
                        ? max(16, geometry.size.width / 2) : CGFloat(16)
                    let verticalPadding: CGFloat = 16
                    ScrollView([.horizontal, .vertical]) {
                        if store.editorMode == .score {
                            let canvas = ScoreCanvas(
                                notes: store.displayedNotes,
                                chords: store.document.chordEvents,
                                repeats: store.document.repeatSections,
                                navigation: store.document.navigationMarks,
                                chordEditingTick: store.chordEditingTick,
                                page: displayedPage,
                                clef: store.selectedTrack?.clef ?? .treble,
                                grid: store.grid,
                                selectedIDs: store.selectedNoteIDs,
                                playbackBeat: store.visiblePlaybackBeat,
                                isPlaying: store.isPlaying,
                                onSelect: { id, additive in store.selectNote(id, additive: additive) },
                                onSelectMany: { ids, additive in store.selectNotes(ids, additive: additive) },
                                onNoteDoubleClick: { store.seekToNote($0) },
                                onSeek: { store.seekToBeat($0) },
                                onEdit: { store.applyNoteEdits($0) },
                                onDoubleClick: { target in
                                    activeSheet = target == .clef ? .clef : .meter
                                },
                                onMeasureDoubleClick: { store.seekToMeasure($0) },
                                onChordClick: { tick, view in
                                    presentChordEditor(at: tick, in: view)
                                },
                                onReady: { scoreView = $0 }
                            )
                            canvas
                                .frame(width: canvas.layout.width, height: canvas.layout.height)
                                .frame(minWidth: geometry.size.width - 32,
                                       minHeight: geometry.size.height - 32,
                                       alignment: .topLeading)
                                .padding(.horizontal, horizontalPadding)
                                .padding(.vertical, verticalPadding)
                        } else {
                            let canvas = PianoRollCanvas(
                                notes: store.displayedNotes,
                                page: displayedPage,
                                grid: store.grid,
                                selectedIDs: store.selectedNoteIDs,
                                playbackBeat: store.visiblePlaybackBeat,
                                isPlaying: store.isPlaying,
                                onSelect: { id, additive in store.selectNote(id, additive: additive) },
                                onSelectMany: { ids, additive in store.selectNotes(ids, additive: additive) },
                                onNoteDoubleClick: { store.seekToPianoRollNote($0) },
                                onSeek: { store.seekToPianoRollBeat($0) },
                                onAdd: { beat, pitch in store.addNote(at: beat, pitch: pitch) },
                                onEdit: { store.applyNoteEdits($0) }
                            )
                            canvas
                                .frame(width: canvas.layout.width, height: canvas.layout.height)
                                .frame(minWidth: geometry.size.width - 32,
                                       minHeight: geometry.size.height - 32,
                                       alignment: .topLeading)
                                .padding(.horizontal, horizontalPadding)
                                .padding(.vertical, verticalPadding)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                }
                Divider()
                HStack {
                    Text(store.status)
                    Spacer()
                    Text("\(store.selectedTrack?.notes.count ?? 0)개 음표")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
            }
            if store.editorMode != .printPreview {
                Divider()
                if showingPageSettings { pageInspector } else { inspector }
            }
        }
        .alert("오류", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "알 수 없는 오류")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .meter: MeterSettingsSheet(store: store)
            case .clef: ClefSettingsSheet(store: store)
            case .repeats: RepeatSettingsSheet(store: store)
            case .navigation: NavigationSettingsSheet(store: store)
            }
        }
        .onAppear { installShiftMonitor(); installKeyMonitor(); installKeyUpMonitor() }
        .onChange(of: store.editorMode) { _, mode in
            if mode != .score {
                chordSession?.close()
                scoreView = nil
            }
        }
        .onDisappear {
            chordSession?.close()
            if let shiftMonitor { NSEvent.removeMonitor(shiftMonitor) }
            shiftMonitor = nil
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
            keyUpMonitor = nil
            if store.isRecording || store.isCountingIn { store.toggleRecording() }
        }
    }

    private func presentChordEditor(at tick: Int, in view: StaffView) {
        chordSession?.close()
        store.chordEditingTick = tick
        view.chordEditingTick = tick
        view.needsDisplay = true
        let anchorRect = view.chordAnchorRect(for: tick)
        PlaybackScrollFollower.center(
            CGPoint(x: anchorRect.midX, y: anchorRect.midY), in: view, smoothly: false)
        let session = ChordEditorSession(store: store, tick: tick, anchor: view)
        session.onClose = { [weak session] in
            guard let session, chordSession === session else { return }
            chordSession = nil
            store.chordEditingTick = nil
        }
        session.onAdvance = { next, anchor in
            store.chordEditingTick = next
            anchor.chordEditingTick = next
            anchor.needsDisplay = true
            DispatchQueue.main.async {
                presentChordEditor(at: next, in: anchor)
            }
        }
        chordSession = session
        session.show()
    }

    private func installShiftMonitor() {
        guard shiftMonitor == nil else { return }
        shiftMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if activeSheet != nil || showingPageSettings {
                shiftWasDown = false
                lastShiftPress = -10
                return event
            }
            let pressed = event.modifierFlags.contains(.shift)
            if pressed && !shiftWasDown {
                shiftPressedAt = event.timestamp
                shiftChordUsed = false
            } else if !pressed && shiftWasDown {
                if !shiftChordUsed && event.timestamp - shiftPressedAt < 0.55 {
                    if event.timestamp - lastShiftPress < 0.55 {
                        store.toggleLyricMode()
                        lastShiftPress = -10
                    } else {
                        lastShiftPress = event.timestamp
                    }
                } else {
                    lastShiftPress = -10
                }
            }
            shiftWasDown = pressed
            return event
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.shift) { shiftChordUsed = true }
            let flags = event.modifierFlags
            if activeSheet == nil, !showingPageSettings, store.isRecording,
               (event.keyCode == 34 || event.charactersIgnoringModifiers?.lowercased() == "i"),
               !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
                if !event.isARepeat { store.beginRecordedNote() }
                return nil
            }
            guard activeSheet == nil, !showingPageSettings,
                  !(event.window?.firstResponder is NSTextView) else { return event }
            if flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
                if event.keyCode == 0, store.editorMode == .pianoRoll {
                    store.selectAllNotes(); return nil
                }
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a" where store.editorMode == .pianoRoll:
                    store.selectAllNotes(); return nil
                case "c" where !store.selectedNoteIDs.isEmpty:
                    store.copySelectedNotes(); return nil
                case "v":
                    store.pasteNotes(); return nil
                case "m" where flags.contains(.shift):
                    store.splitSelectedNotes(); return nil
                case "m":
                    store.mergeSelectedNotes(); return nil
                default: break
                }
            }
            guard !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return event }
            if event.keyCode == 49 {
                store.play(); return nil
            }
            guard !store.selectedNoteIDs.isEmpty else { return event }
            if event.keyCode == 51 || event.keyCode == 117 {
                store.deleteSelected(); return nil
            }
            let direction: NoteKeyDirection
            switch event.keyCode {
            case 123: direction = .left
            case 124: direction = .right
            case 125: direction = .down
            case 126: direction = .up
            default: return event
            }
            store.nudgeSelection(direction, shift: flags.contains(.shift))
            return nil
        }
    }

    private func installKeyUpMonitor() {
        guard keyUpMonitor == nil else { return }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            guard store.isRecording,
                  (event.keyCode == 34 || event.charactersIgnoringModifiers?.lowercased() == "i")
            else { return event }
            store.endRecordedNote()
            return nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("트랙").font(.headline)
                Spacer()
                Button { store.addTrack() } label: { Image(systemName: "plus") }
                    .help("트랙 추가")
            }
            .padding(.horizontal, 12).padding(.top, 16)
            ForEach(store.document.tracks.indices, id: \.self) { index in
                Button {
                    store.selectTrack(index)
                } label: {
                    HStack {
                        Image(systemName: "music.note.list")
                        VStack(alignment: .leading) {
                            Text(store.document.tracks[index].name).lineLimit(1)
                            Text("\(store.document.tracks[index].notes.count)개 음표")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(index == store.selectedTrackIndex ? Color.accentColor.opacity(0.16) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
            }
            HStack {
                Button("이름 변경") { store.renameSelectedTrack() }
                Button("삭제") { store.deleteSelectedTrack() }
                    .disabled(store.document.tracks.count <= 1)
            }
            .padding(.horizontal, 12)
            Spacer()
            Button("MIDI 가져오기…") { store.importMIDI() }
                .padding(12)
        }
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var toolbar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                Text(store.document.title + (store.hasUnsavedChanges ? " •" : ""))
                    .font(.headline).lineLimit(1)
                Button("\(store.document.numerator)/\(store.document.denominator) · \(store.document.page.keySignature.label)") {
                    activeSheet = .meter
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Picker("보기", selection: $store.editorMode) {
                    ForEach(EditorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .frame(width: 255)
                if store.editorMode != .printPreview {
                    Button("페이지 설정") {
                        pageDraft = store.document.page
                        showingPageSettings = true
                    }
                }
            }
            if store.editorMode != .printPreview {
            HStack(spacing: 12) {
                Button {
                    store.play()
                } label: {
                    Label(store.isPlaying ? "정지" : "재생",
                          systemImage: store.isPlaying ? "stop.fill" : "play.fill")
                }
                Button {
                    store.toggleRecording()
                } label: {
                    Label(store.isCountingIn ? "카운트 취소" : (store.isRecording ? "녹음 종료" : "녹음"),
                          systemImage: store.isRecording || store.isCountingIn ? "stop.circle.fill" : "record.circle")
                }
                .foregroundStyle(store.isRecording || store.isCountingIn ? Color.red : Color.primary)
                .help("녹음 중 I 키를 누른 동안 C4 음표를 기록합니다")
                Button { store.addNote() } label: { Label("음표 추가", systemImage: "plus") }
                if store.editorMode == .score {
                    Menu("반복·이동 기호") {
                        Button("도돌이·1/2번 괄호…") { activeSheet = .repeats }
                        Button("D.C.·D.S.·Coda·Fine…") { activeSheet = .navigation }
                    }
                    Button("마디 코드") {
                        guard let scoreView else { return }
                        let page = store.document.page
                        let beat = store.visiblePlaybackBeat ?? 0
                        let index = max(0, Int(beat / page.beatsPerMeasure))
                        let tick = ChordGrid.snappedTick(beat: beat, measure: index, page: page)
                        presentChordEditor(at: tick, in: scoreView)
                    }
                    .help("재생선이 있는 박자의 코드를 입력합니다. 악보에서 마디 위를 클릭해도 됩니다.")
                }
                Spacer()
                Picker("정렬", selection: $store.grid) {
                    ForEach(ScoreGrid.allCases) { grid in Text(grid.label).tag(grid) }
                }
                .frame(width: 150)
                Toggle("멜로디 모드", isOn: $store.melodyMode)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Button(store.selectedNoteIDs.isEmpty ? "전체 정렬" : "선택 정렬") {
                    store.quantizeTrack()
                }
            }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: store.editorMode == .printPreview ? 48 : 86)
    }

    private var pageInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("페이지 설정").font(.headline)
                    Text("변경 내용은 악보에 미리 표시됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("곡 제목").font(.caption).foregroundStyle(.secondary)
                        TextField("곡 제목", text: $pageDraft.title)
                        Text("작곡가").font(.caption).foregroundStyle(.secondary)
                        TextField("작곡가", text: $pageDraft.composer)
                        Text("편곡가").font(.caption).foregroundStyle(.secondary)
                        TextField("편곡가", text: $pageDraft.arranger)
                    }
                    .textFieldStyle(.roundedBorder)
                    Divider()
                    Stepper("한 줄에 \(pageDraft.measuresPerLine)마디",
                            value: $pageDraft.measuresPerLine, in: 1...16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("음표 간격: \(Int(pageDraft.noteSpacing))pt")
                        Slider(value: $pageDraft.noteSpacing, in: 18...60, step: 1)
                        HStack {
                            Text("좁게")
                            Spacer()
                            Text("넓게")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("마디 간격: \(Int((pageDraft.measureWidthRatio * 100).rounded()))%")
                        Slider(value: $pageDraft.measureWidthRatio, in: 0.5...4, step: 0.05)
                        HStack {
                            Text("촘촘하게")
                            Spacer()
                            Text("넉넉하게")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("행간 여백: \(Int(pageDraft.rowGap))pt")
                        Slider(value: $pageDraft.rowGap, in: 0...160, step: 1)
                    }
                    Picker("가사 글꼴", selection: $pageDraft.lyricFontName) {
                        Text("시스템 기본").tag("")
                        if !pageDraft.lyricFontName.isEmpty &&
                            !Self.lyricFontFamilies.contains(pageDraft.lyricFontName) {
                            Text(pageDraft.lyricFontName).tag(pageDraft.lyricFontName)
                        }
                        ForEach(Self.lyricFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("가사 크기: \(Int(pageDraft.lyricFontSize))pt")
                        Slider(value: $pageDraft.lyricFontSize, in: 10...28, step: 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("취소") { showingPageSettings = false }
                Spacer()
                Button("적용") {
                    store.updatePage { page in
                        page.title = pageDraft.title
                        page.composer = pageDraft.composer
                        page.arranger = pageDraft.arranger
                        page.measuresPerLine = pageDraft.measuresPerLine
                        page.noteSpacing = pageDraft.noteSpacing
                        page.measureWidthRatio = pageDraft.measureWidthRatio
                        page.rowGap = pageDraft.rowGap
                        page.lyricFontName = pageDraft.lyricFontName
                        page.lyricFontSize = pageDraft.lyricFontSize
                    }
                    showingPageSettings = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 250, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("음표 편집").font(.headline)
                Spacer()
                if store.selectedNoteIDs.count > 1 {
                    Text("\(store.selectedNoteIDs.count)개 선택")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("복사") { store.copySelectedNotes() }
                    .disabled(store.selectedNoteIDs.isEmpty)
                Button("붙여넣기") { store.pasteNotes() }
                    .disabled(!store.canPasteNotes)
            }
            Text("빈 곳을 드래그해 여러 음표 선택 · Shift+클릭으로 추가")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = store.selectedNote {
                Text(NotatedPitch.spell(note.pitch, in: store.document.page.keySignature).name)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                HStack {
                    Button("♭") { store.updateSelected { $0.pitch -= 1 } }
                    Button("♯") { store.updateSelected { $0.pitch += 1 } }
                }
                Text("시작: \(note.startBeat.formatted())박")
                HStack {
                    Button("←") { store.updateSelected { $0.startBeat -= store.grid.rawValue } }
                    Button("→") { store.updateSelected { $0.startBeat += store.grid.rawValue } }
                }
                Text("길이: \(note.durationBeats.formatted())박")
                Picker("길이", selection: Binding(
                    get: { note.durationBeats },
                    set: { value in store.updateSelected { $0.durationBeats = value } }
                )) {
                    if ![0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
                        .contains(where: { abs($0 - note.durationBeats) < 0.001 }) {
                        Text("\(note.durationBeats.formatted())박").tag(note.durationBeats)
                    }
                    Text("16분").tag(0.25)
                    Text("8분").tag(0.5)
                    Text("점8분").tag(0.75)
                    Text("4분").tag(1.0)
                    Text("점4분").tag(1.5)
                    Text("2분").tag(2.0)
                    Text("점2분").tag(3.0)
                    Text("온음표").tag(4.0)
                }
                .labelsHidden()
                Button("음표 삭제", role: .destructive) { store.deleteSelected() }
                Text("원래 위치: \(note.originalStartBeat.formatted())박")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("음표를 클릭해 선택하세요.")
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("가사").font(.headline)
                Spacer()
                Button(store.lyricMode.rawValue) { store.toggleLyricMode() }
            }
            Picker("절", selection: $store.selectedLyricVerse) {
                ForEach(1...4, id: \.self) { verse in Text("\(verse)절").tag(verse) }
            }
            .pickerStyle(.segmented)
            Text(store.selectedNote?.lyric(for: store.selectedLyricVerse).isEmpty == false
                 ? "현재: \(store.selectedNote?.lyric(for: store.selectedLyricVerse) ?? "")"
                 : "선택한 음표부터 입력")
                .font(.caption).foregroundStyle(.secondary)
            LyricInputField(mode: store.lyricMode, enabled: store.selectedNote != nil) {
                store.assignLyricAndAdvance($0)
            }
            .id(store.selectedLyricVerse)
            .frame(height: 24)
            Text("Shift 두 번: 모드 변경 · 여러 글자 모드에서 Space: 다음 음")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Divider()
            Text("빠르기: \(Int(store.document.tempo)) BPM")
            HStack {
                Button("−") { store.setTempo(store.document.tempo - 5) }
                Button("+") { store.setTempo(store.document.tempo + 5) }
            }
        }
        .padding(16)
        .frame(width: 210, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
