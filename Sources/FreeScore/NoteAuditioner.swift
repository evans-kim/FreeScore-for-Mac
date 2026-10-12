import AVFAudio
import Foundation

@MainActor
protocol NoteSoundPlaying: AnyObject {
    func playNote(pitch: Int, velocity: Int)
    func playCountInClick()
}

@MainActor
final class NoteAuditioner: NoteSoundPlaying {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var activePitch: UInt8?
    private var releaseTask: Task<Void, Never>?
    private var didLoadInstrument = false

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    func playNote(pitch: Int, velocity: Int) {
        play(pitch: pitch, velocity: velocity, duration: 0.28)
    }

    func playCountInClick() {
        play(pitch: 84, velocity: 110, duration: 0.09)
    }

    private func play(pitch: Int, velocity: Int, duration: TimeInterval) {
        guard prepareAudio() else { return }
        releaseTask?.cancel()
        if let activePitch { sampler.stopNote(activePitch, onChannel: 0) }
        let midiPitch = UInt8(clamping: pitch)
        sampler.startNote(midiPitch, withVelocity: UInt8(clamping: velocity), onChannel: 0)
        activePitch = midiPitch
        releaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.sampler.stopNote(midiPitch, onChannel: 0)
            self.activePitch = nil
            self.releaseTask = nil
        }
    }

    private func prepareAudio() -> Bool {
        do {
            if !didLoadInstrument {
                let soundBank = URL(fileURLWithPath:
                    "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
                if FileManager.default.fileExists(atPath: soundBank.path) {
                    try sampler.loadSoundBankInstrument(at: soundBank, program: 0,
                                                        bankMSB: 0x79, bankLSB: 0)
                }
                didLoadInstrument = true
            }
            if !engine.isRunning { try engine.start() }
            return true
        } catch {
            return false
        }
    }
}
