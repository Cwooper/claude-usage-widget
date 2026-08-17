#!/bin/sh
#
# Symlinks rather than copies, so edits in the checkout take effect on the next
# plasmashell restart without reinstalling.

set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_target="$HOME/.local/bin/claude-usage-probe"
plasmoid_target="$HOME/.local/share/plasma/plasmoids/dev.cwooper.claudeusage"

link() {
    src=$1
    dst=$2
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        # Refuse to delete real files: they may be an older hand-installed copy
        # holding changes that were never moved into the checkout.
        echo "error: $dst exists and is not a symlink; move it aside first" >&2
        exit 1
    fi
    mkdir -p "$(dirname -- "$dst")"
    ln -s "$src" "$dst"
    echo "linked $dst -> $src"
}

link "$repo/bin/claude-usage-probe" "$bin_target"
link "$repo/plasmoid" "$plasmoid_target"

echo
echo "Add it with: right-click desktop -> Add Widgets -> \"Claude Usage\""
