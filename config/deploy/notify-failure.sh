#!/usr/bin/env bash
# Sends an email when a systemd service fails.
# Called by systemd-failure-notify@.service with the failed unit name as $1.
#
# Requires: msmtp (apt install msmtp msmtp-mta)
# Config:   /etc/msmtprc

UNIT="$1"
HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# --- Cooldown: skip if notified within the last 30 minutes ---
COOLDOWN=1800
STAMP_FILE="/tmp/notify-failure-${UNIT}.last"
NOW="$(date +%s)"

if [ -f "$STAMP_FILE" ]; then
  LAST="$(cat "$STAMP_FILE")"
  if [ $(( NOW - LAST )) -lt $COOLDOWN ]; then
    exit 0
  fi
fi

echo "$NOW" > "$STAMP_FILE"
# --- End cooldown ---

LOGS="$(journalctl -u "$UNIT" -n 30 --no-pager 2>/dev/null)"

RECIPIENT="gmferm@gmail.com"
SENDER="noreply@4luckyclovers.com"

sendmail -t <<EOF
To: ${RECIPIENT}
From: ${SENDER}
Subject: [Soul Link] Service failed: ${UNIT} on ${HOST}

Service ${UNIT} entered a failed state on ${HOST}.
Time: ${TIMESTAMP}

--- Last 30 log lines ---
${LOGS}
EOF
