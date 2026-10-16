//
//  WifiSnapFlags.swift
//  WifiSnap
//
//  원격 킬스위치 — 심사 없이 문제가 된 기능만 끄는 장치 (LeeoRemoteFlags).
//
//  CloudKit Dashboard(FeedbackHub 컨테이너) → 레코드 타입 `RemoteFlags`,
//  recordName `flags_com.leeo.wifisnap`, 필드 이름 = 아래 rawValue (Int64, 1=켬 · 0=끔).
//  필드가 없거나 조회에 실패하면 켬으로 동작한다 — 킬스위치가 장애 원인이 되면 안 된다.
//
//  ⚠️ rawValue 는 Dashboard 필드 이름과의 계약이다 — 바꾸지 말 것.
//

import LeeoKit

enum WifiSnapFlag: String, LeeoRemoteFlag, CaseIterable {
    /// 연결 실패 시 대소문자 표기를 바꿔 한 번 더 시도하는 단계 (WifiConnector).
    /// 시도마다 시스템 확인 창이 한 번 더 뜨므로, iOS 동작이 바뀌어 이 재시도가
    /// 사용자를 괴롭히게 되면 꺼서 '첫 시도 실패 → 표기 후보 안내'로 되돌린다.
    case connectCaseRetry

    /// '설정 캡처에서 목록 가져오기' (WifiListImportSheet).
    /// 설정 앱 화면 모양을 OCR 로 추측하는 기능이라, iOS 업데이트로 화면이 바뀌어
    /// 엉뚱한 이름이 쌓이기 시작하면 메뉴에서 내린다.
    case settingsListImport
}
