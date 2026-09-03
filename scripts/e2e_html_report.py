#!/usr/bin/env python3
"""Build an HTML E2E report from suite logs + case catalog."""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
RESULT_RE = re.compile(
    r"^(PASS|FAIL|SKIP)\s+(.+?)(?:\s+[—–-]\s+(.+))?$"
)


def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)


def parse_results(log_text: str) -> list[dict]:
    """Parse PASS/FAIL/SKIP lines (prefer Summary block if present)."""
    lines = [strip_ansi(l).rstrip() for l in log_text.splitlines()]
    results: list[dict] = []
    in_summary = False
    for line in lines:
        if line.strip() == "==> Summary":
            in_summary = True
            results = []
            continue
        if in_summary and line.startswith("Passed:"):
            break
        if in_summary or line.startswith(("PASS  ", "FAIL  ", "SKIP  ")):
            m = RESULT_RE.match(line.strip())
            if not m:
                continue
            status, message, detail = m.group(1), m.group(2).strip(), (m.group(3) or "").strip()
            results.append(
                {
                    "status": status,
                    "message": message,
                    "detail": detail,
                    "raw": line.strip(),
                }
            )
    # Deduplicate while keeping order (summary preferred already)
    seen = set()
    out = []
    for r in results:
        key = (r["status"], r["message"], r["detail"])
        if key in seen:
            continue
        seen.add(key)
        out.append(r)
    return out


def match_case(message: str, cases: list[dict]) -> dict | None:
    msg = message.lower()
    best = None
    best_len = -1
    for case in cases:
        for pat in case.get("match", []):
            p = pat.lower()
            if p in msg and len(p) > best_len:
                best = case
                best_len = len(p)
    return best


