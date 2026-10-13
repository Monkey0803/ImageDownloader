#!/usr/bin/env bash
# card.sh <file> <name> <subtitle> <viewport> <group> — writes the card header and
# leaves stdin to be appended as the body. Keeps the 18 cards consistent.
set -euo pipefail
f="$1"; name="$2"; sub="$3"; vp="$4"; grp="${5:-Foundations}"
{
  printf '<!-- @dsCard group="%s" viewport="%s" name="%s" subtitle="%s" -->\n' "$grp" "$vp" "$name" "$sub"
  cat <<EOF
<!DOCTYPE html>
<html lang="zh-CN" data-theme="light">
<head>
<meta charset="UTF-8">
<title>${name}</title>
<link rel="stylesheet" href="../styles.css">
</head>
<body class="hm-host">
<div class="hm-spec">
EOF
  cat
  cat <<'EOF'
</div>
</body>
</html>
EOF
} > "$f"
echo "  + guidelines/$f"
