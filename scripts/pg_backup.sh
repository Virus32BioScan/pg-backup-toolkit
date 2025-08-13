#!/usr/bin/env bash
set -euo pipefail
umask 077
log(){ echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"; }
fail(){ log "ERROR: $*"; exit 1; }
PROFILE="${PROFILE:-nightly}"
BASE_CONF="/etc/pg-backup.conf"
PROF_CONF="/etc/pg-backup.d/${PROFILE}.conf"
HOOKS_BASE="/etc/pg-backup.hooks"
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
MAIL_TO="${MAIL_TO:-}"
MAIL_FROM="${MAIL_FROM:-}"
COMPRESS="${COMPRESS:-zstd}"
BACKUP_DIR="${BACKUP_DIR:-/backups/postgres}"
LOG_DIR="${LOG_DIR:-/var/log/pg-backup}"
JOBS="${JOBS:-4}"
KEEP_DAYS="${KEEP_DAYS:-30}"
INCLUDE_DBS="${INCLUDE_DBS:-}"
EXCLUDE_DBS="${EXCLUDE_DBS:-template0 template1}"
ENCRYPT_GPG="${ENCRYPT_GPG:-false}"
GPG_RECIPIENT="${GPG_RECIPIENT:-}"
[ -f "$BASE_CONF" ] && . "$BASE_CONF"
[ -f "$PROF_CONF" ] && . "$PROF_CONF"
mkdir -p "$BACKUP_DIR/$PROFILE" "$LOG_DIR"
ts="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="$LOG_DIR/${PROFILE}_${ts}.log"
need_bin(){ command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"; }
need_bin pg_dump; need_bin psql
run_hook_dir(){ local d="$1"; [ -d "$d" ] || return 0; for s in "$d"/*; do [ -f "$s" ] && [ -x "$s" ] && "$s" >>"$LOG_FILE" 2>&1 || true; done; }
log "ENV: PROFILE=${PROFILE} BACKUP_DIR=${BACKUP_DIR} LOG_DIR=${LOG_DIR} COMPRESS=${COMPRESS} JOBS=${JOBS} KEEP_DAYS=${KEEP_DAYS}"
run_hook_dir "${HOOKS_BASE}/pre.d"
if [ -n "${INCLUDE_DBS:-}" ]; then dblist="$INCLUDE_DBS"; else exq="${EXCLUDE_DBS// /','}"; dblist=$(PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" psql -Atqc "select datname from pg_database where datallowconn and datname not in ('${exq}')" postgres); fi
[ -n "$dblist" ] || fail "No databases to backup"
ret=0
for db in $dblist; do
  outbase="${BACKUP_DIR}/${PROFILE}/${ts}_${db}.dump"
  tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
  log "Dumping: $db"
  if ! PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" pg_dump -Fc -j "$JOBS" -f "${tmpdir}/${db}.dump" "$db" >>"$LOG_FILE" 2>&1; then log "Dump failed: $db"; ret=1; continue; fi
  final="${tmpdir}/${db}.dump"
  case "$COMPRESS" in
    none) mv "$final" "${outbase}" ; final="${outbase}" ;;
    gzip) gzip -c "$final" > "${outbase}.gz" ; final="${outbase}.gz" ;;
    zstd) zstd -q -f -T0 "$final" -o "${outbase}.zst" ; final="${outbase}.zst" ;;
    *) mv "$final" "${outbase}" ; final="${outbase}" ;;
  esac
  if [ "${ENCRYPT_GPG}" = "true" ] && [ -n "${GPG_RECIPIENT}" ]; then gpg --yes --batch -r "${GPG_RECIPIENT}" -o "${final}.gpg" -e "${final}" >>"$LOG_FILE" 2>&1 && rm -f "${final}" && final="${final}.gpg"; fi
  log "Done: $(basename "$final")"
  DB_NAME="$db" ARTIFACT_PATH="$final" run_hook_dir "${HOOKS_BASE}/post-db.d"
done
[ "$KEEP_DAYS" -gt 0 ] 2>/dev/null && find "${BACKUP_DIR}/${PROFILE}" -type f -mtime +"$KEEP_DAYS" -print -delete >>"$LOG_FILE" 2>&1 || true
run_hook_dir "${HOOKS_BASE}/post.d"
if [ -n "$MAIL_TO" ] && command -v mail >/dev/null 2>&1; then subj="[pg-backup] ${PROFILE} $( [ $ret -eq 0 ] && echo SUCCESS || echo FAIL ) @$(hostname)"; [ -n "$MAIL_FROM" ] && mail -a "From: ${MAIL_FROM}" -s "$subj" "$MAIL_TO" < "$LOG_FILE" || mail -s "$subj" "$MAIL_TO" < "$LOG_FILE"; fi
[ $ret -eq 0 ] && log "Backup finished: SUCCESS" || log "Backup finished: FAIL"
exit $ret
