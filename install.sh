#!/usr/bin/env bash
# performance-engineering-skill installer (curl | bash)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Ziad-Abaza/performance-engineering-skill/main/install.sh | bash
#   ... | bash -s -- --project          # install into ./.agents/skills
#   ... | bash -s -- --claude           # install into ~/.claude/skills
#   ... | bash -s -- --dir /custom/path
#
set -euo pipefail

REPO="https://github.com/Ziad-Abaza/performance-engineering-skill"
SKILL_NAME="performance-engineering"
MODE="global"
CUSTOM_DIR=""

for arg in "$@"; do
    case "$arg" in
        --project) MODE="project" ;;
        --claude)  MODE="claude" ;;
        --dir=*)   MODE="custom"; CUSTOM_DIR="${arg#--dir=}" ;;
        --dir)     MODE="custom-next" ;;
        *) if [ "${MODE:-}" = "custom-next" ]; then MODE="custom"; CUSTOM_DIR="$arg"; fi ;;
    esac
done

case "$MODE" in
    global)  TARGET="${HOME}/.agents/skills/${SKILL_NAME}" ;;
    project) TARGET="$(pwd)/.agents/skills/${SKILL_NAME}" ;;
    claude)  TARGET="${HOME}/.claude/skills/${SKILL_NAME}" ;;
    custom)  TARGET="${CUSTOM_DIR%/}" ;;
    *) echo "error: could not resolve target directory" >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO.git" "$TMP/repo" --quiet
    SRC="$TMP/repo"
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" -o "$TMP/pkg.tar.gz"
    tar -xzf "$TMP/pkg.tar.gz" -C "$TMP"
    SRC="$TMP/performance-engineering-skill-main"
else
    echo "error: need git or curl to download" >&2; exit 1
fi

for required in SKILL.md references scripts templates; do
    [ -e "$SRC/$required" ] || { echo "error: missing $required in download" >&2; exit 1; }
done

# Copy only the functional payload — repo-level files (README.md, LICENSE,
# package.json, install.sh) stay out of the skills directory.
mkdir -p "$TARGET"
cp -f "$SRC/SKILL.md" "$TARGET/"
cp -rf "$SRC/references" "$SRC/scripts" "$SRC/templates" "$TARGET/"

echo ""
echo "performance-engineering skill installed to:"
echo "  $TARGET"
echo ""
echo "Restart your agent session, then try: \"Audit this page for performance issues.\""
