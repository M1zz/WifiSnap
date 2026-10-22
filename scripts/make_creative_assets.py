#!/usr/bin/env python3
"""App Store 크리에이티브 자산(제품 페이지 헤더 · 검색 결과) 생성: HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_creative_assets.py [언어 ...]     (없으면 전부)

자리
  docs/screenshots/creative/<스토어 로케일>/header.png   3840x1646  제품 페이지 맨 위
  docs/screenshots/creative/<스토어 로케일>/search.png   3840x2560  검색 결과 (없으면 스크린샷이 대신 보인다)

기기 화면은 docs/screenshots/raw/creative/ko/ 의 시뮬레이터 캡처다(예시 와이파이를 넣고 띄운 QR 상세 ·
손님용 안내판 화면). 스토어 언어는 한국어 하나다.

⚠️ 안전 영역 밖은 기기에 따라 잘린다. 글은 **반드시** 안전 영역 안에 둔다(배경 · 기기 그림은 넘쳐도 된다).
   수치는 Apple 공식 PSD 템플릿에서 잰 값이다(https://developer.apple.com/app-store/asset-best-practices/).
   아이폰에서 헤더는 가운데만 남고, 검색 결과는 약 385pt 폭으로 줄어 보인다. 그래서 글이 크다.

⚠️ 가격 · 할인 · 주소(URL) · 수상 · 다른 플랫폼 이름은 넣지 않는다(Apple 가이드).
"""
import shutil, subprocess, sys, pathlib, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw" / "creative"
OUT = ROOT / "docs" / "screenshots" / "creative"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 문구 언어 → App Store Connect 로케일
STORE = {"en": "en-US"}
# 문구 언어 → 기기 화면 캡처 폴더
SCREEN = {"ko": "ko"}

# (가로, 세로, 안전 영역 left, top, right, bottom)
SPEC = {
    "header": (3840, 1646, (1097, 493, 2743, 1154)),
    "search": (3840, 2560, (836, 765, 3004, 1795)),
}

# 검색 결과: 눈썹글은 사람들이 검색창에 치는 말. 앱의 약속은 "와이파이를 QR 한 장으로 나눈다".
# QR 공유 · 손님용 안내판(카드/A4) · 인쇄는 앱에 있는 것이다(README).
SEARCH = {
    "ko": ("와이파이 QR", "손님용 와이파이<br>안내판 만들기", "QR로 바로 연결되고<br>인쇄까지 한 번에"),
}

# 헤더: 처음 온 사람에게 한 가지 약속.
HEADER = {
    "ko": ("와이파이 공유", "비밀번호 불러주지 말고<br>QR 한 장 보여주세요"),
}

