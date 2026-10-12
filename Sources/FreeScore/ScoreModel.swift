import Foundation

struct ScoreNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var pitch: Int
    var startBeat: Double
    var durationBeats: Double
    var velocity: Int = 90
    var channel: Int = 0
    var originalStartBeat: Double
    var originalDurationBeats: Double
    var lyric: String = ""
    var additionalLyrics: [String] = []

    func lyric(for verse: Int) -> String {
        guard (1...4).contains(verse) else { return "" }
        return verse == 1 ? lyric : (additionalLyrics.indices.contains(verse - 2)
            ? additionalLyrics[verse - 2] : "")
    }

    mutating func setLyric(_ value: String, for verse: Int) {
        guard (1...4).contains(verse) else { return }
        if verse == 1 { lyric = value; return }
        while additionalLyrics.count < verse - 1 { additionalLyrics.append("") }
        additionalLyrics[verse - 2] = value
        while additionalLyrics.last == "" { additionalLyrics.removeLast() }
    }

    var highestLyricVerse: Int {
        (1...4).reversed().first { !lyric(for: $0).isEmpty } ?? 0
    }

    var name: String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[(pitch % 12 + 12) % 12])\(pitch / 12 - 1)"
    }
}

extension ScoreNote {
    private enum CodingKeys: String, CodingKey {
        case id, pitch, startBeat, durationBeats, velocity, channel
        case originalStartBeat, originalDurationBeats, lyric, additionalLyrics
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        pitch = try values.decode(Int.self, forKey: .pitch)
        startBeat = try values.decode(Double.self, forKey: .startBeat)
        durationBeats = try values.decode(Double.self, forKey: .durationBeats)
        velocity = try values.decodeIfPresent(Int.self, forKey: .velocity) ?? 90
        channel = try values.decodeIfPresent(Int.self, forKey: .channel) ?? 0
        originalStartBeat = try values.decodeIfPresent(Double.self, forKey: .originalStartBeat) ?? startBeat
        originalDurationBeats = try values.decodeIfPresent(Double.self, forKey: .originalDurationBeats) ?? durationBeats
        lyric = try values.decodeIfPresent(String.self, forKey: .lyric) ?? ""
        additionalLyrics = Array((try values.decodeIfPresent([String].self,
            forKey: .additionalLyrics) ?? []).prefix(3))
    }
}

enum Clef: String, Codable, CaseIterable, Identifiable {
    case treble, bass, alto

    var id: String { rawValue }
    var label: String {
        switch self {
        case .treble: return "높은음자리표"
        case .bass: return "낮은음자리표"
        case .alto: return "가온음자리표"
        }
    }
    var symbol: String {
        switch self {
        case .treble: return "𝄞"
        case .bass: return "𝄢"
        case .alto: return "𝄡"
        }
    }
}

enum KeySignature: Int, Codable, CaseIterable, Identifiable {
    case cFlat = -7, gFlat = -6, dFlat = -5, aFlat = -4
    case eFlat = -3, bFlat = -2, f = -1, c = 0
    case g = 1, d = 2, a = 3, e = 4, b = 5, fSharp = 6, cSharp = 7

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .cFlat: "C♭ 장조"
        case .gFlat: "G♭ 장조"
        case .dFlat: "D♭ 장조"
        case .aFlat: "A♭ 장조"
        case .eFlat: "E♭ 장조"
        case .bFlat: "B♭ 장조"
        case .f: "F 장조"
        case .c: "C 장조"
        case .g: "G 장조"
        case .d: "D 장조"
        case .a: "A 장조"
        case .e: "E 장조"
        case .b: "B 장조"
        case .fSharp: "F♯ 장조"
        case .cSharp: "C♯ 장조"
        }
    }
    var accidentalCount: Int { abs(rawValue) }
    var isFlat: Bool { rawValue < 0 }
    var tonicPitchClass: Int { ((rawValue * 7) % 12 + 12) % 12 }
    var alteredLetters: [Int] {
        let order = isFlat ? [6, 2, 5, 1, 4, 0, 3] : [3, 0, 4, 1, 5, 2, 6]
        return Array(order.prefix(accidentalCount))
    }
    func alteration(for letter: Int) -> Int {
        alteredLetters.contains(letter) ? (isFlat ? -1 : 1) : 0
    }
}

enum ChordQuality: String, Codable, CaseIterable, Identifiable {
    case major, minor, diminished, augmented, dominantSeventh, majorSeventh, minorSeventh, suspendedFourth

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .major: ""
        case .minor: "m"
        case .diminished: "dim"
        case .augmented: "aug"
        case .dominantSeventh: "7"
        case .majorSeventh: "maj7"
        case .minorSeventh: "m7"
        case .suspendedFourth: "sus4"
        }
    }
    var label: String {
        switch self {
        case .major: "장화음"
        case .minor: "단화음"
        case .diminished: "감화음"
        case .augmented: "증화음"
        case .dominantSeventh: "도미넌트 7"
        case .majorSeventh: "메이저 7"
        case .minorSeventh: "마이너 7"
        case .suspendedFourth: "서스 4"
        }
    }
}

