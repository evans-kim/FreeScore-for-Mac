import AppKit
import SwiftUI

enum ScoreHeaderTarget { case clef, meter }

struct ScoreLayout {
    let page: Page
    let notes: [ScoreNote]
    let chords: [ChordEvent]
    let repeats: [RepeatSection]
    let navigation: [NavigationMark]
    let chordEditingTick: Int?
    let playbackBeat: Double?
    let clef: Clef
    let measureCount: Int
    private let measureOnsets: [Int: [Double]]
    private let naturalMeasureWidths: [CGFloat]
    private let naturalRowWidths: [CGFloat]
    let alignedRowWidth: CGFloat
    let staffStart: CGFloat = 36
    var rowHeight: CGFloat {
        170 + CGFloat(page.rowGap.isFinite ? max(0, min(160, page.rowGap)) : 15) +
            lyricExtraHeight + (repeats.contains(where: \.hasEndings) ? 30 : 0) +
            (navigation.isEmpty ? 0 : 100)
    }
    var firstRowTop: CGFloat {
        navigation.isEmpty ? (repeats.contains(where: \.hasEndings) ? 190 : 160) : 250
    }
    var rowHeadingOffset: CGFloat {
        navigation.isEmpty ? (repeats.contains(where: \.hasEndings) ? 90 : 52) : 150
    }
    var lyricLineStep: CGFloat { CGFloat(max(10, min(28, page.lyricFontSize))) + 5 }
    var lyricVerseCount: Int { max(1, notes.map(\.highestLyricVerse).max() ?? 0) }
    var lyricExtraHeight: CGFloat { CGFloat(lyricVerseCount - 1) * lyricLineStep }
    var staffBottomOffset: CGFloat { 117 + lyricExtraHeight }

    init(page: Page, notes: [ScoreNote], chords: [ChordEvent] = [],
         repeats: [RepeatSection] = [], navigation: [NavigationMark] = [],
         chordEditingTick: Int? = nil, playbackBeat: Double? = nil,
         clef: Clef = .treble) {
        self.page = page
        self.notes = notes
        self.chords = chords
        self.repeats = repeats
        self.navigation = navigation
        self.chordEditingTick = chordEditingTick
        self.playbackBeat = playbackBeat
        self.clef = clef
        let barBeats = max(0.25, page.beatsPerMeasure)
        let numberOfMeasures = max(RepeatPlaybackPlan.measureCount(
            page: page, notes: notes, chords: chords, repeats: repeats,
            navigation: navigation),
            chordEditingTick.map { ChordGrid.measure(for: $0, page: page) + 1 } ?? 0)
        measureCount = numberOfMeasures
        var counts: [Int: Int] = [:]
        var onsets: [Int: Set<Double>] = [:]
        for segment in ScoreNotation.displayNotes(for: notes, page: page) {
            let bar = max(0, Int(segment.note.startBeat / barBeats))
            counts[bar, default: 0] += 1
            onsets[bar, default: []].insert(segment.note.startBeat - Double(bar) * barBeats)
        }
        for rest in ScoreNotation.rests(for: notes, page: page, measureCount: numberOfMeasures) {
            counts[max(0, Int(rest.startBeat / barBeats)), default: 0] += 1
        }
        measureOnsets = onsets.mapValues { $0.sorted() }
        let spacing = page.noteSpacing.isFinite ? max(18, min(60, page.noteSpacing)) : 29
        let ratio = page.measureWidthRatio.isFinite
            ? max(0.5, min(4, page.measureWidthRatio)) : 1
        let widths = (0..<numberOfMeasures).map { index -> CGFloat in
            let preferred = max(112, CGFloat(counts[index, default: 0]) * 29 + 24) * CGFloat(ratio)
            let minimum = CGFloat(max(0, (onsets[index]?.count ?? 0) - 1)) * CGFloat(spacing) + 24
            return max(preferred, minimum)
        }
        naturalMeasureWidths = widths
        let barsPerRow = max(1, min(16, page.measuresPerLine))
        let rowWidths = stride(from: 0, to: numberOfMeasures, by: barsPerRow).map { start in
            widths[start..<min(numberOfMeasures, start + barsPerRow)].reduce(0, +)
        }
        naturalRowWidths = rowWidths
        alignedRowWidth = ((rowWidths.min() ?? 0) + (rowWidths.max() ?? 0)) / 2
    }

