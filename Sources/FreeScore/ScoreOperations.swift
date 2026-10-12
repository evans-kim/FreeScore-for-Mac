import Foundation

enum ScoreOperations {
    static func quantizedNotes(_ source: [ScoreNote], grid: ScoreGrid,
                               selectedIDs: Set<UUID> = [], melodyMode: Bool = false) -> [ScoreNote] {
        let quantizeAll = selectedIDs.isEmpty
        var notes = source.map { note in
            quantizeAll || selectedIDs.contains(note.id) ? grid.quantize(note) : note
        }
        notes.sort { $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat }
        if melodyMode {
            var nextDistinctStart: Double?
            for index in notes.indices.reversed() {
                let start = notes[index].startBeat
                if index + 1 < notes.count, notes[index + 1].startBeat > start + 0.000001 {
                    nextDistinctStart = notes[index + 1].startBeat
                }
                if let nextDistinctStart,
                   quantizeAll || selectedIDs.contains(notes[index].id) {
                    notes[index].durationBeats = nextDistinctStart - start
                }
            }
        }
        return notes
    }
}