struct MeasureChord: Codable, Equatable {
    // The interval from the key tonic keeps the harmonic role when the key changes.
    var tonicOffset: Int
    var quality: ChordQuality

    init(rootPitchClass: Int, quality: ChordQuality, key: KeySignature) {
        tonicOffset = ((rootPitchClass - key.tonicPitchClass) % 12 + 12) % 12
        self.quality = quality
    }

    func rootPitchClass(in key: KeySignature) -> Int {
        ((key.tonicPitchClass + tonicOffset) % 12 + 12) % 12
    }

    func symbol(in key: KeySignature) -> String {
        Self.rootName(for: rootPitchClass(in: key), in: key) + quality.symbol
    }

    static func rootName(for pitchClass: Int, in key: KeySignature) -> String {
        let natural = [0, 2, 4, 5, 7, 9, 11]
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        let target = ((pitchClass % 12) + 12) % 12
        let preferFlat = key.isFlat || (key == .c && [3, 8, 10].contains(target))
        let candidates = (0..<7).map { letter -> (score: Int, name: String) in
            let inKey = (natural[letter] + key.alteration(for: letter) + 12) % 12
            let deviation = ((target - inKey + 18) % 12) - 6
            let accidental = key.alteration(for: letter) + deviation
            let directionPenalty = deviation == 0 ? 0 :
                ((preferFlat && deviation > 0) || (!preferFlat && deviation < 0) ? 1 : 0)
            let marks = switch accidental {
            case -2: "𝄫"
            case -1: "♭"
            case 0: ""
            case 1: "♯"
            case 2: "𝄪"
            default: ""
            }
            return (abs(deviation) * 10 + max(0, abs(accidental) - 1) * 3 + directionPenalty,
                    letters[letter] + marks)
        }
        return candidates.min { $0.score < $1.score }!.name
    }
}

struct ScoreTrack: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var notes: [ScoreNote]
    var clef: Clef = .treble
}

extension ScoreTrack {
    private enum CodingKeys: String, CodingKey { case id, name, notes, clef }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        notes = try values.decode([ScoreNote].self, forKey: .notes)
        clef = try values.decodeIfPresent(Clef.self, forKey: .clef) ?? .treble
    }
}

struct Page: Codable, Equatable {
    var title: String = "새 악보"
    var composer: String = ""
    var arranger: String = ""
    var keySignature: KeySignature = .c
    var measuresPerLine: Int = 8
    var noteSpacing: Double = 29
    var measureWidthRatio: Double = 1
    var rowGap: Double = 15
    var lyricFontName: String = ""
    var lyricFontSize: Double = 15
    var numerator: Int = 4
    var denominator: Int = 4

    var beatsPerMeasure: Double { Double(numerator) * 4.0 / Double(denominator) }

    init(title: String = "새 악보", composer: String = "", arranger: String = "",
         keySignature: KeySignature = .c, measuresPerLine: Int = 8,
         numerator: Int = 4, denominator: Int = 4, noteSpacing: Double = 29,
         measureWidthRatio: Double = 1, rowGap: Double = 15,
         lyricFontName: String = "", lyricFontSize: Double = 15) {
        self.title = title
        self.composer = composer
        self.arranger = arranger
        self.keySignature = keySignature
        self.measuresPerLine = measuresPerLine
        self.noteSpacing = noteSpacing
        self.measureWidthRatio = measureWidthRatio
        self.rowGap = rowGap
        self.lyricFontName = lyricFontName
        self.lyricFontSize = lyricFontSize
        self.numerator = numerator
        self.denominator = denominator
    }

    private enum CodingKeys: String, CodingKey {
        case title, composer, arranger, keySignature, measuresPerLine, noteSpacing,
             measureWidthRatio, rowGap, lyricFontName, lyricFontSize,
             numerator, denominator
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "새 악보"
        composer = try values.decodeIfPresent(String.self, forKey: .composer) ?? ""
        arranger = try values.decodeIfPresent(String.self, forKey: .arranger) ?? ""
        keySignature = try values.decodeIfPresent(KeySignature.self, forKey: .keySignature) ?? .c
        measuresPerLine = try values.decodeIfPresent(Int.self, forKey: .measuresPerLine) ?? 8
        noteSpacing = try values.decodeIfPresent(Double.self, forKey: .noteSpacing) ?? 29
        measureWidthRatio = try values.decodeIfPresent(Double.self, forKey: .measureWidthRatio) ?? 1
        rowGap = try values.decodeIfPresent(Double.self, forKey: .rowGap) ?? 15
        lyricFontName = try values.decodeIfPresent(String.self, forKey: .lyricFontName) ?? ""
        lyricFontSize = try values.decodeIfPresent(Double.self, forKey: .lyricFontSize) ?? 15
        numerator = try values.decodeIfPresent(Int.self, forKey: .numerator) ?? 4
        denominator = try values.decodeIfPresent(Int.self, forKey: .denominator) ?? 4
    }
}

