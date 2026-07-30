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

## 근처 위치 기반 추천 — 완료
- [x] SavedNetwork에 위치(latitude/longitude) 저장 (기존 데이터 nil 호환)
- [x] CurrentNetworkService: 현재 위치 추적/발행(startUpdatingLocation, 100m 정밀도)
- [x] 연결/QR 생성 시 현재 좌표 함께 저장
- [x] 저장 목록 정렬: 반경 150m 내 네트워크를 거리순 최상단 + "📍 근처/여기" 뱃지
- [x] 삭제를 id 기반으로 변경(정렬과 인덱스 불일치 방지)

## 단일 화면 컴팩트 UI — 완료
- [x] NavigationStack/"WifiSnap" 타이틀 제거, 장황한 footer/설명 문구 제거
- [x] List → 카드형 VStack (스크롤 없이 한 화면)
- [x] 촬영/앨범 버튼을 한 줄에 나란히 배치
- [x] 저장 목록은 하단 카드에서 필요 시 내부 스크롤, 삭제는 길게 눌러 컨텍스트 메뉴
- [x] 비밀번호 SecureField로 변경

## UI 정리 & 공유/지도/카메라-퍼스트 개편 — 완료
- [x] ContentView 단순화: 죽은 상태(recognizedLines)·모디파이어 제거, 행 아이콘/버튼 스타일 헬퍼(rowIcon/rowIconButton)로 중복 제거
- [x] "내 와이파이 공유" 카드 제거 → 연결된(로그인 정보 보유) 네트워크만 큰 카드로 QR 표시(공유 버튼 없이 QR 자체 노출)
- [x] 저장된 네트워크 목록 접기/펼치기 (연결 시 자동 접힘, 미연결 시 자동 펼침)
- [x] 저장 행 QR 보기 버튼 제거, SSID 한 줄 가운데 말줄임(줄바꿈 방지)
- [x] 지도(MapSheet): 위치 기록된 네트워크를 MapKit 핀으로 표시, 핀 탭 시 하단 카드에서 QR 공유
- [x] 메인 기능: 연결된 와이파이가 없으면 카메라 자동 실행(ssidResolved 게이팅 → 권한 응답 후 촬영), OCR 실패해도 직접 입력 카드 유지
- [x] body 하위 표현식 분리로 컴파일러 type-check 경고 제거, 시뮬레이터 실행 검증

## SSID 직접 입력 제거 & 엉뚱한 SSID 차단 — 완료
- [x] 전제 확인: iOS는 주변 와이파이 스캔 API를 일반 앱에 제공하지 않음 (NEHotspotHelper 특별 엔타이틀먼트 전용)
- [x] CurrentNetworkService: getConfiguredSSIDs()로 '이 폰에 설정된 SSID' 추가 → 선택 목록 확대
- [x] 선택 목록 = 지금 연결됨 + 저장됨(근처순) + 이 폰에 설정됨, 출처 아이콘/뱃지 표시
- [x] SSIDMatcher 신설: SSID 규격 검증(1~32바이트) + OCR 혼동 글자(O/0, l/1, S/5…) 보정 유사도 매칭
- [x] 파서가 SSID 후보 목록(WifiScanResult.ssidCandidates)을 함께 반환 → 칩으로 탭 선택
- [x] OCR 결과를 아는 이름으로 자동 교정 (짧은 이름 오교정 방지: 5자 이상 + 유사도 0.85)
- [x] OCR 직후 자동 저장 제거 — 잘못 읽은 이름이 목록에 쌓이던 원인
- [x] WifiConnector: apply() 후 fetchCurrent로 실제 접속 확인(최대 5초), 실패 시 설정 되돌리고 에러
- [x] 파서/매처 로직 실행 검증 + iOS 빌드 성공

