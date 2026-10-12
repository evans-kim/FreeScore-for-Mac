import AVFAudio
import Foundation

enum MIDIService {
    enum MIDIError: LocalizedError {
        case noNotes
        case invalidDocument

        var errorDescription: String? {
            switch self {
            case .noNotes: return "음표가 있는 MIDI 트랙을 찾지 못했습니다."
            case .invalidDocument: return "저장할 악보 데이터가 없습니다."
            }
        }
    }

    static func importFile(_ url: URL, grid: ScoreGrid = .sixteenth) throws -> ScoreDocument {
        let sourceData = try Data(contentsOf: url)
        let metadata = MIDIMetadata(data: sourceData)
        let sequencer = AVAudioSequencer()
        try sequencer.load(from: url)
        var tempo = 120.0
        let numerator = metadata.numerator
        let denominator = metadata.denominator
        var foundTempo = false
        let entireRange = AVBeatRange(start: 0, length: 1_000_000)

        sequencer.tempoTrack.enumerateEvents(in: entireRange) { event, _, _ in
            if let value = event as? AVExtendedTempoEvent, !foundTempo {
                tempo = value.tempo
                foundTempo = true
            }
        }

        let tracks = sequencer.tracks.enumerated().compactMap { index, track -> ScoreTrack? in
            let name = metadata.trackNames[index] ?? "트랙 \(index + 1)"
            var notes: [ScoreNote] = []
            track.enumerateEvents(in: entireRange) { event, beat, _ in
                guard let note = event as? AVMIDINoteEvent, note.velocity > 0 else { return }
                let start = max(0, beat.pointee)
                let duration = max(0.01, note.duration)
                let original = ScoreNote(
                    pitch: Int(note.key), startBeat: start, durationBeats: duration,
                    velocity: Int(note.velocity), channel: Int(note.channel),
                    originalStartBeat: start, originalDurationBeats: duration
                )
                notes.append(grid.quantize(original))
            }
            guard !notes.isEmpty else { return nil }
            notes.sort { $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat }
            return ScoreTrack(name: name, notes: notes)
        }
        guard !tracks.isEmpty else { throw MIDIError.noNotes }
        return ScoreDocument(
            title: url.deletingPathExtension().lastPathComponent,
            tempo: tempo, numerator: numerator, denominator: denominator,
            tracks: tracks, sourceMIDI: sourceData
        )
    }

    static func midiData(document: ScoreDocument, trackIndex: Int,
                         minimumDurationBeats: Double? = nil) throws -> Data {
        guard document.tracks.indices.contains(trackIndex) else { throw MIDIError.invalidDocument }
        let sequencer = AVAudioSequencer()
        let tempo = max(20, min(300, document.tempo))
        sequencer.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: tempo), at: 0)
        let exponent = UInt8(max(0, min(7, Int(log2(Double(document.denominator))))))
        let meter = Data([UInt8(clamping: document.numerator), exponent, 24, 8])
        sequencer.tempoTrack.addEvent(AVMIDIMetaEvent(type: .timeSignature, data: meter), at: 0)
        let track = sequencer.createAndAppendTrack()
        for note in document.tracks[trackIndex].notes {
            let event = AVMIDINoteEvent(
                channel: UInt32(clamping: note.channel), key: UInt32(clamping: note.pitch),
                velocity: UInt32(clamping: note.velocity), duration: max(0.01, note.durationBeats)
            )
            track.addEvent(event, at: max(0, note.startBeat))
        }
        if let minimumDurationBeats, minimumDurationBeats.isFinite {
            track.lengthInBeats = max(0, minimumDurationBeats)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        defer { try? FileManager.default.removeItem(at: url) }
        try sequencer.write(to: url, smpteResolution: 0, replaceExisting: true)
        return try Data(contentsOf: url)
    }
}

private struct MIDIMetadata {
    var numerator = 4
    var denominator = 4
    var trackNames: [Int: String] = [:]

    init(data: Data) {
        let bytes = [UInt8](data)
        var cursor = 0
        func read(_ count: Int) -> [UInt8]? {
            guard count >= 0, cursor + count <= bytes.count else { return nil }
            defer { cursor += count }
            return Array(bytes[cursor..<(cursor + count)])
        }
        func number(_ count: Int) -> Int? {
            guard let value = read(count) else { return nil }
            return value.reduce(0) { ($0 << 8) | Int($1) }
        }
        func variableLength() -> Int? {
            var result = 0
            for _ in 0..<4 {
                guard let byte = read(1)?.first else { return nil }
                result = (result << 7) | Int(byte & 0x7f)
                if byte & 0x80 == 0 { return result }
            }
            return nil
        }

        guard read(4) == [0x4d, 0x54, 0x68, 0x64],
              let headerLength = number(4), headerLength >= 6,
              let header = read(headerLength) else { return }
        let trackCount = Int(header[2]) << 8 | Int(header[3])
        for trackIndex in 0..<min(trackCount, 256) {
            guard read(4) == [0x4d, 0x54, 0x72, 0x6b],
                  let length = number(4), cursor + length <= bytes.count else { return }
            let end = cursor + length
            var runningStatus: UInt8 = 0
            while cursor < end {
                guard variableLength() != nil, let next = read(1)?.first else { break }
                var status = next
                if next < 0x80 {
                    guard runningStatus != 0 else { break }
                    status = runningStatus
                    cursor -= 1
                } else if next < 0xf0 {
                    runningStatus = next
                } else {
                    runningStatus = 0
                }
                if status == 0xff {
                    guard let kind = read(1)?.first,
                          let size = variableLength(), cursor + size <= end,
                          let payload = read(size) else { break }
                    if kind == 0x03, trackNames[trackIndex] == nil {
                        let name = String(bytes: payload, encoding: .utf8)
                            ?? String(bytes: payload, encoding: .isoLatin1)
                        if let name, !name.isEmpty { trackNames[trackIndex] = name }
                    } else if kind == 0x58, payload.count >= 2,
                              payload[0] > 0, payload[1] <= 6 {
                        numerator = Int(payload[0])
                        denominator = 1 << Int(payload[1])
                    }
                } else if status == 0xf0 || status == 0xf7 {
                    guard let size = variableLength(), cursor + size <= end else { break }
                    cursor += size
                } else if status >= 0x80 && status < 0xf0 {
                    let high = status & 0xf0
                    let size = high == 0xc0 || high == 0xd0 ? 1 : 2
                    guard cursor + size <= end else { break }
                    cursor += size
                } else {
                    break
                }
            }
            cursor = end
        }
    }
}
