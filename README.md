# WifiSnap

와이파이를 더 쉽게 공유하고 연결하는 iOS 앱.

1. **내 와이파이 공유** — 지금 연결된 와이파이를 감지해, 친구가 카메라로 비추면 바로 연결되는 표준 WiFi QR(`WIFI:S:...;T:WPA;P:...;;`)을 만들어 줍니다.
2. **촬영 → 연결** — 와이파이 안내판(ID/PW)을 카메라로 찍으면 OCR로 자동 인식해 바로 연결합니다.
3. **손님용 안내판 만들기** — 카페·숙소·매장이 비치할 예쁜 와이파이 안내판을 7가지 테마로 꾸며 이미지로 저장·공유하거나 **AirPrint로 바로 인쇄**합니다. **매장 로고·이름**을 얹고, **카드형 / A4 세로 포스터**(인쇄용 고해상) 중에서 고를 수 있습니다. (QR + SSID/비밀번호 + 안내 문구) iOS 기본 QR 공유가 못 하는 "비치용 제작" 니즈를 겨냥한 도구입니다.

## 링크

- 🏠 [홈페이지](https://m1zz.github.io/WifiSnap/)
- 🛟 [지원 / 도움말](https://m1zz.github.io/WifiSnap/support.html)
- 🔒 [개인정보 처리방침](https://m1zz.github.io/WifiSnap/privacy.html)

> 위 페이지는 저장소의 [`docs/`](docs/) 폴더로 만들어집니다. GitHub 저장소 **Settings → Pages** 에서
> Source를 `main` 브랜치의 `/docs` 폴더로 설정하면 위 URL로 게시됩니다.

## 요구 사항

- Xcode 15 이상 (개발은 Xcode 26 기준)
- iOS 17.0+ / **실기기** (와이파이 연결 `NEHotspotConfiguration`은 시뮬레이터 미지원)
- 애플 개발자 계정

## 빌드

```bash
open WifiSnap.xcodeproj
```

프로젝트 파일은 [XcodeGen](https://github.com/yonaskolb/XcodeGen)의 `project.yml`로 생성됩니다. 재생성하려면:

```bash
xcodegen generate
```

### 실기기 실행 전 설정

1. **Signing & Capabilities** → 본인 개발자 Team 선택, Bundle Identifier 변경
2. Capability 두 개 확인/추가: **Hotspot Configuration**, **Access Wi-Fi Information**
3. 권한 문구는 `project.yml`에서 자동 생성됨 (카메라 / 위치 사용 중)

자세한 내용은 [`설치가이드.md`](설치가이드.md) 참고.

## 구조

```
WifiSnap/
├── WifiSnapApp.swift          # 앱 진입점
├── Views/
│   ├── ContentView.swift      # 메인 화면
│   ├── ImagePicker.swift      # 카메라/앨범 래퍼
│   ├── QRCodeSheet.swift      # 연결용 QR 표시/공유
│   └── WifiPosterSheet.swift  # 손님용 안내판 꾸미기·이미지 내보내기(인쇄)
├── Services/
│   ├── CurrentNetworkService.swift  # 현재 SSID 감지
│   ├── TextRecognizer.swift         # Vision OCR (한/영)
│   ├── WifiCredentialParser.swift   # ID/PW 파싱
│   ├── WifiConnector.swift          # 와이파이 연결
│   └── QRCodeGenerator.swift        # WiFi QR 생성
└── Models/
    └── SavedNetwork.swift     # 저장된 네트워크 (UserDefaults)
```

## 알아두면 좋은 점

- iOS 보안 정책상 **어떤 앱도 저장된 와이파이 비밀번호를 읽을 수 없습니다.** 그래서 공유는 "SSID 자동 감지 + 비밀번호 최초 1회 입력" 구조입니다.
- 저장소는 UserDefaults 기반입니다. 보안이 중요하면 Keychain으로 교체를 권장합니다.
