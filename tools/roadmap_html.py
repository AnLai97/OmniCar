# Sinh ROADMAP.html tu ROADMAP.md (cung thu muc goc repo). Chay lai moi khi sua ROADMAP.md:
#   python tools/roadmap_html.py
# Trang tu chua (khong can mang), mo bang trinh duyet. Danh dau [x] trong ROADMAP.md moi la luu that;
# tick tren trang chi luu tam trong trinh duyet.
import html, io, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ROADMAP.md")
OUT = os.path.join(ROOT, "ROADMAP.html")


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"`(.+?)`", r"<code>\1</code>", s)
    return s


def level(diff):
    d = diff.strip().lower()
    for key, name in (("thấp", "low"), ("vừa", "mid"), ("cao", "high")):
        if d.startswith(key):
            return name
    return "other"


def parse(md):
    lines = md.splitlines()
    doc = {"title": "", "intro": [], "sections": []}
    cur = None      # section dang doc
    item = None     # muc dang doc (de gom dong thut le)
    prev_blank = True
    for raw in lines:
        line = raw.rstrip()
        if line.startswith("# "):
            doc["title"] = line[2:].strip()
            continue
        if line.strip() == "---":
            continue
        if line.startswith("## "):
            cur = {"title": line[3:].strip(), "items": [], "notes": [], "groups": []}
            doc["sections"].append(cur)
            item = None
            continue
        if line.startswith("### ") and cur is not None:
            cur["groups"].append({"title": line[4:].strip(), "notes": []})
            item = None
            prev_blank = True
            continue
        if not line.strip():
            item = None
            prev_blank = True
            continue
        was_blank, prev_blank = prev_blank, False
        target = (cur["groups"][-1]["notes"] if cur["groups"] else cur["notes"]) if cur else doc["intro"]
        m = re.match(r"^- \[( |x)\] (.*)$", line)
        if m and cur is not None:
            text = m.group(2)
            head, diff = (text.rsplit(" · ", 1) + [""])[:2] if " · " in text else (text, "")
            item = {"done": m.group(1) == "x", "title": inline(head), "diff": diff.strip(),
                    "level": level(diff) if diff else "other", "desc": [], "doneWhen": "",
                    "g": len(cur["groups"]) - 1}
            cur["items"].append(item)
            continue
        if item is not None and line.startswith("  "):
            t = line.strip()
            if t.startswith("Xong khi:"):
                item["doneWhen"] = inline(t[len("Xong khi:"):].strip())
            else:
                item["desc"].append(inline(t))
            continue
        item = None
        if line.startswith("- "):
            target.append({"kind": "li", "html": inline(line[2:].strip())})
        elif line.startswith("  ") and target and target[-1]["kind"] == "li":
            target[-1]["html"] += " " + inline(line.strip())
        elif not was_blank and target and target[-1]["kind"] == "p":
            target[-1]["html"] += " " + inline(line.strip())   # dong xuong dong cua cung mot doan
        else:
            target.append({"kind": "p", "html": inline(line.strip())})
    return doc