    var barsPerLine: Int { max(1, min(16, page.measuresPerLine)) }
    func barsInRow(_ row: Int) -> Int {
        max(0, min(barsPerLine, measureCount - row * barsPerLine))
    }
    var beatsPerMeasure: Double { max(0.25, page.beatsPerMeasure) }
    var beatsPerLine: Double { beatsPerMeasure * Double(barsPerLine) }
    let clefX: CGFloat = 44
    let accidentalSpacing: CGFloat = 14
    // The clef glyphs have different visible widths. These offsets leave about 6 pt
    // between their ink and the next symbol rather than between text rectangles.
    private var clefInkOffset: CGFloat {
        switch clef {
        case .treble: 0
        case .bass: 5
        case .alto: 3
        }
    }
    var keySignatureX: CGFloat { 76 + clefInkOffset }
    var meterX: CGFloat {
        75 + clefInkOffset + CGFloat(page.keySignature.accidentalCount) * accidentalSpacing
    }
    var musicStart: CGFloat { meterX + 37 }
    var width: CGFloat {
        let chordMargin = chords.map { event -> CGFloat in
            let symbol = event.chord.symbol(in: page.keySignature)
            let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            return ceil((symbol as NSString).size(withAttributes: [.font: font]).width) + 12
        }.max() ?? 0
        return musicStart + alignedRowWidth + max(35, chordMargin)
    }
    var rows: Int {
        max(1, Int(ceil(Double(measureCount) / Double(barsPerLine))))
    }
    var height: CGFloat { staffTop(row: rows - 1) + 137 + lyricExtraHeight }
    func row(for beat: Double) -> Int { max(0, min(rows - 1, Int(beat / beatsPerLine))) }
    func naturalRowWidth(_ row: Int) -> CGFloat { naturalRowWidths[row] }
    private func rowScale(_ row: Int) -> CGFloat {
        let width = naturalRowWidths[row]
        return width > 0 ? alignedRowWidth / width : 1
    }
    func measureWidth(_ index: Int) -> CGFloat {
        naturalMeasureWidths[index] * rowScale(index / barsPerLine)
    }
    func rowWidth(_ row: Int) -> CGFloat {
        barsInRow(row) > 0 ? alignedRowWidth : 0
    }
    func measureStartX(_ index: Int) -> CGFloat {
        let row = index / barsPerLine
        let bar = index % barsPerLine
        return musicStart + (0..<bar).reduce(0) { $0 + measureWidth(row * barsPerLine + $1) }
    }
    func x(for beat: Double) -> CGFloat {
        let index = max(0, Int(beat / beatsPerMeasure))
        let local = beat - Double(index) * beatsPerMeasure
        return measureStartX(index) + localX(for: local, in: index)
    }
    func playbackX(for beat: Double) -> CGFloat {
        let visibleBeat = max(0, min(beat, Double(measureCount) * beatsPerMeasure - 0.001))
        let index = Int(visibleBeat / beatsPerMeasure)
        let local = visibleBeat - Double(index) * beatsPerMeasure
        return local < 0.0001 ? measureStartX(index) : x(for: visibleBeat)
    }
    func staffTop(row: Int) -> CGFloat { firstRowTop + CGFloat(row) * rowHeight }
    func beat(at point: CGPoint) -> Double {
        let row = max(0, min(rows - 1, Int((point.y - firstRowTop + 30) / rowHeight)))
        for bar in 0..<barsInRow(row) {
            let index = row * barsPerLine + bar
            let left = measureStartX(index)
            let right = left + measureWidth(index)
            if point.x < right || bar == barsInRow(row) - 1 {
                return Double(index) * beatsPerMeasure +
                    localBeat(at: point.x - left, in: index)
            }
        }
        return 0
    }
    func measureIndex(at point: CGPoint) -> Int? {
        for row in 0..<rows {
            let top = staffTop(row: row)
            guard point.y >= top - 26, point.y <= top - 4 else { continue }
            for bar in 0..<barsInRow(row) {
                let x = measureStartX(row * barsPerLine + bar)
                if point.x >= x + 2, point.x <= x + 36 {
                    return row * barsPerLine + bar
                }
            }
        }
        return nil
    }

    func chordTick(at point: CGPoint) -> Int? {
        for row in 0..<rows {
            let top = staffTop(row: row)
            guard point.y >= top - 54, point.y < top - 27 else { continue }
            for bar in 0..<barsInRow(row) {
                let index = row * barsPerLine + bar
                let left = measureStartX(index)
                guard point.x >= left, point.x < left + measureWidth(index) else { continue }
                return ChordGrid.snappedTick(beat: beat(at: point), measure: index, page: page)
            }
        }
        return nil
    }

    func chordRect(for tick: Int) -> CGRect {
        let beat = ChordGrid.beat(for: tick)
        let measure = ChordGrid.measure(for: tick, page: page)
        let row = min(rows - 1, measure / barsPerLine)
        let startX = x(for: beat)
        let right = measureStartX(measure) + measureWidth(measure)
        let nextX = ChordGrid.slot(for: tick, page: page) + 1 >= page.numerator
            ? right : x(for: ChordGrid.beat(for: ChordGrid.next(tick, page: page)))
        return CGRect(x: startX - 3, y: staffTop(row: row) - 54,
                      width: max(18, nextX - startX), height: 27)
    }

    private func notePositions(in index: Int) -> [CGFloat] {
        let onsets = measureOnsets[index] ?? []
        guard !onsets.isEmpty else { return [] }
        let width = naturalMeasureWidths[index]
        let spacing = CGFloat(page.noteSpacing.isFinite ? max(18, min(60, page.noteSpacing)) : 29)
        var positions = onsets.map { 12 + CGFloat($0 / beatsPerMeasure) * (width - 24) }
        if positions.count > 1 {
            for i in 1..<positions.count {
                positions[i] = max(positions[i], positions[i - 1] + spacing)
            }
            positions[positions.count - 1] = min(positions[positions.count - 1], width - 12)
            for i in stride(from: positions.count - 2, through: 0, by: -1) {
                positions[i] = min(positions[i], positions[i + 1] - spacing)
            }
            if positions[0] < 12 {
                let shift = 12 - positions[0]
                positions = positions.map { $0 + shift }
            }
        }
        let scale = rowScale(index / barsPerLine)
        return positions.map { $0 * scale }
    }

    private func anchors(in index: Int) -> [(beat: Double, x: CGFloat)] {
        let onsets = measureOnsets[index] ?? []
        let positions = notePositions(in: index)
        let scale = rowScale(index / barsPerLine)
        var result: [(Double, CGFloat)] = [(0, 12 * scale)]
        for (beat, x) in zip(onsets, positions) where beat > 0.0001 {
            result.append((beat, x))
        }
        result.append((beatsPerMeasure, (naturalMeasureWidths[index] - 12) * scale))
        return result
    }

    private func localX(for beat: Double, in index: Int) -> CGFloat {
        let points = anchors(in: index)
        let local = max(0, min(beatsPerMeasure, beat))
        for i in 1..<points.count {
            if local <= points[i].beat {
                let span = points[i].beat - points[i - 1].beat
                let fraction = span > 0 ? (local - points[i - 1].beat) / span : 0
                return points[i - 1].x + CGFloat(fraction) * (points[i].x - points[i - 1].x)
            }
        }
        return points.last!.x
    }

