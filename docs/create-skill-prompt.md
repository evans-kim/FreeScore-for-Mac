# FreeScore for Mac 편집 스킬 생성 안내 프롬프트

아래 프롬프트를 별도 Codex 작업에 전달하면 됩니다. 현재 저장소의 CLI와 사용 안내를 먼저 읽고, 그 계약을 참조하는 작은 스킬을 만들도록 지정했습니다.

```text
$skill-creator를 사용해서 `midiscore-edit` Codex 스킬을 만들어줘.

이 스킬은 사용자가 macOS FreeScore for Mac의 MIDI 또는 .mscore 악보를 읽고 편집해 달라고 요청할 때 적용한다. 현재 작업 중인 FreeScore for Mac 저장소 루트의 `AGENTS.md`, `docs/codex-editing.md`, `Scripts/midiscore --help`를 확인하고, 실제 지원되는 명령만 스킬에 기술한다. 앱 기능 설명과 CLI 옵션을 길게 복제하지 말고 이 자료를 참조하도록 한다.

Codex가 먼저 `inspect`로 박자표, 트랙 번호, 대상 마디와 음표 UUID를 확인한 다음 `Scripts/midiscore`로 편집하고, 결과 파일을 다시 `inspect`해 요청한 변경을 검증하도록 안내해줘. `note add/set --lyric TEXT --verse 1..4`로 절별 가사를 쓰고 `repeat add/remove`로 도돌이와 1·2번 괄호를, `navigation add/remove`로 D.C./D.S./Segno/Coda/Fine을 관리하며 `inspect --json`의 `lyrics`, `repeats`, `navigationMarks`, `playbackBars`를 검증하도록 해줘. 마디·박자·트랙 번호는 1부터 시작하고, `--at` 및 `--duration`은 4분음표 기준이라는 점을 명시해줘. 박자표를 변경하면 음표와 코드의 절대 위치는 유지되므로 마디·박자 번호를 다시 확인해야 한다. 기본 작업은 `--out`으로 새 프로젝트 파일을 만들고, 사용자가 기존 파일을 직접 수정하도록 요청했을 때만 `--in-place`를 사용한다. 앱에서 같은 파일을 열고 수정 중이면 먼저 저장하고 닫아 충돌을 피하도록 한다. 직접 JSON을 고치는 대신 CLI를 사용하고, MIDI 내보내기는 선택 트랙의 악보 순서 음표만 담으며 코드·가사·반복 및 이동 기호·페이지 설정은 .mscore에 보존된다는 점을 정확하게 설명한다.

화면 확인이 필요한 작업은 실제 FreeScore for Mac 앱에서 결과 파일을 열어 악보·피아노 롤·인쇄 미리보기를 확인하도록 한다. 스킬에 전용 스크립트를 새로 만들 필요가 없다면 만들지 말고, 짧은 SKILL.md와 필요한 참조만 만든다. 생성 후 skill-creator의 quick_validate.py로 검증하고 `python3 Scripts/test-cli.py Samples/scale.mid`로 CLI 사용 흐름을 시험해줘. 스킬이 자동으로 선택되도록 기본 호출 정책을 유지해줘.
```
