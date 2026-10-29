// 마이파이 웹 체험: 이름과 비밀번호를 넣으면 앱과 같은 와이파이 QR과 손님용 안내판이 만들어진다.
// 규칙은 앱과 같다. 문자열은 QRCodeGenerator.wifiString(특수문자 \ ; , : " 이스케이프, 비밀번호가 없으면 nopass),
// 오류 정정은 M, 테마 색은 PosterTheme.all. 휴대폰 카메라로 비추면 실제로 연결 제안이 뜬다.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);

  // ---- QR 부호기 (바이트 모드, 오류 정정 M, 버전 1~10) ----
  const EXP = [], LOG = [];
  for (let i = 0, x = 1; i < 255; i++) { EXP[i] = EXP[i + 255] = x; LOG[x] = i; x = (x << 1) ^ (x & 128 ? 0x11d : 0); }
  const mul = (a, b) => (a && b ? EXP[LOG[a] + LOG[b]] : 0);
  function ecc(data, n) {
    let g = [1];
    for (let i = 0; i < n; i++) g = [...g, 0].map((c, j) => c ^ (j ? mul(g[j - 1], EXP[i]) : 0));
    const r = Array(n).fill(0);
    for (const d of data) { const f = d ^ r.shift(); r.push(0); for (let i = 0; i < n; i++) r[i] ^= mul(g[i + 1], f); }
    return r;
  }
  const BLOCKS = [[10, 1, 16], [16, 1, 28], [26, 1, 44], [18, 2, 32], [24, 2, 43], [16, 4, 27], [18, 4, 31],
    [22, 2, 38, 2, 39], [22, 3, 36, 2, 37], [26, 4, 43, 1, 44]];
  const ALIGN = [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];

  function qr(text) {
    const bytes = [...new TextEncoder().encode(text)];
    let v = 1, b;
    for (; v <= 10; v++) {
      b = BLOCKS[v - 1];
      const cap = b[1] * b[2] + (b[3] || 0) * (b[4] || 0);
      if (4 + (v < 10 ? 8 : 16) + bytes.length * 8 <= cap * 8) break;
    }
    if (v > 10) return null;
    const cap = b[1] * b[2] + (b[3] || 0) * (b[4] || 0), bits = [];
    const put = (val, len) => { for (let i = len - 1; i >= 0; i--) bits.push((val >> i) & 1); };
    put(4, 4); put(bytes.length, v < 10 ? 8 : 16); bytes.forEach(x => put(x, 8));
    put(0, Math.min(4, cap * 8 - bits.length)); while (bits.length % 8) bits.push(0);
    const words = []; for (let i = 0; i < bits.length; i += 8) words.push(parseInt(bits.slice(i, i + 8).join(""), 2));
    for (let p = 0; words.length < cap; p++) words.push(p % 2 ? 0x11 : 0xec);
    const data = [], ecs = [];
    let k = 0;
    for (const [count, len] of [[b[1], b[2]], [b[3] || 0, b[4] || 0]])
      for (let i = 0; i < count; i++) { const blk = words.slice(k, k += len); data.push(blk); ecs.push(ecc(blk, b[0])); }
    const stream = [];
    for (const group of [data, ecs])
      for (let i = 0; i < Math.max(...group.map(g => g.length)); i++) group.forEach(g => i < g.length && stream.push(g[i]));
    const sbits = stream.flatMap(w => [7, 6, 5, 4, 3, 2, 1, 0].map(i => (w >> i) & 1));

    const n = 17 + 4 * v, m = [...Array(n)].map(() => Array(n).fill(0)), fn = m.map(r => r.map(() => false));
    const set = (x, y, d) => { m[y][x] = d ? 1 : 0; fn[y][x] = true; };
    for (const [fx, fy] of [[0, 0], [n - 7, 0], [0, n - 7]])
      for (let dy = -1; dy <= 7; dy++) for (let dx = -1; dx <= 7; dx++) {
        const x = fx + dx, y = fy + dy;
        if (x < 0 || y < 0 || x >= n || y >= n) continue;
        const ring = Math.max(Math.abs(dx - 3), Math.abs(dy - 3));
        set(x, y, ring !== 2 && ring !== 4);
      }
    for (let i = 8; i < n - 8; i++) { set(i, 6, i % 2 === 0); set(6, i, i % 2 === 0); }
    const al = ALIGN[v - 1];
    for (const ay of al) for (const ax of al) {
      if ((ax === 6 && ay === 6) || (ax === 6 && ay === al.at(-1)) || (ax === al.at(-1) && ay === 6)) continue;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
    for (let i = 0; i < 9; i++) if (i !== 6) { set(8, i, 0); set(i, 8, 0); }   // 6 은 타이밍 줄
    for (let i = 0; i < 8; i++) { set(n - 1 - i, 8, 0); set(8, n - 1 - i, 0); }
    if (v >= 7) {
      let r = v; for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >> 11) * 0x1f25);
      const vb = (v << 12) | r;
      for (let i = 0; i < 18; i++) { const d = (vb >> i) & 1, a = n - 11 + (i % 3), c = Math.floor(i / 3); set(a, c, d); set(c, a, d); }
    }
    let bi = 0;
    for (let right = n - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < n; vert++) for (let j = 0; j < 2; j++) {
        const x = right - j, y = ((right + 1) & 2) === 0 ? n - 1 - vert : vert;
        if (!fn[y][x]) m[y][x] = bi < sbits.length ? sbits[bi] : 0, bi++;
      }
    }
    const MASKS = [(x, y) => (x + y) % 2, (x, y) => y % 2, (x, y) => x % 3, (x, y) => (x + y) % 3,
      (x, y) => (Math.floor(y / 2) + Math.floor(x / 3)) % 2, (x, y) => (x * y) % 2 + (x * y) % 3,
      (x, y) => ((x * y) % 2 + (x * y) % 3) % 2, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2];
    let best, bestScore = Infinity;
    MASKS.forEach((fnMask, mask) => {
      const g = m.map((row, y) => row.map((d, x) => (fn[y][x] || fnMask(x, y) ? d : d ^ 1)));
      let r = mask; for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >> 9) * 0x537);
      const fb = ((mask << 10) | r) ^ 0x5412, bit = i => (fb >> i) & 1;
      for (let i = 0; i < 6; i++) g[i][8] = bit(i);
      g[7][8] = bit(6); g[8][8] = bit(7); g[8][7] = bit(8);
      for (let i = 9; i < 15; i++) g[8][14 - i] = bit(i);
      for (let i = 0; i < 8; i++) g[8][n - 1 - i] = bit(i);
      for (let i = 8; i < 15; i++) g[n - 15 + i][8] = bit(i);
      g[n - 8][8] = 1;
      const lines = [...g.map(r => r.join("")), ...g.map((_, x) => g.map(r => r[x]).join(""))];
      let s = 0, dark = 0;
      for (const l of lines) {
        for (const run of l.match(/0{5,}|1{5,}/g) || []) s += run.length - 2;
        for (const p of ["10111010000", "00001011101"]) for (let i = l.indexOf(p); i >= 0; i = l.indexOf(p, i + 1)) s += 40;
      }
      for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
        dark += g[y][x];
        if (x < n - 1 && y < n - 1 && g[y][x] === g[y][x + 1] && g[y][x] === g[y + 1][x] && g[y][x] === g[y + 1][x + 1]) s += 3;
      }
      s += Math.floor(Math.abs(dark * 20 - n * n * 10) / (n * n)) * 10;
      if (s < bestScore) { bestScore = s; best = g; }
    });
    return best;
  }

  // ---- 앱과 같은 와이파이 문자열 ----
  const esc = s => s.replace(/\\/g, "\\\\").replace(/[;,:"]/g, c => "\\" + c);
  const wifi = (ssid, pw) => pw ? `WIFI:S:${esc(ssid)};T:WPA;P:${esc(pw)};;` : `WIFI:S:${esc(ssid)};T:nopass;;`;

  const THEMES = [["#1E1B4B,#4338CA,#7C3AED", "#fff", "#C7D2FE"], ["#FF6B6B,#FF8E53,#FFB088", "#fff", "#FFF1E6"],
    ["#06B6D4,#10B981", "#fff", "#E0F7F4"], ["#2563EB,#0EA5E9,#22D3EE", "#fff", "#DBEAFE"],
    ["#065F46,#059669,#34D399", "#fff", "#D1FAE5"], ["#F5E9DA,#E8D3B5", "#5B3A29", "#8A6E56"], ["#FAFAFA,#EDEDED", "#111111", "#6B7280"]];
  const h = s => s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  root.innerHTML = `
    <div class="mf-sign" role="img" aria-live="polite">
      <span class="mf-badge">WiFi</span>
      <b class="mf-heading">${h(T.heading)}</b>
      <span class="mf-sub">${h(T.subtitle)}</span>
      <div class="mf-qr"></div>
      <dl class="mf-rows"><div><dt>${h(T.network)}</dt><dd class="mf-ssid"></dd></div><div><dt>${h(T.password)}</dt><dd class="mf-pw"></dd></div></dl>
      <span class="mf-foot">${h(T.footer)}</span>
    </div>
    <div class="mf-form">
      <label class="mf-field"><span>${h(T.ssidLabel)}</span><input name="ssid" maxlength="32" autocomplete="off" spellcheck="false" value="Lounge_Cafe_5G"></label>
      <label class="mf-field"><span>${h(T.pwLabel)}</span><input name="pw" maxlength="63" autocomplete="off" spellcheck="false" value="lounge2026!"></label>
      <p class="mf-label">${h(T.themeLabel)}</p>
      <div class="mf-themes">${THEMES.map((t, i) => `<button type="button" data-theme="${i}" aria-label="${h(T.themes[i])}" title="${h(T.themes[i])}" style="background:linear-gradient(135deg,${t[0]})"></button>`).join("")}</div>
      <p class="mf-scan">${h(T.scan)}</p>
      <p class="muted small">${h(T.note)}</p>
    </div>`;

  const $ = s => root.querySelector(s);
  const sign = $(".mf-sign"), ssidIn = $('[name="ssid"]'), pwIn = $('[name="pw"]');
  let theme = 0;

  function render() {
    const ssid = ssidIn.value.trim() || "Lounge_Cafe_5G", pw = pwIn.value;
    const g = qr(wifi(ssid, pw)), q = 4;
    if (!g) return;                                  // 한 장에 담기지 않는 길이
    const n = g.length;
    let d = "";
    g.forEach((row, y) => row.forEach((on, x) => { if (on) d += `M${x + q} ${y + q}h1v1h-1z`; }));
    $(".mf-qr").innerHTML = `<svg viewBox="0 0 ${n + q * 2} ${n + q * 2}" shape-rendering="crispEdges" aria-hidden="true"><path d="${d}"/></svg>`;
    $(".mf-ssid").textContent = ssid;
    $(".mf-pw").textContent = pw || T.open;
    const [bg, fg, sub] = THEMES[theme];
    sign.style.background = `linear-gradient(135deg,${bg})`;
    sign.style.setProperty("--fg", fg); sign.style.setProperty("--sub", sub);
    sign.setAttribute("aria-label", `${T.heading}: ${ssid}`);
    root.querySelectorAll("[data-theme]").forEach(b => b.setAttribute("aria-pressed", +b.dataset.theme === theme));
  }

  root.addEventListener("input", render);
  root.addEventListener("click", e => {
    const b = e.target.closest("[data-theme]");
    if (b) { theme = +b.dataset.theme; render(); }
  });
  render();
})();