    private func localBeat(at x: CGFloat, in index: Int) -> Double {
        let onsets = measureOnsets[index] ?? []
        let positions = notePositions(in: index)
        for (beat, position) in zip(onsets, positions) where abs(x - position) < 0.001 {
            return beat
        }
        let points = anchors(in: index)
        for i in 1..<points.count {
            if x <= points[i].x {
                let span = points[i].x - points[i - 1].x
                let fraction = span > 0 ? (x - points[i - 1].x) / span : 0
                return max(0, min(beatsPerMeasure * 0.9999,
                                  points[i - 1].beat + Double(fraction) *
                                  (points[i].beat - points[i - 1].beat)))
            }
        }
        return beatsPerMeasure * 0.9999
    }
}

struct ScoreCanvas: NSViewRepresentable {
    let notes: [ScoreNote]
    let chords: [ChordEvent]
    let repeats: [RepeatSection]
    let navigation: [NavigationMark]
    let chordEditingTick: Int?
    let page: Page
    let clef: Clef
    let grid: ScoreGrid
    let selectedIDs: Set<UUID>
    let playbackBeat: Double?
    let isPlaying: Bool
    let onSelect: (UUID?, Bool) -> Void
    let onSelectMany: (Set<UUID>, Bool) -> Void
    let onNoteDoubleClick: (UUID) -> Void
    let onSeek: (Double) -> Void
    let onEdit: ([ScoreNote]) -> Void
    let onDoubleClick: (ScoreHeaderTarget) -> Void
    let onMeasureDoubleClick: (Int) -> Void
    let onChordClick: (Int, StaffView) -> Void
    let onReady: (StaffView) -> Void

    var layout: ScoreLayout {
        ScoreLayout(page: page, notes: notes, chords: chords, repeats: repeats,
                    navigation: navigation,
                    chordEditingTick: chordEditingTick,
                    playbackBeat: playbackBeat, clef: clef)
    }

