# 보안 안내 / Security

## 공식 배포처

YelPoint는 옐샘 블로그(https://blog.naver.com/yelsam_lab)에 안내된 곳에서만 배포해요.
다른 사이트·카페·메신저·자료실에 올라온 YelPoint는 누군가 바꿨을 수 있으니 실행하지 마세요.

## 받은 파일 확인하기

릴리스마다 파일의 SHA-256 값을 함께 올려요. 받은 파일의 값이 같아야 진짜예요.

- 맥(터미널): `shasum -a 256 YelPoint-macOS.zip`
- 윈도우(PowerShell): `Get-FileHash YelPoint-Setup.exe`

YelPoint는 인터넷에서 프로그램을 내려받거나 스스로 업데이트하지 않아요.
업데이트 알림을 띄우며 다른 파일을 받으라고 하는 YelPoint가 있다면 가짜예요.

## 가짜·변조 파일이나 보안 문제 알리기

이 저장소의 Security 탭에서 **Report a vulnerability**로 알려 주세요. 저장소 주인만 볼 수 있어요.

---

## Official source

YelPoint is distributed only from the places listed on Yelsam's blog (https://blog.naver.com/yelsam_lab).
Copies from anywhere else may have been altered. Do not run them.

## Verify a download

Each release lists the SHA-256 of its files. Compare them with `shasum -a 256 <file>` (Mac) or
`Get-FileHash <file>` (Windows PowerShell).

YelPoint never downloads programs or updates itself. A "YelPoint" that asks you to download an update is fake.

## Report a fake copy or a security problem

Use **Report a vulnerability** in this repository's Security tab. Only the owner can see it.
