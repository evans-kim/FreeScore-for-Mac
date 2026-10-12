import Foundation

struct RepeatSection: Codable, Equatable, Identifiable {
    var startMeasure: Int
    var endMeasure: Int
    var firstEndingStartMeasure: Int?
    var secondEndingEndMeasure: Int?

    var id: Int { startMeasure }
    var hasEndings: Bool { firstEndingStartMeasure != nil }
    var lastMeasure: Int { secondEndingEndMeasure ?? endMeasure }

    var description: String {
        let range = "\(startMeasure + 1)~\(endMeasure + 1)마디"
        guard let firstEndingStartMeasure, let secondEndingEndMeasure else { return range + " 도돌이" }
        return range + " 도돌이 · 1번 \(firstEndingStartMeasure + 1)~\(endMeasure + 1)마디" +
            " · 2번 \(endMeasure + 2)~\(secondEndingEndMeasure + 1)마디"
    }
}

struct NavigationMark: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case segno, coda, toCoda = "to-coda", fine
        case daCapo = "dc", dalSegno = "ds"
        case daCapoAlFine = "dc-fine", dalSegnoAlFine = "ds-fine"
        case daCapoAlCoda = "dc-coda", dalSegnoAlCoda = "ds-coda"

        var id: String { rawValue }
        var isJump: Bool {
            switch self {
            case .daCapo, .dalSegno, .daCapoAlFine, .dalSegnoAlFine,
                    .daCapoAlCoda, .dalSegnoAlCoda: true
            default: false
            }
        }
        var isDalSegno: Bool {
            [.dalSegno, .dalSegnoAlFine, .dalSegnoAlCoda].contains(self)
        }
        var endsAtFine: Bool { [.daCapoAlFine, .dalSegnoAlFine].contains(self) }
        var goesToCoda: Bool { [.daCapoAlCoda, .dalSegnoAlCoda].contains(self) }
        var atMeasureStart: Bool { self == .segno || self == .coda }
        var label: String {
            switch self {
            case .segno: "Segno"
            case .coda: "Coda"
            case .toCoda: "To Coda"
            case .fine: "Fine"
            case .daCapo: "D.C."
            case .dalSegno: "D.S."
            case .daCapoAlFine: "D.C. al Fine"
            case .dalSegnoAlFine: "D.S. al Fine"
            case .daCapoAlCoda: "D.C. al Coda"
            case .dalSegnoAlCoda: "D.S. al Coda"
            }
        }
    }

    var measure: Int
    var kind: Kind
    var id: String { "\(measure)-\(kind.rawValue)" }
    var description: String { "\(measure + 1)마디 · \(kind.label)" }
}

