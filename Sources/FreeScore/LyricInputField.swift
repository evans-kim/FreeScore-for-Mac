import AppKit
import SwiftUI

struct LyricInputField: NSViewRepresentable {
    let mode: LyricMode
    let enabled: Bool
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "가사를 입력하세요"
        field.delegate = context.coordinator
        field.isEnabled = enabled
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = enabled
        field.placeholderString = mode == .single ? "한 글자씩 입력" : "스페이스로 다음 음표"
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LyricInputField

        init(_ parent: LyricInputField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView,
                  !editor.hasMarkedText() else { return }
            consume(field, flush: false)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            consume(field, flush: true)
        }

        private func consume(_ field: NSTextField, flush: Bool) {
            guard parent.enabled else { return }
            let text = field.stringValue
            if parent.mode == .single {
                for character in text { parent.onCommit(String(character)) }
                field.stringValue = ""
            } else {
                let parts = text.split(separator: " ", omittingEmptySubsequences: false)
                if parts.count > 1 {
                    for part in parts.dropLast() { parent.onCommit(String(part)) }
                    field.stringValue = String(parts.last ?? "")
                } else if flush, !text.isEmpty {
                    parent.onCommit(text)
                    field.stringValue = ""
                }
            }
        }
    }
}
