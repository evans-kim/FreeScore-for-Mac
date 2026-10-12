import SwiftUI

struct MeterSettingsSheet: View {
    @ObservedObject var store: ScoreStore
    @Environment(\.dismiss) private var dismiss
    @State private var numerator: Int
    @State private var denominator: Int
    @State private var keySignature: KeySignature

    init(store: ScoreStore) {
        self.store = store
        _numerator = State(initialValue: store.document.numerator)
        _denominator = State(initialValue: store.document.denominator)
        _keySignature = State(initialValue: store.document.page.keySignature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("박자표와 조표 변경").font(.title2).bold()
            Stepper("분자: \(numerator)", value: $numerator, in: 1...12)
            Picker("분모", selection: $denominator) {
                ForEach([2, 4, 8, 16], id: \.self) { value in Text("\(value)").tag(value) }
            }
            Picker("조성", selection: $keySignature) {
                ForEach(KeySignature.allCases) { key in Text(key.label).tag(key) }
            }
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("적용") {
                    store.updatePage {
                        $0.numerator = numerator
                        $0.denominator = denominator
                        $0.keySignature = keySignature
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct ClefSettingsSheet: View {
    @ObservedObject var store: ScoreStore
    @Environment(\.dismiss) private var dismiss
    @State private var clef: Clef

    init(store: ScoreStore) {
        self.store = store
        _clef = State(initialValue: store.selectedTrack?.clef ?? .treble)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("음자리표 변경").font(.title2).bold()
            Picker("음자리표", selection: $clef) {
                ForEach(Clef.allCases) { value in Text(value.label).tag(value) }
            }
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("적용") { store.setClef(clef); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct RepeatSettingsSheet: View {
    @ObservedObject var store: ScoreStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingIndex: Int?
    @State private var startBar = 1
    @State private var endBar = 2
    @State private var hasEndings = false
    @State private var firstEndingBar = 2
    @State private var secondEndingEndBar = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("도돌이와 1·2번 괄호").font(.title2).bold()
            Text("마디 번호는 1부터 시작합니다. 1번 괄호의 마지막 마디에 도돌이 끝을 놓고, 바로 다음 마디에서 2번 괄호가 시작됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.document.repeatSections.enumerated()), id: \.offset) { index, section in
                HStack {
                    Button(section.description) { edit(index, section) }
                        .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) { store.removeRepeatSection(at: index); editingIndex = nil } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            Divider()
            Text(editingIndex == nil ? "구간 추가" : "구간 수정").font(.headline)
            Stepper("도돌이 시작: \(startBar)마디", value: $startBar, in: 1...10_000)
            Stepper("도돌이 끝: \(endBar)마디", value: $endBar, in: 1...10_000)
            Toggle("1·2번 괄호", isOn: $hasEndings)
            if hasEndings {
                Stepper("1번 괄호 시작: \(firstEndingBar)마디", value: $firstEndingBar, in: 1...10_000)
                Stepper("2번 괄호 끝: \(secondEndingEndBar)마디", value: $secondEndingEndBar, in: 1...10_000)
            }
            HStack {
                Button("새 구간") { reset() }
                Spacer()
                Button("닫기") { dismiss() }
                Button(editingIndex == nil ? "추가" : "수정") {
                    let section = RepeatSection(startMeasure: startBar - 1,
                        endMeasure: endBar - 1,
                        firstEndingStartMeasure: hasEndings ? firstEndingBar - 1 : nil,
                        secondEndingEndMeasure: hasEndings ? secondEndingEndBar - 1 : nil)
                    if store.upsertRepeatSection(section, replacing: editingIndex) { reset() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func edit(_ index: Int, _ section: RepeatSection) {
        editingIndex = index
        startBar = section.startMeasure + 1
        endBar = section.endMeasure + 1
        hasEndings = section.hasEndings
        firstEndingBar = (section.firstEndingStartMeasure ?? section.endMeasure) + 1
        secondEndingEndBar = (section.secondEndingEndMeasure ?? section.endMeasure + 1) + 1
    }

    private func reset() {
        editingIndex = nil
        startBar = 1
        endBar = 2
        hasEndings = false
        firstEndingBar = 2
        secondEndingEndBar = 3
    }
}

struct NavigationSettingsSheet: View {
    @ObservedObject var store: ScoreStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingIndex: Int?
    @State private var bar = 1
    @State private var kind: NavigationMark.Kind = .segno

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("악보 이동 기호").font(.title2).bold()
            Text("Segno·Coda는 마디 시작, Fine·To Coda·D.C.·D.S.는 마디 끝에 놓입니다. Fine과 To Coda는 되돌아온 연주에서만 작동합니다. 이동 명령 전에 목적지 기호를 먼저 추가하세요.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.document.navigationMarks.enumerated()), id: \.offset) { index, mark in
                HStack {
                    Button(mark.description) { edit(index, mark) }.buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) {
                        store.removeNavigationMark(at: index)
                        editingIndex = nil
                    } label: { Image(systemName: "trash") }
                }
            }
            Divider()
            Text(editingIndex == nil ? "기호 추가" : "기호 수정").font(.headline)
            Picker("기호", selection: $kind) {
                ForEach(NavigationMark.Kind.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            Stepper("위치: \(bar)마디", value: $bar, in: 1...10_000)
            HStack {
                Button("새 기호") { reset() }
                Spacer()
                Button("닫기") { dismiss() }
                Button(editingIndex == nil ? "추가" : "수정") {
                    if store.upsertNavigationMark(
                        NavigationMark(measure: bar - 1, kind: kind), replacing: editingIndex) {
                        reset()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func edit(_ index: Int, _ mark: NavigationMark) {
        editingIndex = index
        bar = mark.measure + 1
        kind = mark.kind
    }

    private func reset() {
        editingIndex = nil
        bar = 1
        kind = .segno
    }
}
