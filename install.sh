#!/bin/sh
#
# Usage: ./install.sh [--link]
#
# Copies by default. --link symlinks the checkout instead, which is convenient
# while developing but unsafe once the widget is on a live desktop: plasmashell
# reloads an applet whenever its package changes, and reloading a half-saved
# set of files segfaults it.

set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_target="$HOME/.local/bin/claude-usage-probe"
plasmoid_target="$HOME/.local/share/plasma/plasmoids/dev.cwooper.claudeusage"
mode=copy

[ "${1:-}" = "--link" ] && mode=link

clear_target() {
    dst=$1
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ] && [ "$mode" = copy ]; then
        rm -rf "$dst"
    elif [ -e "$dst" ]; then
        echo "error: $dst exists and is not a symlink; move it aside first" >&2
        exit 1
    fi
    mkdir -p "$(dirname -- "$dst")"
}

install_path() {
    src=$1
    dst=$2
    if [ "$mode" = link ]; then
        clear_target "$dst"
        ln -s "$src" "$dst"
        echo "linked $dst -> $src"
        return
    fi
    # Stage then rename: a copy straight onto the target would leave the package
    # incomplete for long enough for plasmashell to load it in that state.
    stage="$(dirname -- "$dst")/.$(basename -- "$dst").stage"
    rm -rf "$stage"
    cp -a "$src" "$stage"
    clear_target "$dst"
    mv "$stage" "$dst"
    echo "installed $dst"
}

install_path "$repo/bin/claude-usage-probe" "$bin_target"
install_path "$repo/plasmoid" "$plasmoid_target"

echo
if [ "$mode" = link ]; then
    echo "Linked mode: remove the widget from your desktop before editing."
else
    echo "Add it with: right-click desktop -> Add Widgets -> \"Claude Usage\""
    echo "Already added? Restart plasmashell to pick this up:"
    echo "  systemctl --user restart plasma-plasmashell"
fi