# i18n-begin
STORE["en"] = "en-US"
SCREEN["en"] = "en"
SEARCH["en"] = ("Wi-Fi QR", "Make guest<br>Wi-Fi signs", "Connect with a QR code,<br>print in one go")
HEADER["en"] = ("Share Wi-Fi", "Skip reading out passwords.<br>Show a QR code.")
STORE["en-GB"] = "en-GB"
SCREEN["en-GB"] = "en-GB"
SEARCH["en-GB"] = ("Wi-Fi QR", "Make guest<br>Wi-Fi signs", "Connect with a QR code,<br>print in one go")
HEADER["en-GB"] = ("Share Wi-Fi", "Skip reading out passwords.<br>Show a QR code.")
STORE["zh-Hans"] = "zh-Hans"
SCREEN["zh-Hans"] = "zh-Hans"
SEARCH["zh-Hans"] = ("Wi-Fi 二维码", "制作访客<br>Wi-Fi 提示牌", "扫码即连<br>打印一步到位")
HEADER["zh-Hans"] = ("分享 Wi-Fi", "不用再报密码<br>亮出二维码就行")
STORE["zh-Hant"] = "zh-Hant"
SCREEN["zh-Hant"] = "zh-Hant"
SEARCH["zh-Hant"] = ("Wi-Fi QR Code", "製作訪客<br>Wi-Fi 告示牌", "掃碼即連線<br>列印一步到位")
HEADER["zh-Hant"] = ("分享 Wi-Fi", "不用再報密碼<br>亮出 QR Code 就行")
STORE["ja"] = "ja"
SCREEN["ja"] = "ja"
SEARCH["ja"] = ("Wi-Fi QR", "お客様用Wi-Fi<br>案内ボードを作成", "QRコードですぐ接続<br>印刷までワンステップ")
HEADER["ja"] = ("Wi-Fiを共有", "パスワードを伝える代わりに<br>QRコードを見せるだけ")
STORE["ru"] = "ru"
SCREEN["ru"] = "ru"
SEARCH["ru"] = ("QR-код Wi-Fi", "Гостевые таблички<br>для Wi-Fi", "Подключение по QR-коду,<br>печать в пару касаний")
HEADER["ru"] = ("Делитесь Wi-Fi", "Не диктуйте пароль —<br>покажите QR-код")
STORE["es"] = "es"
SCREEN["es"] = "es"
SEARCH["es"] = ("QR de Wi-Fi", "Crea carteles de<br>Wi-Fi para invitados", "Conecta con un QR<br>e imprime de una vez")
HEADER["es"] = ("Comparte tu Wi-Fi", "Sin dictar contraseñas:<br>enseña un QR")
STORE["de"] = "de"
SCREEN["de"] = "de"
SEARCH["de"] = ("WLAN-QR-Code", "WLAN-Aushänge<br>für Gäste erstellen", "Per QR-Code verbinden,<br>in einem Rutsch drucken")
HEADER["de"] = ("WLAN teilen", "Passwort nicht ansagen –<br>einfach QR-Code zeigen")
STORE["fr"] = "fr"
SCREEN["fr"] = "fr"
SEARCH["fr"] = ("QR Wi-Fi", "Créez des affichettes<br>Wi-Fi pour invités", "Connexion par QR code,<br>impression en un geste")
HEADER["fr"] = ("Partagez votre Wi-Fi", "Ne dictez plus le mot de passe :<br>montrez un QR code")
STORE["it"] = "it"
SCREEN["it"] = "it"
SEARCH["it"] = ("QR Wi-Fi", "Crea cartelli Wi-Fi<br>per gli ospiti", "Connessione con un QR,<br>stampa in un attimo")
HEADER["it"] = ("Condividi il Wi-Fi", "Non dettare la password:<br>mostra un QR")
STORE["pt-BR"] = "pt-BR"
SCREEN["pt-BR"] = "pt-BR"
SEARCH["pt-BR"] = ("QR do Wi-Fi", "Crie placas de Wi-Fi<br>para visitantes", "Conecte com um QR,<br>imprima de uma vez")
HEADER["pt-BR"] = ("Compartilhe o Wi-Fi", "Chega de ditar a senha:<br>mostre um QR")
STORE["th"] = "th"
SCREEN["th"] = "th"
SEARCH["th"] = ("QR ของ Wi-Fi", "สร้างป้าย Wi-Fi<br>สำหรับแขก", "เชื่อมต่อด้วย QR<br>พิมพ์ได้ในขั้นตอนเดียว")
HEADER["th"] = ("แชร์ Wi-Fi", "ไม่ต้องบอกรหัสผ่าน<br>แค่โชว์ QR")
STORE["vi"] = "vi"
SCREEN["vi"] = "vi"
SEARCH["vi"] = ("Mã QR Wi-Fi", "Tạo bảng Wi-Fi<br>cho khách", "Kết nối bằng mã QR,<br>in ngay một lần")
HEADER["vi"] = ("Chia sẻ Wi-Fi", "Đừng đọc mật khẩu nữa:<br>hãy đưa mã QR")
STORE["cs"] = "cs"
SCREEN["cs"] = "cs"
SEARCH["cs"] = ("QR kód Wi-Fi", "Vytvořte Wi-Fi tabulky<br>pro hosty", "Připojení přes QR kód,<br>tisk jedním krokem")
HEADER["cs"] = ("Sdílejte Wi-Fi", "Nediktujte heslo,<br>ukažte QR kód")
STORE["da"] = "da"
SCREEN["da"] = "da"
SEARCH["da"] = ("Wi-Fi QR", "Lav Wi-Fi-opslag<br>til gæster", "Forbind med QR-kode,<br>udskriv i ét trin")
HEADER["da"] = ("Del Wi-Fi", "Læs ikke adgangskoden op:<br>vis en QR-kode")
STORE["el"] = "el"
SCREEN["el"] = "el"
SEARCH["el"] = ("QR Wi-Fi", "Φτιάξτε πινακίδες<br>Wi-Fi για επισκέπτες", "Σύνδεση με QR,<br>εκτύπωση με ένα βήμα")
HEADER["el"] = ("Κοινοποιήστε το Wi-Fi", "Μην υπαγορεύετε τον κωδικό:<br>δείξτε έναν κωδικό QR")
STORE["fi"] = "fi"
SCREEN["fi"] = "fi"
SEARCH["fi"] = ("Wi-Fi-QR", "Tee Wi-Fi-kyltit<br>vieraille", "Yhdistä QR-koodilla,<br>tulosta yhdellä kertaa")
HEADER["fi"] = ("Jaa Wi-Fi", "Älä sanele salasanaa:<br>näytä QR-koodi")
STORE["id"] = "id"
SCREEN["id"] = "id"
SEARCH["id"] = ("QR Wi-Fi", "Buat papan Wi-Fi<br>untuk tamu", "Tersambung lewat QR,<br>cetak sekali jalan")
HEADER["id"] = ("Bagikan Wi-Fi", "Tak perlu sebut kata sandi:<br>tunjukkan kode QR")
STORE["nb"] = "nb"
SCREEN["nb"] = "nb"
SEARCH["nb"] = ("Wi-Fi-QR", "Lag Wi-Fi-oppslag<br>til gjester", "Koble til med QR-kode,<br>skriv ut i ett trinn")
HEADER["nb"] = ("Del Wi-Fi", "Ikke les opp passordet:<br>vis en QR-kode")
STORE["nl"] = "nl"
SCREEN["nl"] = "nl"
SEARCH["nl"] = ("Wifi-QR", "Maak wifi-bordjes<br>voor gasten", "Verbind met een QR-code,<br>print in één keer")
HEADER["nl"] = ("Deel wifi", "Lees het wachtwoord niet voor:<br>laat een QR-code zien")
STORE["pl"] = "pl"
SCREEN["pl"] = "pl"
SEARCH["pl"] = ("Kod QR Wi-Fi", "Twórz tabliczki Wi-Fi<br>dla gości", "Połączenie kodem QR,<br>druk jednym krokiem")
HEADER["pl"] = ("Udostępnij Wi-Fi", "Nie dyktuj hasła:<br>pokaż kod QR")
STORE["sv"] = "sv"
SCREEN["sv"] = "sv"
SEARCH["sv"] = ("Wi-Fi-QR", "Gör Wi-Fi-skyltar<br>för gäster", "Anslut med QR-kod,<br>skriv ut i ett steg")
HEADER["sv"] = ("Dela Wi-Fi", "Läs inte upp lösenordet:<br>visa en QR-kod")
# i18n-end














































