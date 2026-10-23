#!/bin/sh
# App Store 원본 스크린샷 캡처 — 시뮬레이터에서 DEBUG 스크린샷 장면(-ScreenshotScene)을 언어별로 띄워 찍는다.
#
# 사용법: sh scripts/capture_screenshots.sh <시뮬레이터 UDID> <WifiSnap.app 경로> [언어 ...]
#   (언어를 주지 않으면 deploy.env 의 LOCALES 전부)
#   앱은 Debug 구성으로 미리 빌드해 둔다 (스크린샷 장면은 DEBUG 빌드에만 있다):
#   xcodebuild build -project WifiSnap.xcodeproj -scheme WifiSnap -configuration Debug \
#     -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath <dd>
#
# 결과: docs/screenshots/raw/<언어>/01-scan.png … 05-saved.png  (그다음 make_marketing_screenshots.py)
# 시뮬레이터는 한 번만 켜고, 언어는 -AppleLanguages/-AppleLocale 실행 인자로만 바꾼다.
set -e
UDID="$1"; APP="$2"; shift 2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.leeo.wifisnap"
if [ $# -eq 0 ]; then
  set -- $(grep '^LOCALES=' "$ROOT/deploy.env" | cut -d= -f2 | tr ',' ' ')
fi

t() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # 모든 시뮬레이터 명령에 시간 제한

apple_locale() {
  case "$1" in
    ko) echo ko_KR;; en) echo en_US;; en-GB) echo en_GB;; zh-Hans) echo zh_CN;; zh-Hant) echo zh_TW;;
    ja) echo ja_JP;; ru) echo ru_RU;; es) echo es_ES;; de) echo de_DE;; fr) echo fr_FR;; it) echo it_IT;;
    pt-BR) echo pt_BR;; th) echo th_TH;; vi) echo vi_VN;; cs) echo cs_CZ;; da) echo da_DK;; el) echo el_GR;;
    fi) echo fi_FI;; id) echo id_ID;; nb) echo nb_NO;; nl) echo nl_NL;; pl) echo pl_PL;; sv) echo sv_SE;;
    tr) echo tr_TR;; *) echo en_US;;
  esac
}

t 120 xcrun simctl boot "$UDID" 2>/dev/null || true
t 300 xcrun simctl bootstatus "$UDID" >/dev/null
t 60 xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
t 120 xcrun simctl install "$UDID" "$APP"
t 30 xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true
t 30 xcrun simctl location "$UDID" set 37.5665,126.9780 || true

for LANG_ in "$@"; do
  OUT="$ROOT/docs/screenshots/raw/$LANG_"
  mkdir -p "$OUT"
  LOC="$(apple_locale "$LANG_")"
  for PAIR in 01-scan:scan 02-qr:qr 03-poster-card:poster-card 04-poster-a4:poster-a4 05-saved:saved; do
    FILE="${PAIR%%:*}"; SCENE="${PAIR#*:}"
    t 30 xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    t 60 xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "($LANG_)" -AppleLocale "$LOC" -ScreenshotScene "$SCENE" >/dev/null
    # 시트가 열리고 QR·안내판이 다 그려질 때까지 기다린다
    case "$SCENE" in poster-*) sleep 6;; qr) sleep 5;; *) sleep 4;; esac
    # simctl 은 있는 파일을 덮어쓰지 않고, 한글 경로에는 느리다 — 임시 파일로 찍고 옮긴다
    TMP_PNG="${TMPDIR:-/tmp}/wifisnap-shot-$$.png"; rm -f "$TMP_PNG"
    t 60 xcrun simctl io "$UDID" screenshot --type=png "$TMP_PNG" >/dev/null 2>&1
    mv -f "$TMP_PNG" "$OUT/$FILE.png"
    echo "📸 $LANG_ $FILE"
  done
done
t 30 xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
