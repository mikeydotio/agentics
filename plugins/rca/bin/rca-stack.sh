#!/usr/bin/env bash
# rca-stack.sh — detect the project's test stack(s) from marker files.
#
# Usage:
#   rca-stack.sh detect [--dir .]
#
# Output: one JSON object on stdout:
#   {ok, stacks:[{id,test_cmd,single_test_cmd_template,setup_cmd,needs:[]}],
#    primary, confidence:high|medium|none}
# `make` wins as `primary` whenever a Makefile `test:` target is present. With
# no markers the result is still ok:true (stacks:[], primary:null, confidence:none)
# so the caller can ask the user.
# Errors: no_jq, bad_args, bad_subcommand.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }

cmd_detect() {
  local dir="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) dir="${2:-.}"; shift 2 ;;
      *)     jq -n --arg a "$1" '{ok:false, error:"bad_args", detail:("unexpected argument: "+$a)}'; exit 1 ;;
    esac
  done

  # glob_exists <glob...> — true if any literal path matches (no nullglob needed).
  glob_exists() { local f; for f in "$@"; do [ -e "$f" ] && return 0; done; return 1; }

  local stacks="[]" have_make=false ids=()
  add() { stacks=$(printf '%s' "$stacks" | jq --argjson s "$1" '. + [$s]'); ids+=("$2"); }

  # swift-pm
  if [ -f "$dir/Package.swift" ]; then
    add '{"id":"swift-pm","test_cmd":"swift test","single_test_cmd_template":"swift test --filter {test}","setup_cmd":null,"needs":[]}' swift-pm
  elif glob_exists "$dir"/*.xcodeproj "$dir"/*.xcworkspace; then
    # xcode only when there is no Package.swift (checked above via elif).
    add '{"id":"xcode","test_cmd":null,"single_test_cmd_template":"xcodebuild test -scheme {scheme} -only-testing:{test}","setup_cmd":null,"needs":["scheme"]}' xcode
  fi

  # cargo
  if [ -f "$dir/Cargo.toml" ]; then
    add '{"id":"cargo","test_cmd":"cargo test","single_test_cmd_template":"cargo test {test}","setup_cmd":null,"needs":[]}' cargo
  fi

  # node (pnpm vs npm)
  if [ -f "$dir/package.json" ]; then
    if [ -f "$dir/pnpm-lock.yaml" ]; then
      add '{"id":"pnpm","test_cmd":"pnpm test","single_test_cmd_template":null,"setup_cmd":"pnpm install --frozen-lockfile","needs":[]}' pnpm
    else
      add '{"id":"npm","test_cmd":"npm test","single_test_cmd_template":null,"setup_cmd":"npm ci","needs":[]}' npm
    fi
  fi

  # pytest
  local is_pytest=false
  if [ -f "$dir/pytest.ini" ]; then is_pytest=true; fi
  if [ -f "$dir/pyproject.toml" ] && grep -q '\[tool.pytest' "$dir/pyproject.toml" 2>/dev/null; then is_pytest=true; fi
  if glob_exists "$dir"/tests/*.py; then is_pytest=true; fi
  if [ "$is_pytest" = true ]; then
    add '{"id":"pytest","test_cmd":"python3 -m pytest","single_test_cmd_template":"python3 -m pytest {test}","setup_cmd":null,"needs":[]}' pytest
  fi

  # bats (under test/ or tests/)
  local bats_dir=""
  if glob_exists "$dir"/tests/*.bats; then bats_dir="tests"
  elif glob_exists "$dir"/test/*.bats; then bats_dir="test"; fi
  if [ -n "$bats_dir" ]; then
    add "$(jq -n --arg c "bats $bats_dir" '{id:"bats",test_cmd:$c,single_test_cmd_template:null,setup_cmd:null,needs:[]}')" bats
  fi

  # make (a Makefile/GNUmakefile with a `test:` target) — wins as primary.
  local mf=""
  [ -f "$dir/Makefile" ] && mf="$dir/Makefile"
  [ -z "$mf" ] && [ -f "$dir/GNUmakefile" ] && mf="$dir/GNUmakefile"
  if [ -n "$mf" ] && grep -qE '^test:' "$mf" 2>/dev/null; then
    add '{"id":"make","test_cmd":"make test","single_test_cmd_template":null,"setup_cmd":null,"needs":[]}' make
    have_make=true
  fi

  local n="${#ids[@]}" primary="null" confidence="none"
  if [ "$n" -eq 0 ]; then
    primary="null"; confidence="none"
  elif [ "$have_make" = true ]; then
    primary='"make"'; confidence="high"
  elif [ "$n" -eq 1 ]; then
    primary=$(printf '%s' "${ids[0]}" | jq -R .); confidence="high"
  else
    primary=$(printf '%s' "${ids[0]}" | jq -R .); confidence="medium"
  fi

  jq -n --argjson stacks "$stacks" --argjson primary "$primary" --arg confidence "$confidence" '
    {ok:true, stacks:$stacks, primary:$primary, confidence:$confidence,
     display:("[rca] " + (($stacks|length)|tostring) + " stack(s) detected"
              + (if $primary==null then "" else "; primary=" + $primary end)
              + " (confidence " + $confidence + ")")}'
}

case "${1:-}" in
  detect) shift; cmd_detect "$@" ;;
  *)      jq -n '{ok:false, error:"bad_subcommand", detail:"usage: rca-stack.sh detect [--dir .]"}'; exit 1 ;;
esac