    func makeNSView(context: Context) -> StaffView {
        let view = StaffView()
        updateNSView(view, context: context)
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateNSView(_ view: StaffView, context: Context) {
        if view.page != page { view.lastFollowedPlaybackBeat = nil }
        view.notes = notes
        view.chords = chords
        view.repeats = repeats
        view.navigation = navigation
        view.chordEditingTick = chordEditingTick
        view.page = page
        view.clef = clef
        view.grid = grid
        view.selectedIDs = selectedIDs
        view.playbackBeat = playbackBeat
        view.isPlaying = isPlaying
        view.onSelect = onSelect
        view.onSelectMany = onSelectMany
        view.onNoteDoubleClick = onNoteDoubleClick
        view.onSeek = onSeek
        view.onEdit = onEdit
        view.onDoubleClick = onDoubleClick
        view.onMeasureDoubleClick = onMeasureDoubleClick
        view.onChordClick = onChordClick
        view.needsDisplay = true
        view.centerGuideOnEntryIfNeeded()
        if let playbackBeat, isPlaying || playbackBeat != view.lastFollowedPlaybackBeat {
            let layout = self.layout
            let row = layout.row(for: playbackBeat)
            let followed = PlaybackScrollFollower.center(
                CGPoint(x: layout.playbackX(for: playbackBeat),
                        y: layout.staffTop(row: row) + 44),
                in: view, smoothly: isPlaying
            )
            if followed { view.lastFollowedPlaybackBeat = playbackBeat }
        } else if playbackBeat == nil {
            view.lastFollowedPlaybackBeat = nil
        }
    }
}

final class StaffView: NSView {
    var notes: [ScoreNote] = []
    var chords: [ChordEvent] = []
    var repeats: [RepeatSection] = []
    var navigation: [NavigationMark] = []
    var chordEditingTick: Int?
    var page = Page()
    var clef: Clef = .treble
    var grid: ScoreGrid = .sixteenth
    var selectedIDs: Set<UUID> = []
    var playbackBeat: Double?
    var isPlaying = false
    var lastFollowedPlaybackBeat: Double?
    private var needsEntryGuideCentering = true
    var onSelect: ((UUID?, Bool) -> Void)?
    var onSelectMany: ((Set<UUID>, Bool) -> Void)?
    var onNoteDoubleClick: ((UUID) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onEdit: (([ScoreNote]) -> Void)?
    var onDoubleClick: ((ScoreHeaderTarget) -> Void)?
    var onMeasureDoubleClick: ((Int) -> Void)?
    var onChordClick: ((Int, StaffView) -> Void)?
    private var hoveredChordTick: Int?
    private var chordTrackingArea: NSTrackingArea?
    private var hitAreas: [(UUID, CGRect)] = []
    private enum DragMode { case move, start, end }
    private var drag: (origin: CGPoint, originals: [ScoreNote], mode: DragMode, previews: [UUID: ScoreNote])?
    private var marqueeOrigin: CGPoint?
    private var marqueeRect: CGRect?
    private var marqueeAdditive = false
    private var clickOrigin: CGPoint?
    private var layout: ScoreLayout {
        ScoreLayout(page: page, notes: notes, chords: chords, repeats: repeats,
                    navigation: navigation,
                    chordEditingTick: chordEditingTick,
                    playbackBeat: playbackBeat, clef: clef)
    }

    func chordAnchorRect(for tick: Int) -> CGRect {
        layout.chordRect(for: tick)
    }

    override func updateTrackingAreas() {
        if let chordTrackingArea { removeTrackingArea(chordTrackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        chordTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let next = layout.chordTick(at: convert(event.locationInWindow, from: nil))
        if next != hoveredChordTick {
            hoveredChordTick = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredChordTick = nil
        needsDisplay = true
    }

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
        let row = layout.row(for: playbackBeat)
        if PlaybackScrollFollower.center(
            CGPoint(x: layout.playbackX(for: playbackBeat),
                    y: layout.staffTop(row: row) + 44),
            in: self, smoothly: false
        ) {
            needsEntryGuideCentering = false
            lastFollowedPlaybackBeat = playbackBeat
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        hitAreas.removeAll()
        let layout = self.layout
        let shownNotes = notes.map { drag?.previews[$0.id] ?? $0 }
        let displayNotes = ScoreNotation.displayNotes(for: shownNotes, page: page)

        drawText(page.title, in: CGRect(x: 30, y: 17, width: layout.width - 60, height: 34),
                 size: 25, weight: .semibold, color: .labelColor, alignment: .center)
        if !page.composer.isEmpty {
            drawText("작곡  \(page.composer)", in: CGRect(x: layout.width - 280, y: 61, width: 240, height: 20),
                     size: 13, weight: .regular, color: .secondaryLabelColor, alignment: .right)
        }
        if !page.arranger.isEmpty {
            drawText("편곡  \(page.arranger)", in: CGRect(x: layout.width - 280, y: 81, width: 240, height: 20),
                     size: 13, weight: .regular, color: .secondaryLabelColor, alignment: .right)
        }

        for row in 0..<layout.rows {
            let top = layout.staffTop(row: row)
            let right = layout.musicStart + layout.rowWidth(row)
            for line in 0..<5 {
                drawLine(from: CGPoint(x: layout.staffStart, y: top + CGFloat(line) * 10),
                         to: CGPoint(x: right, y: top + CGFloat(line) * 10), color: .labelColor, width: 1)
            }
            for bar in 0...layout.barsInRow(row) {
                let x = bar == layout.barsInRow(row) ? right : layout.measureStartX(row * layout.barsPerLine + bar)
                drawLine(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: top + 40),
                         color: .secondaryLabelColor, width: bar == layout.barsInRow(row) ? 2 : 1)
                if bar < layout.barsInRow(row) {
                    drawText("\(row * layout.barsPerLine + bar + 1)",
                             in: CGRect(x: x + 4, y: top - 23, width: 30, height: 17),
                             size: 11, weight: .regular, color: .secondaryLabelColor)
                }
            }
            drawText(clef.symbol, in: CGRect(x: layout.clefX, y: top - (clef == .treble ? 25 : 7),
                                           width: 48, height: clef == .treble ? 83 : 58),
                     size: clef == .treble ? 62 : 50, weight: .regular,
                     color: .labelColor, alignment: .center)
            drawKeySignature(top: top, layout: layout)
            drawText("\(page.numerator)", in: CGRect(x: layout.meterX, y: top - 3, width: 28, height: 21),
                     size: 21, weight: .bold, color: .labelColor, alignment: .center)
            drawText("\(page.denominator)", in: CGRect(x: layout.meterX, y: top + 18, width: 28, height: 21),
                     size: 21, weight: .bold, color: .labelColor, alignment: .center)
        }
        drawRepeats(layout: layout)
        drawNavigation(layout: layout)

        for event in chords where event.positionTick >= 0 &&
            ChordGrid.measure(for: event.positionTick, page: page) < layout.measureCount {
            let rect = layout.chordRect(for: event.positionTick)
            let symbol = event.chord.symbol(in: page.keySignature)
            let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            let textWidth = ceil((symbol as NSString).size(withAttributes: [.font: font]).width) + 4
            let row = ChordGrid.measure(for: event.positionTick, page: page) / layout.barsPerLine
            let nextChordX = chords
                .filter { $0.positionTick > event.positionTick &&
                    ChordGrid.measure(for: $0.positionTick, page: page) / layout.barsPerLine == row }
                .map { layout.chordRect(for: $0.positionTick).minX }
                .min() ?? layout.musicStart + layout.rowWidth(row)
            let availableWidth = max(0, nextChordX - (rect.minX + 4) - 4)
            drawText(symbol, in: CGRect(x: rect.minX + 4, y: rect.minY + 2,
                                        width: max(textWidth, availableWidth), height: 23),
                     size: 15, weight: .semibold, color: .labelColor,
                     font: font, lineBreak: .byClipping)
        }
        if let tick = hoveredChordTick ?? chordEditingTick,
           ChordGrid.measure(for: tick, page: page) < layout.measureCount {
            let rect = layout.chordRect(for: tick).insetBy(dx: 0, dy: 1)
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            if !chords.contains(where: { $0.positionTick == tick }) {
                drawText("+ 코드", in: rect.insetBy(dx: 4, dy: 2), size: 11,
                         weight: .medium, color: .secondaryLabelColor)
            }
        }

        for rest in ScoreNotation.rests(for: shownNotes, page: page,
                                        measureCount: layout.measureCount) {
            drawRest(rest, layout: layout)
        }

        let notationNotes = displayNotes.map(\.note)
        let accidentals = ScoreNotation.accidentals(for: notationNotes, page: page)
        let beamGroups = ScoreNotation.beamGroups(for: notationNotes, page: page)
        let shownByID = Dictionary(uniqueKeysWithValues: notationNotes.map { ($0.id, $0) })
        var beamForNote: [UUID: (down: Bool, y: CGFloat)] = [:]
        for group in beamGroups {
            let members = group.compactMap { shownByID[$0] }
            let steps = members.map { Self.staffStep(for: NotatedPitch.spell($0.pitch, in: page.keySignature), clef: clef) }
            guard let first = members.first, !steps.isEmpty else { continue }
            let down = Double(steps.reduce(0, +)) / Double(steps.count) >= 5
            let top = layout.staffTop(row: layout.row(for: first.startBeat))
            let ys = steps.map { top + 40 - CGFloat($0) * 5 }
            let beamY = (down ? ys.max()! + 34 : ys.min()! - 34)
            for note in members { beamForNote[note.id] = (down, beamY) }
        }

        for display in displayNotes {
            let note = display.note
            let row = layout.row(for: note.startBeat)
            let x = layout.x(for: note.startBeat)
            let top = layout.staffTop(row: row)
            let step = Self.staffStep(for: NotatedPitch.spell(note.pitch, in: page.keySignature), clef: clef)
            let y = top + 40 - CGFloat(step) * 5
            let color: NSColor = selectedIDs.contains(display.sourceID) ? .systemBlue : .labelColor
            if step < 0 {
                for ledger in stride(from: -2, through: step, by: -2) {
                    drawLine(from: CGPoint(x: x - 11, y: top + 40 - CGFloat(ledger) * 5),
                             to: CGPoint(x: x + 11, y: top + 40 - CGFloat(ledger) * 5),
                             color: .labelColor, width: 1)
                }
            } else if step > 8 {
                for ledger in stride(from: 10, through: step, by: 2) {
                    drawLine(from: CGPoint(x: x - 11, y: top + 40 - CGFloat(ledger) * 5),
                             to: CGPoint(x: x + 11, y: top + 40 - CGFloat(ledger) * 5),
                             color: .labelColor, width: 1)
                }
            }
            if !display.tiedFromPrevious, let accidental = accidentals[note.id] {
                drawText(accidental, in: CGRect(x: x - 27, y: y - 15, width: 20, height: 26),
                         size: 20, weight: .regular, color: color)
            }
            let head = NSBezierPath(ovalIn: CGRect(x: x - 6, y: y - 4, width: 13, height: 9))
            color.setStroke()
            head.lineWidth = 1.5
            head.stroke()
            if note.durationBeats < 2 { color.setFill(); head.fill() }
            if [0.1875, 0.375, 0.75, 1.5, 3].contains(where: { abs($0 - note.durationBeats) < 0.001 }) {
                color.setFill()
                NSBezierPath(ovalIn: CGRect(x: x + 13, y: y - 2, width: 4, height: 4)).fill()
            }
            if note.durationBeats < 4 {
                let stemDown = beamForNote[note.id]?.down ?? (step >= 5)
                let stemX = stemDown ? x - 6 : x + 7
                let stemEnd = beamForNote[note.id]?.y ?? y + (stemDown ? 34 : -34)
                drawLine(from: CGPoint(x: stemX, y: y), to: CGPoint(x: stemX, y: stemEnd),
                         color: color, width: 1.5)
                let beamLevel = ScoreNotation.beamLevel(for: note.durationBeats)
                if beamLevel > 0 && beamForNote[note.id] == nil {
                    for level in 0..<beamLevel {
                        let offset = CGFloat(level) * 7 * (stemDown ? -1 : 1)
                        drawFlag(at: CGPoint(x: stemX, y: stemEnd + offset),
                                 stemDown: stemDown, color: color)
                    }
                }
            }
            if display.showsLyric && note.highestLyricVerse > 0 {
                let size = CGFloat(page.lyricFontSize.isFinite
                    ? max(10, min(28, page.lyricFontSize)) : 15)
                let font = page.lyricFontName.isEmpty ? nil : NSFontManager.shared.font(
                    withFamily: page.lyricFontName, traits: [], weight: 5, size: size)
                for verse in 1...4 where !note.lyric(for: verse).isEmpty {
                    drawText(note.lyric(for: verse),
                             in: CGRect(x: x - 60,
                                        y: top + 78 + CGFloat(verse - 1) * layout.lyricLineStep,
                                        width: 120, height: max(28, size + 8)),
                             size: size, weight: .regular, color: .labelColor,
                             alignment: .center, font: font)
                }
            }
            hitAreas.append((display.sourceID, CGRect(x: x - 14, y: y - 14, width: 30, height: 28)))
        }
        for group in beamGroups {
            let members = group.compactMap { shownByID[$0] }
            guard let first = members.first, let last = members.last,
                  let beam = beamForNote[first.id] else { continue }
            let startX = layout.x(for: first.startBeat) + (beam.down ? -6 : 7)
            let endX = layout.x(for: last.startBeat) + (beam.down ? -6 : 7)
            drawLine(from: CGPoint(x: startX, y: beam.y), to: CGPoint(x: endX, y: beam.y),
                     color: .labelColor, width: 5)
            for level in 2...3 {
                let secondaryY = beam.y + (beam.down ? -1 : 1) * CGFloat((level - 1) * 8)
                for index in members.indices where ScoreNotation.beamLevel(for: members[index].durationBeats) >= level {
                    let currentX = layout.x(for: members[index].startBeat) + (beam.down ? -6 : 7)
                    let next = index + 1 < members.count &&
                        ScoreNotation.beamLevel(for: members[index + 1].durationBeats) >= level
                    let previous = index > 0 &&
                        ScoreNotation.beamLevel(for: members[index - 1].durationBeats) >= level
                    if next {
                        let nextX = layout.x(for: members[index + 1].startBeat) + (beam.down ? -6 : 7)
                        drawLine(from: CGPoint(x: currentX, y: secondaryY),
                                 to: CGPoint(x: nextX, y: secondaryY), color: .labelColor, width: 4)
                    } else if !previous {
                        let hook: CGFloat = index == members.count - 1 ? -11 : 11
                        drawLine(from: CGPoint(x: currentX, y: secondaryY),
                                 to: CGPoint(x: currentX + hook, y: secondaryY), color: .labelColor, width: 4)
                    }
                }
            }
        }
        for (index, display) in displayNotes.enumerated() where display.tiedToNext {
            guard index + 1 < displayNotes.count,
                  displayNotes[index + 1].sourceID == display.sourceID else { continue }
            drawTie(from: display.note, to: displayNotes[index + 1].note,
                    layout: layout, selected: selectedIDs.contains(display.sourceID))
        }
        for slur in ScoreNotation.lyricSlurs(for: displayNotes) {
            drawTie(from: slur.from, to: slur.to, layout: layout,
                    selected: selectedIDs.contains(slur.fromID) ||
                        selectedIDs.contains(slur.toID))
        }
        if let beat = playbackBeat {
            let visibleBeat = min(beat, Double(layout.measureCount) * layout.beatsPerMeasure - 0.001)
            let row = layout.row(for: visibleBeat)
            let top = layout.staffTop(row: row)
            let x = min(layout.musicStart + layout.rowWidth(row), layout.playbackX(for: visibleBeat))
            drawLine(from: CGPoint(x: x, y: top - 28),
                     to: CGPoint(x: x, y: top + 117),
                     color: .systemRed, width: 2.5)
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
        if let tick = layout.chordTick(at: point) {
            onChordClick?(tick, self)
            return
        }
        drag = nil
        let row = layout.row(for: layout.beat(at: point))
        let top = layout.staffTop(row: row)
        let isOnStaff = point.x >= layout.musicStart &&
            point.x <= layout.musicStart + layout.rowWidth(row) &&
            point.y >= top - 25 && point.y <= top + 115
        clickOrigin = event.clickCount == 1 && !event.modifierFlags.contains(.shift) && isOnStaff
            ? point : nil
        let hit = hitAreas.last(where: { $0.1.contains(point) })?.0
        if event.clickCount == 2 {
            if let headHit = hitAreas.last(where: { $0.1.insetBy(dx: 7, dy: 9).contains(point) })?.0 {
                onNoteDoubleClick?(headHit); return
            }
            if let measure = layout.measureIndex(at: point) {
                onMeasureDoubleClick?(measure); return
            }
            for row in 0..<layout.rows {
                let top = layout.staffTop(row: row)
                if CGRect(x: layout.clefX - 3, y: top - 25,
                          width: layout.keySignatureX - layout.clefX + 1, height: 82).contains(point) {
                    onDoubleClick?(.clef); return
                }
                if page.keySignature.accidentalCount > 0,
                   CGRect(x: layout.keySignatureX - 2, y: top - 22,
                          width: layout.meterX - layout.keySignatureX + 2, height: 76).contains(point) {
                    onDoubleClick?(.meter); return
                }
                if CGRect(x: layout.meterX - 2, y: top - 5, width: 33, height: 52).contains(point) {
                    onDoubleClick?(.meter); return
                }
            }
        }
        let additive = event.modifierFlags.contains(.shift)
        if let hit, let note = notes.first(where: { $0.id == hit }) {
            onSelect?(hit, additive)
            guard !additive else { return }
            let mode: DragMode = event.modifierFlags.contains(.option)
                ? (event.modifierFlags.contains(.command) ? .start : .end) : .move
            let originals = selectedIDs.contains(hit) && selectedIDs.count > 1
                ? notes.filter { selectedIDs.contains($0.id) } : [note]
            drag = (point, originals, mode, Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) }))
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
            let rawDelta = grid.quantize(layout.beat(at: point) - layout.beat(at: drag.origin))
            let minStart = drag.originals.map(\.startBeat).min() ?? 0
            let minDuration = drag.originals.map(\.durationBeats).min() ?? grid.rawValue
            let staffSteps = Int(round((drag.origin.y - point.y) / 5))
            for original in drag.originals {
                var preview = original
                switch drag.mode {
                case .move:
                    preview.startBeat += max(-minStart, rawDelta)
                    if staffSteps != 0 {
                        preview.pitch = ScoreNotation.transpose(original.pitch, staffSteps: staffSteps,
                                                                key: page.keySignature)
                    }
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
        let seekBeat = clickOrigin.map { layout.beat(at: $0) }
        if let drag {
            let edited = drag.originals.compactMap { drag.previews[$0.id] }
            if zip(drag.originals, edited).contains(where: { $0.0 != $0.1 }) { onEdit?(edited) }
            self.drag = nil
        } else if let marqueeRect, (marqueeRect.width > 3 || marqueeRect.height > 3) {
            let ids = Set(hitAreas.filter { $0.1.intersects(marqueeRect) }.map(\.0))
            onSelectMany?(ids, marqueeAdditive)
        }
        marqueeOrigin = nil
        marqueeRect = nil
        if let seekBeat { onSeek?(seekBeat) }
        clickOrigin = nil
        needsDisplay = true
    }

    private func drawRepeats(layout: ScoreLayout) {
        for section in repeats where section.startMeasure >= 0 &&
            section.lastMeasure < layout.measureCount {
            let startRow = section.startMeasure / layout.barsPerLine
            let startTop = layout.staffTop(row: startRow)
            let startX = layout.measureStartX(section.startMeasure)
            drawLine(from: CGPoint(x: startX + 3, y: startTop),
                     to: CGPoint(x: startX + 3, y: startTop + 40),
                     color: .labelColor, width: 3)
            for offset: CGFloat in [15, 25] {
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: CGRect(x: startX + 10, y: startTop + offset - 2,
                                           width: 4, height: 4)).fill()
            }

            let endRow = section.endMeasure / layout.barsPerLine
            let endTop = layout.staffTop(row: endRow)
            let endX = layout.measureStartX(section.endMeasure) +
                layout.measureWidth(section.endMeasure)
            drawLine(from: CGPoint(x: endX - 4, y: endTop),
                     to: CGPoint(x: endX - 4, y: endTop + 40),
                     color: .labelColor, width: 3)
            for offset: CGFloat in [15, 25] {
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: CGRect(x: endX - 13, y: endTop + offset - 2,
                                           width: 4, height: 4)).fill()
            }
            if let first = section.firstEndingStartMeasure,
               let secondEnd = section.secondEndingEndMeasure {
                drawEnding(from: first, through: section.endMeasure,
                           label: "1.", layout: layout)
                drawEnding(from: section.endMeasure + 1, through: secondEnd,
                           label: "2.", layout: layout)
            }
        }
    }

    private func drawNavigation(layout: ScoreLayout) {
        for mark in navigation where (0..<layout.measureCount).contains(mark.measure) {
            let top = layout.staffTop(row: mark.measure / layout.barsPerLine)
            let left = layout.measureStartX(mark.measure)
            let x = mark.kind.atMeasureStart ? left + 5 :
                max(left + 4, left + layout.measureWidth(mark.measure) - 132)
            let y = top - (mark.kind.atMeasureStart ? 138 : 108)
            if mark.kind == .segno || mark.kind == .coda {
                drawNavigationSymbol(mark.kind, at: CGPoint(x: x, y: y))
                drawText(mark.kind.label,
                         in: CGRect(x: x + 28, y: y, width: 100, height: 23),
                         size: 13, weight: .semibold, color: .labelColor)
            } else {
                drawText(mark.kind.label, in: CGRect(x: x, y: y, width: 130, height: 23),
                         size: 14, weight: .semibold, color: .labelColor)
            }
        }
    }

    private func drawNavigationSymbol(_ kind: NavigationMark.Kind, at point: CGPoint) {
        NSColor.labelColor.setStroke()
        if kind == .coda {
            let circle = NSBezierPath(ovalIn: CGRect(x: point.x + 4, y: point.y + 4,
                                                    width: 16, height: 16))
            circle.lineWidth = 2
            circle.stroke()
            drawLine(from: CGPoint(x: point.x + 12, y: point.y - 2),
                     to: CGPoint(x: point.x + 12, y: point.y + 26),
                     color: .labelColor, width: 2)
            drawLine(from: CGPoint(x: point.x - 2, y: point.y + 12),
                     to: CGPoint(x: point.x + 26, y: point.y + 12),
                     color: .labelColor, width: 2)
        } else {
            let s = NSBezierPath()
            s.move(to: CGPoint(x: point.x + 20, y: point.y + 3))
            s.curve(to: CGPoint(x: point.x + 6, y: point.y + 8),
                    controlPoint1: CGPoint(x: point.x + 9, y: point.y - 3),
                    controlPoint2: CGPoint(x: point.x + 1, y: point.y + 2))
            s.curve(to: CGPoint(x: point.x + 18, y: point.y + 17),
                    controlPoint1: CGPoint(x: point.x + 9, y: point.y + 13),
                    controlPoint2: CGPoint(x: point.x + 21, y: point.y + 11))
            s.curve(to: CGPoint(x: point.x + 4, y: point.y + 22),
                    controlPoint1: CGPoint(x: point.x + 19, y: point.y + 23),
                    controlPoint2: CGPoint(x: point.x + 9, y: point.y + 27))
            s.lineWidth = 2
            s.stroke()
            drawLine(from: CGPoint(x: point.x + 3, y: point.y + 1),
                     to: CGPoint(x: point.x + 22, y: point.y + 24),
                     color: .labelColor, width: 1.4)
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: point.x + 2, y: point.y + 15,
                                       width: 3, height: 3)).fill()
            NSBezierPath(ovalIn: CGRect(x: point.x + 19, y: point.y + 6,
                                       width: 3, height: 3)).fill()
        }
    }

