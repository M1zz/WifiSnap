#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: 시뮬레이터 원본 캡처 + 헤드라인 → HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_marketing_screenshots.py [언어 ...]   (없으면 전부)

  원본  docs/screenshots/raw/<언어>/NN-….png         (iPhone 6.9" 시뮬레이터 캡처 1320x2868, 올라가지 않는다)
  제출  docs/screenshots/marketing/<스토어 로케일>/NN-….png   (1242x2688, DeployBar 가 그대로 올린다)

파일 이름 순서가 스토어에 보이는 순서다. 다음 릴리즈에는 원본만 다시 찍고 이 스크립트를 다시 돌린다.
"""
import subprocess, sys, pathlib, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1242, 2688   # 이 계정의 iPhone 제출 규격

# ── 앱마다 고치는 곳 ──────────────────────────────────────────────
# 앱 언어 → App Store 로케일 (스토어 폴더 이름)
STORE = {"ko": "ko"}
# 바탕 · 포인트 색 (헤더·검색 결과 그림과 맞춘다)
BG, ACCENT, INK, SUB = "#F2F2F7", "#0A7CFF", "#111114", "#6E6E76"
# 언어 → [(원본 파일, 레이아웃, 헤드라인, 서브카피)]
SHOTS = {
    "ko": [
        ("01-scan.png",        "hero-bleed",  "안내판을 찍으면<br>바로 연결", "아이디와 비밀번호를 사진에서 읽어요"),
        ("02-qr.png",          "left-text",   "비밀번호 대신<br>QR 한 장", "친구는 카메라로 비추기만 하면 돼요"),
        ("03-poster-card.png", "text-bottom", "손님용 와이파이 안내판", "매장 이름과 영업시간까지 넣어 꾸며요"),
        ("04-poster-a4.png",   "flat-rotate", "A4 포스터로<br>바로 인쇄", "7가지 테마, AirPrint로 한 번에"),
        ("05-saved.png",       "dark",        "가 본 곳 와이파이를<br>한곳에", "근처에 오면 그곳 와이파이가 먼저 보여요"),
    ],
}

# i18n-begin
STORE["en"] = "en-US"
SHOTS["en"] = [
    ("01-scan.png", "hero-bleed", "Snap a sign,<br>connect instantly", "Reads the name and password from a photo"),
    ("02-qr.png", "left-text", "A QR code<br>instead of a password", "Friends just point their camera at it"),
    ("03-poster-card.png", "text-bottom", "Guest Wi-Fi signs", "Add your shop name and opening hours"),
    ("04-poster-a4.png", "flat-rotate", "Print an A4<br>poster in one go", "7 themes, straight to AirPrint"),
    ("05-saved.png", "dark", "Every Wi-Fi you've<br>used, in one place", "Nearby networks show up first"),
]
STORE["en-GB"] = "en-GB"
SHOTS["en-GB"] = [
    ("01-scan.png", "hero-bleed", "Snap a sign,<br>connect instantly", "Reads the name and password from a photo"),
    ("02-qr.png", "left-text", "A QR code<br>instead of a password", "Friends just point their camera at it"),
    ("03-poster-card.png", "text-bottom", "Guest Wi-Fi signs", "Add your shop name and opening hours"),
    ("04-poster-a4.png", "flat-rotate", "Print an A4<br>poster in one go", "7 themes, straight to AirPrint"),
    ("05-saved.png", "dark", "Every Wi-Fi you've<br>used, in one place", "Nearby networks show up first"),
]
STORE["zh-Hans"] = "zh-Hans"
SHOTS["zh-Hans"] = [
    ("01-scan.png", "hero-bleed", "拍下提示牌<br>立刻连接", "从照片中识别账号和密码"),
    ("02-qr.png", "left-text", "不用报密码<br>一张二维码搞定", "朋友只需用相机扫一扫"),
    ("03-poster-card.png", "text-bottom", "访客 Wi-Fi 提示牌", "还能加上店名和营业时间"),
    ("04-poster-a4.png", "flat-rotate", "A4 海报<br>直接打印", "7 种主题，AirPrint 一步完成"),
    ("05-saved.png", "dark", "去过的 Wi-Fi<br>集中在一处", "走到附近，那里的 Wi-Fi 会排在最前"),
]
STORE["zh-Hant"] = "zh-Hant"
SHOTS["zh-Hant"] = [
    ("01-scan.png", "hero-bleed", "拍下告示牌<br>立刻連線", "從照片中辨識帳號和密碼"),
    ("02-qr.png", "left-text", "不用報密碼<br>一張 QR Code 搞定", "朋友只需用相機掃一掃"),
    ("03-poster-card.png", "text-bottom", "訪客 Wi-Fi 告示牌", "還能加上店名和營業時間"),
    ("04-poster-a4.png", "flat-rotate", "A4 海報<br>直接列印", "7 種主題，AirPrint 一步完成"),
    ("05-saved.png", "dark", "去過的 Wi-Fi<br>集中在一處", "走到附近，那裡的 Wi-Fi 會排在最前"),
]
STORE["ja"] = "ja"
SHOTS["ja"] = [
    ("01-scan.png", "hero-bleed", "案内を撮るだけで<br>すぐ接続", "IDとパスワードを写真から読み取ります"),
    ("02-qr.png", "left-text", "パスワードの代わりに<br>QRコード1枚", "友だちはカメラで読み取るだけ"),
    ("03-poster-card.png", "text-bottom", "お客様用Wi-Fi案内ボード", "店名や営業時間まで入れて作れます"),
    ("04-poster-a4.png", "flat-rotate", "A4ポスターを<br>そのまま印刷", "7つのテーマ、AirPrintでワンステップ"),
    ("05-saved.png", "dark", "行った先のWi-Fiを<br>ひとつにまとめて", "近くに来るとそのWi-Fiが先頭に表示されます"),
]
STORE["ru"] = "ru"
SHOTS["ru"] = [
    ("01-scan.png", "hero-bleed", "Снимите табличку —<br>и вы в сети", "Логин и пароль читаются с фото"),
    ("02-qr.png", "left-text", "QR-код вместо<br>пароля на словах", "Другу достаточно навести камеру"),
    ("03-poster-card.png", "text-bottom", "Гостевые таблички Wi-Fi", "Добавьте название и часы работы"),
    ("04-poster-a4.png", "flat-rotate", "Плакат A4<br>сразу на печать", "7 тем, печать через AirPrint"),
    ("05-saved.png", "dark", "Все сети, где вы бывали,<br>в одном месте", "Рядом — нужная сеть сверху"),
]
STORE["es"] = "es"
SHOTS["es"] = [
    ("01-scan.png", "hero-bleed", "Fotografía el cartel<br>y conéctate al instante", "Lee usuario y contraseña de la foto"),
    ("02-qr.png", "left-text", "Un QR en lugar de<br>dictar la contraseña", "Tu amigo solo apunta con la cámara"),
    ("03-poster-card.png", "text-bottom", "Carteles de Wi-Fi para invitados", "Añade el nombre del local y el horario"),
    ("04-poster-a4.png", "flat-rotate", "Póster A4<br>listo para imprimir", "7 temas, con AirPrint de una vez"),
    ("05-saved.png", "dark", "Todas tus Wi-Fi<br>en un solo lugar", "Al llegar, la de ese sitio aparece primero"),
]
STORE["de"] = "de"
SHOTS["de"] = [
    ("01-scan.png", "hero-bleed", "Aushang fotografieren,<br>sofort verbinden", "Kennung und Passwort aus dem Foto lesen"),
    ("02-qr.png", "left-text", "Ein QR-Code statt<br>Passwort ansagen", "Freunde richten einfach die Kamera aus"),
    ("03-poster-card.png", "text-bottom", "WLAN-Aushänge für Gäste", "Mit Lokalname und Öffnungszeiten"),
    ("04-poster-a4.png", "flat-rotate", "A4-Poster<br>direkt drucken", "7 Designs, mit AirPrint in einem Rutsch"),
    ("05-saved.png", "dark", "Alle WLANs von<br>unterwegs an einem Ort", "In der Nähe steht das passende WLAN oben"),
]
STORE["fr"] = "fr"
SHOTS["fr"] = [
    ("01-scan.png", "hero-bleed", "Photographiez l’affichette,<br>connexion immédiate", "Lit l’identifiant et le mot de passe sur la photo"),
    ("02-qr.png", "left-text", "Un QR code plutôt que<br>dicter le mot de passe", "Vos amis n’ont qu’à scanner"),
    ("03-poster-card.png", "text-bottom", "Affichettes Wi-Fi pour invités", "Avec le nom du lieu et les horaires"),
    ("04-poster-a4.png", "flat-rotate", "Une affiche A4<br>prête à imprimer", "7 thèmes, impression AirPrint en un geste"),
    ("05-saved.png", "dark", "Tous vos Wi-Fi<br>au même endroit", "À proximité, le bon réseau passe en premier"),
]
STORE["it"] = "it"
SHOTS["it"] = [
    ("01-scan.png", "hero-bleed", "Fotografa il cartello<br>e ti connetti subito", "Legge ID e password dalla foto"),
    ("02-qr.png", "left-text", "Un QR al posto<br>della password a voce", "Gli amici inquadrano e basta"),
    ("03-poster-card.png", "text-bottom", "Cartelli Wi-Fi per gli ospiti", "Con nome del locale e orari"),
    ("04-poster-a4.png", "flat-rotate", "Poster A4<br>pronto da stampare", "7 temi, stampa con AirPrint in un attimo"),
    ("05-saved.png", "dark", "Tutte le tue Wi-Fi<br>in un unico posto", "Quando sei vicino, la rete giusta è in cima"),
]
STORE["pt-BR"] = "pt-BR"
SHOTS["pt-BR"] = [
    ("01-scan.png", "hero-bleed", "Fotografe a placa<br>e conecte na hora", "Lê usuário e senha direto da foto"),
    ("02-qr.png", "left-text", "Um QR no lugar de<br>ditar a senha", "Seu amigo só aponta a câmera"),
    ("03-poster-card.png", "text-bottom", "Placas de Wi-Fi para visitantes", "Com nome do local e horário"),
    ("04-poster-a4.png", "flat-rotate", "Pôster A4<br>pronto para imprimir", "7 temas, com AirPrint de uma vez"),
    ("05-saved.png", "dark", "Todas as suas redes<br>em um só lugar", "Ao chegar, a rede do local aparece primeiro"),
]
STORE["th"] = "th"
SHOTS["th"] = [
    ("01-scan.png", "hero-bleed", "ถ่ายป้าย<br>เชื่อมต่อทันที", "อ่าน ID และรหัสผ่านจากรูปถ่าย"),
    ("02-qr.png", "left-text", "ใช้ QR แทน<br>การบอกรหัสผ่าน", "เพื่อนแค่สแกนด้วยกล้อง"),
    ("03-poster-card.png", "text-bottom", "ป้าย Wi-Fi สำหรับแขก", "ใส่ชื่อร้านและเวลาทำการได้"),
    ("04-poster-a4.png", "flat-rotate", "โปสเตอร์ A4<br>พิมพ์ได้ทันที", "7 ธีม พิมพ์ด้วย AirPrint ในขั้นตอนเดียว"),
    ("05-saved.png", "dark", "Wi-Fi ที่เคยใช้<br>รวมไว้ในที่เดียว", "เมื่อไปถึง Wi-Fi ของที่นั่นจะขึ้นก่อน"),
]
STORE["vi"] = "vi"
SHOTS["vi"] = [
    ("01-scan.png", "hero-bleed", "Chụp bảng<br>là kết nối ngay", "Đọc tài khoản và mật khẩu từ ảnh chụp"),
    ("02-qr.png", "left-text", "Một mã QR thay cho<br>việc đọc mật khẩu", "Bạn bè chỉ cần quét bằng camera"),
    ("03-poster-card.png", "text-bottom", "Bảng Wi-Fi cho khách", "Thêm tên cửa hàng và giờ mở cửa"),
    ("04-poster-a4.png", "flat-rotate", "Áp phích A4<br>in ngay", "7 giao diện, in bằng AirPrint một lần"),
    ("05-saved.png", "dark", "Mọi Wi-Fi từng dùng<br>ở một nơi", "Đến gần là Wi-Fi nơi đó lên đầu"),
]
STORE["cs"] = "cs"
SHOTS["cs"] = [
    ("01-scan.png", "hero-bleed", "Vyfoťte tabulku<br>a hned se připojte", "Jméno a heslo přečte z fotky"),
    ("02-qr.png", "left-text", "QR kód místo<br>diktování hesla", "Kamarádi jen namíří fotoaparát"),
    ("03-poster-card.png", "text-bottom", "Wi-Fi tabulky pro hosty", "S názvem podniku a otevírací dobou"),
    ("04-poster-a4.png", "flat-rotate", "Plakát A4<br>rovnou k tisku", "7 vzhledů, tisk přes AirPrint jedním krokem"),
    ("05-saved.png", "dark", "Všechny vaše Wi-Fi<br>na jednom místě", "V okolí se ta správná zobrazí první"),
]
STORE["da"] = "da"
SHOTS["da"] = [
    ("01-scan.png", "hero-bleed", "Fotografér opslaget,<br>og vær forbundet med det samme", "Læser id og adgangskode fra billedet"),
    ("02-qr.png", "left-text", "En QR-kode i stedet for<br>at sige adgangskoden højt", "Venner skal bare pege kameraet"),
    ("03-poster-card.png", "text-bottom", "Wi-Fi-opslag til gæster", "Med stedets navn og åbningstider"),
    ("04-poster-a4.png", "flat-rotate", "A4-plakat<br>klar til udskrift", "7 temaer, udskriv med AirPrint i ét trin"),
    ("05-saved.png", "dark", "Alt det Wi-Fi, du har brugt,<br>samlet ét sted", "Når du er tæt på, kommer det rigtige først"),
]
STORE["el"] = "el"
SHOTS["el"] = [
    ("01-scan.png", "hero-bleed", "Φωτογραφίστε την πινακίδα,<br>συνδεθείτε αμέσως", "Διαβάζει αναγνωριστικό και κωδικό από τη φωτογραφία"),
    ("02-qr.png", "left-text", "Κωδικός QR αντί να<br>υπαγορεύετε τον κωδικό", "Οι φίλοι απλώς στρέφουν την κάμερα"),
    ("03-poster-card.png", "text-bottom", "Πινακίδες Wi-Fi για επισκέπτες", "Με όνομα καταστήματος και ωράριο"),
    ("04-poster-a4.png", "flat-rotate", "Αφίσα A4<br>έτοιμη για εκτύπωση", "7 θέματα, εκτύπωση με AirPrint με ένα βήμα"),
    ("05-saved.png", "dark", "Όλα τα Wi-Fi που έχετε<br>χρησιμοποιήσει, σε ένα μέρος", "Όταν είστε κοντά, το σωστό εμφανίζεται πρώτο"),
]
STORE["fi"] = "fi"
SHOTS["fi"] = [
    ("01-scan.png", "hero-bleed", "Kuvaa kyltti<br>ja yhdistä heti", "Lukee tunnuksen ja salasanan kuvasta"),
    ("02-qr.png", "left-text", "QR-koodi salasanan<br>sanelun sijaan", "Ystävä osoittaa vain kameralla"),
    ("03-poster-card.png", "text-bottom", "Wi-Fi-kyltit vieraille", "Paikan nimi ja aukioloajat mukaan"),
    ("04-poster-a4.png", "flat-rotate", "A4-juliste<br>suoraan tulostukseen", "7 teemaa, tulosta AirPrintillä yhdellä kertaa"),
    ("05-saved.png", "dark", "Kaikki käyttämäsi Wi-Fi-verkot<br>yhdessä paikassa", "Kun olet lähellä, oikea verkko nousee ensin"),
]
STORE["id"] = "id"
SHOTS["id"] = [
    ("01-scan.png", "hero-bleed", "Foto papannya,<br>langsung tersambung", "Membaca ID dan kata sandi dari foto"),
    ("02-qr.png", "left-text", "Cukup satu QR,<br>tak perlu menyebut kata sandi", "Teman tinggal arahkan kamera"),
    ("03-poster-card.png", "text-bottom", "Papan Wi-Fi untuk tamu", "Lengkap dengan nama tempat dan jam buka"),
    ("04-poster-a4.png", "flat-rotate", "Poster A4<br>langsung cetak", "7 tema, cetak lewat AirPrint sekali jalan"),
    ("05-saved.png", "dark", "Semua Wi-Fi yang pernah dipakai<br>di satu tempat", "Saat di dekatnya, yang pas muncul paling atas"),
]
# i18n-end





































# ─────────────────────────────────────────────────────────────────

BASE_CSS = f"""
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:{BG}; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", "Hiragino Sans", "PingFang SC", sans-serif; }}
.headline {{ font-size:96px; font-weight:800; color:{INK}; letter-spacing:-0.03em; line-height:1.18; }}
.sub {{ font-size:48px; font-weight:500; color:{SUB}; letter-spacing:-0.01em; line-height:1.35; }}
:lang(ko) .headline, :lang(ko) .sub {{ word-break:keep-all; }}
.phone {{ background:#17171a; border-radius:112px; border:3px solid #3a3a3e; padding:24px;
  box-shadow: 50px 80px 120px rgba(20,40,90,.25), 16px 26px 46px rgba(0,0,0,.16); }}
.phone img {{ width:100%; display:block; border-radius:90px; }}
.dot {{ display:inline-block; width:22px; height:22px; border-radius:50%; background:{ACCENT}; margin-bottom:46px; }}
"""

LAYOUTS = {
    "hero-bleed": """
.text { text-align:center; padding:250px 80px 0; }
.sub { margin-top:44px; }
.wrap { display:flex; justify-content:center; margin-top:120px; }
.phone { width:960px; }
""",
    "left-text": """
.text { text-align:left; padding:260px 100px 0 110px; }
.sub { margin-top:44px; }
.wrap { perspective:2600px; perspective-origin:30% 30%; position:absolute; left:290px; top:930px; }
.phone { width:820px; transform:rotateY(16deg) rotateX(2deg); }
""",
    "text-bottom": """
.wrap { perspective:2800px; perspective-origin:50% 40%; display:flex; justify-content:center; margin-top:150px; }
.phone { width:840px; transform:rotateY(-10deg) rotateX(2deg); }
.text { text-align:center; padding:100px 80px 0; }
.sub { margin-top:40px; }
""",
    "flat-rotate": """
.text { text-align:center; padding:240px 80px 0; }
.sub { margin-top:44px; }
.wrap { position:absolute; left:120px; top:950px; }
.phone { width:960px; transform:rotate(-6deg); }
""",
    "dark": f"""
body {{ background:#131316; }}
.headline {{ color:#f5f5f7; }} .sub {{ color:#8a8a90; }}
.text {{ text-align:center; padding:250px 80px 0; }}
.sub {{ margin-top:44px; }}
.wrap {{ display:flex; justify-content:center; margin-top:120px; }}
.phone {{ width:900px; border-color:#48484e;
  box-shadow: 0 0 160px rgba(80,140,255,.22), 40px 70px 110px rgba(0,0,0,.55); }}
""",
}

TEXT = '<div class="text"><div class="dot"></div><div class="headline">{headline}</div><div class="sub">{sub}</div></div>'
PHONE = '<div class="wrap"><div class="phone"><img src="{img}"></div></div>'
HTML = '<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head><body>{body}</body></html>'


def chrome_shot(html, png, tmp):
    """헤드리스 Chrome 으로 한 장 그린다.

    ⚠️ Chrome 은 그림을 다 쓰고도 끝나지 않고 멈추는 일이 잦다(여러 개가 동시에 돌 때 특히).
       그래서 끝나기를 기다리지 않고, 파일이 생겨 크기가 멈추면 프로세스를 닫는다.
    """
    png.unlink(missing_ok=True)
    proc = subprocess.Popen([CHROME, "--headless=new", f"--user-data-dir={tmp}/chrome", "--no-first-run",
                             "--disable-component-update", "--no-default-browser-check", "--disable-extensions",
                             f"--screenshot={png}", f"--window-size={W},{H}", "--force-device-scale-factor=1",
                             "--hide-scrollbars", "--allow-file-access-from-files", html.as_uri()],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    last, deadline = -1, time.time() + 180
    try:
        while time.time() < deadline:
            time.sleep(1)
            size = png.stat().st_size if png.exists() else -1
            if size > 10000 and size == last:
                return True
            last = size
            if proc.poll() is not None and size <= 0:
                return False
        return False
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        # 남은 도우미 프로세스도 이 프로필 것만 골라 닫는다
        subprocess.run(["pkill", "-f", f"{tmp}/chrome"], capture_output=True)


def render(lang):
    out_dir = OUT / STORE[lang]
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.png"):
        old.unlink()
    with tempfile.TemporaryDirectory() as tmp:
        for fname, layout, headline, sub in SHOTS[lang]:
            src = RAW / lang / fname
            assert src.exists(), f"원본이 없다: {src}"
            text = TEXT.format(headline=headline, sub=sub)
            phone = PHONE.format(img=src.as_uri())
            body = phone + text if layout == "text-bottom" else text + phone
            html = pathlib.Path(tmp) / f"{lang}-{fname}.html"
            html.write_text(HTML.format(lang=lang, css=BASE_CSS + LAYOUTS[layout], body=body), encoding="utf-8")
            png = out_dir / fname
            if not any(chrome_shot(html, png, tmp) for _ in range(3)):
                raise SystemExit(f"그리지 못했다: {png}")
            print("rendered", png.relative_to(ROOT))


if __name__ == "__main__":
    for lang in (sys.argv[1:] or list(SHOTS)):
        render(lang)