# 바탕 · 글자색은 앱의 색이다: 밝은 시스템 그룹 배경 + iOS 파랑 포인트(앱의 주 버튼 색).
BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#F2F2F7; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(160px); pointer-events:none; }
.text { position:absolute; display:flex; flex-direction:column; justify-content:center; }
.eyebrow { font-weight:700; color:#0A7CFF; letter-spacing:-0.01em; line-height:1.15; }
.headline { font-weight:800; color:#111114; letter-spacing:-0.03em; line-height:1.12; text-wrap:balance; }
.sub { font-weight:500; color:#6E6E76; letter-spacing:-0.01em; line-height:1.35; text-wrap:balance; }
/* 한국어는 낱말 중간에서 끊지 않는다. */
:lang(ko) .headline, :lang(ko) .sub, :lang(ko) .eyebrow { word-break:keep-all; }
.phone { position:absolute; background:#1c1c1f; border:6px solid #3a3a3e; padding:40px; border-radius:190px;
  box-shadow: 0 60px 160px rgba(20,40,90,.28), 0 0 0 2px #232327 inset; }
.phone img { width:100%%; display:block; border-radius:152px; }
.star { position:absolute; border-radius:50%%; background:#0A7CFF; }
"""

# 글이 상자를 넘지 않을 때까지 줄인다. 잘리는 글은 없다 - 끝까지 안 맞으면 표시하고 멈춘다.
FIT_JS = """
<script>
// 문구에 적은 줄(<br>)보다 더 쪼개지면 "Rispondi / con un / tocco" 처럼 읽기가 끊긴다.
// 적은 줄 수를 지킬 때까지 줄인다.
function lines(el) {
  return Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
}
function fit(box, el, max, min) {
  const want = el.querySelectorAll('br').length + 1;
  let size = max;
  el.style.fontSize = size + 'px';
  while (size > min && (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 ||
         lines(el) > want)) {
    size -= 4; el.style.fontSize = size + 'px';
  }
  if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 || lines(el) > want)
    document.body.dataset.overflow = '1';
}
document.fonts.ready.then(() => {
  const box = document.querySelector('.text');
  const h = document.querySelector('.headline');
  fit(box, h, +h.dataset.max, +h.dataset.min);
  document.body.dataset.done = '1';
});
</script>
"""


def phone(img, left, top, width, rotate=0):
    return (f'<div class="phone" style="left:{left}px;top:{top}px;width:{width}px;'
            f'transform:rotate({rotate}deg)"><img src="{img}"></div>')


def stars(W, H, seed, n):
    """앱 배경처럼 흩어진 별. 같은 시드면 같은 자리라 언어마다 그림이 같다."""
    import random
    rnd = random.Random(seed)
    out = []
    for _ in range(n):
        size = rnd.choice([4, 5, 6, 8, 10])
        out.append(f'<div class="star" style="left:{rnd.randrange(W)}px;top:{rnd.randrange(H)}px;'
                   f'width:{size}px;height:{size}px;opacity:{rnd.uniform(.15, .6):.2f}"></div>')
    return "".join(out)


def shot(lang, name):
    return (RAW / SCREEN[lang] / name).as_uri()


def search_html(lang):
    W, H, (l, t, r, b) = SPEC["search"]
    eyebrow, headline, sub = SEARCH[lang]
    sw, sh = r - l, b - t
    col = int(sw * 0.56)
    ph_w = 1040
    ph_left = l + col + int(sw * 0.04)
    return f"""
<div class="glow" style="left:{ph_left - 300}px;top:500px;width:1700px;height:1700px;background:rgba(10,124,255,.16)"></div>
<div class="glow" style="left:{l - 700}px;top:{t - 500}px;width:1400px;height:1000px;background:rgba(124,77,255,.07)"></div>
{stars(W, H, 7, 0)}
{phone(shot(lang, "02-poster.png"), ph_left, t - 360, ph_w, 0)}
<div class="text" style="left:{l}px;top:{t}px;width:{col}px;height:{sh}px">
  <div class="eyebrow" style="font-size:96px">{eyebrow}</div>
  <div class="headline" data-max="250" data-min="140" style="margin-top:36px">{headline}</div>
  <div class="sub" style="font-size:84px;margin-top:52px">{sub}</div>
</div>"""


def header_html(lang):
    W, H, (l, t, r, b) = SPEC["header"]
    eyebrow, headline = HEADER[lang]
    sw, sh = r - l, b - t
    dots = ""
    return f"""
<div class="glow" style="left:{l - 200}px;top:{t - 400}px;width:{sw + 400}px;height:{sh + 800}px;background:rgba(10,124,255,.12)"></div>
{dots}
{phone(shot(lang, "01-qr.png"), 300, 360, 640, -9)}
{phone(shot(lang, "03-poster-teal.png"), 2900, 360, 640, 9)}
<div class="text" style="left:{l}px;top:{t}px;width:{sw}px;height:{sh}px;align-items:center;text-align:center">
  <div class="eyebrow" style="font-size:76px">{eyebrow}</div>
  <div class="headline" data-max="210" data-min="110" style="margin-top:22px">{headline}</div>
</div>"""


def render(lang, kind):
    W, H, _ = SPEC[kind]
    body = search_html(lang) if kind == "search" else header_html(lang)
    page = (f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>'
            f'{BASE_CSS % {"W": W, "H": H}}</style></head><body>{body}{FIT_JS}</body></html>')
    html_path = pathlib.Path(tempfile.gettempdir()) / f"wifisnap-creative-{lang}-{kind}.html"
    html_path.write_text(page, encoding="utf-8")
    # 글이 끝까지 안 맞으면 그림을 만들지 않는다(잘린 글이 스토어에 올라가는 것보다 낫다).
    dom = subprocess.run([CHROME, "--headless=new", "--dump-dom", f"--window-size={W},{H}",
                          "--force-device-scale-factor=1", "--disable-gpu", "--virtual-time-budget=3000",
                          html_path.as_uri()], capture_output=True, text=True, timeout=90).stdout
    if 'data-done="1"' not in dom:
        raise SystemExit(f"글 맞추기가 끝나지 않았다: {lang} {kind}")
    if 'data-overflow="1"' in dom:
        raise SystemExit(f"글이 안전 영역을 넘는다: {lang} {kind} - 문구를 줄일 것")
    out_dir = OUT / STORE.get(lang, lang)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_png = out_dir / f"{kind}.png"
    # ⚠️ Chrome 은 가끔 아무것도 안 그리고 끝나거나 멈춘다. 세 번까지 한다.
    for _ in range(3):
        try:
            r = subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                                f"--window-size={W},{H}", "--force-device-scale-factor=1",
                                "--hide-scrollbars", "--disable-gpu", "--virtual-time-budget=3000",
                                "--allow-file-access-from-files", html_path.as_uri()],
                               capture_output=True, timeout=90)
        except subprocess.TimeoutExpired:
            continue
        if r.returncode == 0:
            break
    else:
        raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
    print(f"rendered {out_png}")


if __name__ == "__main__":
    langs = sys.argv[1:] or list(SEARCH)
    for lang in langs:
        if lang not in SEARCH:
            raise SystemExit(f"모르는 언어: {lang} (아는 것: {', '.join(SEARCH)})")
        for kind in ("header", "search"):
            render(lang, kind)
