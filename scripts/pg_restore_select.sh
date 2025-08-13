#!/usr/bin/env bash
set -euo pipefail
need_bin(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found"; exit 1; }; }
need_bin pg_restore; need_bin psql
BACKUP_DIR="${BACKUP_DIR:-/backups/postgres}"
PROFILE="${PROFILE:-}"
NONINT=0; SRC_DB=""; SRC_FILE=""; TARGET_DB=""; JOBS="${JOBS:-4}"; FORCE_DROP=0
while [ $# -gt 0 ]; do case "$1" in
  --non-interactive) NONINT=1 ;;
  --select-db) SRC_DB="$2"; shift ;;
  --select-file|--select-backup) SRC_FILE="$2"; shift ;;
  --db|--target-db) TARGET_DB="$2"; shift ;;
  --force-drop) FORCE_DROP=1 ;;
  --jobs) JOBS="$2"; shift ;;
  -h|--help) echo "Usage: pg_restore_select.sh [--non-interactive] [--select-file FILE] [--db TARGET] [--force-drop] [--jobs N]"; exit 0 ;;
  *) echo "Unknown arg: $1"; exit 1 ;;
esac; shift; done
if [ "$NONINT" -eq 0 ] && [ -z "${PROFILE:-}" ]; then echo "Available profiles:"; find "$BACKUP_DIR" -maxdepth 1 -type d -printf "%f\n" | tail -n +2; read -rp "Choose profile (empty = ALL): " PROFILE; fi
shopt -s nullglob; files=()
if [ -n "${PROFILE:-}" ]; then for f in "$BACKUP_DIR/$PROFILE"/*; do files+=("$f"); done; else for f in "$BACKUP_DIR"/*/*; do files+=("$f"); done; fi
[ ${#files[@]} -gt 0 ] || { echo "No backup files found in $BACKUP_DIR"; exit 1; }
if [ "$NONINT" -eq 0 ] && [ -z "${SRC_FILE:-}" ]; then i=0; for f in "${files[@]}"; do echo "[$i] $f"; i=$((i+1)); done; read -rp "Pick index: " idx; SRC_FILE="${files[$idx]}"; fi
[ -n "$SRC_FILE" ] || { echo "No backup file selected"; exit 1; }
if [ -z "$SRC_DB" ]; then base="$(basename "$SRC_FILE")"; name="${base%.*}"; name="${name%.*}"; SRC_DB="${name##*_}"; fi
if [ "$NONINT" -eq 0 ] && [ -z "${TARGET_DB:-}" ]; then read -rp "Target DB name [${SRC_DB}_restored]: " TARGET_DB; TARGET_DB="${TARGET_DB:-${SRC_DB}_restored}"; fi
[ -n "$TARGET_DB" ] || { echo "Target DB not specified"; exit 1; }
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
case "$SRC_FILE" in
  *.gpg) gpg --decrypt --batch --yes -o "$tmp" "$SRC_FILE" ;;
  *.zst) zstd -d -q -f -o "$tmp" "$SRC_FILE" ;;
  *.gz)  gzip -dc "$SRC_FILE" > "$tmp" ;;
  *)     cp -f "$SRC_FILE" "$tmp" ;;
esac
[ "$FORCE_DROP" -eq 1 ] && psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"$TARGET_DB\";" postgres
psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$TARGET_DB\" TEMPLATE template0;" postgres
pg_restore -v -j "${JOBS}" -d "$TARGET_DB" "$tmp"
echo "Restore completed into $TARGET_DB"
