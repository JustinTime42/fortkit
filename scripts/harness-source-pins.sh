#!/bin/bash
# Finds harness defaults that break when verify-impl extracts an instrument to a
# temporary directory. This intentionally reads the verifier, but never invokes
# it, so it is suitable for a pre-wiring, no-network check. It detects
# `${VAR:-...}` defaults and plain self-relative roots that subsequently escape
# their own scripts directory. The conventional `here` self-directory alias is
# propagated into a later root, but is not itself reported. A default ending in
# `# harness-source-pins: self` is exempt only when that default names the
# harness file itself. It does not evaluate shell, follow command substitutions
# beyond self-directory aliases, or recognize dynamically constructed harness
# names or environment variables.
set -uo pipefail

verify_impl="${1:-${VERIFY_IMPL_SH:-scripts/verify-impl.sh}}"
if [ ! -r "$verify_impl" ]; then
  printf 'HARNESS SOURCE PINS REFUSES: cannot read verifier: %s\n' "$verify_impl" >&2
  exit 3
fi

scripts_dir="$(cd "$(dirname "$verify_impl")" && pwd -P)" || {
  printf 'HARNESS SOURCE PINS REFUSES: cannot resolve scripts directory: %s\n' "$verify_impl" >&2
  exit 3
}

findings=0

step_pins_variable() {
  local step_line="$1" variable="$2"
  [ -n "$variable" ] || return 1
  [[ "$step_line" =~ (^|[[:space:]])${variable}= ]]
}

