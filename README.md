# FreeScore for Mac

**Made with Codex. 필요한 프로그램을 직접 구현해 쓰는 새로운 시대를 기념하는 macOS 악보 편집기.**

MIDI를 오선 악보와 피아노 롤로 열고, 음표·코드·가사·반복 기호를 편집하세요. 재생과 녹음, PDF 인쇄까지 한 앱에서 이어집니다.

**[기능 소개와 실제 화면](https://evans-kim.github.io/FreeScore-for-Mac/)** · **[최신 버전 다운로드](https://github.com/evans-kim/FreeScore-for-Mac/releases/latest/download/FreeScore-for-Mac.zip)** · **[버전 기록](https://github.com/evans-kim/FreeScore-for-Mac/releases)**

![FreeScore for Mac 악보 화면](site/assets/screenshots/score.png)

## 설치

macOS 14 이상에서 최신 릴리스의 `FreeScore-for-Mac.zip`을 내려받아 압축을 풀고 `FreeScore for Mac.app`을 응용 프로그램 폴더로 옮깁니다. 현재 자동 배포본은 Apple 공증을 거치지 않았습니다. 처음 실행할 때 macOS가 차단하면 Finder에서 앱을 Control-클릭하여 **열기**를 선택하거나, 시스템 설정 → 개인정보 보호 및 보안에서 실행을 허용하세요. 출처와 무결성은 릴리스에 함께 제공되는 `SHA256SUMS.txt`로 확인할 수 있습니다.

GitHub Packages에도 같은 ZIP을 GHCR의 OCI 아티팩트로 게시합니다. ORAS CLI 사용자는 `oras pull ghcr.io/evans-kim/freescore-for-mac:0.5.0`으로 받을 수 있습니다. 일반 설치에는 위 GitHub Releases ZIP을 사용하세요.

## 할 수 있는 일

- MIDI 트랙 가져오기, 이름 변경·추가·삭제, 음표의 위치·높이·길이 편집과 정렬
- 오선 악보와 피아노 롤, 재생선 따라가기, 선택한 위치부터 재생
- 박자표·음자리표·조표와 마디별 코드, 조성 변경에 따른 코드 이조
- 한 음당 한국어 한 글자 입력과 최대 4절 가사, 이음줄·쉼표·빔 표기
- 도돌이표, 1·2번 괄호, D.C./D.S./Segno/Coda/Fine 표기와 재생
- 메트로놈 카운트 후 `I` 키로 C4 음표 녹음, 음표 이동 시 소리 미리듣기
- 페이지 간격·가사 글꼴 설정, 세로·가로 인쇄 미리보기와 PDF 출력
- Codex가 `Scripts/midiscore` CLI로 프로젝트를 검사하고 편집하는 흐름

## 개발

Xcode 15.3 이상과 Swift 5.10이 필요합니다.

```bash
swift run FreeScore
swift test
bash Scripts/build-app.sh
open "build/FreeScore for Mac.app"
python3 Scripts/test-cli.py Samples/scale.mid
```

`Samples/feature-demo.mscore`는 소개 페이지 스크린샷에 사용한 공개 예제입니다. 프로젝트 파일은 JSON 기반 `.mscore`이며 MusicXML과 다릅니다. 이름 변경 전의 `.mscore` 파일과 `Scripts/midiscore` 명령은 계속 사용할 수 있습니다. Codex 자동 편집은 [CLI 안내](docs/codex-editing.md)와 [스킬 생성 안내](docs/create-skill-prompt.md)를 참고하세요.

## 배포와 버전

`VERSION`을 올리고 변경 사항을 `docs/releases/vX.Y.Z.md`에 기록한 뒤 동일한 버전의 태그를 푸시합니다. GitHub Actions가 테스트, macOS 앱 빌드, ZIP·SHA256 게시와 GHCR 패키지 게시를 수행합니다. 소개 페이지는 GitHub Pages에 게시되고 최신 릴리스 정보를 자동으로 표시합니다. 자세한 과정은 [배포 안내](docs/releasing.md)에 있습니다.

소스 구조와 프로젝트 모델은 [AGENTS.md](AGENTS.md)에 정리했습니다. MIT 라이선스입니다.
