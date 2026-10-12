import Foundation

struct NotatedPitch: Equatable {
    let letter: Int // C=0 ... B=6
    let octave: Int
    let alteration: Int // ♭=-1, natural=0, ♯=1

    var diatonicIndex: Int { octave * 7 + letter }
    var name: String {
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        let symbol = alteration < 0 ? "♭" : alteration > 0 ? "♯" : ""
        return "\(letters[letter])\(symbol)\(octave)"
    }

    static func spell(_ midiPitch: Int, in key: KeySignature) -> NotatedPitch {
        let naturals = [0, 2, 4, 5, 7, 9, 11]
        var candidates: [NotatedPitch] = []
        for letter in 0..<7 {
            for alteration in -1...1 {
                let base = midiPitch - naturals[letter] - alteration
                guard base.isMultiple(of: 12) else { continue }
                candidates.append(NotatedPitch(letter: letter, octave: base / 12 - 1,
                                               alteration: alteration))
            }
        }
        let preferFlat = key.isFlat
        return candidates.min { lhs, rhs in
            func rank(_ pitch: NotatedPitch) -> (Int, Int, Int, Int) {
                let matchesKey = pitch.alteration == key.alteration(for: pitch.letter)
                let signPreference = pitch.alteration == 0 ||
                    (preferFlat ? pitch.alteration < 0 : pitch.alteration > 0)
                return (matchesKey ? 0 : 1, pitch.alteration == 0 ? 0 : 1,
                        signPreference ? 0 : 1, pitch.letter)
            }
            return rank(lhs) < rank(rhs)
        } ?? NotatedPitch(letter: 0, octave: 4, alteration: 0)
    }
}

struct ScoreDisplayNote {
    let note: ScoreNote
    let sourceID: UUID
    let tiedFromPrevious: Bool
    let tiedToNext: Bool
    let showsLyric: Bool
}

struct ScoreRest: Equatable {
    let startBeat: Double
    let durationBeats: Double
    let wholeMeasure: Bool
}

enum ScoreNotation {
    private static let durationValues: [Double] = [4, 3, 2, 1.5, 1, 0.75, 0.5, 0.375,
                                                    0.25, 0.1875, 0.125]
    private static let epsilon = 0.0001

    static func displayNotes(for notes: [ScoreNote], page: Page) -> [ScoreDisplayNote] {
        let barBeats = max(0.25, page.beatsPerMeasure)
        var result: [ScoreDisplayNote] = []
        for source in notes where source.durationBeats > epsilon {
            var cursor = max(0, source.startBeat)
            let end = cursor + source.durationBeats
            while cursor < end - epsilon {
                let bar = Int(floor((cursor + epsilon) / barBeats))
                let barEnd = Double(bar + 1) * barBeats
                let remaining = min(end, barEnd) - cursor
                guard remaining > epsilon else { break }
                let value = durationValues.first(where: { $0 <= remaining + epsilon }) ?? remaining
                let duration = min(value, remaining)
                var segment = source
                segment.id = UUID()
                segment.startBeat = cursor
                segment.durationBeats = duration
                let first = result.last?.sourceID != source.id
                let next = cursor + duration
                result.append(ScoreDisplayNote(note: segment, sourceID: source.id,
                                               tiedFromPrevious: !first,
                                               tiedToNext: next < end - epsilon,
                                               showsLyric: first))
                cursor = next
            }
        }
        return result
    }

    static func lyricSlurs(for displayNotes: [ScoreDisplayNote])
        -> [(from: ScoreNote, to: ScoreNote, fromID: UUID, toID: UUID)] {
        let firstSegments = displayNotes.filter(\.showsLyric).sorted {
            $0.note.startBeat == $1.note.startBeat
                ? $0.note.pitch < $1.note.pitch : $0.note.startBeat < $1.note.startBeat
        }
        let segmentsBySource = Dictionary(grouping: displayNotes, by: \.sourceID)
        var previousBeat: Double?
        var previousSourceID: UUID?
        var priorBeatSourceID: UUID?
        var result: [(from: ScoreNote, to: ScoreNote, fromID: UUID, toID: UUID)] = []
        for display in firstSegments {
            if let previousBeat, display.note.startBeat > previousBeat + epsilon {
                priorBeatSourceID = previousSourceID
            }
            if (1...4).contains(where: {
                display.note.lyric(for: $0).trimmingCharacters(in: .whitespacesAndNewlines) == "-"
            }),
               let priorBeatSourceID,
               let previous = segmentsBySource[priorBeatSourceID]?
                .filter({ $0.note.startBeat < display.note.startBeat - epsilon })
                .max(by: { $0.note.startBeat < $1.note.startBeat }) {
                result.append((from: previous.note, to: display.note,
                               fromID: priorBeatSourceID, toID: display.sourceID))
            }
            previousBeat = display.note.startBeat
            previousSourceID = display.sourceID
        }
        return result
    }

