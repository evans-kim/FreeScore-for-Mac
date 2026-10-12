import AppKit
import PDFKit
import SwiftUI

struct ScorePrintSettings: Codable, Equatable {
    enum Orientation: String, Codable, CaseIterable, Identifiable {
        case portrait = "세로"
        case landscape = "가로"
        var id: Self { self }
    }

    enum Sizing: String, Codable, CaseIterable, Identifiable {
        case fitPage = "한 페이지에 맞춤"
        case fitWidth = "너비에 맞춤"
        case custom = "배율 지정"
        var id: Self { self }
    }

    var orientation: Orientation = .landscape
    var sizing: Sizing = .fitWidth
    var scalePercent: Double = 100

    var paperSize: CGSize {
        orientation == .landscape
            ? CGSize(width: 842, height: 595)
            : CGSize(width: 595, height: 842)
    }
}

struct ScorePrintLayout {
    static let margin: CGFloat = 28

    let score: ScoreLayout
    let settings: ScorePrintSettings
    let paperSize: CGSize
    let scale: CGFloat
    let pageStarts: [CGFloat]
    let horizontalStarts: [CGFloat]

    var pageCount: Int { pageStarts.count * horizontalStarts.count }

    init(score: ScoreLayout, settings: ScorePrintSettings = .init()) {
        self.score = score
        self.settings = settings
        paperSize = settings.paperSize
        let printableWidth = paperSize.width - Self.margin * 2
        let printableHeight = paperSize.height - Self.margin * 2
        switch settings.sizing {
        case .fitPage:
            scale = min(printableWidth / score.width, printableHeight / score.height)
        case .fitWidth:
            // Keep the first complete staff on the first sheet, even for a narrow score.
            scale = min(printableWidth / score.width,
                        printableHeight / (score.staffTop(row: 0) + score.staffBottomOffset))
        case .custom:
            scale = CGFloat(max(25, min(180, settings.scalePercent)) / 100)
        }
        let sourcePanelWidth = printableWidth / scale
        let panelCount = max(1, Int(ceil(score.width / sourcePanelWidth - 0.000001)))
        horizontalStarts = (0..<panelCount).map { CGFloat($0) * sourcePanelWidth }
        let availableSourceHeight = printableHeight / scale
        var starts: [CGFloat] = []
        var firstRow = 0
        while firstRow < score.rows {
            let sourceTop: CGFloat = firstRow == 0 ? 0 :
                score.staffTop(row: firstRow) - score.rowHeadingOffset
            starts.append(sourceTop)
            var nextRow = firstRow
            while nextRow < score.rows,
                  score.staffTop(row: nextRow) + score.staffBottomOffset <=
                      sourceTop + availableSourceHeight {
                nextRow += 1
            }
            firstRow = max(firstRow + 1, nextRow)
        }
        pageStarts = starts
    }
}

enum ScorePrintRenderer {
    enum PrintError: Error { case invalidTrack, sourcePDF, outputPDF }

