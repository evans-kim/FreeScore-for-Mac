# FreeScore for Mac 작업 안내

이 저장소는 macOS 14 이상에서 실행하는 SwiftUI/AppKit 기반 MIDI 악보 편집기 **FreeScore for Mac**이다. SwiftPM 실행 파일 이름은 `FreeScore`다. 기존 사용자의 프로젝트와 설정을 보존하려고 `.mscore` 확장자, `Scripts/midiscore` CLI 경로, `com.evanskim.midiscore` 번들 ID를 유지한다. `.mscore`는 이 앱의 JSON 프로젝트 파일이며 MusicXML이 아니다. MIDI를 가져오면 트랙별 음표를 편집하고, 악보와 피아노 롤로 보고, 선택 트랙을 재생하거나 MIDI로 내보내고, 악보를 PDF/프린터로 출력한다.

## 디렉터리

- `Sources/FreeScore/`: 앱 소스. `ScoreModel.swift`는 프로젝트·페이지·트랙·음표 모델, `RepeatPlayback.swift`는 도돌이·D.C./D.S.·Coda·Fine의 검증과 재생 순서, `ScoreStore.swift`는 편집 상태와 재생, `ScoreCanvas.swift`는 악보 렌더링, `ScorePrint.swift`는 인쇄, `PianoRollCanvas.swift`는 피아노 롤, `MIDIService.swift`는 MIDI 입출력이다.
- `Sources/FreeScoreCLI/main.swift`: 앱과 같은 모델을 사용하는 CLI 명령 구현.
- `Scripts/midiscore`: CLI 빌드 및 실행 진입점. `Scripts/build-app.sh`는 앱 번들 및 아이콘을 생성한다. `Scripts/test-cli.py`는 MIDI 파일을 사용한 CLI 통합 검사다.
- `Tests/FreeScoreTests/`: Swift 기능·회귀 테스트. `Samples/`: 공개용 작은 MIDI와 프로젝트 예제.
- `docs/codex-editing.md`: CLI 계약과 Codex 작업 흐름. `docs/create-skill-prompt.md`: 재사용 가능한 Codex 스킬 생성용 프롬프트.
- `site/`: GitHub Pages용 HTML과 실제 앱 스크린샷. `.github/workflows/`: 테스트, Pages, 버전 태그 배포. `VERSION`이 앱과 태그의 버전 기준이다.
- `.build/`, `build/`: 생성물이며 Git 추적 대상이 아니다. 아이콘 PNG/ICNS도 `build/Assets/`에 생성된다.

## 모델과 편집 계약

- 음악의 내부 시간은 4분음표 기준 `Double` 절대 박자다. CLI의 트랙·마디·박자 번호는 1부터 시작한다. `--at`과 `--duration`은 절대 4분음표 박자다.
- `ScoreNote.lyric`는 1절의 기존 저장 필드다. `additionalLyrics`는 2~4절이다. 읽기·쓰기는 `lyric(for:)`와 `setLyric(_:for:)`를 이용한다. 옛 `.mscore` 파일은 추가 가사와 도돌이를 빈 값으로 읽어야 한다.
- 도돌이 구간은 `ScoreDocument.repeatSections`에 0부터 시작하는 마디 번호로 저장한다. 구간은 서로 겹치지 않는다. `firstEndingStartMeasure`와 `secondEndingEndMeasure`는 함께 지정한다. 1번 괄호는 첫 재생 때 포함하고, 두 번째 재생 때 건너뛰어 도돌이 끝 다음 마디의 2번 괄호로 간다. 재생 순서는 `RepeatPlaybackPlan`에서 한 번 정의하고 앱과 CLI가 공유한다. 음표가 없는 악보도 반복 구간의 마지막 마디까지 표시한다.
- 악보 이동 기호는 `ScoreDocument.navigationMarks`에 저장한다. `segno`, `coda`는 마디 시작, `to-coda`, `fine`, `dc`, `ds`와 `*-fine`·`*-coda`는 마디 끝에 둔다. 한 곡에 D.C./D.S. 명령은 하나만 허용한다. 첫 연주에는 도돌이를 적용하고 D.C./D.S. 뒤에는 되돌아가서 도돌이를 재실행하지 않는다. 돌아간 연주에서 1번 괄호를 건너뛰고, `al Fine`은 Fine에서 끝나며 `al Coda`는 To Coda에서 Coda로 이동한다. 이동 지점의 유효성은 저장·열기·CLI에서 `RepeatPlaybackPlan.validate(repeats:navigation:)`로 검사한다.
- 프로젝트 변경은 기존 데이터를 보존해야 한다. 특히 원본 MIDI, 원래 음표 위치, 기존 1절 가사와 코드의 조성 추적을 유지한다. 기존 `.mscore` 디코딩 호환성을 테스트한다.
- CLI 편집은 `--out` 또는 `--in-place`를 명시한다. `--out` 기존 파일을 덮으려면 `--force`가 필요하다. GUI에서 같은 파일을 편집 중이라면 저장하고 닫은 다음 CLI를 사용한다. Codex는 `inspect --json`으로 대상 트랙·UUID·마디를 확인하고 편집 뒤 다시 검사한다. 지원 명령은 `Scripts/midiscore --help`를 따른다.

## 확인 명령

```bash
swift build
swift test
python3 Scripts/test-cli.py Samples/scale.mid
bash Scripts/build-app.sh
```

긴 MIDI의 동작을 확인할 때는 `MIDI_TEST_FILE=/path/to/file.mid swift test` 및 `python3 Scripts/test-cli.py /path/to/file.mid`로 외부 테스트 파일을 지정할 수 있다. 생성된 앱은 `build/FreeScore for Mac.app`이다. UI와 인쇄 변경은 실제 앱 화면 및 인쇄 미리보기를 확인한다. 공개 저장소에는 빌드 결과, 개인 MIDI·프로젝트 파일, 계정 정보와 자격 증명을 추가하지 않는다.

## 공개 배포

태그 `vX.Y.Z`는 `VERSION`과 일치해야 하며 GitHub Actions가 GitHub Releases ZIP과 GHCR 패키지를 만든다. 공개 저장소에는 개인 MIDI·프로젝트 파일, 계정 정보와 자격 증명을 추가하지 않는다. 스크린샷은 `Samples/feature-demo.mscore`만 사용한다.
