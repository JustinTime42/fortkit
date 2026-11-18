#!/bin/bash
# shellcheck disable=SC2088 # Alert paths deliberately use a literal ~ for readability.
# Watch Claude skills and commands for content, link-target, and executable changes.
#
# Monitoring limit (ForgeOs-wzdtr): the manifest, snapshots, and append-only log
# live in the user's state directory. A secrets-only seat can alter that state,
# so this is monitoring rather than tamper-proof enforcement. A host timer outside
# seats is the stronger form and is later gate-6 work (fort/scripts, systemd).
#
# Usage: skills-watch.sh [--user-skills DIR] [--user-commands DIR]
#                          [--project-skills DIR] [--project-commands DIR]
#                          [--state-dir DIR] [--emit-sh PATH]
# Exit: 0 no change or baseline recorded; 1 changes reported; 3 I/O failure.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
user_skills="${HOME}/.claude/skills"
user_commands="${HOME}/.claude/commands"
project_skills="${repo_root}/.claude/skills"
project_commands="${repo_root}/.claude/commands"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/proofdelve-skills-watch"
emit_sh="${repo_root}/fort/scripts/emit.sh"

usage() {
  sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user-skills) user_skills="${2:?missing value for --user-skills}"; shift 2 ;;
    --user-commands) user_commands="${2:?missing value for --user-commands}"; shift 2 ;;
    --project-skills) project_skills="${2:?missing value for --project-skills}"; shift 2 ;;
    --project-commands) project_commands="${2:?missing value for --project-commands}"; shift 2 ;;
    --state-dir) state_dir="${2:?missing value for --state-dir}"; shift 2 ;;
    --emit-sh) emit_sh="${2:?missing value for --emit-sh}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "skills-watch.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
done

fail() { echo "skills-watch.sh: $*" >&2; exit 3; }
mkdir -p "$state_dir" || fail "could not create state directory: $state_dir"
[ -w "$state_dir" ] || fail "could not write state directory: $state_dir"

manifest="$state_dir/manifest.tsv"
snapshot="$state_dir/snapshot"
next_manifest="$state_dir/manifest.tsv.next.$$"
next_snapshot="$state_dir/snapshot.next.$$"
changes_tmp="$state_dir/changes.next.$$"
find_list="$state_dir/find.next.$$"
trap 'rm -rf "$next_manifest" "$next_snapshot" "$changes_tmp" "$find_list"' EXIT
mkdir -p "$next_snapshot" || fail "could not prepare snapshot"
: > "$next_manifest" || fail "could not write manifest"

# Fields are path, sha256, size, and link target. The controlled trees are
# expected to use ordinary filenames; tabs/newlines are refused rather than
# producing an ambiguous one-line manifest.
record_tree() { # $1 manifest prefix, $2 directory
  local prefix="$1" tree="$2" file relative key sha size link target
  [ -d "$tree" ] && [ -r "$tree" ] && [ -x "$tree" ] || fail "could not read tree: $tree"

  # A directory link has no file record of its own in a followed walk. Record
  # it separately, while the second walk below still records its file content.
  # Its digest/size describe its target, so the four manifest columns remain
  # useful even though a directory has no byte content to snapshot.
  if ! find "$tree" -type l -print0 | sort -z > "$find_list"; then
    fail "could not read tree: $tree"
  fi
  while IFS= read -r -d '' file; do
    [ -d "$file" ] || continue
    relative="${file#"$tree"/}"
    key="$prefix/$relative"
    target="$(readlink "$file")" || fail "could not read link: $file"
    case "$key$target" in *$'\t'*|*$'\n'*) fail "unsupported link in tree: $key" ;; esac
    sha="$(printf '%s' "$target" | sha256sum | awk '{print $1}')" || fail "could not hash link: $file"
    size="$(printf '%s' "$target" | wc -c)" || fail "could not size link: $file"
    printf '%s\t%s\t%s\t%s\n' "$key" "$sha" "$size" "$target" >> "$next_manifest" || fail "could not write manifest"
  done < "$find_list"

  if ! find -L "$tree" -type f -print0 | sort -z > "$find_list"; then
    fail "could not read tree: $tree"
  fi
  while IFS= read -r -d '' file; do
    relative="${file#"$tree"/}"
    key="$prefix/$relative"
    case "$key" in *$'\t'*|*$'\n'*) fail "unsupported filename in tree: $key" ;; esac
    sha="$(sha256sum "$file" | awk '{print $1}')" || fail "could not hash: $file"
    size="$(wc -c < "$file")" || fail "could not size: $file"
    link=""
    if [ -L "$file" ]; then
      target="$(readlink "$file")" || fail "could not read link: $file"
      case "$target" in *$'\t'*|*$'\n'*) fail "unsupported link target: $file" ;; esac
      link="$target"
    fi
    printf '%s\t%s\t%s\t%s\n' "$key" "$sha" "$size" "$link" >> "$next_manifest" || fail "could not write manifest"
    mkdir -p "$next_snapshot/$(dirname "$key")" || fail "could not prepare snapshot"
    cp -L -- "$file" "$next_snapshot/$key" || fail "could not snapshot: $file"
  done < "$find_list"
}

record_tree user-skills "$user_skills"
record_tree user-commands "$user_commands"
record_tree project-skills "$project_skills"
record_tree project-commands "$project_commands"
sort -o "$next_manifest" "$next_manifest" || fail "could not sort manifest"

if [ ! -e "$manifest" ]; then
  mv -f "$next_manifest" "$manifest" || fail "could not install baseline manifest"
  rm -rf "$snapshot" || fail "could not replace baseline snapshot"
  mv -f "$next_snapshot" "$snapshot" || fail "could not install baseline snapshot"
  echo "baseline recorded"
  exit 0