## 저장 목록 재구성 (이름 잘림 제거 · 스와이프 · 상세 화면) — 완료
- [x] 행에서 프린터/공유 버튼 제거 → 이름이 전체 폭 사용, 말줄임 대신 줄바꿈(잘림 없음)
- [x] 왼쪽으로 밀면 QR 공유 (스와이프 액션에선 ShareLink가 안 되므로 ActivityShareSheet 직접 제시)
- [x] 오른쪽으로 밀면 이 폰 연결
- [x] 행 탭 → NetworkDetailSheet(상세): 큰 QR + 전체 이름 + 비밀번호 표시/복사
- [x] 상세에 프린트 버튼(손님용 안내판 인쇄·공유) + 이 폰 연결 + QR 이미지 공유
- [x] 삭제·안내판은 길게 눌러 컨텍스트 메뉴로 유지 (스와이프 자리를 공유/연결에 내줬으므로)
- [x] ActivityShareSheet 공용 파일로 분리, WifiPosterSheet의 중복 래퍼 제거
- [x] 목록 높이를 글자 폭 기반 줄 수 추정으로 계산 (고정 58pt → 여백/잘림 방지)
- [x] 시뮬레이터에서 31자 SSID·한글 SSID 렌더링 및 상세 화면 스크린샷 확인

## 안내판 문구 커스텀 저장 & 메인 카드 확대 — 완료
- [x] PosterSettings 신설: 매장 이름·제목·안내 문구·비밀번호 표시·테마·레이아웃을 @AppStorage 키로 공유
- [x] WifiPosterSheet의 @State → @AppStorage로 전환 (다음에 열어도 문구 유지)
- [x] 메인 카드 뒷면이 하드코딩 문구("무료 와이파이") 대신 저장된 설정을 사용 → 즉시 반영
- [x] 문구·테마 변경 시 안내판 재렌더 (renderKey 기반 .task(id:))
- [x] '되돌리기' 버튼으로 기본 문구·디자인 복원
- [x] 뒷면: 고정 300pt에 축소되던 것 → GeometryReader로 카드 폭 측정 후 원본 비율 높이 사용(글자 약 2배)
- [x] 앞면 QR 210 → 264로 확대, 카드 높이 300 → 340
- [x] 메인 버튼을 '안내판 문구·디자인 바꾸기'로 변경해 편집 진입점 명확화
- [x] 시뮬레이터에서 앞면·뒷면 렌더링 확인

## 상시 안내 문구 → TipKit 전환 — 완료
- [x] "친구에게 QR을 보여주면 바로 연결…" → ConnectedCardTip (카드를 뒤집으면 invalidate)
- [x] "탭하면 QR·상세 · 밀면 연결/공유" → SavedRowActionsTip (행을 쓰면 invalidate)
- [x] 죽은 ShareWifiTip·usedShare 이벤트 제거 (공유 카드가 사라지며 도네이션이 끊긴 상태였음)
- [x] 그 탓에 영영 안 뜨던 ScanWifiTip의 usedShare 조건 제거 → 첫 실행부터 노출
- [x] 팁 순서 재정의: 스캔 → 연결 카드 → 목록 조작법 → (usedSavedRow 후) 근처 추천
- [x] savedNetwork 도네이션을 onAppear에도 추가 (기존 사용자에게도 목록 팁이 뜨도록)
- [x] 시뮬레이터에서 두 팁 렌더링·닫기 버튼 확인

## 설정 화면 캡처로 와이파이 목록 가져오기 — 완료
- [x] TextRecognizer.recognize(): 텍스트 + boundingBox 반환 (기존 recognizeLines는 래퍼로 유지)
- [x] WifiListParser 신설: 왼쪽 정렬(x<0.5)만 채택, UI 문구는 '줄 전체 일치'로만 제거
      → "SKT_WiFi_GIGA" 같은 진짜 이름이 살아남음
- [x] 시계·긴 안내 문장·오른쪽 상태 텍스트("연결됨"/"알림") 필터
- [x] KnownSSIDStore: 사용자가 가져온 이름 저장 (이름만, 비밀번호 없음)
- [x] WifiListImportSheet: 캡처 선택 → 후보 체크박스 + 이름 직접 수정 → 추가,
      직접 적어 넣기, 가져온 이름 스와이프 삭제
- [x] SSID 선택 메뉴에 '설정 캡처에서 목록 가져오기…' 진입점 추가
- [x] 고를 게 없어도 메뉴를 띄우도록 변경 (가져오기 진입점을 항상 노출)
- [x] 실제 설정 화면 텍스트 20줄로 파서 검증 (SSID 6개 정확 추출), 화면 렌더링 확인

## 영문 우선 추측 & 드래그 앤 드롭 퍼즐 — 완료
- [x] Vision 인식 언어 순서 en-US 우선으로 변경 (한국어는 라벨용으로 유지)
- [x] 한글·한자·가나 포함 여부로 latinBonus(10) 가산 → passwordRank/ssidRank로 분리
      (pwScore 범위 ±6보다 크게 잡아 영문 값이 항상 앞서고, 후보가 전부 한글이면 무효화)