    private func drawEnding(from first: Int, through last: Int, label: String,
                            layout: ScoreLayout) {
        guard first <= last else { return }
        let firstRow = first / layout.barsPerLine
        let lastRow = last / layout.barsPerLine
        for row in firstRow...lastRow {
            let firstInRow = max(first, row * layout.barsPerLine)
            let lastInRow = min(last, row * layout.barsPerLine + layout.barsInRow(row) - 1)
            let top = layout.staffTop(row: row)
            let y = top - 76
            let left = layout.measureStartX(firstInRow)
            let right = layout.measureStartX(lastInRow) + layout.measureWidth(lastInRow)
            drawLine(from: CGPoint(x: left, y: y), to: CGPoint(x: right, y: y),
                     color: .labelColor, width: 1.4)
            if row == firstRow {
                drawLine(from: CGPoint(x: left, y: y),
                         to: CGPoint(x: left, y: y + 12), color: .labelColor, width: 1.4)
                drawText(label, in: CGRect(x: left + 6, y: y + 2, width: 28, height: 18),
                         size: 12, weight: .semibold, color: .labelColor)
            }
            if row == lastRow {
                drawLine(from: CGPoint(x: right, y: y),
                         to: CGPoint(x: right, y: y + 12), color: .labelColor, width: 1.4)
            }
        }
    }

