#!/usr/bin/env bash
# One-shot Pixel 9 Pro XL debloat. Missing packages are skipped.
# Usage: ./debloat.sh [debloat|restore]
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
ACTION="${1:-debloat}"
ADB=""

case "$ACTION" in
  debloat|restore) ;;
  *)
    echo "usage: $0 [debloat|restore]" >&2
    exit 1
    ;;
esac

find_adb() {
  local candidate
  local -a candidates=()
  shopt -s nullglob
  candidates+=(
    "$(command -v adb 2>/dev/null || true)"
    "$(command -v adb.exe 2>/dev/null || true)"
    "$ROOT/adb"
    "$ROOT/adb.exe"
    "${ANDROID_HOME:-}/platform-tools/adb"
    "${ANDROID_HOME:-}/platform-tools/adb.exe"
    "$HOME/Downloads/platform-tools-latest-windows/platform-tools/adb.exe"
    "$HOME/Downloads/platform-tools/adb.exe"
  )
  candidates+=(/mnt/c/Users/*/Downloads/platform-tools-latest-windows/platform-tools/adb.exe)
  candidates+=(/mnt/c/Users/*/AppData/Local/Android/Sdk/platform-tools/adb.exe)
  shopt -u nullglob
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      ADB="$candidate"
      return 0
    fi
  done
  return 1
}

adb_shell() {
  "$ADB" shell "$@" 2>&1 | tr -d '\r' || true
}

has_pkg() {
  local out
  out="$(adb_shell pm path "$1")"
  [[ "$out" == package:* ]]
}

read_list() {
  local file="$1" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done < "$file"
}

apply_setting() {
  local op="$1" ns="$2" key="$3" value="${4:-}"
  if [[ "$op" == "put" ]]; then
    if "$ADB" shell settings put "$ns" "$key" "$value" >/dev/null 2>&1; then
      echo "set   $ns $key=$value"
    else
      echo "warn  settings put $ns $key failed, continuing"
    fi
  elif [[ "$op" == "delete" ]]; then
    if "$ADB" shell settings delete "$ns" "$key" >/dev/null 2>&1; then
      echo "del   $ns $key"
    else
      echo "warn  settings delete $ns $key failed, continuing"
    fi
  else
    echo "warn  unknown settings op '$op', continuing"
  fi
}

disable_pkg() {
  local pkg="$1" out
  if ! has_pkg "$pkg"; then
    echo "skip  $pkg (not installed)"
    return 0
  fi
  out="$(adb_shell pm disable-user --user 0 "$pkg")"
  if [[ "$out" == *"disabled-user"* ]]; then
    echo "off   $pkg"
  else
    echo "warn  $pkg (${out:-disable failed}), continuing"
  fi
}

enable_pkg() {
  local pkg="$1" out
  if ! has_pkg "$pkg"; then
    echo "skip  $pkg (not installed)"
    return 0
  fi
  out="$(adb_shell pm enable --user 0 "$pkg")"
  if [[ "$out" == *"enabled"* || "$out" == *"new state"* ]]; then
    echo "on    $pkg"
  else
    echo "warn  $pkg (${out:-enable failed}), continuing"
  fi
}

pkg_uid() {
  adb_shell pm list packages -U "$1" | sed -n "s/^package:${1} uid://p" | head -n 1
}

