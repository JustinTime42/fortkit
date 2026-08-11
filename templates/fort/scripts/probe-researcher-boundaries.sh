#!/bin/bash
# Static Researcher boundary probe (fortkit-vhk.5.1).  A HAND installation
# must chmod 755 this file; fort-init applies that mode to shipped scripts.
#
# Usage: fort/scripts/probe-researcher-boundaries.sh <repo-root>
# In the fortkit factory checkout this examines templates/fort; in a founded
# fort it examines fort/.  Every assertion prints a named PASS/FAIL line.
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  root="${1:?Usage: $0 <repo-root>}"
  if [ -f "$root/templates/fort/scripts/researcher.sh" ]; then
    fort_root="$root/templates/fort"
  else
    fort_root="$root/fort"
  fi
  launcher="$fort_root/scripts/researcher.sh"
  profile="$fort_root/profiles/researcher-settings.json"
  pass=0; fail=0

  report() { # report <description> <command...>
    local desc="$1"
    shift
    if "$@"; then
      echo "PASS $desc"; pass=$((pass + 1))
    else
      echo "FAIL $desc"; fail=$((fail + 1))
    fi
  }

  exact_tools() {
    local tools
    tools="$(launcher_tools "$launcher")"
    [ "$tools" = "WebSearch,WebFetch,Read,Grep,Glob" ]
  }
  no_forbidden_tool() {
    local tool
    for tool in Bash Edit Write NotebookEdit Task Agent; do
      launcher_tools "$launcher" | tr ',' '\n' | grep -Fx "$tool" >/dev/null && return 1
    done
  }
  settings_profile_selected() {
    [ "$(launcher_flag_value "$launcher" --settings)" = "\$root/fort/profiles/researcher-settings.json" ]
  }
  no_dangerous_skip() {
    ! grep -Fq -- '--dangerously-skip-permissions' "$launcher"
  }
  empty_setting_sources() {
    [ "$(launcher_flag_value "$launcher" --setting-sources)" = "" ]
  }

  echo "== Researcher static boundary: $root =="
  report "launcher exact tool set" exact_tools
  report "launcher omits dangerously-skip-permissions" no_dangerous_skip
  report "launcher isolates settings sources" empty_setting_sources
  report "launcher enables strict MCP config" launcher_has_flag "$launcher" --strict-mcp-config
  report "launcher selects researcher profile" settings_profile_selected
  report "launcher has no forbidden allow tool" no_forbidden_tool

  report "profile default mode is non-bypass" profile_check "$profile" default-safe
  report "profile denies Edit(**)" profile_check "$profile" edit-deny
  report "profile allows exactly web tools" profile_check "$profile" web-only

  # shellcheck source=fort/scripts/lib/seat-sandbox.sh
  # shellcheck disable=SC1091  # the chosen factory/founded-fort path is runtime data
  source "$fort_root/scripts/lib/seat-sandbox.sh"
  require_bwrap || exit 78
  mask=()
  build_mask claude "$root" --env-root "$root-worktrees" "$root" "$root-worktrees"
  mask_env claude

  probe_write_denied() { # probe_write_denied <path>
    ! bwrap "${mask[@]}" -- sh -c ": >> \"\$1\"" sh "$1" >/dev/null 2>&1
  }
  ordinary_readable() {
    local bytes
    bytes="$(bwrap "${mask[@]}" -- sh -c "wc -c < \"\$1\"" sh "$root/README.md" 2>/dev/null)" || return 1
    [ "$bytes" -gt 0 ]
  }
  secret_inode_masked() {
    local secret bytes
    for secret in "$root"/.env*; do
      [ -f "$secret" ] || continue
      # /dev/null bind reads empty successfully; SELinux may make the read fail.
      bytes="$(bwrap "${mask[@]}" -- sh -c "wc -c < \"\$1\"" sh "$secret" 2>/dev/null)" || return 0
      [ "$bytes" -eq 0 ] && return 0
      return 1
    done
    return 1
  }
  git_status_works() {
    bwrap "${mask[@]}" -- git -C "$root" status --porcelain >/dev/null 2>&1
  }

  report "mask denies product-code writes (src/)" probe_write_denied "$root/src/.researcher-boundary-canary"
  report "mask denies constitution charter write" probe_write_denied "$root/fort/charter.md"
  report "mask denies constitution seats write" probe_write_denied "$root/fort/seats/.researcher-boundary-canary"
  report "mask denies constitution profiles write" probe_write_denied "$root/fort/profiles/.researcher-boundary-canary"
  report "mask denies constitution scripts write" probe_write_denied "$root/fort/scripts/.researcher-boundary-canary"
  report "mask denies .git/config write" probe_write_denied "$root/.git/config"
  report "mask denies .git/hooks write" probe_write_denied "$root/.git/hooks/researcher-boundary-canary"
  report "mask inode-masks .env* bytes" secret_inode_masked
  report "mask permits ordinary repository reads" ordinary_readable
  report "mask permits git status" git_status_works

  echo "== Researcher static boundary: $pass pass, $fail fail =="
  [ "$fail" -eq 0 ]
fi
