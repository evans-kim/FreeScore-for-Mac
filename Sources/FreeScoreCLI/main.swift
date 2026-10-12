import Foundation

private struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func fail(_ message: String) -> CLIError { CLIError(message: message) }

private struct Options {
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ arguments: [String], allowedValues: Set<String>, allowedFlags: Set<String> = []) throws {
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--") else { throw fail("알 수 없는 인수: \(key)") }
            if allowedFlags.contains(key) {
                guard flags.insert(key).inserted else { throw fail("중복 옵션: \(key)") }
                index += 1
            } else if allowedValues.contains(key) {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw fail("\(key)에 값이 필요합니다.")
                }
                guard values[key] == nil else { throw fail("중복 옵션: \(key)") }
                values[key] = arguments[index + 1]
                index += 2
            } else {
                throw fail("지원하지 않는 옵션: \(key)")
            }
        }
    }

    func required(_ key: String) throws -> String {
        guard let value = values[key] else { throw fail("\(key)가 필요합니다.") }
        return value
    }
    func int(_ key: String, range: ClosedRange<Int>) throws -> Int? {
        guard let raw = values[key] else { return nil }
        guard let value = Int(raw), range.contains(value) else {
            throw fail("\(key)는 \(range.lowerBound)~\(range.upperBound) 정수여야 합니다.")
        }
        return value
    }
    func double(_ key: String, range: ClosedRange<Double>) throws -> Double? {
        guard let raw = values[key] else { return nil }
        guard let value = Double(raw), value.isFinite, range.contains(value) else {
            throw fail("\(key)는 \(range.lowerBound)~\(range.upperBound) 숫자여야 합니다.")
        }
        return value
    }
    func uuid(_ key: String) throws -> UUID {
        guard let id = UUID(uuidString: try required(key)) else { throw fail("\(key)는 UUID여야 합니다.") }
        return id
    }
}

private struct NoteInfo: Encodable {
    let id: UUID
    let pitch: Int
    let name: String
    let startBeat: Double
    let bar: Int
    let beat: Double
    let durationBeats: Double
    let velocity: Int
    let channel: Int
    let lyric: String
    let lyrics: [String]
}

private struct TrackInfo: Encodable {
    let index: Int
    let id: UUID
    let name: String
    let clef: Clef
    let noteCount: Int
    let notes: [NoteInfo]
    let omittedNotes: Int
}

private struct ChordInfo: Encodable {
    let bar: Int
    let beat: Int
    let positionTick: Int
    let symbol: String
    let followsKey: Bool
}

private struct Inspection: Encodable {
    let page: Page
    let tempo: Double
    let tracks: [TrackInfo]
    let chords: [ChordInfo]
    let repeats: [RepeatSection]
    let navigationMarks: [NavigationMark]
    let playbackBars: [Int]
}

