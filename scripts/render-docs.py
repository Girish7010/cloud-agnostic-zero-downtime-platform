#!/usr/bin/env python3
"""Render a Markdown doc to a print-ready HTML file (A4, 10pt) with Mermaid
diagrams, for PDF export via headless Chrome (scripts/render-docs.sh).
Requires: pip install markdown==3.10"""
import re, sys, markdown

src, out = sys.argv[1], sys.argv[2]
font = sys.argv[3] if len(sys.argv) > 3 else "9.2"
text = open(src, encoding="utf-8").read()
# Turn ```mermaid blocks into <div class="mermaid"> so mermaid.js renders them.
blocks = []
def keep(m):
    blocks.append(m.group(1))
    return f"MERMAIDBLOCK{len(blocks)-1}"
# Python-Markdown (unlike GitHub) needs a blank line before a list.
lines, prev = [], ""
for line in text.split("\n"):
    is_item = re.match(r"\s*([-*]|\d+\.)\s", line)
    prev_item = re.match(r"\s*([-*]|\d+\.)\s", prev)
    if is_item and prev.strip() and not prev_item and not prev.startswith("|"):
        lines.append("")
    lines.append(line); prev = line
text = "\n".join(lines)
# Nested items: GitHub accepts 2-space indents, Python-Markdown needs 4.
text = re.sub(r"(?m)^  ([-*]|\d+\.) ", r"    \1 ", text)
text = re.sub(r"```mermaid\n(.*?)```", keep, text, flags=re.S)
html = markdown.markdown(text, extensions=["tables", "fenced_code"])
for i, b in enumerate(blocks):
    html = html.replace(f"<p>MERMAIDBLOCK{i}</p>", f'<div class="mermaid">{b}</div>')
open(out, "w", encoding="utf-8").write(f"""<!doctype html><html><head><meta charset="utf-8">
<style>
@page {{ size: A4; margin: 14mm 13mm; }}
body {{ font-family: "DejaVu Sans", Arial, sans-serif; font-size: {font}pt; line-height: 1.3; color:#111; }}
h1 {{ font-size: 15pt; margin: 0 0 4px; }} h2 {{ font-size: 11.5pt; margin: 10px 0 4px; border-bottom: 1px solid #ccc; }}
table {{ border-collapse: collapse; width: 100%; margin: 4px 0; font-size: 8.4pt; }}
th, td {{ border: 1px solid #bbb; padding: 2px 4px; vertical-align: top; }} th {{ background:#eee; }}
code {{ font-size: 8.2pt; }} pre {{ font-size: 8pt; }} p, ul, ol {{ margin: 3px 0; }} li {{ margin: 0; }} blockquote {{ margin: 4px 0; padding: 2px 8px; border-left: 3px solid #999; background:#f6f6f6; }}
.mermaid {{ text-align: center; margin: 4px 0; }} .mermaid svg {{ width: 100%; height: auto; max-height: 420px; }}
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
<script>mermaid.initialize({{startOnLoad:true, theme:'neutral', flowchart:{{useMaxWidth:true}}}});</script>
</head><body>{html}</body></html>""")