fi

old_field() { # $1 key, $2 field number
  awk -F '\t' -v key="$1" -v field="$2" '$1 == key { print $field; exit }' "$manifest"
}
new_field() { # $1 key, $2 field number
  awk -F '\t' -v key="$1" -v field="$2" '$1 == key { print $field; exit }' "$next_manifest"
}
is_executable() { # $1 key, $2 current content path
  local key="$1" content="$2"
  case "$key" in *.sh|*.py|*.js|*.mjs) return 0 ;; esac
  [ -x "$content" ] && return 0
  case "$key" in
    *commands/*) grep -q '^[[:space:]]*!' "$content" && return 0 ;;
    *skills/*) awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit } NR > 1 && /^[[:space:]]*hooks:/ { found=1 } END { exit !found }' "$content" && return 0 ;;
  esac
  return 1
}
is_executable_directory() { # $1 key, $2 current directory path
  local key="$1" directory="$2" file relative
  while IFS= read -r -d '' file; do
    relative="${file#"$directory"/}"
    is_executable "$key/$relative" "$file" && return 0
  done < <(find -L "$directory" -type f -print0)
  return 1
}
display_path() { # $1 manifest key
  case "$1" in
    user-skills/*) printf '%s/%s' '~/.claude/skills' "${1#user-skills/}" ;;
    user-commands/*) printf '%s/%s' '~/.claude/commands' "${1#user-commands/}" ;;
    project-skills/*) printf '%s/%s' '.claude/skills' "${1#project-skills/}" ;;
    project-commands/*) printf '%s/%s' '.claude/commands' "${1#project-commands/}" ;;
    *) printf '%s' "$1" ;;
  esac
}
write_diff() { # $1 old path, $2 new path, $3 key
  local old="$1" new="$2" key="$3" display diff_file lines
  grep -Iq . "$new" 2>/dev/null || [ ! -s "$new" ] || return 0
  display="$(display_path "$key")"
  diff_file="$state_dir/diff.next.$$"
  diff -u --label "old/$display" --label "new/$display" "$old" "$new" > "$diff_file" || true
  lines="$(wc -l < "$diff_file")"
  if [ "$lines" -gt 200 ]; then
    head -n 200 "$diff_file" >> "$changes_tmp"
    printf '%s\n' "DIFF CUT after 200 lines for $display" >> "$changes_tmp"
  else
    cat "$diff_file" >> "$changes_tmp"
  fi
  rm -f "$diff_file"
}

declare -A keys=()
while IFS=$'\t' read -r key _; do keys["$key"]=1; done < "$manifest"
while IFS=$'\t' read -r key _; do keys["$key"]=1; done < "$next_manifest"

added=0; removed=0; changed=0; retargeted=0; executable=0; first_changed=""
: > "$changes_tmp" || fail "could not prepare change log"
while IFS= read -r key; do
  old_sha="$(old_field "$key" 2)"; new_sha="$(new_field "$key" 2)"
  old_link="$(old_field "$key" 4)"; new_link="$(new_field "$key" 4)"
  status=""
  if [ -z "$old_sha" ]; then status=ADDED; added=$((added + 1))
  elif [ -z "$new_sha" ]; then status=REMOVED; removed=$((removed + 1))
  elif [ "$old_link" != "$new_link" ]; then status=RETARGETED; retargeted=$((retargeted + 1))
  elif [ "$old_sha" != "$new_sha" ]; then status=CHANGED; changed=$((changed + 1))
  else continue
  fi
  display="$(display_path "$key")"
  [ -n "$first_changed" ] || first_changed="$display"
  flag=""
  if [ "$status" != REMOVED ]; then
    if [ -d "$next_snapshot/$key" ]; then
      is_executable_directory "$key" "$next_snapshot/$key" && flag=" EXECUTABLE"
    elif is_executable "$key" "$next_snapshot/$key"; then
      flag=" EXECUTABLE"
    fi
    [ -n "$flag" ] && executable=$((executable + 1))
  fi
  printf '%s %s old=%s new=%s old-link=%s new-link=%s%s\n' "$status" "$display" "${old_sha:--}" "${new_sha:--}" "${old_link:--}" "${new_link:--}" "$flag" >> "$changes_tmp"
  if [ "$status" = ADDED ] && [ -f "$next_snapshot/$key" ]; then write_diff /dev/null "$next_snapshot/$key" "$key"
  elif [ "$status" != REMOVED ] && [ "$old_sha" != "$new_sha" ] && [ -f "$next_snapshot/$key" ]; then write_diff "$snapshot/$key" "$next_snapshot/$key" "$key"
  fi
done < <(printf '%s\n' "${!keys[@]}" | sort)

if [ ! -s "$changes_tmp" ]; then
  rm -rf "$next_snapshot"
  rm -f "$next_manifest"
  exit 0
fi

timestamp="$(date -Is)"
{ printf '%s\n' "$timestamp"; cat "$changes_tmp"; } >> "$state_dir/changes.log" || fail "could not append changes log"

summary="skills/commands changed: $added added, $removed removed, $changed changed, $retargeted retargeted ($executable EXECUTABLE): $first_changed"
summary="${summary:0:139}"
[ -x "$emit_sh" ] || fail "could not emit alert: $emit_sh is not executable"
"$emit_sh" watcher.alert "$summary" -a watcher:skills -s watcher -t "$first_changed" || fail "could not emit alert"
mv -f "$next_manifest" "$manifest" || fail "could not update manifest"
rm -rf "$snapshot" || fail "could not replace snapshot"
mv -f "$next_snapshot" "$snapshot" || fail "could not update snapshot"
exit 1