struct RepeatPlaybackPlan: Equatable {
    enum PlanError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }

    let scoreMeasures: [Int]
    let beatsPerMeasure: Double

    var totalBeats: Double { Double(scoreMeasures.count) * beatsPerMeasure }

    static func measureCount(page: Page, notes: [ScoreNote], chords: [ChordEvent],
                             repeats: [RepeatSection], navigation: [NavigationMark] = []) -> Int {
        let barBeats = max(0.25, page.beatsPerMeasure)
        let lastBeat = notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        let lastChord = chords.filter { $0.positionTick >= 0 }
            .map { ChordGrid.measure(for: $0.positionTick, page: page) + 1 }.max() ?? 0
        let lastRepeat = repeats.map { $0.lastMeasure + 1 }.max() ?? 0
        let lastNavigation = navigation.map { $0.measure + 1 }.max() ?? 0
        return max(1, Int(ceil(lastBeat / barBeats)), lastChord, lastRepeat, lastNavigation)
    }

    static func validate(_ sections: [RepeatSection]) throws {
        let sorted = sections.sorted { $0.startMeasure < $1.startMeasure }
        var lastEnd = -1
        for section in sorted {
            guard section.startMeasure >= 0, section.endMeasure >= section.startMeasure,
                  section.lastMeasure < 10_000 else {
                throw PlanError.invalid("도돌이 구간의 시작·끝 마디를 확인하세요 (최대 10000마디).")
            }
            guard (section.firstEndingStartMeasure == nil) ==
                    (section.secondEndingEndMeasure == nil) else {
                throw PlanError.invalid("1번과 2번 괄호 범위를 함께 지정하세요.")
            }
            if let first = section.firstEndingStartMeasure,
               let secondEnd = section.secondEndingEndMeasure {
                guard first > section.startMeasure, first <= section.endMeasure,
                      secondEnd > section.endMeasure else {
                    throw PlanError.invalid("1번 괄호는 도돌이 안쪽, 2번 괄호는 그 다음 마디부터 시작해야 합니다.")
                }
            }
            guard section.startMeasure > lastEnd else {
                throw PlanError.invalid("도돌이 구간은 서로 겹치거나 중첩될 수 없습니다.")
            }
            lastEnd = section.lastMeasure
        }
    }

    static func validate(repeats: [RepeatSection], navigation: [NavigationMark]) throws {
        try validate(repeats)
        guard navigation.allSatisfy({ (0..<10_000).contains($0.measure) }),
              Set(navigation.map(\.kind)).count == navigation.count else {
            throw PlanError.invalid("이동 기호는 종류별로 한 번씩, 1~10000마디 안에 배치하세요.")
        }
        let jumps = navigation.filter { $0.kind.isJump }
        guard jumps.count <= 1 else {
            throw PlanError.invalid("D.C. 또는 D.S. 이동 명령은 한 곡에 하나만 배치할 수 있습니다.")
        }
        guard let jump = jumps.first else { return }
        guard jump.measure > (repeats.map(\.lastMeasure).max() ?? -1) else {
            throw PlanError.invalid("D.C./D.S.는 모든 도돌이 구간 뒤의 마디에 배치하세요.")
        }
        let segno = navigation.first { $0.kind == .segno }?.measure
        guard !jump.kind.isDalSegno || (segno != nil && segno! < jump.measure) else {
            throw PlanError.invalid("D.S. 앞쪽 마디에 Segno를 배치하세요.")
        }
        let target = jump.kind.isDalSegno ? segno! : 0
        if jump.kind.endsAtFine {
            guard let fine = navigation.first(where: { $0.kind == .fine })?.measure,
                  (target..<jump.measure).contains(fine),
                  !repeats.contains(where: { section in
                      guard let first = section.firstEndingStartMeasure else { return false }
                      return (first...section.endMeasure).contains(fine)
                  }) else {
                throw PlanError.invalid("al Fine의 Fine은 돌아가는 지점부터 D.C./D.S. 앞까지, 1번 괄호 밖에 배치하세요.")
            }
        }
        if jump.kind.goesToCoda {
            guard let toCoda = navigation.first(where: { $0.kind == .toCoda })?.measure,
                  (target..<jump.measure).contains(toCoda),
                  let coda = navigation.first(where: { $0.kind == .coda })?.measure,
                  coda > jump.measure,
                  !repeats.contains(where: { section in
                      guard let first = section.firstEndingStartMeasure else { return false }
                      return (first...section.endMeasure).contains(toCoda)
                  }) else {
                throw PlanError.invalid("al Coda에는 D.C./D.S. 앞의 To Coda와 그 뒤의 Coda가 필요합니다. To Coda는 1번 괄호 밖에 배치하세요.")
            }
        }
        if jump.kind.isDalSegno {
            guard !repeats.contains(where: { section in
                guard let first = section.firstEndingStartMeasure else { return false }
                return (first...section.endMeasure).contains(target)
            }) else {
                throw PlanError.invalid("Segno는 1번 괄호 밖에 배치하세요.")
            }
        }
    }

    init(page: Page, notes: [ScoreNote], chords: [ChordEvent] = [],
         repeats: [RepeatSection] = [], navigation: [NavigationMark] = [],
         playRepeats: Bool = true) throws {
        try Self.validate(repeats: repeats, navigation: navigation)
        beatsPerMeasure = max(0.25, page.beatsPerMeasure)
        let count = Self.measureCount(page: page, notes: notes, chords: chords,
                                      repeats: repeats, navigation: navigation)
        if !playRepeats {
            scoreMeasures = Array(0..<count)
            return
        }
        let sections = repeats.sorted { $0.startMeasure < $1.startMeasure }
        var result: [Int] = []
        var measure = 0
        for section in sections {
            if measure < section.startMeasure { result += Array(measure..<section.startMeasure) }
            result += Array(section.startMeasure...section.endMeasure)
            if let first = section.firstEndingStartMeasure,
               let secondEnd = section.secondEndingEndMeasure {
                result += Array(section.startMeasure..<first)
                result += Array((section.endMeasure + 1)...secondEnd)
            } else {
                result += Array(section.startMeasure...section.endMeasure)
            }
            measure = section.lastMeasure + 1
        }
        if measure < count { result += Array(measure..<count) }
        if let jump = navigation.first(where: { $0.kind.isJump }),
           let jumpIndex = result.firstIndex(of: jump.measure) {
            result = Array(result.prefix(through: jumpIndex))
            let target = jump.kind.isDalSegno
                ? navigation.first(where: { $0.kind == .segno })!.measure : 0
            let stop = jump.kind.endsAtFine
                ? navigation.first(where: { $0.kind == .fine })!.measure
                : jump.kind.goesToCoda
                    ? navigation.first(where: { $0.kind == .toCoda })!.measure
                    : count - 1
            result += (target...stop).filter { measure in
                !repeats.contains { section in
                    guard let first = section.firstEndingStartMeasure else { return false }
                    return (first...section.endMeasure).contains(measure)
                }
            }
            if jump.kind.goesToCoda {
                let coda = navigation.first(where: { $0.kind == .coda })!.measure
                result += Array(coda..<count)
            }
        }
        scoreMeasures = result
    }

    func scoreBeat(at performanceBeat: Double) -> Double {
        guard !scoreMeasures.isEmpty else { return 0 }
        let beat = max(0, min(performanceBeat, totalBeats))
        if beat >= totalBeats { return Double(scoreMeasures.last! + 1) * beatsPerMeasure }
        let index = Int(beat / beatsPerMeasure)
        return Double(scoreMeasures[index]) * beatsPerMeasure +
            beat - Double(index) * beatsPerMeasure
    }

    func performanceBeat(for scoreBeat: Double) -> Double {
        let beat = max(0, scoreBeat)
        let measure = Int(beat / beatsPerMeasure)
        guard let index = scoreMeasures.firstIndex(of: measure) else { return totalBeats }
        return Double(index) * beatsPerMeasure + beat - Double(measure) * beatsPerMeasure
    }

    func expandedNotes(_ notes: [ScoreNote]) -> [ScoreNote] {
        var result: [ScoreNote] = []
        for (visit, sourceMeasure) in scoreMeasures.enumerated() {
            let sourceStart = Double(sourceMeasure) * beatsPerMeasure
            let sourceEnd = sourceStart + beatsPerMeasure
            var contiguousEnd = visit
            while contiguousEnd + 1 < scoreMeasures.count,
                  scoreMeasures[contiguousEnd + 1] == scoreMeasures[contiguousEnd] + 1 {
                contiguousEnd += 1
            }
            for original in notes where original.startBeat >= sourceStart &&
                original.startBeat < sourceEnd {
                var note = original
                note.startBeat = Double(visit) * beatsPerMeasure +
                    original.startBeat - sourceStart
                let boundary = Double(contiguousEnd + 1) * beatsPerMeasure
                note.durationBeats = min(original.durationBeats, boundary - note.startBeat)
                guard note.durationBeats > 0.0001 else { continue }
                note.id = UUID()
                result.append(note)
            }
        }
        return result.sorted { $0.startBeat < $1.startBeat }
    }
}
