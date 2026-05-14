# claude-tmux

A tmux session picker that knows what your Claude Code sessions are doing.

Each tmux session gets a colored dot reflecting the live state of any Claude
Code processes running in its windows:

- 🟢 **green (idle)** — Claude finished its turn, awaiting your next prompt
- 🟡 **yellow (thinking)** — Claude is processing
- 🔴 **red (waiting)** — Claude is at a permission prompt
- *no dot* — no Claude in this session

<img width="1273" height="650" alt="image" src="https://github.com/user-attachments/assets/a8f0ea73-c449-4bbb-b99a-7781afa0d5a5" />


Two pickers ship with the package:

- `prefix + s` — native tmux `choose-tree`, sessions only, with an aggregated dot
- `prefix + F` — fzf popup with the same dots, plus sort-by-priority+recency,
  age column, search/nav modes, kill-with-confirmation, and an auto-reload
  that ticks only while a session is `thinking`

## Requirements

- macOS or Linux
- `tmux` 3.0+
- `fzf` 0.40+
- `jq` (used by the installer for non-destructive `settings.json` merging)
- [Claude Code](https://docs.anthropic.com/claude/code) (the CLI)

The installer offers to `brew install` any missing dependency.

## Install

```sh
git clone <this repo> ~/workspace/claude-tmux
cd ~/workspace/claude-tmux
./install.sh
```

The installer:

1. Checks for `tmux` / `fzf` / `jq`, offers `brew install` for any missing.
2. Copies the picker script to `~/.tmux/claude-session-picker.sh`.
3. Adds a single `source-file` line to `~/.tmux.conf` (idempotent).
4. Deep-merges the Claude Code hooks into `~/.claude/settings.json`, backing
   up the original first.

Re-running the installer is safe.

## After installing

- **Reload Claude Code hooks**: open `/hooks` in any running Claude Code
  session, or start a fresh session. Hooks load at session start.
- **Reload tmux**: the installer attempts this, but if you see no effect,
  run `tmux source-file ~/.tmux.conf` manually or restart tmux.

## How it works

Claude Code's hook system fires events (`UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `PermissionRequest`, `Stop`, etc.) for each session lifecycle
point. The installed hooks each write a single value (`thinking`, `waiting`,
`idle`) to a tmux **window option** called `@claude_status`, scoped to the
window where Claude is running.

The pickers read `@claude_status` across all windows in each session and
aggregate to a per-session color (priority: waiting > thinking > idle > none).

## Customize

- **Resize the fzf popup** — edit the `bind F display-popup -h H -w W` line
  in `~/workspace/claude-tmux/tmux/claude-tmux.conf`.
- **Change the auto-reload interval** — edit the `sleep N` in the
  `--maybe-reload` branch of `tmux/claude-session-picker.sh`. Default `1`.
- **Change the colors** — `color_dot()` in the picker script.

## Known limitations

- **One `@claude_status` per window.** If multiple Claudes run in the same
  window's panes, they share a single slot. Last write wins.
- **Stale state on abrupt termination.** `SessionEnd` doesn't always fire if
  you close a terminal or kill the pane mid-prompt; the previous color can
  linger. Press `Ctrl-R` in the fzf popup to reload, or run `tmux
  set-option -wu @claude_status` on the affected window.
- **Hook event names can change** between Claude Code versions. If new
  states appear in Claude Code that aren't covered by current hooks, dot
  colors may stop reflecting reality until this repo is updated.

## Uninstall

1. Remove the `source-file ~/workspace/claude-tmux/tmux/claude-tmux.conf`
   line from `~/.tmux.conf`.
2. Restore the `~/.claude/settings.json.bak.*` backup the installer made.
3. Optionally delete `~/.tmux/claude-session-picker.sh`.