struct ScoreDocument: Codable, Equatable {
    var page: Page
    var tempo: Double
    var tracks: [ScoreTrack]
    var sourceMIDI: Data?
    var chordEvents: [ChordEvent]
    var repeatSections: [RepeatSection]
    var navigationMarks: [NavigationMark]

    var title: String {
        get { page.title }
        set { page.title = newValue }
    }
    var numerator: Int {
        get { page.numerator }
        set { page.numerator = newValue }
    }
    var denominator: Int {
        get { page.denominator }
        set { page.denominator = newValue }
    }
    var beatsPerMeasure: Double { page.beatsPerMeasure }

    init(page: Page, tempo: Double, tracks: [ScoreTrack], sourceMIDI: Data?,
         chordEvents: [ChordEvent] = [], repeatSections: [RepeatSection] = [],
         navigationMarks: [NavigationMark] = []) {
        self.page = page
        self.tempo = tempo
        self.tracks = tracks
        self.sourceMIDI = sourceMIDI
        self.chordEvents = chordEvents
        self.repeatSections = repeatSections
        self.navigationMarks = navigationMarks
    }

    init(title: String, tempo: Double, numerator: Int, denominator: Int,
         tracks: [ScoreTrack], sourceMIDI: Data?) {
        self.init(page: Page(title: title, numerator: numerator, denominator: denominator),
                  tempo: tempo, tracks: tracks, sourceMIDI: sourceMIDI)
    }

    static let empty = ScoreDocument(
        title: "새 악보", tempo: 120, numerator: 4, denominator: 4,
        tracks: [ScoreTrack(name: "트랙 1", notes: [])], sourceMIDI: nil
    )
}

extension ScoreDocument {
    private enum CodingKeys: String, CodingKey {
        case page, title, tempo, numerator, denominator, tracks, sourceMIDI,
             measureChords, chordEvents, repeatSections, navigationMarks
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let page = try values.decodeIfPresent(Page.self, forKey: .page) {
            self.page = page
        } else {
            self.page = Page(
                title: try values.decodeIfPresent(String.self, forKey: .title) ?? "새 악보",
                numerator: try values.decodeIfPresent(Int.self, forKey: .numerator) ?? 4,
                denominator: try values.decodeIfPresent(Int.self, forKey: .denominator) ?? 4
            )
        }
        tempo = try values.decode(Double.self, forKey: .tempo)
        tracks = try values.decode([ScoreTrack].self, forKey: .tracks)
        sourceMIDI = try values.decodeIfPresent(Data.self, forKey: .sourceMIDI)
        if let saved = try values.decodeIfPresent([ChordEvent].self, forKey: .chordEvents) {
            chordEvents = saved.filter { $0.positionTick >= 0 }
                .sorted { $0.positionTick < $1.positionTick }
        } else {
            let legacy = try values.decodeIfPresent([Int: MeasureChord].self,
                                                    forKey: .measureChords) ?? [:]
            let loadedPage = page
            chordEvents = legacy.filter { $0.key >= 0 }.map { index, chord in
                ChordEvent(positionTick: ChordGrid.tick(measure: index, slot: 0, page: loadedPage),
                           chord: ChordSymbol(legacy: chord, key: loadedPage.keySignature))
            }.sorted { $0.positionTick < $1.positionTick }
        }
        repeatSections = try values.decodeIfPresent([RepeatSection].self,
            forKey: .repeatSections) ?? []
        navigationMarks = try values.decodeIfPresent([NavigationMark].self,
            forKey: .navigationMarks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(page, forKey: .page)
        try values.encode(tempo, forKey: .tempo)
        try values.encode(tracks, forKey: .tracks)
        try values.encodeIfPresent(sourceMIDI, forKey: .sourceMIDI)
        try values.encode(chordEvents, forKey: .chordEvents)
        try values.encode(repeatSections, forKey: .repeatSections)
        try values.encode(navigationMarks, forKey: .navigationMarks)
    }
}

enum ScoreGrid: Double, CaseIterable, Identifiable {
    case quarter = 1
    case eighth = 0.5
    case sixteenth = 0.25
    case thirtySecond = 0.125

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .quarter: return "4분음표"
        case .eighth: return "8분음표"
        case .sixteenth: return "16분음표"
        case .thirtySecond: return "32분음표"
        }
    }

    func quantize(_ value: Double) -> Double {
        (value / rawValue).rounded() * rawValue
    }

    func quantize(_ note: ScoreNote) -> ScoreNote {
        var result = note
        result.startBeat = max(0, quantize(note.startBeat))
        result.durationBeats = max(rawValue, quantize(note.durationBeats))
        return result
    }
}