    static func rests(for notes: [ScoreNote], page: Page, measureCount: Int) -> [ScoreRest] {
        guard measureCount > 0 else { return [] }
        let barBeats = max(0.25, page.beatsPerMeasure)
        var result: [ScoreRest] = []
        var occupiedByBar: [Int: [(Double, Double)]] = [:]
        for note in notes where note.durationBeats > epsilon {
            let noteEnd = note.startBeat + note.durationBeats
            let firstBar = max(0, Int(floor(note.startBeat / barBeats)))
            let lastBar = min(measureCount - 1, Int(floor((noteEnd - epsilon) / barBeats)))
            guard firstBar <= lastBar else { continue }
            for bar in firstBar...lastBar {
                let barStart = Double(bar) * barBeats
                let left = max(barStart, note.startBeat)
                let right = min(barStart + barBeats, noteEnd)
                if right > left + epsilon {
                    occupiedByBar[bar, default: []].append((left, right))
                }
            }
        }
        for bar in 0..<measureCount {
            let start = Double(bar) * barBeats
            let end = start + barBeats
            let occupied = (occupiedByBar[bar] ?? []).sorted { $0.0 < $1.0 }
            if occupied.isEmpty {
                result.append(ScoreRest(startBeat: start, durationBeats: barBeats,
                                        wholeMeasure: true))
                continue
            }
            var cursor = start
            for (left, right) in occupied {
                if left > cursor + epsilon {
                    appendRests(from: cursor, to: left, barStart: start,
                                barBeats: barBeats, page: page, into: &result)
                }
                cursor = max(cursor, right)
            }
            if end > cursor + epsilon {
                appendRests(from: cursor, to: end, barStart: start,
                            barBeats: barBeats, page: page, into: &result)
            }
        }
        return result
    }

    private static func appendRests(from start: Double, to end: Double,
                                    barStart: Double, barBeats: Double, page: Page,
                                    into result: inout [ScoreRest]) {
        let compoundEighths = page.denominator == 8 && page.numerator >= 6 &&
            page.numerator.isMultiple(of: 3)
        let pulse = compoundEighths ? 1.5 : 4.0 / Double(page.denominator)
        let group: Double = compoundEighths ? 1.5 :
            (page.denominator == 4 && page.numerator >= 4 &&
             page.numerator.isMultiple(of: 2) ? 2 : barBeats)
        var cursor = start
        while cursor < end - epsilon {
            let groupIndex = floor((cursor - barStart + epsilon) / group)
            let groupEnd = min(barStart + (groupIndex + 1) * group, barStart + barBeats)
            let remaining = min(end, groupEnd) - cursor
            guard remaining > epsilon else { break }
            let value = durationValues.first(where: { value in
                if !compoundEighths && abs(value - 1.5) < epsilon { return false }
                if value < pulse - epsilon {
                    let pulseIndex = floor((cursor - barStart + epsilon) / pulse)
                    let pulseEnd = barStart + (pulseIndex + 1) * pulse
                    if cursor + value > pulseEnd + epsilon { return false }
                }
                return value <= remaining + epsilon &&
                    abs(cursor / value - round(cursor / value)) < epsilon
            }) ?? remaining
            let duration = min(value, remaining)
            result.append(ScoreRest(startBeat: cursor, durationBeats: duration,
                                    wholeMeasure: false))
            cursor += duration
        }
    }

    static func beamLevel(for duration: Double) -> Int {
        if duration < 0.25 - 0.0001 { return 3 }
        if duration < 0.5 - 0.0001 { return 2 }
        if duration < 1 - 0.0001 { return 1 }
        return 0
    }

    static func transpose(_ midiPitch: Int, staffSteps: Int, key: KeySignature) -> Int {
        let original = NotatedPitch.spell(midiPitch, in: key)
        let index = original.diatonicIndex + staffSteps
        let letter = ((index % 7) + 7) % 7
        let octave = (index - letter) / 7
        let naturals = [0, 2, 4, 5, 7, 9, 11]
        let result = (octave + 1) * 12 + naturals[letter] + key.alteration(for: letter)
        return max(0, min(127, result))
    }

    static func accidentals(for notes: [ScoreNote], page: Page) -> [UUID: String] {
        let ordered = notes.sorted {
            $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat
        }
        var state: [String: Int] = [:]
        var measure = -1
        var result: [UUID: String] = [:]
        for note in ordered {
            let currentMeasure = Int(floor(note.startBeat / max(0.25, page.beatsPerMeasure)))
            if currentMeasure != measure {
                state.removeAll()
                measure = currentMeasure
            }
            let pitch = NotatedPitch.spell(note.pitch, in: page.keySignature)
            let key = "\(pitch.letter):\(pitch.octave)"
            let expected = state[key] ?? page.keySignature.alteration(for: pitch.letter)
            if pitch.alteration != expected {
                result[note.id] = pitch.alteration < 0 ? "♭" : pitch.alteration > 0 ? "♯" : "♮"
            }
            state[key] = pitch.alteration
        }
        return result
    }

    static func beamGroups(for notes: [ScoreNote], page: Page) -> [[UUID]] {
        let ordered = notes.sorted {
            $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat
        }
        let barBeats = max(0.25, page.beatsPerMeasure)
        let beatGroup: Double = page.denominator == 8 && page.numerator >= 6 && page.numerator.isMultiple(of: 3)
            ? 1.5 : 4.0 / Double(page.denominator)
        var groups: [[UUID]] = []
        var pending: [ScoreNote] = []
        func flush() {
            if pending.count > 1 { groups.append(pending.map(\.id)) }
            pending.removeAll()
        }
        for note in ordered {
            guard note.durationBeats > 0, beamLevel(for: note.durationBeats) > 0 else {
                flush(); continue
            }
            let bar = Int(floor(note.startBeat / barBeats))
            let local = note.startBeat - Double(bar) * barBeats
            let pulse = Int(floor((local + 0.0001) / beatGroup))
            if let previous = pending.last {
                let previousBar = Int(floor(previous.startBeat / barBeats))
                let previousLocal = previous.startBeat - Double(previousBar) * barBeats
                let previousPulse = Int(floor((previousLocal + 0.0001) / beatGroup))
                let contiguous = abs(previous.startBeat + previous.durationBeats - note.startBeat) < 0.001
                if !contiguous || previousBar != bar || previousPulse != pulse { flush() }
            }
            pending.append(note)
        }
        flush()
        return groups
    }
}
