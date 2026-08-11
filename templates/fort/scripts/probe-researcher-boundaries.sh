#!/bin/bash
# Static Researcher boundary probe (fortkit-vhk.5.1).  A HAND installation
# must chmod 755 this file; fort-init applies that mode to shipped scripts.
#
# This probe writes a temporary $root/.env.probe-canary and removes it on a
# normal exit. SIGKILL prevents that cleanup. If a write-denial assertion
# fails, its .researcher-boundary-canary target can likewise remain in src/,
# fort/seats/, fort/profiles/, fort/scripts/, or .git/hooks/.
#
# Usage: fort/scripts/probe-researcher-boundaries.sh <repo-root> [--strict]
# In the fortkit factory checkout this examines templates/fort; in a founded
# fort it examines fort/. Every assertion prints a named PASS/FAIL/SKIP line.
# --strict exits non-zero when any assertion was skipped.
set -u

launcher_tools() { # launcher_tools <launcher>
  awk '
    /^[[:space:]]*--tools[[:space:]]+"[^"]*"[[:space:]]*(\\|)?[[:space:]]*$/ {
      line = $0
      sub(/^[[:space:]]*--tools[[:space:]]+"/, "", line)
      sub(/"[[:space:]]*(\\|)?[[:space:]]*$/, "", line)
      print line
    }
  ' "$1"
}

launcher_has_flag() { # launcher_has_flag <launcher> <flag>
  grep -Eq "^[[:space:]]*${2}([[:space:]]|$)" "$1"
}

launcher_flag_value() { # launcher_flag_value <launcher> <flag>
  awk -v flag="$2" '
    $1 == flag {
      value = $2
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
    }
  ' "$1"
}

profile_check() { # profile_check <profile> <default-safe|edit-deny|web-only>
  node -e '
    const fs = require("node:fs");
    const permissions = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).permissions;
    const check = process.argv[2];
    const allow = permissions.allow;
    if (check === "default-safe") process.exit(
      permissions.defaultMode !== "bypassPermissions" && permissions.defaultMode !== "acceptEdits" ? 0 : 1,
    );
    if (check === "edit-deny") process.exit(permissions.deny.includes("Edit(**)") ? 0 : 1);
    if (check === "web-only") process.exit(
      Array.isArray(allow) && allow.length === 2 && allow.includes("WebSearch") && allow.includes("WebFetch") ? 0 : 1,
    );
    process.exit(2);
  ' "$1" "$2"
}

exact_tools() { # exact_tools <launcher>
  [ "$(launcher_tools "$1")" = "WebSearch,WebFetch,Read,Grep,Glob" ]
}

no_forbidden_tool() { # no_forbidden_tool <launcher>
  local tool
  for tool in Bash Edit Write NotebookEdit Task Agent; do
    launcher_tools "$1" | tr ',' '\n' | grep -Fx "$tool" >/dev/null && return 1
  done
  return 0
}

settings_profile_selected() { # settings_profile_selected <launcher>
  [ "$(launcher_flag_value "$1" --settings)" = "\$root/fort/profiles/researcher-settings.json" ]
}

no_dangerous_skip() { # no_dangerous_skip <launcher>
  ! grep -Fq -- '--dangerously-skip-permissions' "$1"
}

empty_setting_sources() { # empty_setting_sources <launcher>
  launcher_has_flag "$1" --setting-sources && [ "$(launcher_flag_value "$1" --setting-sources)" = "" ]
}

probe_write_denied() { # probe_write_denied <path>
  # shellcheck disable=SC2016 # $1 expands in the nested sh, not this shell.
  [ -d "$(dirname "$1")" ] && ! bwrap "${mask[@]}" -- sh -c ': >> "$1"' sh "$1" >/dev/null 2>&1
}

ordinary_readable() {
  local bytes
  # shellcheck disable=SC2016 # $1 expands in the nested sh, not this shell.
  bytes="$(bwrap "${mask[@]}" -- sh -c 'wc -c < "$1"' sh "$root/README.md" 2>/dev/null)" || return 1
  [ "$bytes" -gt 0 ]
}

secret_inode_masked() { # secret_inode_masked <canary>
  local bytes
  # /dev/null bind reads empty successfully; SELinux may make the read fail.
  # shellcheck disable=SC2016 # $1 expands in the nested sh, not this shell.
  bytes="$(bwrap "${mask[@]}" -- sh -c 'wc -c < "$1"' sh "$1" 2>/dev/null)" || return 0
  [ "$bytes" -eq 0 ]
}