    static func makePDF(document: ScoreDocument, trackIndex: Int,
                        settings: ScorePrintSettings = .init()) throws -> Data {
        guard document.tracks.indices.contains(trackIndex) else { throw PrintError.invalidTrack }
        let track = document.tracks[trackIndex]
        let layout = ScoreLayout(page: document.page, notes: track.notes,
                                 chords: document.chordEvents, repeats: document.repeatSections,
                                 navigation: document.navigationMarks,
                                 clef: track.clef)
        let pages = ScorePrintLayout(score: layout, settings: settings)
        let staff = StaffView(frame: CGRect(origin: .zero,
                                           size: CGSize(width: layout.width, height: layout.height)))
        staff.appearance = NSAppearance(named: .aqua)
        staff.page = document.page
        staff.notes = track.notes
        staff.chords = document.chordEvents
        staff.repeats = document.repeatSections
        staff.navigation = document.navigationMarks
        staff.clef = track.clef
        guard let provider = CGDataProvider(data: staff.dataWithPDF(inside: staff.bounds) as CFData),
              let source = CGPDFDocument(provider), let sourcePage = source.page(at: 1) else {
            throw PrintError.sourcePDF
        }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw PrintError.outputPDF
        }
        var mediaBox = CGRect(origin: .zero, size: pages.paperSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PrintError.outputPDF
        }
        for (pageIndex, sourceTop) in pages.pageStarts.enumerated() {
            for sourceLeft in pages.horizontalStarts {
                context.beginPDFPage(nil)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(mediaBox)
                context.saveGState()
                let nextSourceTop = pageIndex + 1 < pages.pageStarts.count
                    ? pages.pageStarts[pageIndex + 1] : layout.height
                let segmentHeight = min(mediaBox.height - ScorePrintLayout.margin * 2,
                                        (nextSourceTop - sourceTop) * pages.scale)
                let segmentWidth = min(mediaBox.width - ScorePrintLayout.margin * 2,
                                       (layout.width - sourceLeft) * pages.scale)
                let clipLeft = (mediaBox.width - segmentWidth) / 2
                context.clip(to: CGRect(x: clipLeft,
                                        y: mediaBox.height - ScorePrintLayout.margin - segmentHeight,
                                        width: segmentWidth,
                                        height: segmentHeight))
                let left = clipLeft - sourceLeft * pages.scale
                let pageTop = mediaBox.height - ScorePrintLayout.margin
                context.translateBy(x: left,
                                    y: pageTop - (layout.height - sourceTop) * pages.scale)
                context.scaleBy(x: pages.scale, y: pages.scale)
                context.drawPDFPage(sourcePage)
                context.restoreGState()
                context.endPDFPage()
            }
        }
        context.closePDF()
        return output as Data
    }

    static func printDocument(_ pdf: PDFDocument, settings: ScorePrintSettings) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = settings.paperSize
        info.orientation = settings.orientation == .landscape ? .landscape : .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleNone,
                                                 autoRotate: false) else { return }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}

struct ScorePDFPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

struct PrintModeView: View {
    @ObservedObject var store: ScoreStore
    @State private var pdf: PDFDocument?
    @State private var renderError: String?

    private var settings: ScorePrintSettings { store.printSettings }

    private var layout: ScorePrintLayout? {
        guard let track = store.selectedTrack else { return nil }
        let score = ScoreLayout(page: store.document.page, notes: track.notes,
                                chords: store.document.chordEvents,
                                repeats: store.document.repeatSections,
                                navigation: store.document.navigationMarks, clef: track.clef)
        return ScorePrintLayout(score: score, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("인쇄 미리보기 · A4 \(settings.orientation.rawValue)").font(.headline)
                    Text("미리보기와 같은 PDF를 인쇄합니다. 인쇄 대화상자에서 A4 \(settings.orientation.rawValue)를 확인하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let pdf {
                    Text("\(pdf.pageCount)쪽").foregroundStyle(.secondary)
                    Button("인쇄…") { ScorePrintRenderer.printDocument(pdf, settings: settings) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            HStack(spacing: 16) {
                Picker("용지 방향", selection: $store.printSettings.orientation) {
                    ForEach(ScorePrintSettings.Orientation.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .frame(width: 175)
                Picker("악보 크기", selection: $store.printSettings.sizing) {
                    ForEach(ScorePrintSettings.Sizing.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .frame(width: 240)
                if settings.sizing == .custom {
                    Slider(value: $store.printSettings.scalePercent, in: 25...180, step: 5)
                        .frame(width: 140)
                    Text("\(Int(settings.scalePercent))%")
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                } else if let layout {
                    Text("악보 배율 \(Int((layout.scale * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            if let layout, layout.horizontalStarts.count > 1 {
                Text("가로 \(layout.horizontalStarts.count)구역으로 나누어 인쇄합니다. 페이지 순서는 왼쪽에서 오른쪽입니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            Divider()
            if let pdf {
                ScorePDFPreview(document: pdf)
            } else {
                ContentUnavailableView("미리보기를 만들 수 없습니다", systemImage: "printer",
                                       description: Text(renderError ?? "악보를 확인해 주세요."))
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.document) { _, _ in refresh() }
        .onChange(of: store.selectedTrackIndex) { _, _ in refresh() }
        .onChange(of: settings) { _, _ in refresh() }
    }

    private func refresh() {
        guard store.document.tracks.indices.contains(store.selectedTrackIndex) else { return }
        do {
            let data = try ScorePrintRenderer.makePDF(document: store.document,
                                                       trackIndex: store.selectedTrackIndex,
                                                       settings: settings)
            pdf = PDFDocument(data: data)
            renderError = nil
        } catch {
            pdf = nil
            renderError = error.localizedDescription
        }
    }
}
