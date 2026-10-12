# Codex로 FreeScore for Mac 악보 편집하기

`Scripts/midiscore`는 macOS 앱과 같은 `.mscore` 모델을 사용합니다. 첫 실행이나 소스 변경 뒤에는 공유 Swift 모델을 컴파일해 `.build/midiscore-cli`를 만들고, 이후에는 바로 실행합니다. `Scripts/midiscore --help`에 전체 명령이 있습니다.

## 작업 순서

1. 앱에서 편집 중인 프로젝트를 저장하고 닫습니다. CLI 변경 사항은 열린 앱 화면에 자동 반영되지 않습니다.
2. `inspect`로 트랙 번호, 음표 UUID, 박자표와 코드 위치를 확인합니다. 큰 MIDI는 마디 범위를 좁혀 조회합니다.
3. 편집 명령에 `--out`을 넣어 새 `.mscore` 파일을 만듭니다. 사용자가 원본 파일 수정을 원할 때는 `--in-place`를 명시합니다. 기존 `--out` 파일 덮어쓰기는 `--force`가 필요합니다.
4. 결과를 다시 `inspect`하고 앱에서 열어 악보·재생·인쇄 모습을 확인합니다. `inspect --json`의 `lyrics`, `repeats`, `navigationMarks`, `playbackBars`로 절별 가사와 실제 재생 순서를 확인할 수 있습니다. `export-midi`는 선택 트랙의 **원본 악보 순서 음표**만 MIDI로 내보냅니다. 페이지, 코드, 가사, 반복·이동 기호는 `.mscore`에 유지됩니다.

트랙 번호와 마디·박자 번호는 **1부터** 셉니다. `--bar 2 --beat 1`은 두 번째 마디의 첫 박입니다. `--at`은 곡 시작부터 센 **4분음표 단위의 절대 위치**이며, `--duration`도 4분음표 단위입니다. 따라서 4/4에서 `--at 4 --duration 0.5`는 두 번째 마디 첫 박부터 8분음표 길이입니다. 음높이는 `C4`, `F#3`, `Bb4` 또는 MIDI 번호로 지정합니다.

박자표를 변경해도 기존 음표와 코드는 시간상 절대 위치를 유지하므로, 화면의 마디·박자 번호가 달라질 수 있습니다. 박자표 변경 뒤에는 `inspect`로 대상 위치를 다시 확인하세요.

## CLI 예시

아래 예시는 저장소 루트에서 실행합니다. 실제 파일명은 작업마다 바꿉니다.

```bash
# MIDI를 프로젝트로 가져오기 (16분음표 정렬)
Scripts/midiscore import-midi Samples/scale.mid --grid 16 --out work.mscore

# 첫 4마디의 첫 트랙 음표 ID와 코드 확인
Scripts/midiscore inspect work.mscore --track 1 --from-bar 1 --to-bar 4 --limit 0 --json

# 조성, 박자표, 인쇄에도 적용되는 마디 간격 설정
Scripts/midiscore page set work.mscore --title '새 곡' --key G --meter 4/4 --measure-spacing 160 --out layout.mscore

# 2마디 1박에 코드, 2박에 음표 추가
Scripts/midiscore chord set layout.mscore --bar 2 --beat 1 --symbol Am --out harmony.mscore
Scripts/midiscore note add harmony.mscore --track 1 --bar 2 --beat 2 --pitch C4 --duration 1 --lyric '가' --out melody.mscore

# 위 명령이 출력한 UUID로 음표 수정. 가사를 비우려면 --lyric ''
Scripts/midiscore note set melody.mscore --track 1 --id UUID --pitch D4 --duration 0.5 --lyric '나' --out corrected.mscore

# 같은 음표의 2절·4절 가사 입력 (1절 필드도 유지)
Scripts/midiscore note set corrected.mscore --track 1 --id UUID --lyric '둘' --verse 2 --out verse2.mscore
Scripts/midiscore note set verse2.mscore --track 1 --id UUID --lyric '넷' --verse 4 --out verse4.mscore

# 1마디부터 3마디 끝까지 연주 후 반복, 3마디는 1번 괄호, 4~5마디는 2번 괄호
Scripts/midiscore repeat add verse4.mscore --start-bar 1 --end-bar 3 --first-ending-bar 3 --second-ending-end-bar 5 --out repeats.mscore
Scripts/midiscore inspect repeats.mscore --json --limit 0
Scripts/midiscore repeat remove repeats.mscore --start-bar 1 --out no-repeat.mscore

# D.S. al Coda: 1마디 Segno, 3마디 To Coda, 4마디 이동 명령, 5마디 Coda
Scripts/midiscore navigation add no-repeat.mscore --bar 1 --kind segno --out nav1.mscore
Scripts/midiscore navigation add nav1.mscore --bar 3 --kind to-coda --out nav2.mscore
Scripts/midiscore navigation add nav2.mscore --bar 5 --kind coda --out nav3.mscore
Scripts/midiscore navigation add nav3.mscore --bar 4 --kind ds-coda --out nav4.mscore
Scripts/midiscore inspect nav4.mscore --json --limit 0

# 다른 예: 3마디 Fine, 5마디 D.C. al Fine
Scripts/midiscore navigation add work.mscore --bar 3 --kind fine --out fine-mark.mscore
Scripts/midiscore navigation add fine-mark.mscore --bar 5 --kind dc-fine --out dc-fine.mscore

# 선택 음표만 8분음표 정렬. --ids를 빼면 트랙 전체를 정렬
Scripts/midiscore quantize corrected.mscore --track 1 --grid 8 --ids UUID --melody --out quantized.mscore

# 트랙과 코드 관리, MIDI 내보내기
Scripts/midiscore track add quantized.mscore --name Strings --clef bass --out two-tracks.mscore
Scripts/midiscore chord remove two-tracks.mscore --bar 2 --beat 1 --out no-chord.mscore
Scripts/midiscore export-midi quantized.mscore --track 1 --out edited.mid
```

