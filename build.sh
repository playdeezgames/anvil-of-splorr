#!/usr/bin/env bash
# Usage: ./build.sh [check|test]
# Frontend targets (native, web) are added when those frontends exist.
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-test}" in
	check) odin check common -no-entry-point && odin check palette_editor -no-entry-point ;;
	test)  odin test common && odin test palette_editor ;;
	*) echo "unknown target: $1 (expected check or test)" >&2; exit 2 ;;
esac
