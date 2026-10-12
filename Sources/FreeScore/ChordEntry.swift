import Foundation

enum ChordGrid {
    static let ticksPerQuarter = 480

    static func ticksPerSlot(_ page: Page) -> Int {
        ticksPerQuarter * 4 / max(1, page.denominator)
    }

    static func ticksPerMeasure(_ page: Page) -> Int {
        max(1, page.numerator) * ticksPerSlot(page)
    }

    static func tick(measure: Int, slot: Int, page: Page) -> Int {
        max(0, measure) * ticksPerMeasure(page) +
            max(0, min(max(1, page.numerator) - 1, slot)) * ticksPerSlot(page)
    }

    static func measure(for tick: Int, page: Page) -> Int {
        max(0, tick) / ticksPerMeasure(page)
    }

    static func slot(for tick: Int, page: Page) -> Int {
        max(0, tick) % ticksPerMeasure(page) / ticksPerSlot(page)
    }

    static func beat(for tick: Int) -> Double {
        Double(tick) / Double(ticksPerQuarter)
    }

    static func snappedTick(beat: Double, measure: Int, page: Page) -> Int {
        guard beat.isFinite else { return tick(measure: measure, slot: 0, page: page) }
        let local = beat - Double(max(0, measure)) * page.beatsPerMeasure
        let slot = Int(floor(local * Double(ticksPerQuarter) /
                             Double(ticksPerSlot(page))))
        return tick(measure: measure, slot: slot, page: page)
    }

    static func next(_ tick: Int, page: Page) -> Int {
        max(0, tick) + ticksPerSlot(page)
    }

    static func previous(_ tick: Int, page: Page) -> Int {
        max(0, tick - ticksPerSlot(page))
    }
}

struct ChordSymbol: Codable, Equatable {
    var tonicOffset: Int
    var suffix: String
    var bassOffset: Int?
    var enteredRoot: String
    var enteredBass: String?
    var entryKey: KeySignature
    var followsKey: Bool

    init?(text: String, key: KeySignature, followsKey: Bool = true) {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        guard !compact.isEmpty, !compact.contains(where: { $0.isWhitespace }) else { return nil }
        let pieces = compact.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              let root = Self.parseRoot(String(pieces[0]), allowSuffix: true) else { return nil }
        let bass = pieces.count == 2
            ? Self.parseRoot(String(pieces[1]), allowSuffix: false) : nil
        guard pieces.count == 1 || bass != nil else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#b+()-°ø△")
        guard root.remainder.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        tonicOffset = (root.pitchClass - key.tonicPitchClass + 12) % 12
        suffix = root.remainder
        bassOffset = bass.map { ($0.pitchClass - key.tonicPitchClass + 12) % 12 }
        enteredRoot = root.name
        enteredBass = bass?.name
        entryKey = key
        self.followsKey = followsKey
    }

    init(legacy: MeasureChord, key: KeySignature) {
        tonicOffset = legacy.tonicOffset
        suffix = legacy.quality.symbol
        bassOffset = nil
        enteredRoot = MeasureChord.rootName(for: legacy.rootPitchClass(in: key), in: key)
        enteredBass = nil
        entryKey = key
        followsKey = true
    }

    func symbol(in key: KeySignature) -> String {
        let spellingKey = followsKey ? key : entryKey
        let root = spellingKey == entryKey ? enteredRoot :
            MeasureChord.rootName(for: (spellingKey.tonicPitchClass + tonicOffset) % 12,
                                  in: spellingKey)
        let bass: String
        if let bassOffset {
            let name = spellingKey == entryKey ? enteredBass ?? "" :
                MeasureChord.rootName(for: (spellingKey.tonicPitchClass + bassOffset) % 12,
                                      in: spellingKey)
            bass = "/" + name
        } else {
            bass = ""
        }
        return root + suffix + bass
    }

    private static func parseRoot(_ text: String, allowSuffix: Bool)
        -> (name: String, pitchClass: Int, remainder: String)? {
        guard let letter = text.first?.uppercased(),
              let index = ["C", "D", "E", "F", "G", "A", "B"].firstIndex(of: letter) else {
            return nil
        }
        var remainder = String(text.dropFirst())
        var accidental = 0
        var name = letter
        if let mark = remainder.first, mark == "#" || mark == "b" {
            accidental = mark == "#" ? 1 : -1
            name.append(mark)
            remainder.removeFirst()
        }
        guard allowSuffix || remainder.isEmpty else { return nil }
        let naturals = [0, 2, 4, 5, 7, 9, 11]
        return (name, (naturals[index] + accidental + 12) % 12, remainder)
    }
}

struct ChordEvent: Codable, Equatable {
    var positionTick: Int
    var chord: ChordSymbol

    var startBeat: Double { ChordGrid.beat(for: positionTick) }
}

enum ChordSuggestions {
    static func diatonicTriads(in key: KeySignature) -> [String] {
        let intervals = [0, 2, 4, 5, 7, 9, 11]
        let qualities = ["", "m", "m", "", "", "m", "dim"]
        return zip(intervals, qualities).map { interval, quality in
            MeasureChord.rootName(for: (key.tonicPitchClass + interval) % 12,
                                  in: key) + quality
        }
    }

    static func matching(_ query: String, in key: KeySignature) -> [String] {
        let candidates = diatonicTriads(in: key)
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "♯")
            .replacingOccurrences(of: "b", with: "♭")
        return normalized.isEmpty ? candidates : candidates.filter {
            $0.localizedCaseInsensitiveContains(normalized)
        }
    }
}
