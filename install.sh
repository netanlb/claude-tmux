#!/usr/bin/env bash
# claude-tmux installer.
# - copies the picker script to ~/.tmux/
# - source-files the tmux conf snippet from your ~/.tmux.conf
# - merges the Claude Code hooks into ~/.claude/settings.json
# Re-runnable; idempotent.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_DIR="$HOME/.tmux"
TMUX_CONF="$HOME/.tmux.conf"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
SOURCE_LINE="source-file $REPO_DIR/tmux/claude-tmux.conf"

c_red()    { printf '\033[31m%s\033[0m' "$1"; }
c_green()  { printf '\033[32m%s\033[0m' "$1"; }
c_yellow() { printf '\033[33m%s\033[0m' "$1"; }
c_dim()    { printf '\033[2m%s\033[0m' "$1"; }

step()  { printf '%s %s\n' "$(c_green '▸')" "$1"; }
warn()  { printf '%s %s\n' "$(c_yellow '!')" "$1"; }
fail()  { printf '%s %s\n' "$(c_red '✗')" "$1" >&2; exit 1; }
info()  { printf '  %s\n' "$(c_dim "$1")"; }

# --- 1. Dependency check ------------------------------------------------------

REQUIRED=(tmux fzf jq)
MISSING=()
for dep in "${REQUIRED[@]}"; do
    command -v "$dep" >/dev/null 2>&1 || MISSING+=("$dep")
done

if (( ${#MISSING[@]} > 0 )); then
    warn "Missing dependencies: ${MISSING[*]}"
    if command -v brew >/dev/null 2>&1; then
        printf 'Install via Homebrew now? [y/N] '
        read -n 1 -r ans
        echo
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
            brew install "${MISSING[@]}"
        else
            fail "Aborted. Install manually: brew install ${MISSING[*]}"
        fi
    else
        fail "Homebrew not found. Install ${MISSING[*]} manually before re-running."
    fi
fi

# --- 2. Picker script ---------------------------------------------------------

step "Installing picker script → $TMUX_DIR/claude-session-picker.sh"
mkdir -p "$TMUX_DIR"
cp "$REPO_DIR/tmux/claude-session-picker.sh" "$TMUX_DIR/claude-session-picker.sh"
chmod +x "$TMUX_DIR/claude-session-picker.sh"

# --- 3. ~/.tmux.conf source-file ----------------------------------------------

step "Wiring tmux bindings"
if [[ -f "$TMUX_CONF" ]] && grep -Fq "$SOURCE_LINE" "$TMUX_CONF"; then
    info "$TMUX_CONF already sources $REPO_DIR/tmux/claude-tmux.conf"
else
    {
        [[ -f "$TMUX_CONF" ]] && echo ""
        echo "# claude-tmux"
        echo "$SOURCE_LINE"
    } >> "$TMUX_CONF"
    info "Added source-file line to $TMUX_CONF"
fi

if command -v tmux >/dev/null && tmux info >/dev/null 2>&1; then
    tmux source-file "$TMUX_CONF" && info "Reloaded tmux config"
fi

# --- 4. Claude Code hooks merge ----------------------------------------------

step "Merging Claude Code hooks into $CLAUDE_SETTINGS"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo '{}' > "$CLAUDE_SETTINGS"
    info "Created empty $CLAUDE_SETTINGS"
fi

# Back up before mutating.
BACKUP="$CLAUDE_SETTINGS.bak.$(date +%s)"
cp "$CLAUDE_SETTINGS" "$BACKUP"
info "Backup: $BACKUP"

# Deep-merge: existing.hooks <- repo.hooks (repo wins per-event).
# Other top-level keys in settings.json are preserved.
tmp=$(mktemp)
jq --slurpfile add "$REPO_DIR/claude/hooks.json" '
  . as $existing
  | $add[0] as $incoming
  | $existing
  | .hooks = ((.hooks // {}) * $incoming.hooks)
' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"

info "Hooks merged: $(jq -r '.hooks | keys | join(", ")' "$CLAUDE_SETTINGS")"

# --- Done --------------------------------------------------------------------

echo
step "Done."
echo
echo "Next steps:"
echo "  1. Open '/hooks' in any running Claude Code session to reload its config"
echo "     (or start a new Claude session — hooks load at session start)."
echo "  2. Try: tmux prefix + s   (native chooser with aggregated dot)"
echo "     and: tmux prefix + F   (fzf popup with sort, search, kill)"
echo
echo "Uninstall: remove the source-file line from $TMUX_CONF and restore"
echo "$CLAUDE_SETTINGS from $BACKUP."