    private func drawKeySignature(top: CGFloat, layout: ScoreLayout) {
        let sharpSteps: [Int]
        let flatSteps: [Int]
        switch clef {
        case .treble:
            sharpSteps = [8, 5, 9, 6, 3, 7, 4]
            flatSteps = [4, 7, 3, 6, 2, 5, 1]
        case .bass:
            sharpSteps = [6, 3, 7, 4, 1, 5, 2]
            flatSteps = [2, 5, 1, 4, 0, 3, -1]
        case .alto:
            sharpSteps = [7, 4, 8, 5, 2, 6, 3]
            flatSteps = [3, 6, 2, 5, 1, 4, 0]
        }
        let steps = page.keySignature.isFlat ? flatSteps : sharpSteps
        let symbol = page.keySignature.isFlat ? "♭" : "♯"
        for index in 0..<page.keySignature.accidentalCount {
            let y = top + 40 - CGFloat(steps[index]) * 5
            drawText(symbol, in: CGRect(x: layout.keySignatureX + CGFloat(index) * layout.accidentalSpacing,
                                        y: y - 17,
                                        width: 22, height: 31),
                     size: 25, weight: .regular, color: .labelColor, alignment: .center)
        }
    }

    private func drawRest(_ rest: ScoreRest, layout: ScoreLayout) {
        let bar = Int(rest.startBeat / layout.beatsPerMeasure)
        let row = bar / layout.barsPerLine
        let top = layout.staffTop(row: row)
        let x = rest.wholeMeasure
            ? layout.measureStartX(bar) + layout.measureWidth(bar) / 2
            : layout.x(for: rest.startBeat + rest.durationBeats / 2)
        let dottedValues: [Double] = [3, 1.5, 0.75, 0.375, 0.1875]
        let dotted = !rest.wholeMeasure && dottedValues.contains {
            abs($0 - rest.durationBeats) < 0.001
        }
        let base = rest.wholeMeasure ? 4 : rest.durationBeats / (dotted ? 1.5 : 1)
        NSColor.labelColor.setFill()
        if base >= 4 - 0.001 {
            NSBezierPath(rect: CGRect(x: x - 7, y: top + 30, width: 14, height: 5)).fill()
        } else if base >= 2 - 0.001 {
            NSBezierPath(rect: CGRect(x: x - 7, y: top + 15, width: 14, height: 5)).fill()
        } else if base >= 1 - 0.001 {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x - 3, y: top + 8))
            path.line(to: CGPoint(x: x + 2, y: top + 14))
            path.line(to: CGPoint(x: x - 2, y: top + 19))
            path.line(to: CGPoint(x: x + 3, y: top + 26))
            path.line(to: CGPoint(x: x - 2, y: top + 31))
            path.lineWidth = 3.2
            path.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            path.stroke()
        } else {
            let flags = base >= 0.5 - 0.001 ? 1 : base >= 0.25 - 0.001 ? 2 : 3
            drawLine(from: CGPoint(x: x + 3, y: top + 11),
                     to: CGPoint(x: x - 3, y: top + 33), color: .labelColor, width: 2)
            for index in 0..<flags {
                let y = top + 12 + CGFloat(index) * 7
                NSBezierPath(ovalIn: CGRect(x: x - 5, y: y - 3, width: 5, height: 5)).fill()
                drawLine(from: CGPoint(x: x - 1, y: y), to: CGPoint(x: x + 3, y: y + 3),
                         color: .labelColor, width: 1.5)
            }
        }
        if dotted {
            NSBezierPath(ovalIn: CGRect(x: x + 10, y: top + 22, width: 4, height: 4)).fill()
        }
    }

    private func drawTie(from first: ScoreNote, to second: ScoreNote,
                         layout: ScoreLayout, selected: Bool) {
        let firstRow = layout.row(for: first.startBeat)
        let secondRow = layout.row(for: second.startBeat)
        let firstStep = Self.staffStep(for: NotatedPitch.spell(first.pitch, in: page.keySignature),
                                       clef: clef)
        let secondStep = Self.staffStep(for: NotatedPitch.spell(second.pitch, in: page.keySignature),
                                        clef: clef)
        let direction: CGFloat = firstStep + secondStep >= 10 ? -1 : 1
        let color: NSColor = selected ? .systemBlue : .labelColor
        let firstY = layout.staffTop(row: firstRow) + 40 - CGFloat(firstStep) * 5 + direction * 5
        let secondY = layout.staffTop(row: secondRow) + 40 - CGFloat(secondStep) * 5 + direction * 5
        let firstX = layout.x(for: first.startBeat) + 7
        let secondX = layout.x(for: second.startBeat) - 7
        if firstRow == secondRow {
            drawTieArc(from: CGPoint(x: firstX, y: firstY),
                       to: CGPoint(x: secondX, y: secondY), direction: direction, color: color)
        } else {
            let rowEnd = layout.musicStart + layout.rowWidth(firstRow) - 4
            drawTieArc(from: CGPoint(x: firstX, y: firstY),
                       to: CGPoint(x: rowEnd, y: firstY), direction: direction, color: color)
            drawTieArc(from: CGPoint(x: layout.musicStart - 5, y: secondY),
                       to: CGPoint(x: secondX, y: secondY), direction: direction, color: color)
        }
    }

    private func drawTieArc(from start: CGPoint, to end: CGPoint,
                            direction: CGFloat, color: NSColor) {
        guard end.x > start.x + 2 else { return }
        let span = end.x - start.x
        let path = NSBezierPath()
        path.move(to: start)
        path.curve(to: end,
                   controlPoint1: CGPoint(x: start.x + span * 0.28, y: start.y + direction * 9),
                   controlPoint2: CGPoint(x: end.x - span * 0.28, y: end.y + direction * 9))
        path.curve(to: start,
                   controlPoint1: CGPoint(x: end.x - span * 0.28, y: end.y + direction * 6),
                   controlPoint2: CGPoint(x: start.x + span * 0.28, y: start.y + direction * 6))
        path.close()
        color.setFill()
        path.fill()
    }

    private func drawFlag(at stemEnd: CGPoint, stemDown: Bool, color: NSColor) {
        let horizontal: CGFloat = stemDown ? -1 : 1
        let vertical: CGFloat = stemDown ? -1 : 1
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: stemEnd.x + horizontal * x, y: stemEnd.y + vertical * y)
        }
        let flag = NSBezierPath()
        flag.move(to: point(0, 0))
        flag.curve(to: point(12, 23),
                   controlPoint1: point(9, 3), controlPoint2: point(18, 12))
        flag.curve(to: point(4, 9),
                   controlPoint1: point(14, 16), controlPoint2: point(9, 10))
        flag.close()
        color.setFill()
        flag.fill()
    }

    private func drawLine(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func drawText(_ string: String, in rect: CGRect, size: CGFloat,
                          weight: NSFont.Weight, color: NSColor,
                          alignment: NSTextAlignment = .left, font: NSFont? = nil,
                          lineBreak: NSLineBreakMode = .byWordWrapping) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreak
        string.draw(in: rect, withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }

    private static func staffStep(for pitch: NotatedPitch, clef: Clef) -> Int {
        let base: Int
        switch clef {
        case .treble: base = 4 * 7 + 2
        case .bass: base = 2 * 7 + 4
        case .alto: base = 3 * 7 + 3
        }
        return pitch.diatonicIndex - base
    }
}