@main
struct FreeScoreCLI {
    static let help = """
    FreeScore for Mac 프로젝트 편집 CLI — 박자 위치는 1부터, 트랙 번호도 1부터 셉니다.

    Scripts/midiscore import-midi FILE.mid --out FILE.mscore [--grid 4|8|16|32]
    Scripts/midiscore inspect FILE.mscore [--track N] [--from-bar N] [--to-bar N] [--limit N] [--json]
    Scripts/midiscore page set FILE.mscore [--title TEXT] [--composer TEXT] [--arranger TEXT]
      [--key G|Bb|F#...] [--meter 3/4] [--tempo BPM] [--measures-per-line N]
      [--note-spacing PT] [--measure-spacing 50..400] [--row-gap PT]
      [--lyric-font NAME] [--lyric-size PT] (--out NEW.mscore | --in-place)
    Scripts/midiscore track add FILE.mscore --name TEXT (--out NEW.mscore | --in-place)
    Scripts/midiscore track rename|remove FILE.mscore --track N [--name TEXT] (--out NEW.mscore | --in-place)
    Scripts/midiscore note add FILE.mscore --track N --pitch C4 --bar N --beat N --duration QUARTERS
      [--lyric TEXT --verse 1..4] [--velocity 1..127] [--channel 0..15] (--out NEW.mscore | --in-place)
    Scripts/midiscore note set FILE.mscore --track N --id UUID [--pitch C4] [--bar N --beat N]
      [--at QUARTER_BEAT] [--duration QUARTERS] [--lyric TEXT --verse 1..4] [--velocity N]
      (--out NEW.mscore | --in-place)
    Scripts/midiscore note remove FILE.mscore --track N --id UUID (--out NEW.mscore | --in-place)
    Scripts/midiscore chord set FILE.mscore --bar N --beat N --symbol 'D/F#' [--fixed-key]
      (--out NEW.mscore | --in-place)
    Scripts/midiscore chord remove FILE.mscore --bar N --beat N (--out NEW.mscore | --in-place)
    Scripts/midiscore repeat add FILE.mscore --start-bar N --end-bar N
      [--first-ending-bar N --second-ending-end-bar N] (--out NEW.mscore | --in-place)
    Scripts/midiscore repeat remove FILE.mscore --start-bar N (--out NEW.mscore | --in-place)
    Scripts/midiscore navigation add FILE.mscore --bar N
      --kind segno|coda|to-coda|fine|dc|ds|dc-fine|ds-fine|dc-coda|ds-coda
      (--out NEW.mscore | --in-place)
    Scripts/midiscore navigation remove FILE.mscore --kind KIND (--out NEW.mscore | --in-place)
    Scripts/midiscore quantize FILE.mscore --track N --grid 4|8|16|32
      [--ids UUID,UUID] [--melody] (--out NEW.mscore | --in-place)
    Scripts/midiscore export-midi FILE.mscore --track N --out FILE.mid

    모든 편집은 --out으로 새 파일을 만들거나 --in-place를 명시해야 합니다.
    기존 --out 대상은 --force를 추가할 때만 덮어씁니다. GUI에서 같은 파일을 열어 편집 중이라면 먼저 저장하고 닫으세요.
    --at과 --duration은 4분음표 기준 절대 박자입니다. --bar/--beat는 현재 박자표의 1부터 시작하는 위치입니다.
    """

    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
                print(help)
                return
            }
            try run(arguments)
        } catch {
            fputs("오류: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ args: [String]) throws {
        switch args[0] {
        case "import-midi":
            let (path, options) = try pathAndOptions(args, prefix: 1,
                values: ["--out", "--grid"], flags: ["--force"])
            let grid = try parseGrid(options.values["--grid"] ?? "16")
            let output = try outputURL(options, source: nil, extensionName: "mscore")
            let document = try MIDIService.importFile(URL(fileURLWithPath: path), grid: grid)
            try save(document, to: output)
            print("가져오기 완료: \(document.tracks.count)개 트랙 → \(output.path)")
        case "inspect":
            let (path, options) = try pathAndOptions(args, prefix: 1,
                values: ["--track", "--from-bar", "--to-bar", "--limit"], flags: ["--json"])
            let document = try load(path)
            try inspect(document, options: options)
        case "page", "track", "note", "chord", "repeat", "navigation":
            try edit(args)
        case "quantize":
            let (path, options) = try pathAndOptions(args, prefix: 1,
                values: ["--track", "--grid", "--ids", "--out"],
                flags: ["--melody", "--in-place", "--force"])
            var document = try load(path)
            let index = try trackIndex(options, document: document)
            let grid = try parseGrid(options.required("--grid"))
            let ids = try parseIDs(options.values["--ids"], notes: document.tracks[index].notes)
            document.tracks[index].notes = ScoreOperations.quantizedNotes(
                document.tracks[index].notes, grid: grid, selectedIDs: ids,
                melodyMode: options.flags.contains("--melody"))
            try commit(document, source: path, options: options)
        case "export-midi":
            let (path, options) = try pathAndOptions(args, prefix: 1,
                values: ["--track", "--out"], flags: ["--force"])
            let document = try load(path)
            let index = try trackIndex(options, document: document)
            let output = try outputURL(options, source: path, extensionName: "mid")
            try MIDIService.midiData(document: document, trackIndex: index)
                .write(to: output, options: .atomic)
            print("MIDI 내보내기 완료: \(output.path)")
        default:
            throw fail("알 수 없는 명령: \(args[0]). --help를 실행하세요.")
        }
    }

    private static func edit(_ args: [String]) throws {
        guard args.count >= 3 else { throw fail("명령과 프로젝트 경로가 필요합니다. --help를 확인하세요.") }
        let group = args[0], action = args[1], path = args[2]
        let commonValues: Set<String> = ["--out"]
        let commonFlags: Set<String> = ["--in-place", "--force"]
        let extraValues: Set<String>
        let extraFlags: Set<String>
        switch (group, action) {
        case ("page", "set"):
            extraValues = ["--title", "--composer", "--arranger", "--key", "--meter", "--tempo",
                           "--measures-per-line", "--note-spacing", "--measure-spacing",
                           "--row-gap", "--lyric-font", "--lyric-size"]
            extraFlags = []
        case ("track", "add"):
            extraValues = ["--name", "--clef"]
            extraFlags = []
        case ("track", "rename"):
            extraValues = ["--track", "--name", "--clef"]
            extraFlags = []
        case ("track", "remove"):
            extraValues = ["--track"]
            extraFlags = []
        case ("note", "add"):
            extraValues = ["--track", "--pitch", "--bar", "--beat", "--at",
                           "--duration", "--lyric", "--verse", "--velocity", "--channel"]
            extraFlags = []
        case ("note", "set"):
            extraValues = ["--track", "--id", "--pitch", "--bar", "--beat", "--at",
                           "--duration", "--lyric", "--verse", "--velocity", "--channel"]
            extraFlags = []
        case ("note", "remove"):
            extraValues = ["--track", "--id"]
            extraFlags = []
        case ("chord", "set"):
            extraValues = ["--bar", "--beat", "--symbol"]
            extraFlags = ["--fixed-key"]
        case ("chord", "remove"):
            extraValues = ["--bar", "--beat"]
            extraFlags = []
        case ("repeat", "add"):
            extraValues = ["--start-bar", "--end-bar", "--first-ending-bar", "--second-ending-end-bar"]
            extraFlags = []
        case ("repeat", "remove"):
            extraValues = ["--start-bar"]
            extraFlags = []
        case ("navigation", "add"):
            extraValues = ["--bar", "--kind"]
            extraFlags = []
        case ("navigation", "remove"):
            extraValues = ["--kind"]
            extraFlags = []
        default:
            throw fail("알 수 없는 편집 명령: \(group) \(action)")
        }
        let options = try Options(Array(args.dropFirst(3)),
                                  allowedValues: commonValues.union(extraValues),
                                  allowedFlags: commonFlags.union(extraFlags))
        var document = try load(path)
        var createdNoteID: UUID?
        switch group {
        case "page": try editPage(&document, options)
        case "track": try editTrack(&document, action, options)
        case "note": createdNoteID = try editNote(&document, action, options)
        case "chord": try editChord(&document, action, options)
        case "repeat": try editRepeat(&document, action, options)
        case "navigation": try editNavigation(&document, action, options)
        default: break
        }
        try commit(document, source: path, options: options)
        if let createdNoteID { print("새 음표 ID: \(createdNoteID.uuidString)") }
    }

    private static func editPage(_ document: inout ScoreDocument, _ o: Options) throws {
        guard o.values.keys.contains(where: { $0 != "--out" }) else {
            throw fail("변경할 페이지 옵션을 지정하세요.")
        }
        if let value = o.values["--title"] { document.page.title = value }
        if let value = o.values["--composer"] { document.page.composer = value }
        if let value = o.values["--arranger"] { document.page.arranger = value }
        if let value = o.values["--key"] { document.page.keySignature = try parseKey(value) }
        if let value = o.values["--meter"] {
            let parts = value.split(separator: "/")
            guard parts.count == 2, let numerator = Int(parts[0]),
                  let denominator = Int(parts[1]), (1...12).contains(numerator),
                  [2, 4, 8, 16].contains(denominator) else {
                throw fail("--meter 형식은 3/4처럼 쓰고 분모는 2, 4, 8, 16 중 하나여야 합니다.")
            }
            document.page.numerator = numerator
            document.page.denominator = denominator
        }
        if let value = try o.double("--tempo", range: 20...300) { document.tempo = value }
        if let value = try o.int("--measures-per-line", range: 1...16) { document.page.measuresPerLine = value }
        if let value = try o.double("--note-spacing", range: 18...60) { document.page.noteSpacing = value }
        if let value = try o.double("--measure-spacing", range: 50...400) {
            document.page.measureWidthRatio = value / 100
        }
        if let value = try o.double("--row-gap", range: 0...160) { document.page.rowGap = value }
        if let value = o.values["--lyric-font"] { document.page.lyricFontName = value }
        if let value = try o.double("--lyric-size", range: 10...28) { document.page.lyricFontSize = value }
    }

    private static func editTrack(_ document: inout ScoreDocument, _ action: String,
                                  _ o: Options) throws {
        switch action {
        case "add":
            guard o.values["--track"] == nil else { throw fail("track add에는 --track을 사용하지 않습니다.") }
            let name = try nonempty(o.required("--name"), name: "--name")
            let clef = try parseClef(o.values["--clef"] ?? "treble")
            document.tracks.append(ScoreTrack(name: name, notes: [], clef: clef))
        case "rename":
            let index = try trackIndex(o, document: document)
            document.tracks[index].name = try nonempty(o.required("--name"), name: "--name")
            if let clef = o.values["--clef"] { document.tracks[index].clef = try parseClef(clef) }
        case "remove":
            guard document.tracks.count > 1 else { throw fail("마지막 트랙은 삭제할 수 없습니다.") }
            document.tracks.remove(at: try trackIndex(o, document: document))
        default: break
        }
    }

    private static func editNote(_ document: inout ScoreDocument, _ action: String,
                                 _ o: Options) throws -> UUID? {
        let index = try trackIndex(o, document: document)
        let verse = try o.int("--verse", range: 1...4) ?? 1
        guard o.values["--verse"] == nil || o.values["--lyric"] != nil else {
            throw fail("--verse는 --lyric과 함께 지정하세요.")
        }
        switch action {
        case "add":
            let pitch = try parsePitch(o.required("--pitch"))
            let start = try notePosition(o, page: document.page, required: true)!
            let duration = try o.double("--duration", range: 0.000001...1_000_000)
            guard let duration else { throw fail("--duration이 필요합니다.") }
            let velocity = try o.int("--velocity", range: 1...127) ?? 90
            let channel = try o.int("--channel", range: 0...15) ?? 0
            var note = ScoreNote(pitch: pitch, startBeat: start, durationBeats: duration,
                                 velocity: velocity, channel: channel,
                                 originalStartBeat: start, originalDurationBeats: duration,
                                 lyric: "")
            if let lyric = o.values["--lyric"] { note.setLyric(lyric, for: verse) }
            document.tracks[index].notes.append(note)
            sortNotes(&document.tracks[index].notes)
            return note.id
        case "set":
            let id = try o.uuid("--id")
            guard let noteIndex = document.tracks[index].notes.firstIndex(where: { $0.id == id }) else {
                throw fail("트랙 \(index + 1)에서 음표 ID를 찾지 못했습니다: \(id)")
            }
            guard o.values.keys.contains(where: { !["--id", "--track", "--out", "--verse"].contains($0) }) else {
                throw fail("변경할 음표 옵션을 지정하세요.")
            }
            var note = document.tracks[index].notes[noteIndex]
            if let value = o.values["--pitch"] { note.pitch = try parsePitch(value) }
            if let value = try notePosition(o, page: document.page, required: false) {
                note.startBeat = value
            }
            if let value = try o.double("--duration", range: 0.000001...1_000_000) {
                note.durationBeats = value
            }
            if let value = o.values["--lyric"] { note.setLyric(value, for: verse) }
            if let value = try o.int("--velocity", range: 1...127) { note.velocity = value }
            if let value = try o.int("--channel", range: 0...15) { note.channel = value }
            document.tracks[index].notes[noteIndex] = note
            sortNotes(&document.tracks[index].notes)
        case "remove":
            let id = try o.uuid("--id")
            let before = document.tracks[index].notes.count
            document.tracks[index].notes.removeAll { $0.id == id }
            guard document.tracks[index].notes.count < before else { throw fail("음표 ID를 찾지 못했습니다: \(id)") }
        default: break
        }
        return nil
    }

    private static func editChord(_ document: inout ScoreDocument, _ action: String,
                                  _ o: Options) throws {
        let bar = try o.int("--bar", range: 1...100_000)
        let beat = try o.int("--beat", range: 1...document.page.numerator)
        guard let bar, let beat else { throw fail("코드 위치에는 --bar와 --beat가 필요합니다.") }
        let tick = ChordGrid.tick(measure: bar - 1, slot: beat - 1, page: document.page)
        if action == "set" {
            let text = try o.required("--symbol")
            guard let chord = ChordSymbol(text: text, key: document.page.keySignature,
                                          followsKey: !o.flags.contains("--fixed-key")) else {
                throw fail("코드 형식이 올바르지 않습니다: \(text)")
            }
            document.chordEvents.removeAll { $0.positionTick == tick }
            document.chordEvents.append(ChordEvent(positionTick: tick, chord: chord))
            document.chordEvents.sort { $0.positionTick < $1.positionTick }
        } else {
            let before = document.chordEvents.count
            document.chordEvents.removeAll { $0.positionTick == tick }
            guard document.chordEvents.count < before else { throw fail("해당 박자에 코드가 없습니다.") }
        }
    }

    private static func editRepeat(_ document: inout ScoreDocument, _ action: String,
                                   _ o: Options) throws {
        guard let start = try o.int("--start-bar", range: 1...10_000) else {
            throw fail("--start-bar가 필요합니다.")
        }
        if action == "remove" {
            let before = document.repeatSections.count
            document.repeatSections.removeAll { $0.startMeasure == start - 1 }
            guard document.repeatSections.count < before else {
                throw fail("\(start)마디에서 시작하는 도돌이가 없습니다.")
            }
            return
        }
        guard let end = try o.int("--end-bar", range: 1...10_000) else {
            throw fail("--end-bar가 필요합니다.")
        }
        let first = try o.int("--first-ending-bar", range: 1...10_000)
        let second = try o.int("--second-ending-end-bar", range: 1...10_000)
        let section = RepeatSection(startMeasure: start - 1, endMeasure: end - 1,
            firstEndingStartMeasure: first.map { $0 - 1 },
            secondEndingEndMeasure: second.map { $0 - 1 })
        document.repeatSections.removeAll { $0.startMeasure == section.startMeasure }
        document.repeatSections.append(section)
        try RepeatPlaybackPlan.validate(repeats: document.repeatSections,
                                        navigation: document.navigationMarks)
        document.repeatSections.sort { $0.startMeasure < $1.startMeasure }
    }

    private static func editNavigation(_ document: inout ScoreDocument, _ action: String,
                                       _ o: Options) throws {
        let raw = try o.required("--kind")
        guard let kind = NavigationMark.Kind(rawValue: raw) else {
            throw fail("지원하지 않는 이동 기호: \(raw). --help를 확인하세요.")
        }
        if action == "add" {
            guard let bar = try o.int("--bar", range: 1...10_000) else {
                throw fail("--bar가 필요합니다.")
            }
            document.navigationMarks.removeAll { $0.kind == kind }
            document.navigationMarks.append(NavigationMark(measure: bar - 1, kind: kind))
        } else {
            let before = document.navigationMarks.count
            document.navigationMarks.removeAll { $0.kind == kind }
            guard document.navigationMarks.count < before else {
                throw fail("\(raw) 기호가 없습니다.")
            }
        }
        try RepeatPlaybackPlan.validate(repeats: document.repeatSections,
                                        navigation: document.navigationMarks)
        document.navigationMarks.sort {
            $0.measure == $1.measure ? $0.kind.rawValue < $1.kind.rawValue :
                $0.measure < $1.measure
        }
    }

    private static func inspect(_ document: ScoreDocument, options o: Options) throws {
        let from = try o.int("--from-bar", range: 1...100_000) ?? 1
        let to = try o.int("--to-bar", range: 1...100_000) ?? 100_000
        guard from <= to else { throw fail("--from-bar는 --to-bar보다 작거나 같아야 합니다.") }
        let limit = try o.int("--limit", range: 0...1_000_000) ?? 40
        let indices: [Int] = if o.values["--track"] != nil {
            [try trackIndex(o, document: document)]
        } else { Array(document.tracks.indices) }
        let page = document.page
        let tracks = indices.map { index -> TrackInfo in
            let track = document.tracks[index]
            let filtered = track.notes.filter { note in
                let bar = Int(floor(note.startBeat / page.beatsPerMeasure)) + 1
                return (from...to).contains(bar)
            }
            let selected = limit == 0 ? filtered : Array(filtered.prefix(limit))
            let notes = selected.map { note -> NoteInfo in
                let bar = Int(floor(note.startBeat / page.beatsPerMeasure)) + 1
                let beat = (note.startBeat - Double(bar - 1) * page.beatsPerMeasure) /
                    (4.0 / Double(page.denominator)) + 1
                return NoteInfo(id: note.id, pitch: note.pitch, name: note.name,
                                startBeat: note.startBeat, bar: bar, beat: beat,
                                durationBeats: note.durationBeats, velocity: note.velocity,
                                channel: note.channel, lyric: note.lyric,
                                lyrics: (1...4).map { note.lyric(for: $0) })
            }
            return TrackInfo(index: index + 1, id: track.id, name: track.name, clef: track.clef,
                             noteCount: track.notes.count, notes: notes,
                             omittedNotes: filtered.count - notes.count)
        }
        let chords = document.chordEvents.compactMap { event -> ChordInfo? in
            let bar = ChordGrid.measure(for: event.positionTick, page: page) + 1
            guard (from...to).contains(bar) else { return nil }
            return ChordInfo(bar: bar, beat: ChordGrid.slot(for: event.positionTick, page: page) + 1,
                             positionTick: event.positionTick,
                             symbol: event.chord.symbol(in: page.keySignature),
                             followsKey: event.chord.followsKey)
        }
        let plan = try RepeatPlaybackPlan(page: page, notes: document.tracks.flatMap(\.notes),
            chords: document.chordEvents, repeats: document.repeatSections,
            navigation: document.navigationMarks)
        let inspection = Inspection(page: page, tempo: document.tempo, tracks: tracks,
                                    chords: chords, repeats: document.repeatSections,
                                    navigationMarks: document.navigationMarks,
                                    playbackBars: plan.scoreMeasures.map { $0 + 1 })
        if o.flags.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(inspection), encoding: .utf8)!)
        } else {
            print("\(page.title) · \(page.numerator)/\(page.denominator) · \(page.keySignature.label) · \(document.tempo) BPM")
            print("마디 간격 \(Int(page.measureWidthRatio * 100))%, 한 줄 \(page.measuresPerLine)마디")
            for track in tracks {
                print("트랙 \(track.index): \(track.name) (\(track.noteCount)개 음표, \(track.clef.rawValue))")
                for note in track.notes {
                    let lyrics = note.lyrics.enumerated().compactMap { index, value in
                        value.isEmpty ? nil : "\(index + 1)절 \(value)"
                    }.joined(separator: " / ")
                    print("  \(note.id.uuidString)  \(note.name)  \(note.bar)마디 \(note.beat)박  길이 \(note.durationBeats)  가사 \(lyrics)")
                }
                if track.omittedNotes > 0 { print("  … \(track.omittedNotes)개 생략 (--limit 0으로 모두 보기)") }
            }
            for chord in chords { print("코드 \(chord.bar)마디 \(chord.beat)박: \(chord.symbol)") }
            for section in document.repeatSections { print("반복 \(section.description)") }
            for mark in document.navigationMarks { print("이동 \(mark.description)") }
            if !document.repeatSections.isEmpty || !document.navigationMarks.isEmpty {
                print("재생 마디 순서: \(inspection.playbackBars.map(String.init).joined(separator: " → "))")
            }
        }
    }

    private static func pathAndOptions(_ args: [String], prefix: Int,
                                       values: Set<String>, flags: Set<String> = [])
        throws -> (String, Options) {
        guard args.count > prefix, !args[prefix].hasPrefix("--") else { throw fail("파일 경로가 필요합니다.") }
        return (args[prefix], try Options(Array(args.dropFirst(prefix + 1)),
                                          allowedValues: values, allowedFlags: flags))
    }

    private static func load(_ path: String) throws -> ScoreDocument {
        let document = try JSONDecoder().decode(ScoreDocument.self,
                                                from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard !document.tracks.isEmpty else { throw fail("프로젝트에 트랙이 없습니다.") }
        try RepeatPlaybackPlan.validate(repeats: document.repeatSections,
                                        navigation: document.navigationMarks)
        return document
    }

    private static func commit(_ document: ScoreDocument, source: String, options: Options) throws {
        let output = try outputURL(options, source: source, extensionName: "mscore")
        try save(document, to: output)
        print("저장 완료: \(output.path)")
    }

    private static func save(_ document: ScoreDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        _ = try JSONDecoder().decode(ScoreDocument.self, from: data)
        try RepeatPlaybackPlan.validate(repeats: document.repeatSections,
                                        navigation: document.navigationMarks)
        try data.write(to: url, options: .atomic)
    }

    private static func outputURL(_ o: Options, source: String?, extensionName: String) throws -> URL {
        let inPlace = o.flags.contains("--in-place")
        guard !(inPlace && o.values["--out"] != nil) else { throw fail("--out과 --in-place 중 하나만 지정하세요.") }
        guard let raw = inPlace ? source : o.values["--out"] else {
            throw fail("--out NEW.\(extensionName) 또는 --in-place가 필요합니다.")
        }
        guard !inPlace || extensionName == "mscore" else { throw fail("MIDI 내보내기는 --out을 사용하세요.") }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        guard url.pathExtension.lowercased() == extensionName else {
            throw fail("출력 파일 확장자는 .\(extensionName)여야 합니다.")
        }
        if let source, !inPlace,
           url == URL(fileURLWithPath: source).standardizedFileURL {
            throw fail("원본 경로와 출력 경로가 같습니다. --in-place를 명시하세요.")
        }
        if !inPlace && FileManager.default.fileExists(atPath: url.path) && !o.flags.contains("--force") {
            throw fail("출력 파일이 이미 있습니다. 덮어쓰려면 --force를 지정하세요: \(url.path)")
        }
        return url
    }

    private static func trackIndex(_ o: Options, document: ScoreDocument) throws -> Int {
        guard let number = try o.int("--track", range: 1...document.tracks.count) else {
            throw fail("--track 1...\(document.tracks.count)가 필요합니다.")
        }
        return number - 1
    }

    private static func notePosition(_ o: Options, page: Page, required: Bool) throws -> Double? {
        if let at = try o.double("--at", range: 0...1_000_000) {
            guard o.values["--bar"] == nil && o.values["--beat"] == nil else {
                throw fail("--at과 --bar/--beat는 함께 사용할 수 없습니다.")
            }
            return at
        }
        let bar = try o.int("--bar", range: 1...100_000)
        let beat = try o.double("--beat", range: 1...Double(page.numerator))
        if bar != nil || beat != nil {
            guard let bar, let beat else { throw fail("--bar와 --beat는 함께 지정하세요.") }
            return Double(bar - 1) * page.beatsPerMeasure +
                (beat - 1) * 4.0 / Double(page.denominator)
        }
        if required { throw fail("--at 또는 --bar/--beat가 필요합니다.") }
        return nil
    }

    private static func parsePitch(_ raw: String) throws -> Int {
        if let pitch = Int(raw), (0...127).contains(pitch) { return pitch }
        let pattern = try NSRegularExpression(pattern: #"^([A-Ga-g])([#b♯♭]?)(-?\d+)$"#)
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = pattern.firstMatch(in: raw, range: range),
              let letterRange = Range(match.range(at: 1), in: raw),
              let accidentalRange = Range(match.range(at: 2), in: raw),
              let octaveRange = Range(match.range(at: 3), in: raw),
              let octave = Int(raw[octaveRange]),
              let index = ["C", "D", "E", "F", "G", "A", "B"].firstIndex(of: raw[letterRange].uppercased()) else {
            throw fail("--pitch는 C4, F#3, Bb4 또는 MIDI 번호 0...127로 지정하세요.")
        }
        let accidental = String(raw[accidentalRange])
        let offset = accidental == "#" || accidental == "♯" ? 1 :
            accidental == "b" || accidental == "♭" ? -1 : 0
        let pitch = (octave + 1) * 12 + [0, 2, 4, 5, 7, 9, 11][index] + offset
        guard (0...127).contains(pitch) else { throw fail("MIDI 음높이는 0...127이어야 합니다.") }
        return pitch
    }

    private static func parseKey(_ raw: String) throws -> KeySignature {
        let keys: [String: KeySignature] = [
            "Cb": .cFlat, "Gb": .gFlat, "Db": .dFlat, "Ab": .aFlat,
            "Eb": .eFlat, "Bb": .bFlat, "F": .f, "C": .c, "G": .g,
            "D": .d, "A": .a, "E": .e, "B": .b, "F#": .fSharp, "C#": .cSharp
        ]
        let normalized = raw.replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
        guard let key = keys[normalized] else { throw fail("지원하지 않는 장조: \(raw)") }
        return key
    }

    private static func parseClef(_ raw: String) throws -> Clef {
        guard let clef = Clef(rawValue: raw) else { throw fail("--clef는 treble, bass, alto 중 하나입니다.") }
        return clef
    }

    private static func parseGrid(_ raw: String) throws -> ScoreGrid {
        switch raw {
        case "4": return .quarter
        case "8": return .eighth
        case "16": return .sixteenth
        case "32": return .thirtySecond
        default: throw fail("--grid는 4, 8, 16, 32 중 하나입니다.")
        }
    }

    private static func parseIDs(_ raw: String?, notes: [ScoreNote]) throws -> Set<UUID> {
        guard let raw else { return [] }
        let ids = try raw.split(separator: ",").map { item -> UUID in
            guard let id = UUID(uuidString: String(item)) else { throw fail("잘못된 음표 UUID: \(item)") }
            return id
        }
        guard !ids.isEmpty else { throw fail("--ids에 음표 UUID가 필요합니다.") }
        let valid = Set(notes.map(\.id))
        guard Set(ids).isSubset(of: valid) else { throw fail("--ids에 트랙에 없는 음표가 있습니다.") }
        return Set(ids)
    }

    private static func nonempty(_ raw: String, name: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw fail("\(name)은 비워 둘 수 없습니다.") }
        return value
    }

    private static func sortNotes(_ notes: inout [ScoreNote]) {
        notes.sort { $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat }
    }
}
