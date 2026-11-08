# YelPoint

강의용 발표 도우미예요. 화면 아래 도구막대로 강조, 돋보기, 펜, 타이머, 캡처, 스팟, 폰, QR, 칠판을 바로 쓸 수 있어요.

## 받기

**공식 배포처는 옐샘 블로그(https://blog.naver.com/yelsam_lab)에 안내된 곳뿐이에요.**
다른 사이트·카페·메신저로 받은 파일은 누군가 바꿨을 수 있으니 실행하지 마세요.
받은 파일은 릴리스에 적힌 SHA-256 값과 비교해 확인할 수 있어요([SECURITY.md](SECURITY.md)).

| 운영체제 | 파일 | 지원 환경 |
|---|---|---|
| 맥 | `YelPoint-macOS.zip` | macOS 14 이상, Apple Silicon·Intel |
| 윈도우 | `YelPoint-Setup.exe` | Windows 10·11 64비트, .NET Framework 4.8 |
| 윈도우 무설치 | `YelPoint-Windows.zip` | 위와 같아요 |

설치와 사용 방법은 [사용법.txt](사용법.txt)에 있어요. 앱의 설정 → 사용법을 누르면 1분짜리 영상도 볼 수 있어요.

## 할 수 있는 것

- **강조·돋보기:** 커서 주변에 동그라미를 띄우거나 1.5~5배로 확대해요.
- **펜·스팟:** 화면 위에 필기하고, 사각·원·타원으로 볼 곳을 표시해요.
- **타이머:** 1~60분 카운트다운을 화면에 띄워요.
- **캡처·녹화:** 영역을 찍으면 바로 복사돼요. 마이크와 함께 화면을 녹화하고, 영상 아래에서 바로 자막을 입력해요.
- **폰:** 안드로이드 폰·태블릿 화면을 띄우거나 실물화상기로 써요. 폰 갤러리 영상도 가져올 수 있어요.
- **QR·칠판:** 주소를 큰 QR 코드로 보여 주고, 큰 칠판에 분필로 쓰고 그려요.

## 이용 조건

개인·학교 수업과 강의에는 무료로 쓸 수 있어요. 상업적 이용, 수정·재배포, YelPoint 이름·아이콘 사용은 할 수 없어요.
자세한 내용은 [LICENSE.txt](LICENSE.txt)에 있어요. 함께 넣은 외부 프로그램(scrcpy, adb, 나눔 글꼴)은 [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt)의 각 라이선스를 따라요.

## 소스 구성과 빌드

- `macos/`: Swift·AppKit 앱 (macOS 14 이상, Universal)
- `windows/`: WinForms 앱과 설치 프로그램 (x64, .NET Framework 4.8)
- `scripts/`: 빌드, 사용법 영상 렌더링, 배포 파일 묶기
- `vendor/`: 나눔 글꼴과 외부 파일 해시 목록(`VENDOR-SHA256.txt`)

scrcpy 5.0.1은 저장소에 들어 있지 않아요. [공식 릴리스](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)에서 받아 `vendor/scrcpy-5.0.1/`에 두면 돼요.
빌드 스크립트가 모든 외부 파일을 `VENDOR-SHA256.txt`와 대조하고, 하나라도 다르면 빌드를 멈춰요.

```sh
sh scripts/build-macos.sh
sh scripts/build-windows.sh
sh scripts/package.sh
```

빌드 스크립트는 이 프로젝트를 만든 맥의 외장 SSD 경로를 기준으로 되어 있어요(`scripts/build-env.sh`).

---

© yelsam.lab · [블로그](https://blog.naver.com/yelsam_lab)
