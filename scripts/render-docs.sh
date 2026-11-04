#!/usr/bin/env bash
# Export submission documents to PDF and report page counts.
# Usage: scripts/render-docs.sh   (needs .venv with markdown, google-chrome)
set -euo pipefail
OUT="${OUT:-docs/pdf}"; mkdir -p "$OUT"
for spec in architecture:9.2 change-request-us:8.6; do
  doc=${spec%%:*}; font=${spec##*:}
  .venv/bin/python scripts/render-docs.py "docs/$doc.md" "$OUT/$doc.html" "$font"
  google-chrome --headless=new --disable-gpu --no-sandbox --user-data-dir="$(mktemp -d)" --no-first-run --no-pdf-header-footer --virtual-time-budget=15000 \
    --print-to-pdf="$PWD/$OUT/$doc.pdf" "file://$PWD/$OUT/$doc.html" 2>/dev/null
  pages=$(python3 -c "import re,sys;d=open(sys.argv[1],'rb').read();print(len(re.findall(rb'/Type\s*/Page[^s]',d)))" "$OUT/$doc.pdf")
  echo "$doc.pdf pages=$pages"
  rm -f "$OUT/$doc.html"
done
