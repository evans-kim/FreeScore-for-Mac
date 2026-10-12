import AppKit
import SwiftUI

struct PianoRollLayout {
    let notes: [ScoreNote]
    let page: Page
    var playbackBeat: Double? = nil
    let beatWidth: CGFloat = 56
    let keyHeight: CGFloat = 19
    let left: CGFloat = 68
    let top: CGFloat = 32

    var lowPitch: Int { max(0, min(48, (notes.map(\.pitch).min() ?? 60) - 6)) }
    var highPitch: Int { min(127, max(72, (notes.map(\.pitch).max() ?? 60) + 6)) }
    var totalBeats: Double {
        let end = notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        return max(page.beatsPerMeasure * Double(max(1, page.measuresPerLine)),
                   ceil(max(end + 2, (playbackBeat ?? 0) + page.beatsPerMeasure)))
    }
    var width: CGFloat { left + CGFloat(totalBeats) * beatWidth + 30 }
    var height: CGFloat { top + CGFloat(highPitch - lowPitch + 1) * keyHeight + 22 }

    func x(_ beat: Double) -> CGFloat { left + CGFloat(beat) * beatWidth }
    func y(_ pitch: Int) -> CGFloat { top + CGFloat(highPitch - pitch) * keyHeight }
    func pitch(at y: CGFloat) -> Int {
        max(lowPitch, min(highPitch, highPitch - Int(floor((y - top) / keyHeight))))
    }
    func beat(at x: CGFloat) -> Double { max(0, Double((x - left) / beatWidth)) }
    func rect(for note: ScoreNote) -> CGRect {
        CGRect(x: x(note.startBeat), y: y(note.pitch) + 2,
               width: max(6, CGFloat(note.durationBeats) * beatWidth), height: keyHeight - 4)
    }

}

struct PianoRollCanvas: NSViewRepresentable {
    let notes: [ScoreNote]
    let page: Page
    let grid: ScoreGrid
    let selectedIDs: Set<UUID>
    let playbackBeat: Double?
    let isPlaying: Bool
    let onSelect: (UUID?, Bool) -> Void
    let onSelectMany: (Set<UUID>, Bool) -> Void
    let onNoteDoubleClick: (UUID) -> Void
    let onSeek: (Double) -> Void
    let onAdd: (Double, Int) -> Void
    let onEdit: ([ScoreNote]) -> Void

    var layout: PianoRollLayout { PianoRollLayout(notes: notes, page: page, playbackBeat: playbackBeat) }

    func makeNSView(context: Context) -> PianoRollView {
        let view = PianoRollView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PianoRollView, context: Context) {
        view.setNotes(notes)
        view.page = page
        view.grid = grid
        view.selectedIDs = selectedIDs
        view.playbackBeat = playbackBeat
        view.isPlaying = isPlaying
        view.onSelect = onSelect
        view.onSelectMany = onSelectMany
        view.onNoteDoubleClick = onNoteDoubleClick
        view.onSeek = onSeek
        view.onAdd = onAdd
        view.onEdit = onEdit
        view.needsDisplay = true
        view.centerGuideOnEntryIfNeeded()
        view.followPlaybackGuide()
    }
}

final class PianoRollView: NSView {
    var notes: [ScoreNote] = []
    var page = Page()
    var grid: ScoreGrid = .sixteenth
    var selectedIDs: Set<UUID> = []
    var playbackBeat: Double?
    var isPlaying = false
    private var needsEntryGuideCentering = true
    var onSelect: ((UUID?, Bool) -> Void)?
    var onSelectMany: ((Set<UUID>, Bool) -> Void)?
    var onNoteDoubleClick: ((UUID) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onAdd: ((Double, Int) -> Void)?
    var onEdit: (([ScoreNote]) -> Void)?
    private enum DragMode { case move, start, end }
    private var drag: (origin: CGPoint, originals: [ScoreNote], mode: DragMode, previews: [UUID: ScoreNote])?
    private var pendingNotes: [ScoreNote]?
    private var clickOrigin: CGPoint?
    private var marqueeOrigin: CGPoint?
    private var marqueeRect: CGRect?
    private var marqueeAdditive = false
    private var layout: PianoRollLayout { PianoRollLayout(notes: notes, page: page, playbackBeat: playbackBeat) }
    var isDragging: Bool { drag != nil || marqueeOrigin != nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in self?.centerGuideOnEntryIfNeeded() }
    }

