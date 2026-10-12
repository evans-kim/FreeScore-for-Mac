# FreeScore for Mac 배포

## 채널

- **GitHub Pages:** `site/`의 정적 HTML을 `main` 푸시 때 게시합니다. 사이트는 GitHub API에서 최신 릴리스를 읽어 버전, 다운로드 URL, 게시일을 표시합니다.
- **GitHub Releases:** 버전 태그 `vX.Y.Z`를 푸시하면 macOS 14에서 테스트 후 Apple Silicon과 Intel을 포함한 앱 ZIP, `SHA256SUMS.txt`, 버전별 변경 사항을 게시합니다. 앱은 현재 Apple 서명·공증 없이 배포됩니다.
- **GitHub Packages / GHCR:** 같은 ZIP을 ORAS가 `ghcr.io/evans-kim/freescore-for-mac:X.Y.Z`에 OCI 아티팩트로 게시합니다. 이는 일반 macOS 설치 패키지 형식이 아니며 설치용 ZIP은 Releases가 정식 채널입니다. 첫 게시 후 패키지 설정에서 공개 가시성을 확인합니다.

## 다음 버전

1. 변경 사항을 구현하고 `swift test`, `python3 Scripts/test-cli.py Samples/scale.mid`를 통과시킵니다.
2. `VERSION`을 예를 들어 `0.5.1`로 올리고 `docs/releases/v0.5.1.md`에 사용자에게 보일 변경 사항을 적습니다.
3. `main`에 변경을 푸시한 다음 같은 커밋에 `git tag v0.5.1`을 만들고 태그를 푸시합니다. 태그명과 `VERSION`이 다르면 배포 작업이 실패합니다.
4. Release와 GHCR 패키지를 확인합니다. 사이트는 새 최신 릴리스를 자동 표시합니다.

태그 작업을 재실행해야 하는데 태그 이후에 CI·배포 코드를 고친 경우, `main`의 `VERSION`이 해당 릴리스와 같을 때 Actions → **Release app and package** → **Run workflow**에서 버전을 입력해 다시 게시할 수 있습니다. 기존 릴리스의 ZIP과 SHA256은 교체됩니다.

릴리스 자산 이름 `FreeScore-for-Mac.zip`은 모든 버전에서 동일하게 유지합니다. 따라서 `/releases/latest/download/FreeScore-for-Mac.zip` 링크는 최신 버전을 가리킵니다. 릴리스 작업을 재실행하면 기존 릴리스 자산을 교체합니다.

## 로컬 빌드

```bash
swift test
bash Scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent "build/FreeScore for Mac.app" FreeScore-for-Mac.zip
```

`Scripts/build-app.sh`는 두 아키텍처를 빌드해 하나의 universal 앱 실행 파일로 묶습니다. 번들 식별자와 `.mscore` 프로젝트 형식은 이전 MidiScore 파일 호환을 위해 유지합니다.
