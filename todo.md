# WifiSnap TODO

## 빌드 가능하게 만들기 (Xcode 프로젝트 생성) — 완료
- [x] XcodeGen용 project.yml 작성 (capabilities, Info.plist 권한 문구 포함)
- [x] .xcodeproj 생성
- [x] ContentView.swift 컴파일 에러 수정 (Section title+footer 이니셜라이저 → header 사용)
- [x] xcodebuild로 빌드 검증 (BUILD SUCCEEDED)

## 버튼/시트 동작 수정 — 완료
- [x] 저장된 네트워크 행: onTapGesture ↔ 버튼 충돌 제거 (독립 버튼 2개로 분리)
- [x] 같은 뷰에 .sheet 2개 → enum 기반 단일 .sheet로 통합 (QR/피커 시트 충돌 해결)
- [x] "내 와이파이 공유" 무반응 수정: 자동 감지 실패(시뮬/권한) 시 SSID 직접 입력 대체 경로 추가
- [x] 시뮬레이터 실행/스크린샷으로 섹션 렌더링·권한 팝업 확인

## 버튼 비활성화 & 여백 개선 — 완료
- [x] 비밀번호 미입력 시 QR 버튼 비활성 이유 안내 문구 추가 (lock 아이콘)
- [x] 카메라 없는 환경에서 "안내판 촬영하기" 버튼 비활성화(ImagePicker.isCameraAvailable)
- [x] 스캔 버튼 zero-inset 제거 → 좌우 여백 부여, minHeight 상향
- [x] List .listSectionSpacing(24)로 섹션 간격 확대
- [x] 시뮬레이터 재확인 (버튼 여백/레이아웃)

## QR 생성 피드백(로딩 인디케이터) — 완료
- [x] QRCodeSheet: QR 생성을 백그라운드(Task.detached)로 이동
- [x] 생성 중 "QR 만드는 중…" ProgressView 표시 → 탭 즉시 시각 피드백
- [x] QRCodeGenerator: CIContext 매번 생성 → static 1회 재사용(성능)

## 실기기 실행 시 남은 작업 (사용자 몫)
- [ ] Signing & Capabilities에서 본인 개발자 Team 선택
- [ ] Bundle Identifier를 본인 것으로 변경 (현재 com.wifisnap.app)
- [ ] 실제 아이폰에서 ⌘R 실행 (와이파이 연결은 시뮬레이터 미지원)