- [x] 아이디 후보 정렬(rankSSIDCandidates)도 ssidRank 기준으로 변경
- [x] 장식어 필터 버그 수정: contains 매칭이 "MOMO_GUEST"·"KT_WiFi"를 통째로 지우던 문제
      → 장식 단어를 걷어낸 잔여 글자로 판단 + '없으면 그거라도 쓰는' 폴백(preferring)
- [x] WifiScanResult.tokens 추가 — 사진 순서 그대로의 퍼즐 조각 풀
- [x] CredentialPuzzleView: 아이디·비밀번호 드롭 칸 + 조각 칩 드래그, 칸끼리 끌면 값 교환,
      사용 중인 조각 강조, 칸에서 직접 타이핑·지우기도 가능
- [x] FlowLayout(Layout 프로토콜) 신설 — 조각을 가로 스크롤 대신 여러 줄로 전부 노출
- [x] 조각 풀에 '이 폰이 아는 이름'도 함께 얹어 인식이 통째로 틀려도 복구 가능
- [x] CredentialPuzzleTip 추가 (첫 드롭 시 invalidate)
- [x] 파서 7개 시나리오 검증 + 시뮬레이터 렌더링 확인

## 안내판을 문서로 & 모든 글자 직접 수정 — 완료
- [x] PosterDesign 모델 신설 (안내판 = 저장되는 문서 한 장)
- [x] PosterDesignStore: 여러 장 저장, 최근 수정 순, 복제·삭제, 자동 저장
- [x] 전역 설정(PosterSettings) → 안내판 한 장으로 1회 마이그레이션 (기존 문구 보존)
- [x] 인쇄되는 글자 전부 수정 가능: 매장 이름·뱃지·제목·안내 문구·네트워크 라벨·
      비밀번호 라벨·맨 아래 문구 (뱃지/맨 아래 문구는 비우면 숨김)
- [x] '직접 쓰는 줄' 추가/삭제 — 영업시간·인스타 계정 등 원하는 만큼
- [x] 라벨 폭 고정(58pt) 제거 → 라벨을 길게 써도 잘리지 않음
- [x] PosterListSheet 신설: 안내판 목록, 새로 만들기, 스와이프 복제·삭제
- [x] 메인 카드 뒷면은 '가장 최근에 고친 안내판'을 카드 형태로 렌더
- [x] 시뮬레이터 검증: 커스텀 글자 전부 렌더 + 재실행 후에도 안내판 2장·자유 줄 유지

## 직접 입력 연결 & QR 위젯 — 완료
- [x] '와이파이 선택·직접 연결' → '아이디·비밀번호 입력해 연결' (바로 키보드)
- [x] SharedDefaults: App Group(group.com.leeo.wifisnap)으로 와이파이 목록 공유 + 1회 마이그레이션
- [x] WifiSnapWidget 타깃 추가 (app-extension, com.leeo.wifisnap.widget)
- [x] 최근 연결 와이파이 QR을 systemSmall/systemMedium에 표시, 없으면 안내 문구
- [x] 잠금화면 계열 미지원 (잠긴 폰에서 누구나 스캔 가능하므로 의도적으로 제외)
- [x] 목록 변경 시 WidgetCenter.reloadAllTimelines()
- [x] 위젯 데이터 경로(공유 저장소 → 디코딩 → QR 문자열) 검증, 번들 임베드 확인

## 실기기 실행 시 남은 작업 (사용자 몫)
- [ ] Signing & Capabilities에서 본인 개발자 Team 선택
- [x] Bundle Identifier를 com.leeo.wifisnap 으로 고정 (project.yml + 빌드 가드로 변경 차단)
- [ ] **App Group 등록**: 개발자 계정에 group.com.leeo.wifisnap 추가 (없으면 위젯이 빈 상태로 뜸)
- [ ] 위젯 타깃도 같은 Team으로 서명 (앱과 위젯 둘 다 필요)
- [ ] 홈 화면에 위젯 추가해 QR 렌더링 확인 (시뮬레이터 터치 입력 불가로 미검증)
- [ ] 실제 아이폰에서 ⌘R 실행 (와이파이 연결은 시뮬레이터 미지원)