def load_catalog(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def build_report(
    *,
    catalog: dict,
    suite_logs: dict[str, str],
    meta: dict,
) -> str:
    cases = catalog.get("cases", [])
    manual = catalog.get("manual", [])
    suites = catalog.get("suites", {})

    all_results: list[dict] = []
    for suite_id, log in suite_logs.items():
        for r in parse_results(log):
            r["suite"] = suite_id
            matched = match_case(r["message"], [c for c in cases if c.get("suite") == suite_id] or cases)
            r["case"] = matched
            all_results.append(r)

    # Unmatched catalog cases → not_run
    matched_ids = {r["case"]["id"] for r in all_results if r.get("case")}
    not_run = [c for c in cases if c["id"] not in matched_ids]

    pass_n = sum(1 for r in all_results if r["status"] == "PASS")
    fail_n = sum(1 for r in all_results if r["status"] == "FAIL")
    skip_n = sum(1 for r in all_results if r["status"] == "SKIP")

    def esc(s: str) -> str:
        return html.escape(s or "")

    def status_badge(st: str) -> str:
        return f'<span class="badge {st.lower()}">{esc(st)}</span>'

    cards = []
    for i, r in enumerate(all_results, 1):
        case = r.get("case")
        title = case["title"] if case else r["message"]
        cid = case["id"] if case else f"AUTO-{i}"
        steps = case.get("steps", []) if case else ["(See raw result — no catalog match)"]
        expected = case.get("expected", "") if case else ""
        suite_title = suites.get(r["suite"], {}).get("title", r["suite"])
        steps_html = "".join(f"<li>{esc(s)}</li>" for s in steps)
        detail_html = f'<p class="detail"><strong>Detail:</strong> {esc(r["detail"])}</p>' if r["detail"] else ""
        cards.append(
            f"""
<article class="case {r['status'].lower()}" id="{esc(cid)}-{i}">
  <header>
    <div class="ids"><span class="id">{esc(cid)}</span> {status_badge(r['status'])}</div>
    <h2>{esc(title)}</h2>
    <p class="suite">{esc(suite_title)}</p>
  </header>
  <section>
    <h3>Steps</h3>
    <ol class="steps">{steps_html}</ol>
  </section>
  <section>
    <h3>Expected</h3>
    <p>{esc(expected) if expected else "—"}</p>
  </section>
  <section>
    <h3>Result</h3>
    <p class="raw"><code>{esc(r['raw'])}</code></p>
    {detail_html}
  </section>
</article>
"""
        )

    not_run_html = ""
    if not_run:
        items = "".join(
            f"<li><strong>{esc(c['id'])}</strong> — {esc(c['title'])}</li>" for c in not_run
        )
        not_run_html = f"""
<section class="panel">
  <h2>Catalog cases not matched in this run</h2>
  <ul>{items}</ul>
</section>
"""

    manual_cards = []
    for m in manual:
        steps_html = "".join(f"<li>{esc(s)}</li>" for s in m.get("steps", []))
        manual_cards.append(
            f"""
<article class="case manual">
  <header>
    <div class="ids"><span class="id">{esc(m['id'])}</span> <span class="badge manual">MANUAL</span></div>
    <h2>{esc(m['title'])}</h2>
  </header>
  <section>
    <h3>Steps</h3>
    <ol class="steps">{steps_html}</ol>
  </section>
  <section>
    <h3>Expected</h3>
    <p>{esc(m.get('expected', ''))}</p>
  </section>
</article>
"""
        )

    log_panels = []
    for suite_id, log in suite_logs.items():
        title = suites.get(suite_id, {}).get("title", suite_id)
        log_panels.append(
            f"""
<details class="log">
  <summary>Raw log — {esc(title)}</summary>
  <pre>{esc(strip_ansi(log))}</pre>
</details>
"""
        )

    generated = meta.get("generated") or datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    overall = "PASS" if fail_n == 0 else "FAIL"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Oz Downloader E2E Report — {esc(overall)}</title>
<style>
  :root {{
    --bg: #0f1419;
    --panel: #1a222c;
    --text: #e7ecf1;
    --muted: #9aa7b5;
    --pass: #1f8f5f;
    --fail: #c23b3b;
    --skip: #b0862a;
    --manual: #4a6fa5;
    --line: #2a3542;
    --accent: #5b9fd4;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; font-family: "SF Pro Text", "Segoe UI", system-ui, sans-serif;
    background: linear-gradient(165deg, #0b1015 0%, #15202b 50%, #0f1419 100%);
    color: var(--text); line-height: 1.45;
  }}
  header.hero {{
    padding: 2rem clamp(1rem, 4vw, 3rem) 1.25rem;
    border-bottom: 1px solid var(--line);
    background: radial-gradient(ellipse at top left, rgba(91,159,212,.18), transparent 55%);
  }}
  header.hero h1 {{ margin: 0 0 .35rem; font-size: clamp(1.6rem, 3vw, 2.2rem); letter-spacing: -0.02em; }}
  header.hero .meta {{ color: var(--muted); font-size: .95rem; }}
  .stats {{
    display: flex; flex-wrap: wrap; gap: .75rem; margin-top: 1.25rem;
  }}
  .stat {{
    background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
    padding: .75rem 1rem; min-width: 7rem;
  }}
  .stat b {{ display: block; font-size: 1.4rem; }}
  .stat.pass b {{ color: #3dd68c; }}
  .stat.fail b {{ color: #ff7b7b; }}
  .stat.skip b {{ color: #e6c35c; }}
  main {{ padding: 1.5rem clamp(1rem, 4vw, 3rem) 3rem; }}
  .grid {{ display: grid; gap: 1rem; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); }}
  article.case {{
    background: var(--panel); border: 1px solid var(--line); border-radius: 14px;
    padding: 1rem 1.1rem 1.15rem; display: flex; flex-direction: column; gap: .65rem;
  }}
  article.case.pass {{ border-left: 4px solid var(--pass); }}
  article.case.fail {{ border-left: 4px solid var(--fail); }}
  article.case.skip {{ border-left: 4px solid var(--skip); }}
  article.case.manual {{ border-left: 4px solid var(--manual); opacity: .92; }}
  article.case h2 {{ margin: 0; font-size: 1.05rem; }}
  article.case h3 {{ margin: 0 0 .35rem; font-size: .78rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); }}
  .ids {{ display: flex; align-items: center; gap: .5rem; margin-bottom: .35rem; }}
  .id {{
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .78rem;
    background: #0d1218; border: 1px solid var(--line); padding: .15rem .45rem; border-radius: 6px;
    color: var(--accent);
  }}
  .badge {{
    font-size: .7rem; font-weight: 700; letter-spacing: .04em; padding: .2rem .45rem;
    border-radius: 999px; color: #fff;
  }}
  .badge.pass {{ background: var(--pass); }}
  .badge.fail {{ background: var(--fail); }}
  .badge.skip {{ background: var(--skip); }}
  .badge.manual {{ background: var(--manual); }}
  .suite {{ margin: .15rem 0 0; color: var(--muted); font-size: .85rem; }}
  ol.steps {{ margin: 0; padding-left: 1.2rem; }}
  ol.steps li {{ margin: .2rem 0; }}
  .raw code {{
    display: block; white-space: pre-wrap; word-break: break-word;
    background: #0d1218; border-radius: 8px; padding: .55rem .7rem; font-size: .82rem;
  }}
  .detail {{ color: var(--muted); font-size: .9rem; margin: .4rem 0 0; }}
  .panel {{
    margin-top: 2rem; background: var(--panel); border: 1px solid var(--line);
    border-radius: 14px; padding: 1rem 1.25rem;
  }}
  details.log {{ margin-top: 1rem; }}
  details.log summary {{ cursor: pointer; color: var(--accent); margin-bottom: .5rem; }}
  details.log pre {{
    max-height: 420px; overflow: auto; background: #0d1218; padding: 1rem;
    border-radius: 10px; font-size: .75rem; line-height: 1.35;
  }}
  h2.section {{ margin: 2rem 0 1rem; font-size: 1.25rem; }}
</style>
</head>
<body>
<header class="hero">
  <h1>Oz Downloader E2E Report</h1>
  <p class="meta">Generated {esc(generated)} · Overall <strong>{esc(overall)}</strong></p>
  <p class="meta">App: {esc(meta.get('app', ''))}<br/>Host: {esc(meta.get('host', ''))}</p>
  <div class="stats">
    <div class="stat pass"><b>{pass_n}</b>Passed</div>
    <div class="stat fail"><b>{fail_n}</b>Failed</div>
    <div class="stat skip"><b>{skip_n}</b>Skipped</div>
    <div class="stat"><b>{len(all_results)}</b>Automated results</div>
    <div class="stat"><b>{len(manual)}</b>Manual cases</div>
  </div>
</header>
<main>
  <h2 class="section">Automated cases</h2>
  <div class="grid">
    {''.join(cards) if cards else '<p>No automated results parsed.</p>'}
  </div>
  {not_run_html}
  <h2 class="section">Manual cases (not executed by this runner)</h2>
  <div class="grid">
    {''.join(manual_cards)}
  </div>
  <section class="panel">
    <h2>Suite logs</h2>
    {''.join(log_panels)}
  </section>
</main>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--smoke-log", type=Path)
    ap.add_argument("--downloads-log", type=Path)
    ap.add_argument("--ui-log", type=Path)
    ap.add_argument("--app", default="")
    ap.add_argument("--host", default="")
    args = ap.parse_args()

    catalog = load_catalog(args.catalog)
    suite_logs: dict[str, str] = {}
    if args.smoke_log and args.smoke_log.exists():
        suite_logs["smoke"] = args.smoke_log.read_text(encoding="utf-8", errors="replace")
    if args.downloads_log and args.downloads_log.exists():
        suite_logs["downloads"] = args.downloads_log.read_text(encoding="utf-8", errors="replace")
    if args.ui_log and args.ui_log.exists():
        suite_logs["ui"] = args.ui_log.read_text(encoding="utf-8", errors="replace")

    html_out = build_report(
        catalog=catalog,
        suite_logs=suite_logs,
        meta={
            "generated": datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z"),
            "app": args.app,
            "host": args.host,
        },
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html_out, encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
