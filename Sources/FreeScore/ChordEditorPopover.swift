import AppKit
import SwiftUI

@MainActor
final class ChordEditorSession: NSObject, ObservableObject, NSPopoverDelegate {
    @Published var text: String {
        didSet {
            selectedSuggestion = nil
            error = nil
        }
    }
    @Published var followsKey: Bool
    @Published var selectedSuggestion: Int?
    @Published var error: String?

    let tick: Int
    let store: ScoreStore
    weak var anchor: StaffView?
    var onAdvance: ((Int, StaffView) -> Void)?
    var onClose: (() -> Void)?
    private var popover: NSPopover?
    private var keyMonitor: Any?
    private var finished = false

    init(store: ScoreStore, tick: Int, anchor: StaffView) {
        self.store = store
        self.tick = tick
        self.anchor = anchor
        let existing = store.chord(at: tick)?.chord
        text = existing?.symbol(in: store.document.page.keySignature) ?? ""
        followsKey = existing?.followsKey ?? true
    }

    var suggestions: [String] {
        ChordSuggestions.matching(text, in: store.document.page.keySignature)
    }

    var locationDescription: String {
        let page = store.document.page
        return "\(ChordGrid.measure(for: tick, page: page) + 1)마디 " +
            "\(ChordGrid.slot(for: tick, page: page) + 1)박"
    }

    func show() {
        guard let anchor else { return }
        let popup = NSPopover()
        popup.behavior = .transient
        popup.animates = false
        popup.delegate = self
        popup.contentSize = NSSize(width: 330, height: 245)
        popup.contentViewController = NSHostingController(rootView: ChordEditorPopover(session: self))
        popover = popup
        popup.show(relativeTo: anchor.chordAnchorRect(for: tick), of: anchor,
                   preferredEdge: .maxY)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.popover?.isShown == true,
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control) else { return event }
            if let editor = event.window?.firstResponder as? NSTextView,
               editor.hasMarkedText() { return event }
            switch event.keyCode {
            case 49:
                self.advance(backward: event.modifierFlags.contains(.shift))
                return nil
            case 36, 76:
                if let index = self.selectedSuggestion,
                   self.suggestions.indices.contains(index) {
                    self.text = self.suggestions[index]
                } else {
                    self.commitAndClose()
                }
                return nil
            case 125 where !self.suggestions.isEmpty,
                 126 where !self.suggestions.isEmpty:
                let change = event.keyCode == 125 ? 1 : -1
                let count = self.suggestions.count
                self.selectedSuggestion = ((self.selectedSuggestion ?? (change > 0 ? -1 : 0)) +
                    change + count) % count
                return nil
            case 53:
                self.close()
                return nil
            default:
                return event
            }
        }
    }

    func choose(_ suggestion: String) {
        text = suggestion
    }

    func advance(backward: Bool = false) {
        guard saveIfNeeded(), let anchor else { return }
        let next = backward ? ChordGrid.previous(tick, page: store.document.page) :
            ChordGrid.next(tick, page: store.document.page)
        close()
        onAdvance?(next, anchor)
    }

    func commitAndClose() {
        guard saveIfNeeded() else { return }
        close()
    }

    func remove() {
        store.removeChord(at: tick)
        close()
    }

    func close() {
        popover?.close()
        finish()
    }

    func popoverDidClose(_ notification: Notification) {
        finish()
    }

    private func saveIfNeeded() -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        guard store.setChord(at: tick, text: value, followsKey: followsKey) else {
            error = "코드 형식을 확인하세요. 예: G, F#dim, D/F#, Cadd9"
            return false
        }
        return true
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        popover?.delegate = nil
        popover?.contentViewController = nil
        popover = nil
        onClose?()
    }
}

private struct ChordEditorPopover: View {
    @ObservedObject var session: ChordEditorSession
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(session.locationDescription) 코드").font(.headline)
                Spacer()
                Text(session.store.document.page.keySignature.label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("예: G, F#dim, D/F#, Cadd9", text: $session.text)
                .textFieldStyle(.roundedBorder)
                .focused($textFocused)
                .accessibilityLabel("코드 입력")
            if let error = session.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("조성에 맞는 추천 · 직접 입력도 가능")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 5)], spacing: 5) {
                ForEach(Array(session.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button(suggestion) {
                        session.choose(suggestion)
                        textFocused = true
                    }
                    .buttonStyle(.bordered)
                    .tint(session.selectedSuggestion == index ? .accentColor : .gray)
                }
            }
            Toggle("조성 변경 시 코드 이동", isOn: $session.followsKey)
                .font(.caption)
            HStack {
                Button("삭제") { session.remove() }
                    .disabled(session.store.chord(at: session.tick) == nil)
                Spacer()
                Text("Space 다음 박자 · ⇧Space 이전 박자")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("완료") { session.commitAndClose() }
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { textFocused = true }
    }
}
