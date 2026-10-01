# Posture builders for the generic harness. TOOL selects the sandbox.
AJ_BIN="${AJ_BIN:?}"; GW_BIN="${GW_BIN:-}"
AJ=("$AJ_BIN" --clean --no-save-config --exec --no-status-bar)
SG=('.env*' '..env*' '.#*env*' '#*env*#' '.*env*.sw?' '*env*~')
masks_for() { local r m=(); for r in "$@"; do for g in "${SG[@]}"; do m+=(--mask "$r/$g" --mask "$r/*/$g"); done; done; printf '%s\0' "${m[@]}"; }
ro_carve() { local t; for t in "$@"; do printf '%s\0' --map "$t/.claude" --map "$t/fort/profiles" --map "$t/.git/config" --map "$t/.git/hooks" --map "$t/bin" --map "$t/civ/scripts" --map "$t/civ/profiles" --map "$t/fort/scripts"; done; }
HOME_RO=(--map "$HOME/.claude/civilization.json" --map "$HOME/.claude/skills" --map "$HOME/.claude/commands" --map "$HOME/.claude/plugins" --map "$HOME/.claude/settings.json" --map "$HOME/.claude/CLAUDE.md")
posture() {
  local p="$1"; JAIL_CWD=/
  if [ "$TOOL" = ours ]; then
    mask=()
    case $p in
      mayor)  build_mask claude "$ROOT" ;;
      warden_today) build_mask claude "$ROOT" "$ROOT" "$ROOT" ;;
      warden) build_mask claude "$ROOT" "$ROOT" "$ROOT" "$WTS" ;;
      forge)  build_mask codex "$ROOT" --rw-tree "$WTS/wt1" ;;
      researcher) build_mask claude "$ROOT" --env-root "$WTS" "$ROOT" "$WTS" ;;
    esac || { echo "build_mask FAILED"; exit 1; }
    case $p in forge) mask_env codex ;; *) mask_env claude ;; esac
    JAIL=(bwrap "${mask[@]}" --); return
  fi
  if [ "$TOOL" = greywall ]; then posture_gw "$p"; return; fi
  local -a mk rc; mapfile -d '' mk < <(masks_for "$ROOT" "$WTS/wt1" "$WTS/wt2")
  case $p in
    mayor)
      mapfile -d '' rc < <(ro_carve "$ROOT" "$WTS/wt1" "$WTS/wt2")
      JAIL_CWD="$ROOT"; JAIL=("${AJ[@]}" --agent-state --rw-map "$WTS" "${rc[@]}" "${HOME_RO[@]}" "${mk[@]}" --) ;;
    warden_today|warden)
      JAIL_CWD="$ROOT"; JAIL=("${AJ[@]}" --map "$ROOT" --map "$WTS" "${mk[@]}" --) ;;
    forge)
      mapfile -d '' rc < <(ro_carve "$ROOT" "$WTS/wt1")
      local fx=(); for t in "$ROOT" "$WTS/wt1"; do fx+=(--map "$t/fort/charter.md" --map "$t/fort/seats" --map "$t/scripts/verify-impl.sh" --map "$t/skills"); done
      JAIL_CWD="$WTS/wt1"; JAIL=("${AJ[@]}" --rw-map "$ROOT" "${rc[@]}" "${fx[@]}" "${mk[@]}" --) ;;
    researcher)
      JAIL_CWD="$ROOT"; JAIL=("${AJ[@]}" --map "$ROOT" --map "$WTS" "${mk[@]}" --) ;;
  esac
}
gw_json() { # $1 file; $2 allowWrite (newline list); $3 denyWrite (newline list)
  python3 - "$1" "$2" "$3" <<'PY'
import json,sys
f,aw,dw=sys.argv[1],[x for x in sys.argv[2].split("\n") if x],[x for x in sys.argv[3].split("\n") if x]
dr=["**/.env*","**/..env*","**/.#*env*","**/#*env*#","**/.*env*.sw?","**/*env*~"]
json.dump({"filesystem":{"allowWrite":aw,"denyWrite":dw,"denyRead":dr}},open(f,"w"))
PY
}
gw_carve() { local t; for t in "$@"; do printf '%s\n' "$t/.claude" "$t/fort/profiles" "$t/.git/config" "$t/.git/hooks" "$t/bin" "$t/civ/scripts" "$t/civ/profiles" "$t/fort/scripts"; done; }
posture_gw() {
  local p="$1" f="$GW_DIR/gw-$1.json"; JAIL_CWD="$ROOT"
  case $p in
    mayor) gw_json "$f" "$(printf '%s\n' "$ROOT" "$WTS" "$HOME/.claude/teams")" "$(gw_carve "$ROOT" "$WTS/wt1" "$WTS/wt2"; printf '%s\n' "$HOME/.claude/civilization.json" "$HOME/.claude/skills" "$HOME/.claude/commands" "$HOME/.claude/plugins")" ;;
    warden_today|warden|researcher) gw_json "$f" "" "$(printf '%s\n' "$ROOT" "$WTS")" ;;
    forge) JAIL_CWD="$WTS/wt1"; gw_json "$f" "$(printf '%s\n' "$ROOT" "$WTS/wt1")" "$(gw_carve "$ROOT" "$WTS/wt1"; for t in "$ROOT" "$WTS/wt1"; do printf '%s\n' "$t/fort/charter.md" "$t/fort/seats" "$t/scripts/verify-impl.sh" "$t/skills"; done)" ;;
  esac
  JAIL=("$GW_BIN" --settings "$f" --)
}
