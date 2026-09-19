#!/usr/bin/env bash
# Put the working tree where the shell actually reads it, then restart.
#
# The shell loads ~/.config/omarchy/plugins/<id>/, which is a copy — not this
# repo. Editing here and testing there without this step tests the old code and
# reports it as the new code's behaviour. Ask me how I know.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dst="$HOME/.config/omarchy/plugins/reidenxerx.varta"

[ -d "$dst" ] || { echo "not installed: $dst" >&2; exit 1; }
rsync -a --delete --exclude .git --exclude __pycache__ --exclude '*.pyc' \
      "$src"/ "$dst"/
echo "deployed $(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo working-tree) -> $dst"

# keepLoaded plugins do not hot-reload: the log says "Local plugin changed" and
# the old code keeps running.
[ "${1:-}" = "--no-restart" ] || omarchy-restart-shell
