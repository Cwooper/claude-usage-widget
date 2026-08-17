#!/bin/sh
#
# Build dist/<id>-<version>.plasmoid for upload to store.kde.org.
#
# A .plasmoid is a zip whose root holds metadata.json and contents/ -- note the
# package directory's *contents*, not the directory itself.

set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
id=$(python3 -c "import json;print(json.load(open('$repo/plasmoid/metadata.json'))['KPlugin']['Id'])")
version=$(python3 -c "import json;print(json.load(open('$repo/plasmoid/metadata.json'))['KPlugin']['Version'])")

out="$repo/dist/$id-$version.plasmoid"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp -a "$repo/plasmoid/." "$stage/"
find "$stage" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

mkdir -p "$repo/dist"
rm -f "$out"
(cd "$stage" && zip -qr "$out" .)

echo "$out"
unzip -l "$out" | tail -n +4 | head -n -2 | awk '{print "  " $4}'