restrict_pkg() {
  local pkg="$1" op uid
  if ! has_pkg "$pkg"; then
    echo "skip  $pkg (not installed)"
    return 0
  fi
  "$ADB" shell am set-bg-restriction-level --user 0 "$pkg" background_restricted >/dev/null 2>&1 \
    || echo "warn  $pkg background restrict failed, continuing"
  for op in RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND POST_NOTIFICATION SCHEDULE_EXACT_ALARM; do
    "$ADB" shell cmd appops set "$pkg" "$op" ignore >/dev/null 2>&1 \
      || echo "warn  $pkg appops $op failed, continuing"
  done
  "$ADB" shell pm revoke --user 0 "$pkg" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  uid="$(pkg_uid "$pkg")"
  if [[ -n "$uid" ]]; then
    "$ADB" shell cmd netpolicy add restrict-background-blacklist "$uid" >/dev/null 2>&1 \
      || echo "warn  $pkg netpolicy failed, continuing"
  else
    echo "warn  $pkg uid not found, skipped network blacklist"
  fi
  "$ADB" shell am force-stop "$pkg" >/dev/null 2>&1 || true
  echo "limit $pkg"
}

unrestrict_pkg() {
  local pkg="$1" op uid
  if ! has_pkg "$pkg"; then
    echo "skip  $pkg (not installed)"
    return 0
  fi
  "$ADB" shell am set-bg-restriction-level --user 0 "$pkg" adaptive_bucket >/dev/null 2>&1 \
    || echo "warn  $pkg background restore failed, continuing"
  for op in RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND POST_NOTIFICATION SCHEDULE_EXACT_ALARM; do
    "$ADB" shell cmd appops set "$pkg" "$op" allow >/dev/null 2>&1 \
      || echo "warn  $pkg appops $op failed, continuing"
  done
  "$ADB" shell pm grant --user 0 "$pkg" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 \
    || echo "warn  $pkg notification grant failed, continuing"
  uid="$(pkg_uid "$pkg")"
  if [[ -n "$uid" ]]; then
    "$ADB" shell cmd netpolicy remove restrict-background-blacklist "$uid" >/dev/null 2>&1 || true
  fi
  echo "allow $pkg"
}

stop_pkg() {
  local pkg="$1"
  if ! has_pkg "$pkg"; then
    echo "skip  $pkg (not installed)"
    return 0
  fi
  "$ADB" shell am force-stop "$pkg" >/dev/null 2>&1 \
    || echo "warn  $pkg force-stop failed, continuing"
  echo "stop  $pkg"
}

if ! find_adb; then
  echo "adb was not found. Install platform-tools and put adb on PATH, or place adb.exe next to this script." >&2
  exit 1
fi

echo "adb    $ADB"
state="$("$ADB" get-state 2>&1 | tr -d '\r' | head -n 1 || true)"
if [[ "$state" != "device" ]]; then
  echo "No authorized Pixel ($state)." >&2
  echo "Plug in the phone, unlock it, and allow USB debugging." >&2
  exit 1
fi

model="$(adb_shell getprop ro.product.model)"
echo "phone  ${model:-unknown}"
echo "action $ACTION"

if [[ "$ACTION" == "debloat" ]]; then
  settings_file="$ROOT/debloat-settings.txt"
else
  settings_file="$ROOT/restore-settings.txt"
fi

while read -r op ns key value; do
  [[ -z "${op:-}" ]] && continue
  apply_setting "$op" "$ns" "$key" "${value:-}"
done < <(read_list "$settings_file")

while read -r pkg; do
  if [[ "$ACTION" == "debloat" ]]; then
    disable_pkg "$pkg"
  else
    enable_pkg "$pkg"
  fi
done < <(read_list "$ROOT/disable-packages.txt")

while read -r pkg; do
  if [[ "$ACTION" == "debloat" ]]; then
    restrict_pkg "$pkg"
  else
    unrestrict_pkg "$pkg"
  fi
done < <(read_list "$ROOT/restrict-packages.txt")

if [[ "$ACTION" == "debloat" ]]; then
  while read -r pkg; do
    stop_pkg "$pkg"
  done < <(read_list "$ROOT/stop-packages.txt")
  "$ADB" shell pm trim-caches 999999999999 >/dev/null 2>&1 \
    || echo "warn  trim-caches failed, continuing"
fi

"$ADB" shell cmd appops write-settings >/dev/null 2>&1 || true
echo "done   $ACTION"
exit 0