`note remove`, `track rename`, `track remove`, `page set`의 나머지 옵션은 `Scripts/midiscore --help`를 참조합니다. 4·8·16·32분음표 정렬을 지원합니다. `--melody`는 각 대상 음표의 끝을 다음 음표 시작점에 맞춥니다. 조성 변경에 따라 이동하지 않을 코드는 `chord set ... --fixed-key`로 입력합니다.

도돌이의 `--start-bar`와 `--end-bar`는 마디 양쪽의 반복선입니다. 1번 괄호를 쓰면 그 시작은 도돌이 구간 안에, 2번 괄호는 끝 다음 마디부터 놓입니다. 이 둘은 함께 지정하며, 반복 구간끼리 겹칠 수 없습니다. `inspect --json`의 `playbackBars`는 실제 연주되는 마디 번호를 순서대로 출력합니다.

`navigation add`의 `--kind`에는 `segno`, `coda`, `to-coda`, `fine`, `dc`, `ds`, `dc-fine`, `ds-fine`, `dc-coda`, `ds-coda`를 사용합니다. Segno와 Coda는 마디 시작, 나머지는 마디 끝에 놓입니다. D.S.를 추가하기 전에 Segno를, `*-fine`을 추가하기 전에 Fine을, `*-coda`를 추가하기 전에 To Coda와 Coda를 먼저 배치해야 합니다. 이 이동 명령은 한 곡에 하나만 지정하며 기존 명령을 바꾸려면 `navigation remove ... --kind KIND`로 제거합니다. 되돌아간 연주에서는 도돌이를 다시 실행하지 않고 1번 괄호를 건너뜁니다. `fine`과 `to-coda`는 해당 이동 명령 없이 단독으로 놓으면 재생에 영향을 주지 않습니다.

## 앱 단축키와 마우스 조작

| 조작 | 동작 |
| --- | --- |
| ⌘N / ⌘O / ⌘⇧O / ⌘S | 새 악보 / 프로젝트 열기 / MIDI 가져오기 / 프로젝트 저장 |
| ⌘E / ⌘P / ⌘⌥1~5 | 선택 트랙 MIDI 내보내기 / 인쇄 미리보기 / 최근 프로젝트 열기 |
| Space | 악보·피아노 롤 재생/정지. 코드 입력창에서는 저장하고 다음 박자로 이동 |
| Shift+Space / Return / Esc | 코드 입력창에서 이전 박자 / 입력 완료 / 닫기 |
| ⌘A / Delete / ⌘C / ⌘V | 피아노 롤 전체 선택 / 선택 음표 삭제 / 복사 / 재생선에 붙여넣기 |
| ⌘M / ⌘⇧M / ⌘Z / ⌘⇧Z | 같은 음 병합 / 반으로 분할 / 실행 취소 / 다시 실행 |
| 방향키 / Shift+←·→ / Shift+↑·↓ | 선택 음표 이동 / 길이 조절 / 조절할 앞단·뒷단 선택 |
| 녹음 버튼 + I 누름/뗌 | 한 마디 카운트 뒤 C4 음표의 시작·끝 기록 |
| Shift 두 번 | 가사 한 글자·여러 글자 모드 전환 |
| 우측 가사 1~4절 선택 | 선택 절의 가사 입력·수정 |
| 상단 반복·이동 기호 → 도돌이·1/2번 괄호 | 반복 구간 및 첫째·둘째 괄호 설정 |
| 상단 반복·이동 기호 → D.C.·D.S.·Coda·Fine | 악보 이동 기호 설정 |
| 악보 마디 번호 더블 클릭 / 음표 더블 클릭 | 해당 마디 또는 음표 시작으로 재생선 이동 |
| 악보 마디 번호 위 코드 영역 클릭 | 클릭한 박자의 코드 입력창 열기 |
| 피아노 롤 빈 격자 더블 클릭 | 해당 위치에 음표 추가 |

피아노 롤에서 음표의 양 끝을 드래그하면 시작·끝 길이가 바뀝니다. 악보에서 Option+드래그는 뒷단, Option+⌘+드래그는 앞단 길이를 조절합니다. 키보드 단축키는 텍스트 입력창에 초점이 있을 때 다르게 동작할 수 있습니다.

## 검증

```bash
python3 Scripts/test-cli.py Samples/scale.mid
MIDI_TEST_FILE=Samples/scale.mid swift test
bash Scripts/build-app.sh
```

테스트 스크립트는 임시 디렉터리에서 MIDI 가져오기, 페이지·코드·음표·1~4절 가사·도돌이·D.S. al Coda·트랙 편집, 정렬, MIDI 내보내기와 원본 보호를 확인합니다. 개인 MIDI 파일을 시험하려면 두 명령의 경로를 해당 파일 경로로 바꿉니다.