    func centerGuideOnEntryIfNeeded() {
        guard needsEntryGuideCentering else { return }
        guard let playbackBeat else {
            needsEntryGuideCentering = false
            return
        }
        if PlaybackScrollFollower.center(
            CGPoint(x: layout.x(playbackBeat), y: 0),
            in: self, smoothly: false, axes: .horizontal
        ) {
            needsEntryGuideCentering = false
        }
    }

    func followPlaybackGuide() {
        guard isPlaying, let playbackBeat, !isDragging else { return }
        PlaybackScrollFollower.center(
            CGPoint(x: layout.x(playbackBeat), y: 0),
            in: self, smoothly: true, axes: .horizontal
        )
    }

    func setNotes(_ updated: [ScoreNote]) {
        if isDragging {
            pendingNotes = updated
        } else {
            notes = updated
            pendingNotes = nil
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let layout = self.layout
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        for pitch in layout.lowPitch...layout.highPitch {
            let rect = CGRect(x: 0, y: layout.y(pitch), width: layout.width, height: layout.keyHeight)
            if [1, 3, 6, 8, 10].contains(pitch % 12) {
                NSColor.labelColor.withAlphaComponent(0.07).setFill()
                rect.fill()
            }
            stroke(CGPoint(x: 0, y: rect.maxY), CGPoint(x: layout.width, y: rect.maxY),
                   .separatorColor, 0.5)
            if pitch % 12 == 0 {
                label("C\(pitch / 12 - 1)", CGRect(x: 7, y: rect.minY + 1, width: 50, height: 16),
                      11, .secondaryLabelColor)
            }
        }
        for beat in 0...Int(ceil(layout.totalBeats)) {
            let x = layout.x(Double(beat))
            stroke(CGPoint(x: x, y: layout.top), CGPoint(x: x, y: layout.height - 20),
                   .separatorColor, 0.7)
            label("\(beat + 1)", CGRect(x: x + 3, y: 6, width: 30, height: 17),
                  10, .secondaryLabelColor)
        }
        let beatsPerBar = max(0.25, page.beatsPerMeasure)
        for bar in 0...Int(ceil(layout.totalBeats / beatsPerBar)) {
            let x = layout.x(Double(bar) * beatsPerBar)
            stroke(CGPoint(x: x, y: layout.top), CGPoint(x: x, y: layout.height - 20),
                   .secondaryLabelColor, 1.5)
        }
        for note in notes {
            let shown = drag?.previews[note.id] ?? note
            let rect = layout.rect(for: shown)
            let selected = selectedIDs.contains(note.id)
            (selected ? NSColor.systemBlue : NSColor.systemTeal).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            if rect.width >= 38 {
                label(NotatedPitch.spell(shown.pitch, in: page.keySignature).name,
                      rect.insetBy(dx: 5, dy: 1), 10, .white)
            }
        }
        if let playbackBeat {
            let x = layout.x(playbackBeat)
            stroke(CGPoint(x: x, y: 0), CGPoint(x: x, y: layout.height), .systemRed, 2.5)
        }
        if let marqueeRect {
            NSColor.systemBlue.withAlphaComponent(0.16).setFill()
            marqueeRect.fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(rect: marqueeRect).stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        clickOrigin = event.clickCount == 1 && !event.modifierFlags.contains(.shift) ? point : nil
        let layout = self.layout
        let additive = event.modifierFlags.contains(.shift)
        if let note = notes.reversed().first(where: { layout.rect(for: $0).insetBy(dx: -2, dy: -2).contains(point) }) {
            if event.clickCount == 2 {
                clickOrigin = nil
                onNoteDoubleClick?(note.id)
                return
            }
            onSelect?(note.id, additive)
            guard !additive else { return }
            let rect = layout.rect(for: note)
            let mode: DragMode
            if abs(point.x - rect.minX) <= 8 && abs(point.x - rect.minX) < abs(point.x - rect.maxX) {
                mode = .start
            } else if abs(point.x - rect.maxX) <= 8 {
                mode = .end
            } else {
                mode = .move
            }
            let originals = selectedIDs.contains(note.id) && selectedIDs.count > 1
                ? notes.filter { selectedIDs.contains($0.id) } : [note]
            drag = (point, originals, mode, Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) }))
        } else if event.clickCount == 2, point.x >= layout.left, point.y >= layout.top {
            clickOrigin = nil
            onAdd?(grid.quantize(layout.beat(at: point.x)), layout.pitch(at: point.y))
        } else {
            marqueeOrigin = point
            marqueeRect = nil
            marqueeAdditive = additive
            if !additive { onSelect?(nil, false) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let clickOrigin, hypot(point.x - clickOrigin.x, point.y - clickOrigin.y) > 3 {
            self.clickOrigin = nil
        }
        if var drag {
            let rawDelta = grid.quantize(Double((point.x - drag.origin.x) / layout.beatWidth))
            let minStart = drag.originals.map(\.startBeat).min() ?? 0
            let minDuration = drag.originals.map(\.durationBeats).min() ?? grid.rawValue
            let pitchDelta = Int(round((drag.origin.y - point.y) / layout.keyHeight))
            let low = drag.originals.map(\.pitch).min() ?? 0
            let high = drag.originals.map(\.pitch).max() ?? 127
            for original in drag.originals {
                var preview = original
                switch drag.mode {
                case .move:
                    preview.startBeat += max(-minStart, rawDelta)
                    preview.pitch += max(-low, min(127 - high, pitchDelta))
                case .start:
                    let delta = max(-minStart, min(minDuration - grid.rawValue, rawDelta))
                    preview.startBeat += delta
                    preview.durationBeats -= delta
                case .end:
                    preview.durationBeats += max(grid.rawValue - minDuration, rawDelta)
                }
                drag.previews[original.id] = preview
            }
            self.drag = drag
        } else if let marqueeOrigin {
            marqueeRect = CGRect(x: min(marqueeOrigin.x, point.x), y: min(marqueeOrigin.y, point.y),
                                 width: abs(point.x - marqueeOrigin.x), height: abs(point.y - marqueeOrigin.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let seekBeat = clickOrigin.map { layout.beat(at: $0.x) }
        if let drag {
            let edited = drag.originals.compactMap { drag.previews[$0.id] }
            let changed = zip(drag.originals, edited).contains(where: { $0.0 != $0.1 })
            if changed {
                let replacements = Dictionary(uniqueKeysWithValues: edited.map { ($0.id, $0) })
                notes = notes.map { replacements[$0.id] ?? $0 }
            } else if let pendingNotes {
                notes = pendingNotes
            }
            self.drag = nil
            pendingNotes = nil
            if changed { onEdit?(edited) }
        } else if let marqueeRect, (marqueeRect.width > 3 || marqueeRect.height > 3) {
            let ids = Set(notes.filter { layout.rect(for: $0).intersects(marqueeRect) }.map(\.id))
            onSelectMany?(ids, marqueeAdditive)
        } else if let pendingNotes {
            notes = pendingNotes
            self.pendingNotes = nil
        }
        if let seekBeat { onSeek?(seekBeat) }
        clickOrigin = nil
        marqueeOrigin = nil
        marqueeRect = nil
        needsDisplay = true
    }

    private func stroke(_ start: CGPoint, _ end: CGPoint, _ color: NSColor, _ width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func label(_ text: String, _ rect: CGRect, _ size: CGFloat, _ color: NSColor) {
        text.draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: color
        ])
    }
}