is_marked_self_reference() {
  local source_line_text="$1" harness="$2" default_path basename
  [[ "$source_line_text" =~ [[:space:]]#\ harness-source-pins:\ self[[:space:]]*$ ]] || return 1
  [[ "$source_line_text" =~ \$\{[A-Za-z_][A-Za-z0-9_]*:-([^}]*)\} ]] || return 1
  default_path="${BASH_REMATCH[1]}"
  basename="${default_path##*/}"
  [ "$basename" = "$harness.sh" ]
}

uses_variable_outside_scripts_dir() {
  local source_line_text="$1" variable="$2" remaining path_pattern used_path
  remaining="$source_line_text"
  path_pattern="\\$\\{?${variable}\\}?/([^[:space:]\"']*)"

  while [[ "$remaining" =~ $path_pattern ]]; do
    used_path="${BASH_REMATCH[1]}"
    [ "${used_path#scripts/}" = "$used_path" ] && return 0
    remaining="${remaining/"${BASH_REMATCH[0]}"/}"
  done
  return 1
}

inspect_step() {
  local step_line="$1" line_no="$2" harness source_path source_line
  local source_line_text use_line_text variable self_relative overridden self_var default_var
  local changed
  declare -A self_vars=()

  [[ "$step_line" =~ ^[[:space:]]*run_step[[:space:]] ]] || return
  [[ "$step_line" =~ harness_path[[:space:]]+([A-Za-z0-9_-]+) ]] || return
  harness="${BASH_REMATCH[1]}"
  source_path="$scripts_dir/$harness.sh"
  if [ ! -r "$source_path" ]; then
    printf 'HARNESS SOURCE PINS REFUSES: cannot read harness source: %s (verify line %d)\n' "$source_path" "$line_no" >&2
    exit 3
  fi

  # Variables assigned from dirname "$0" (or BASH_SOURCE) are aliases for the
  # copied harness's own directory. Propagate that property through simple
  # variable references, so a default such as $(dirname "$lint") is caught
  # when lint itself defaults from the copied harness directory.
  while IFS= read -r source_line_text || [ -n "$source_line_text" ]; do
    [[ "$source_line_text" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    variable="${BASH_REMATCH[1]}"
    default_var=''
    if [[ "$source_line_text" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\:- ]]; then
      default_var="${BASH_REMATCH[1]}"
    fi
    if [[ "$source_line_text" == *dirname* ]] && [[ "$source_line_text" == *"\$0"* || "$source_line_text" == *BASH_SOURCE* ]] && ! step_pins_variable "$step_line" "$default_var"; then
      self_vars["$variable"]=1
    fi
  done < "$source_path"

  changed=true
  while [ "$changed" = true ]; do
    changed=false
    while IFS= read -r source_line_text || [ -n "$source_line_text" ]; do
      [[ "$source_line_text" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
      variable="${BASH_REMATCH[1]}"
      [ -n "${self_vars[$variable]:-}" ] && continue
      default_var=''
      if [[ "$source_line_text" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\:- ]]; then
        default_var="${BASH_REMATCH[1]}"
      fi
      step_pins_variable "$step_line" "$default_var" && continue
      for self_var in "${!self_vars[@]}"; do
        if [[ "$source_line_text" == *"\$$self_var"* || "$source_line_text" == *"\${$self_var"* ]]; then
          self_vars["$variable"]=1
          changed=true
          break
        fi
      done
    done < "$source_path"
  done

  source_line=0
  while IFS= read -r source_line_text || [ -n "$source_line_text" ]; do
    source_line=$((source_line + 1))
    [[ "$source_line_text" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    [[ "$source_line_text" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\:- ]] || continue
    variable="${BASH_REMATCH[1]}"

    self_relative=false
    if [[ "$source_line_text" == *"\$0"* || "$source_line_text" == *"BASH_SOURCE"* ]]; then
      self_relative=true
    else
      for self_var in "${!self_vars[@]}"; do
        if [[ "$source_line_text" == *"\$$self_var"* || "$source_line_text" == *"\${$self_var"* ]]; then
          self_relative=true
          break
        fi
      done
    fi
    [ "$self_relative" = true ] || continue

    is_marked_self_reference "$source_line_text" "$harness" && continue

    # This environment switch is a deliberately named red-arm seam for the
    # hermetic harness. Production runs always inspect the run_step overrides.
    overridden=false
    if [ "${HARNESS_SOURCE_PINS_IGNORE_OVERRIDES:-0}" != 1 ] && step_pins_variable "$step_line" "$variable"; then
      overridden=true
    fi
    [ "$overridden" = false ] || continue

    printf 'MISSING SOURCE PIN: harness=%s variable=%s source-line=%d verify-line=%d\n' "$harness" "$variable" "$source_line" "$line_no"
    findings=$((findings + 1))
  done < "$source_path"

  # Unlike a `${VAR:-...}` default, a plain assignment cannot be pinned by a
  # run_step environment override. Only report one when a self-relative root
  # actually reaches outside the copied harness's scripts directory; `here`
  # aliases used solely for pinned sibling scripts are intentionally clean.
  source_line=0
  while IFS= read -r source_line_text || [ -n "$source_line_text" ]; do
    source_line=$((source_line + 1))
    [[ "$source_line_text" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    variable="${BASH_REMATCH[1]}"
    [[ "$source_line_text" == *\$\{*:-* ]] && continue
    # `here` is a self-directory alias, not a root in its own right. Its use
    # in a later plain root is still detected through self_vars propagation.
    [ "$variable" = here ] && continue
    [ -n "${self_vars[$variable]:-}" ] || continue
    [[ "$source_line_text" == *'/..'* ]] || continue

    while IFS= read -r use_line_text || [ -n "$use_line_text" ]; do
      uses_variable_outside_scripts_dir "$use_line_text" "$variable" || continue
      default_var=''
      if [[ "$use_line_text" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\:- ]]; then
        default_var="${BASH_REMATCH[1]}"
      fi
      step_pins_variable "$step_line" "$default_var" && continue
      printf 'SELF-RELATIVE ROOT: harness=%s variable=%s source-line=%d verify-line=%d\n' "$harness" "$variable" "$source_line" "$line_no"
      findings=$((findings + 1))
      break
    done < "$source_path"
  done < "$source_path"
}

line_no=0
logical_start=0
logical_line=''
while IFS= read -r step_line || [ -n "$step_line" ]; do
  line_no=$((line_no + 1))
  if [ -z "$logical_line" ]; then
    logical_start=$line_no
  fi
  if [[ "$step_line" =~ \\$ ]]; then
    logical_line+="${step_line%\\} "
    continue
  fi
  logical_line+="$step_line"
  inspect_step "$logical_line" "$logical_start"
  logical_line=''
done < "$verify_impl"

[ -z "$logical_line" ] || inspect_step "$logical_line" "$logical_start"

if [ "$findings" -gt 0 ]; then
  printf 'HARNESS SOURCE PINS: %d finding(s)\n' "$findings" >&2
  exit 1
fi
printf 'HARNESS SOURCE PINS: clean\n'
