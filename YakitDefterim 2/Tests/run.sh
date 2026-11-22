#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
swiftc -module-cache-path "$build_dir/cache" "$project_dir/Sources/Models.swift" "$project_dir/Sources/DatabaseDisk.swift" "$project_dir/Tests/main.swift" -o "$build_dir/tests"
"$build_dir/tests"