git_status_works() {
  bwrap "${mask[@]}" -- git -C "$root" status --porcelain >/dev/null 2>&1
}

report_write_denial() { # report_write_denial <description> <path>
  local desc="$1" target="$2"
  if [ ! -d "$(dirname "$target")" ]; then
    report_skip "$desc" "target parent does not exist in this checkout"
    return 0
  fi
  report "$desc" probe_write_denied "$target"
}

probe_exit_status() { # respects the global fail, skip, and strict counters
  [ "$fail" -eq 0 ] && { [ "$strict" -eq 0 ] || [ "$skip" -eq 0 ]; }
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  root="${1:?Usage: $0 <repo-root>}"
  strict=0
  case "${2:-}" in
    "") ;;
    --strict) strict=1 ;;
    *) echo "Usage: $0 <repo-root> [--strict]" >&2; exit 64 ;;
  esac
  if [ -f "$root/templates/fort/scripts/researcher.sh" ]; then
    fort_root="$root/templates/fort"
  else
    fort_root="$root/fort"
  fi
  launcher="$fort_root/scripts/researcher.sh"
  profile="$fort_root/profiles/researcher-settings.json"
  pass=0; fail=0; skip=0

  report() { # report <description> <command...>
    local desc="$1"
    shift
    if "$@"; then
      echo "PASS $desc"; pass=$((pass + 1))
    else
      echo "FAIL $desc"; fail=$((fail + 1))
    fi
  }

  report_skip() { # report_skip <description> <reason>
    echo "SKIP $1 ($2)"
    skip=$((skip + 1))
  }

  echo "== Researcher static boundary: $root =="
  report "launcher exact tool set" exact_tools "$launcher"
  report "launcher omits dangerously-skip-permissions" no_dangerous_skip "$launcher"
  report "launcher isolates settings sources" empty_setting_sources "$launcher"
  report "launcher enables strict MCP config" launcher_has_flag "$launcher" --strict-mcp-config
  report "launcher selects researcher profile" settings_profile_selected "$launcher"
  report "launcher has no forbidden allow tool" no_forbidden_tool "$launcher"

  report "profile default mode is non-bypass" profile_check "$profile" default-safe
  report "profile denies Edit(**)" profile_check "$profile" edit-deny
  report "profile allows exactly web tools" profile_check "$profile" web-only

  # Create the fixture before build_mask: it snapshots .env* paths while building.
  secret_canary="$root/.env.probe-canary"
  canary_created=0
  if (set -C; : > "$secret_canary") 2>/dev/null; then
    printf 'researcher-boundary-canary\n' >> "$secret_canary"
    canary_created=1
    trap 'rm -f -- "$secret_canary"' EXIT
  fi

  # shellcheck source=fort/scripts/lib/seat-sandbox.sh
  # shellcheck disable=SC1091  # the chosen factory/founded-fort path is runtime data
  source "$fort_root/scripts/lib/seat-sandbox.sh"
  require_bwrap || exit 78
  mask=()
  build_mask claude "$root" --env-root "$root-worktrees" "$root" "$root-worktrees"
  mask_env claude

  report_write_denial "mask denies product-code writes (src/)" "$root/src/.researcher-boundary-canary"
  report_write_denial "mask denies constitution charter write" "$root/fort/charter.md"
  report_write_denial "mask denies constitution seats write" "$root/fort/seats/.researcher-boundary-canary"
  report_write_denial "mask denies constitution profiles write" "$root/fort/profiles/.researcher-boundary-canary"
  report_write_denial "mask denies constitution scripts write" "$root/fort/scripts/.researcher-boundary-canary"
  report_write_denial "mask denies .git/config write" "$root/.git/config"
  report_write_denial "mask denies .git/hooks write" "$root/.git/hooks/researcher-boundary-canary"
  if [ "$canary_created" -eq 1 ]; then
    report "mask inode-masks .env* bytes" secret_inode_masked "$secret_canary"
  else
    report_skip "mask inode-masks .env* bytes" "canary path already exists or is unwritable"
  fi
  report "mask permits ordinary repository reads" ordinary_readable
  report "mask permits git status" git_status_works

  echo "== Researcher static boundary: $pass pass, $fail fail, $skip skip =="
  probe_exit_status
fi