PAGE = r"""<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OmniCar Roadmap</title>
<!-- Sinh tu ROADMAP.md bang tools/roadmap_html.py - dung sua tay, sua ROADMAP.md roi chay lai script. -->
<style>
:root {
  --bg: #f1f3f5; --card: #fff; --text: #0f1115; --sub: #5f6672; --sep: rgba(60,60,67,.14);
  --chip: rgba(120,120,128,.12); --accent: #1f2329; --bar: #1f2329;
  --low: #1e8e5a; --mid: #b7791f; --high: #c53030; --other: #6b7280;
  --hero1: #353a43; --hero2: #101216;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #000; --card: #1c1c1e; --text: #f2f3f5; --sub: #9aa1ab; --sep: rgba(84,84,88,.55);
    --chip: rgba(120,120,128,.24); --accent: #e9ebee; --bar: #e9ebee;
    --low: #4cc38a; --mid: #e3b341; --high: #ff6b6b; --other: #9aa1ab;
  }
}
:root[data-theme="dark"] {
  --bg: #000; --card: #1c1c1e; --text: #f2f3f5; --sub: #9aa1ab; --sep: rgba(84,84,88,.55);
  --chip: rgba(120,120,128,.24); --accent: #e9ebee; --bar: #e9ebee;
  --low: #4cc38a; --mid: #e3b341; --high: #ff6b6b; --other: #9aa1ab;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--text);
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
code { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--chip); padding: 1px 5px; border-radius: 5px; }
.wrap { max-width: 920px; margin: 0 auto; padding: 20px 16px 60px; }

.hero { border-radius: 22px; padding: 22px; color: #fff; background: linear-gradient(180deg, var(--hero1), var(--hero2));
  box-shadow: inset 0 0 0 .5px rgba(255,255,255,.22), 0 10px 24px rgba(0,0,0,.18); position: relative; overflow: hidden; }
.hero::before { content: ""; position: absolute; inset: 0 0 50% 0; background: linear-gradient(180deg, rgba(255,255,255,.08), transparent); pointer-events: none; }
.hero h1 { margin: 0 0 4px; font-size: 26px; }
.hero .goal { color: rgba(255,255,255,.8); margin: 0 0 16px; }
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 10px; }
.stat { background: rgba(255,255,255,.08); border-radius: 14px; padding: 10px 12px; }
.stat .n { font-size: 22px; font-weight: 700; font-variant-numeric: tabular-nums; }
.stat .l { font-size: 12.5px; color: rgba(255,255,255,.7); }
.track { height: 6px; border-radius: 3px; background: rgba(255,255,255,.15); overflow: hidden; margin-top: 14px; }
.track i { display: block; height: 100%; background: #fff; border-radius: 3px; transition: width .3s; }

.intro { margin: 18px 4px 0; color: var(--sub); font-size: 14px; }
.intro p { margin: 6px 0; }
.intro ul { margin: 6px 0; padding-left: 20px; }

.tools { position: sticky; top: 0; z-index: 5; background: var(--bg); padding: 12px 0; margin-top: 8px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.tools input[type=search] { flex: 1 1 200px; min-width: 0; border: 0; border-radius: 10px; padding: 9px 12px; background: var(--chip); color: var(--text); font: inherit; outline: none; }
.chipbtn { border: 0; border-radius: 16px; padding: 7px 12px; background: var(--chip); color: var(--text); font: inherit; font-size: 13.5px; cursor: pointer; }
.chipbtn.on { background: var(--accent); color: var(--bg); }
.chipbtn .dot { display: inline-block; width: 8px; height: 8px; border-radius: 4px; margin-right: 6px; vertical-align: 1px; }

.nav { display: flex; gap: 6px; overflow-x: auto; padding-bottom: 4px; scrollbar-width: none; }
.nav a { flex: none; text-decoration: none; color: var(--sub); font-size: 13px; background: var(--chip); border-radius: 14px; padding: 5px 10px; }

.sec { margin-top: 26px; }
.sec h2 { font-size: 18px; margin: 0 4px 4px; display: flex; justify-content: space-between; gap: 12px; align-items: baseline; }
.sec h2 .pct { font-size: 13px; color: var(--sub); font-weight: 500; font-variant-numeric: tabular-nums; flex: none; }
.sec .bar { height: 4px; border-radius: 2px; background: var(--chip); margin: 6px 4px 10px; overflow: hidden; }
.sec .bar i { display: block; height: 100%; background: var(--bar); transition: width .3s; }
.notes { margin: 0 4px 10px; color: var(--sub); font-size: 14px; }
.notes p { margin: 4px 0; }
.notes ul { margin: 4px 0; padding-left: 20px; }
.card { background: var(--card); border-radius: 16px; overflow: hidden; }
.item { display: flex; gap: 12px; padding: 13px 14px; }
.item + .item { border-top: .5px solid var(--sep); }
.item.hide { display: none; }
.check { flex: none; width: 22px; height: 22px; border-radius: 11px; border: 2px solid var(--sub); margin-top: 1px; cursor: pointer; display: grid; place-items: center; background: none; padding: 0; }
.check svg { width: 13px; height: 13px; opacity: 0; }
.item.done .check { background: var(--accent); border-color: var(--accent); }
.item.done .check svg { opacity: 1; color: var(--bg); }
.item.done .t { color: var(--sub); text-decoration: line-through; }
.body { flex: 1; min-width: 0; }
.row1 { display: flex; gap: 10px; align-items: flex-start; justify-content: space-between; }
.t { font-weight: 500; }
.diff { flex: none; font-size: 12px; font-weight: 600; border-radius: 10px; padding: 2px 9px; white-space: nowrap; }
.diff.low { color: var(--low); background: color-mix(in srgb, var(--low) 14%, transparent); }
.diff.mid { color: var(--mid); background: color-mix(in srgb, var(--mid) 14%, transparent); }
.diff.high { color: var(--high); background: color-mix(in srgb, var(--high) 14%, transparent); }
.diff.other { color: var(--other); background: var(--chip); }
.d { color: var(--sub); font-size: 14px; margin-top: 3px; }
.dw { font-size: 13.5px; margin-top: 6px; padding: 7px 10px; border-radius: 10px; background: var(--chip); }
.dw b { font-weight: 600; }
.local { font-size: 12px; color: var(--sub); margin-left: 6px; }
.grp { padding: 14px 14px 8px; background: var(--chip); }
.grp + .item { border-top: 0; }
.item + .grp { border-top: .5px solid var(--sep); }
.grp .gt { font-size: 13px; font-weight: 700; letter-spacing: .3px; text-transform: uppercase; color: var(--sub); }
.grp .gn { font-size: 13.5px; color: var(--sub); margin-top: 3px; }
.grp .gn p { margin: 2px 0; }
.grp.hide { display: none; }
.empty { padding: 14px; color: var(--sub); font-size: 14px; display: none; }
.foot { margin-top: 30px; color: var(--sub); font-size: 12.5px; text-align: center; }
@media (max-width: 520px) { .row1 { flex-direction: column; gap: 4px; } .hero { padding: 18px; } .hero h1 { font-size: 22px; } }
</style>
</head>
<body>
<div class="wrap">
  <div class="hero">
    <h1 id="title"></h1>
    <p class="goal" id="goal"></p>
    <div class="stats" id="stats"></div>
    <div class="track"><i id="total-bar"></i></div>
  </div>
  <div class="intro" id="intro"></div>
  <div class="tools">
    <input type="search" id="q" placeholder="Tìm tính năng…">
    <button class="chipbtn on" data-lv="all">Tất cả</button>
    <button class="chipbtn" data-lv="low"><span class="dot" style="background:var(--low)"></span>Thấp</button>
    <button class="chipbtn" data-lv="mid"><span class="dot" style="background:var(--mid)"></span>Vừa</button>
    <button class="chipbtn" data-lv="high"><span class="dot" style="background:var(--high)"></span>Cao</button>
    <button class="chipbtn" id="hide-done">Ẩn mục đã xong</button>
    <button class="chipbtn" id="theme" title="Đổi giao diện sáng / tối">◐</button>
  </div>
  <nav class="nav" id="nav"></nav>
  <div id="secs"></div>
  <p class="foot">Sinh từ ROADMAP.md · <span id="gen"></span> · Tick trên trang chỉ lưu tạm trong trình duyệt; đánh <code>[x]</code> trong ROADMAP.md để lưu thật.</p>
</div>
<script>
const DOC = __DATA__;
const GEN = __GEN__;
const $ = s => document.querySelector(s);
const TICK = '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 7.5l3 3 6-7"/></svg>';
const KEY = 'omnicar-roadmap-local';
let local = {};
try { local = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) {}
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(local)); } catch (e) {} };
const state = { lv: 'all', q: '', hideDone: false };
const strip = h => h.replace(/<[^>]+>/g, '');
const idOf = (si, ii) => si + ':' + strip(DOC.sections[si].items[ii].title);
const isDone = (si, ii) => { const id = idOf(si, ii); return id in local ? local[id] : DOC.sections[si].items[ii].done; };

$('#title').textContent = DOC.title;
$('#gen').textContent = GEN;
// Dong "Muc tieu: ..." dau tien len the dau trang, phan con lai cua phan gioi thieu dat ben duoi
const intro = DOC.intro.slice();
const gi = intro.findIndex(b => b.kind === 'p' && strip(b.html).startsWith('Mục tiêu'));
if (gi >= 0) {
  let goal = intro[gi].html; intro.splice(gi, 1);
  while (intro[gi] && intro[gi].kind === 'p' && !/^(Cách dùng|Đã có)/.test(strip(intro[gi].html))) { goal += ' ' + intro[gi].html; intro.splice(gi, 1); }
  goal = goal.replace(/^Mục tiêu:\s*/, '');
  $('#goal').innerHTML = goal.charAt(0).toUpperCase() + goal.slice(1);
}
const blocks = list => { let h = '', ul = false;
  for (const b of list) {
    if (b.kind === 'li') { if (!ul) { h += '<ul>'; ul = true; } h += '<li>' + b.html + '</li>'; }
    else { if (ul) { h += '</ul>'; ul = false; } h += '<p>' + b.html + '</p>'; }
  }
  return h + (ul ? '</ul>' : ''); };
$('#intro').innerHTML = blocks(intro);

const short = t => t.replace(/^Giai đoạn (\d+)\s*–\s*/, 'GĐ $1 · ').replace(/^Mức (\d+)\s*–\s*/, 'Mức $1 · ').replace(/^Phát hành (\d+)\s*–\s*/, 'PH $1 · ').replace(/\s*\(.*\)$/, '');
$('#nav').innerHTML = DOC.sections.map((s, si) => `<a href="#s${si}">${short(s.title)}</a>`).join('');
$('#secs').innerHTML = DOC.sections.map((s, si) => `
  <section class="sec" id="s${si}">
    <h2><span>${s.title}</span>${s.items.length ? `<span class="pct" id="p${si}"></span>` : ''}</h2>
    ${s.items.length ? `<div class="bar"><i id="b${si}"></i></div>` : ''}
    ${s.notes.length ? `<div class="notes">${blocks(s.notes)}</div>` : ''}
    ${s.items.length ? `<div class="card">${s.items.map((it, ii) => `${it.g >= 0 && (ii === 0 || s.items[ii - 1].g !== it.g) ? `
      <div class="grp" data-s="${si}" data-g="${it.g}"><div class="gt">${s.groups[it.g].title}</div>${s.groups[it.g].notes.length ? `<div class="gn">${blocks(s.groups[it.g].notes)}</div>` : ''}</div>` : ''}
      <div class="item" data-s="${si}" data-i="${ii}" data-g="${it.g}" data-lv="${it.level}">
        <button class="check" aria-label="Đánh dấu xong">${TICK}</button>
        <div class="body">
          <div class="row1"><div class="t">${it.title}</div>${it.diff ? `<span class="diff ${it.level}">${it.diff}</span>` : ''}</div>
          ${it.desc.map(d => `<div class="d">${d}</div>`).join('')}
          ${it.doneWhen ? `<div class="dw"><b>Xong khi:</b> ${it.doneWhen}</div>` : ''}
        </div>
      </div>`).join('')}<div class="empty">Không có mục nào khớp bộ lọc.</div></div>` : ''}
  </section>`).join('');

function refresh() {
  let all = 0, done = 0; const by = { low: 0, mid: 0, high: 0 };
  DOC.sections.forEach((s, si) => {
    if (!s.items.length) return;
    let d = 0, shown = 0; const gShown = {};
    s.items.forEach((it, ii) => {
      const el = document.querySelector(`.item[data-s="${si}"][data-i="${ii}"]`);
      const ok = isDone(si, ii); if (ok) d++;
      el.classList.toggle('done', ok);
      const id = idOf(si, ii);
      const t = el.querySelector('.t'); const tag = t.querySelector('.local');
      if (id in local && local[id] !== it.done) { if (!tag) t.insertAdjacentHTML('beforeend', '<span class="local">(tạm)</span>'); } else if (tag) tag.remove();
      const text = el.textContent.toLowerCase();
      const vis = (state.lv === 'all' || it.level === state.lv) && (!state.q || text.includes(state.q)) && !(state.hideDone && ok);
      el.classList.toggle('hide', !vis); if (vis) { shown++; gShown[it.g] = 1; }
      if (!ok && by[it.level] !== undefined) by[it.level]++;
    });
    document.querySelector(`#s${si} .empty`).style.display = shown ? 'none' : 'block';
    document.querySelectorAll(`.grp[data-s="${si}"]`).forEach(g => g.classList.toggle('hide', !gShown[g.dataset.g]));
    const pct = Math.round(d / s.items.length * 100);
    $('#p' + si).textContent = `${d}/${s.items.length} · ${pct}%`;
    $('#b' + si).style.width = pct + '%';
    all += s.items.length; done += d;
  });
  $('#total-bar').style.width = (all ? done / all * 100 : 0) + '%';
  $('#stats').innerHTML = [[done + '/' + all, 'Đã xong'], [by.low, 'Còn lại · Thấp'], [by.mid, 'Còn lại · Vừa'], [by.high, 'Còn lại · Cao']]
    .map(([n, l]) => `<div class="stat"><div class="n">${n}</div><div class="l">${l}</div></div>`).join('');
}

document.addEventListener('click', e => {
  const c = e.target.closest('.check');
  if (c) { const it = c.closest('.item'), si = +it.dataset.s, ii = +it.dataset.i, id = idOf(si, ii);
    const next = !isDone(si, ii); if (next === DOC.sections[si].items[ii].done) delete local[id]; else local[id] = next; save(); refresh(); return; }
  const lv = e.target.closest('[data-lv]');
  if (lv && lv.classList.contains('chipbtn')) { state.lv = lv.dataset.lv; document.querySelectorAll('.chipbtn[data-lv]').forEach(b => b.classList.toggle('on', b === lv)); refresh(); }
});
$('#q').addEventListener('input', e => { state.q = e.target.value.trim().toLowerCase(); refresh(); });
$('#hide-done').addEventListener('click', e => { state.hideDone = !state.hideDone; e.target.classList.toggle('on', state.hideDone); refresh(); });
$('#theme').addEventListener('click', () => {
  const root = document.documentElement, dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  root.dataset.theme = dark ? 'light' : 'dark';
});
refresh();
</script>
</body>
</html>
"""


def main():
    md = io.open(SRC, encoding="utf-8").read()
    doc = parse(md)
    import datetime
    data = json.dumps(doc, ensure_ascii=False).replace("</", "<\\/")
    page = PAGE.replace("__DATA__", data).replace("__GEN__", json.dumps(datetime.date.today().isoformat()))
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(page)
    n = sum(len(s["items"]) for s in doc["sections"])
    print("ROADMAP.html: %d giai doan / muc, %d tinh nang" % (len(doc["sections"]), n))


if __name__ == "__main__":
    main()
