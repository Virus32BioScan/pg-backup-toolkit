#!/usr/bin/env bash
set -euo pipefail

# Проверки
[ -d ".git" ] || { echo "Запусти в корне локального git-клона"; exit 1; }
mkdir -p docs scripts systemd config packaging hooks/pre.d hooks/post-db.d hooks/post.d

# --- Полная инструкция HTML (v1.3.3, цветовая разметка) ---
cat > docs/guide.html <<'HTML'
<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8" />
<title>PG Backup Toolkit — ПОЛНАЯ инструкция v1.3.3</title>
<style>
:root{--red:#e53935;--yellow:#f6c445;--green:#2e7d32;--black:#111}
html,body{margin:0;padding:0;background:#fff;color:var(--black);font:16px/1.6 system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial}
main{max-width:1100px;margin:28px auto;padding:0 20px}
h1,h2,h3{margin:18px 0 10px}h1{font-size:28px}h2{font-size:22px}h3{font-size:18px}
code,kbd,pre{font-family:ui-monospace,Menlo,Consolas,monospace}
pre{background:#fff;border:1px dashed #ddd;padding:12px;border-radius:8px;overflow:auto}
ol,ul{padding-left:22px}li{margin:6px 0}
.red{color:var(--red)}.yellow{color:var(--yellow)}.green{color:var(--green)}
table{border-collapse:collapse;width:100%;font-size:15px}
th,td{border:1px solid #ececec;padding:8px 10px;text-align:left;vertical-align:top}
tr:nth-child(even){background:#fafafa}
hr{border:0;border-top:1px solid #eee;margin:18px 0}
</style></head><body><main>

<h1>PG Backup Toolkit <span class="green">ПОЛНАЯ инструкция</span> <small>(v1.3.3)</small></h1>
<p>Ключевые элементы — <span class="green">зелёным</span>, важно — <span class="yellow">жёлтым</span>, внимание — <span class="red">красным</span>. Без «плашек», только цветной текст.</p>

<h2>0. Быстрый старт <span class="green">pg-backup-setup</span></h2>
<pre>sudo apt install ./pg-backup-toolkit_1.3.3_all.deb
sudo pg-backup-setup
</pre>

<h2>1. Что ставится</h2>
<ol>
  <li><span class="green">/usr/local/sbin/pg_backup.sh</span> — бэкапы (<code>pg_dump -Fc -j</code>, gzip/zstd, GPG, ретеншн, логи, email, хуки).</li>
  <li><span class="green">/usr/local/sbin/pg_restore_select.sh</span> — восстановление (интерактив/CLI).</li>
  <li><span class="green">/usr/local/sbin/pg-backup-setup</span> — мастер настройки и расписаний.</li>
  <li><span class="green">/usr/local/sbin/pg-backup-profile</span> — профили (create/list/show/remove).</li>
  <li><span class="green">/usr/local/sbin/pg-backup-locate</span> — показать каталоги профилей и логов.</li>
  <li><span class="green">/usr/local/sbin/pg-backup-test</span> — тестовый прогон и проверка артефактов.</li>
  <li><span class="green">systemd</span>: <code>pg-backup@.service</code> + таймеры.</li>
  <li><span class="green">/etc/pg-backup.conf</span>, <span class="green">/etc/pg-backup.d/*.conf</span>, <span class="green">/etc/pg-backup.hooks/*</span>.</li>
</ol>

<h2>2. Расписания (systemd OnCalendar)</h2>
<p class="yellow">Можно несколько строк OnCalendar в одном таймере.</p>
<pre># Каждый день в 00:00, 01:00, 05:00
OnCalendar=*-*-* 00:00:00
OnCalendar=*-*-* 01:00:00
OnCalendar=*-*-* 05:00:00

# 1-е и 17-е числа месяца в 02:30
OnCalendar=*-*-01 02:30:00
OnCalendar=*-*-17 02:30:00

# Каждый понедельник в 00:00
OnCalendar=Mon *-*-* 00:00:00
</pre>

<h2>3. Профили (пример)</h2>
<pre>PROFILE_NAME="nightly"
INCLUDE_DBS=""                             # пусто=все (кроме EXCLUDE_DBS)
EXCLUDE_DBS="template0 template1 postgres" # игнорируется, если INCLUDE_DBS задан
JOBS="4"
KEEP_DAYS="30"
COMPRESS="zstd"
ENCRYPT_GPG="false"
GPG_RECIPIENT=""
BACKUP_DIR="/backups/postgres/nightly"
LOG_DIR="/var/log/pg-backup"
</pre>

<h2>4. Как проверить куда сыпет копиями</h2>
<pre>pg-backup-locate
# или посмотреть в /etc/pg-backup.d/&lt;профиль&gt;.conf переменную BACKUP_DIR
</pre>

<h2>5. Ручной запуск и диагностика</h2>
<pre>sudo systemctl start pg-backup@nightly.service
journalctl -u pg-backup@nightly.service -e
sudo pg-backup-test -p nightly
</pre>

<h2>6. Восстановление</h2>
<pre># интерактивно
pg_restore_select.sh

# без вопросов
pg_restore_select.sh --non-interactive --select-file /backups/postgres/nightly/2025-08-10_02-15-00_db.dump.zst \\
  --db db_restored --jobs 6 --force-drop
</pre>

<h2>7. Почта, безопасность</h2>
<ul>
  <li>Почта: <code>MAIL_TO</code>/<code>MAIL_FROM</code>, нужен mailutils/bsd-mailx/msmtp.</li>
  <li class="red">umask 077</li>, приватные каталоги, sandbox systemd.</li>
  <li class="yellow">Клиент psql/pg_dump обязателен</li> (подойдёт пакет от Postgres Pro).</li>
</ul>

<h2>8. Хуки</h2>
<p><span class="green">/etc/pg-backup.hooks/pre.d</span> — до бэкапа; <span class="green">/post-db.d</span> — после каждой БД (ENV: <code>DB_NAME</code>, <code>ARTIFACT_PATH</code>); <span class="green">/post.d</span> — после профиля.</p>

<h2>9. Быстрый FAQ</h2>
<ul>
  <li><b>Разные окна расписаний?</b> — да, просто добавь несколько <code>OnCalendar</code>.</li>
  <li><b>Выбор/исключения БД?</b> — <code>INCLUDE_DBS</code>/<code>EXCLUDE_DBS</code> в профиле.</li>
  <li><b>Свои профили?</b> — <code>pg-backup-profile create myprof</code>, затем включи таймер.</li>
</ul>

<hr /><p><small>Версия документа: <span class="green">1.3.3</span></small></p>
</main></body></html>
HTML

# --- Исполняемые биты на скриптах ---
chmod +x scripts/pg_backup.sh scripts/pg_restore_select.sh scripts/pg-backup-setup \
           scripts/pg-backup-profile scripts/pg-backup-locate scripts/pg-backup-test 2>/dev/null || true

# --- Коммит и пуш ---
git add docs/guide.html scripts .github workflows 2>/dev/null || true
git add -A
git commit -m "Fix: restore FULL guide v1.3.3; ensure +x on scripts" || true
# если remote уже добавлен:
git push || true

# --- (опционально) тэг для автосборки .deb в релиз ---
if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
  git tag -f v1.3.3
  git push -f origin v1.3.3 || true
fi

echo "Готово. Открой docs/guide.html на GitHub и проверь."
