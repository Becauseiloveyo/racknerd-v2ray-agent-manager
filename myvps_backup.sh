#!/usr/bin/env bash
# Encrypted cloud backups. Does not modify live Xray/nginx/SSH or old cloud files.
set -Eeuo pipefail
umask 077
KEY=/etc/myvps/backup.pass
REMOTE=/etc/myvps/backup.remote
SELF=/opt/myvps/backup/myvps_backup.sh
BASE=VPS-Backups/racknerd
TMP=''
trap '[[ -z "$TMP" || ! -d "$TMP" ]] || rm -rf -- "$TMP"' EXIT
msg() { printf '[backup] %s\n' "$*"; }
die() { printf '[backup] ERROR: %s\n' "$*" >&2; exit 1; }
require() { [[ "$EUID" -eq 0 ]] || die 'root required'; command -v "$1" >/dev/null || die "Missing $1"; }
temp() { TMP=$(mktemp -d /var/tmp/myvps.XXXXXXXX); chmod 700 "$TMP"; }
remote() {
  [[ -s "$REMOTE" ]] || die 'Run init first'
  local r
  r=$(cat "$REMOTE")
  [[ "$r" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]] || die 'Bad remote'
  rclone listremotes | grep -Fxq "$r" || die 'Remote missing'
  printf '%s' "$r"
}
keyok() { [[ -s "$KEY" ]] || die 'Encryption key missing'; }
init() {
  require rclone; require openssl; require gpg
  install -d -m 700 /etc/myvps /opt/myvps/backup
  if [[ ! -s "$REMOTE" ]]; then
    local r
    r=$(rclone listremotes | sed -n '2p')
    [[ "$r" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]] || die 'Second GDrive remote missing'
    printf '%s\n' "$r" > "$REMOTE"
    chmod 600 "$REMOTE"
  fi
  remote >/dev/null
  if [[ ! -s "$KEY" ]]; then
    openssl rand -base64 48 > "$KEY"
    chmod 600 "$KEY"
    msg 'NEW KEY GENERATED. Save /etc/myvps/backup.pass OFFLINE or cloud backups cannot be restored.'
  else
    msg 'Existing encryption key preserved'
  fi
}
verify() {
  gpg --quiet --batch --yes --pinentry-mode loopback --passphrase-file "$KEY" -d "$1" 2>/dev/null | tar -tzf - >/dev/null
}
upload() {
  local file=$1 dest=$2 name
  name=$(basename "$file")
  rclone copyto "$file" "$dest/$name" --retries 3 --low-level-retries 5 --transfers 1
  rclone check "$(dirname "$file")" "$dest" --one-way --include "$name" --checkers 1 >/dev/null || die 'Cloud checksum mismatch'
  msg "Remote checksum PASS: $name"
}
probe() {
  require rclone; require openssl; require gpg; keyok
  local r nonce name dest
  r=$(remote)
  temp
  nonce=$(openssl rand -hex 8)
  name="probe-$nonce.gpg"
  printf 'backup-test-%s\n' "$nonce" > "$TMP/plain"
  gpg --quiet --batch --yes --pinentry-mode loopback --passphrase-file "$KEY" -c --cipher-algo AES256 -o "$TMP/$name" "$TMP/plain"
  dest="$r$BASE/.health"
  upload "$TMP/$name" "$dest"
  rclone deletefile "$dest/$name" || die 'Probe deletion failed'
  msg 'Encrypted upload, cloud checksum and own probe cleanup: PASS'
}
snapshot_blog() {
  [[ -d /root/my-blog ]] || die 'Missing blog'
  mkdir -p "$TMP/stage/root/my-blog"
  tar -C /root/my-blog --exclude='./node_modules' --exclude='./.git' -cf - . | tar -C "$TMP/stage/root/my-blog" -xf -
  python3 - "$TMP/stage/root/my-blog" <<'PY'
import os,pathlib,sqlite3,sys
base=pathlib.Path(sys.argv[1]); count=0
for t in base.rglob('*'):
    if not t.is_file() or t.suffix.lower() not in ('.db','.sqlite','.sqlite3','.db3'): continue
    source=pathlib.Path('/root/my-blog')/t.relative_to(base)
    new=t.with_name(t.name+'.consistent')
    try:
        a=sqlite3.connect('file:'+str(source)+'?mode=ro',uri=True,timeout=30)
        b=sqlite3.connect(str(new))
        try:a.backup(b,pages=100,sleep=0.05)
        finally:b.close();a.close()
        os.chmod(new,t.stat().st_mode & 0o777)
        os.replace(new,t)
        for suffix in ('-wal','-shm'):
            journal=pathlib.Path(str(t)+suffix)
            if journal.exists():journal.unlink()
        count+=1
    finally:
        if new.exists():new.unlink()
print('sqlite_snapshot_count='+str(count))
PY
}
stage_config() {
  mkdir -p "$TMP/stage/root"
  cp -a /etc "$TMP/stage/etc"
  rm -f "$TMP/stage/etc/myvps/backup.pass"
  for file in /root/my_vps_manager.sh /root/my_vps_exit_manager.sh /root/my_vps_cf_ws_manager.sh; do
    if [[ -f "$file" ]]; then cp -a "$file" "$TMP/stage/root/"; fi
  done
  if [[ -d /root/.config/rclone ]]; then
    mkdir -p "$TMP/stage/root/.config"
    cp -a /root/.config/rclone "$TMP/stage/root/.config/"
  fi
  if [[ -d /root/.acme.sh ]]; then cp -a /root/.acme.sh "$TMP/stage/root/"; fi
}
backup() {
  require tar; require gpg; require rclone; require flock; require python3; keyok
  local kind=$1 r stamp name dest
  [[ "$kind" == config || "$kind" == blog ]] || die 'Wrong kind'
  r=$(remote)
  exec 9>/run/lock/myvps-backup.lock
  flock -n 9 || die 'Another backup is running'
  temp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  name="myvps-$kind-$stamp.tar.gz.gpg"
  dest="$r$BASE/$kind"
  if [[ "$kind" == blog ]]; then snapshot_blog; else stage_config; fi
  tar -C "$TMP/stage" -czf - . | gpg --quiet --batch --yes --pinentry-mode loopback --passphrase-file "$KEY" -c --cipher-algo AES256 -o "$TMP/$name"
  chmod 600 "$TMP/$name"
  verify "$TMP/$name" || die 'Local decrypt/archive check FAIL'
  msg "Local archive verified ($kind)"
  upload "$TMP/$name" "$dest"
}
restore() {
  require rclone; require gpg; require tar; keyok
  local kind=$1 r prefix file
  [[ "$kind" == config || "$kind" == blog ]] || die 'Wrong kind'
  r=$(remote)
  prefix="$r$BASE/$kind"
  file=$(rclone lsf "$prefix" --files-only --max-depth 1 | grep -E "^myvps-$kind-[0-9]{8}T[0-9]{6}Z.tar.gz.gpg$" | sort | tail -1)
  [[ -n "$file" ]] || die 'No cloud backup found'
  temp
  rclone copyto "$prefix/$file" "$TMP/$file" --transfers 1
  verify "$TMP/$file" || die 'Cloud backup restore rehearsal FAIL'
  msg "Cloud download, decrypt and archive validation: PASS ($kind); live data untouched"
}
timers() {
  require systemctl; keyok; remote >/dev/null
  [[ -f "$SELF" ]] || die 'Backup companion is not installed'
  local kind clock
  for kind in config blog; do
    if [[ "$kind" == config ]]; then clock=02:00:00; else clock=02:30:00; fi
    cat > "/etc/systemd/system/myvps-backup-$kind.service" <<EOF
[Unit]
Description=MyVPS encrypted $kind backup
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/bin/bash $SELF run $kind
TimeoutStartSec=60min
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
    cat > "/etc/systemd/system/myvps-backup-$kind.timer" <<EOF
[Unit]
Description=Daily MyVPS $kind backup
[Timer]
OnCalendar=*-*-* $clock Asia/Shanghai
Persistent=false
Unit=myvps-backup-$kind.service
[Install]
WantedBy=timers.target
EOF
    chmod 644 "/etc/systemd/system/myvps-backup-$kind.service" "/etc/systemd/system/myvps-backup-$kind.timer"
  done
  systemctl daemon-reload
  systemctl enable --now myvps-backup-config.timer myvps-backup-blog.timer
  msg 'Daily timers enabled: config 02:00 and blog 02:30 Asia/Shanghai'
}
case "$*" in
  init) init ;;
  probe) probe ;;
  'run config') backup config ;;
  'run blog') backup blog ;;
  'restore-test config') restore config ;;
  'restore-test blog') restore blog ;;
  timers) timers ;;
  *) echo 'Usage: init|probe|run config|run blog|restore-test config|restore-test blog|timers' ;;
esac
