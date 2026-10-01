#!/bin/bash
set -e
cd "$(dirname "$0")"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot not found on PATH."
	echo "Steam install? Try: ln -sf \"\$HOME/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64\" ~/.local/bin/godot"
	exit 1
fi

if [ ! -f data/map.csv ]; then
	echo "data/map.csv is missing. Run: python3 tools/generate_map.py && cp assets/data/*.csv data/"
	exit 1
fi

exec godot --path .
