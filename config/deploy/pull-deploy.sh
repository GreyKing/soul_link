#!/usr/bin/env bash
# /usr/local/bin/soul-link-deploy — pull-based deploy, run by soul-link-deploy.timer.
#
# The server takes no inbound SSH, so instead of GitHub pushing a deploy in,
# the server asks GitHub: "is there a new commit on main whose tests passed?"
# and deploys it if so. Push to main as usual; the deploy follows within a
# few minutes of the Test workflow going green.
#
#   soul-link-deploy           deploy if origin/main is new and green
#   soul-link-deploy --force   deploy origin/main now, even if unchanged
#
# Each deploy reinstalls this script and the systemd units from the repo, so
# changes to them ship like any other change.
set -euo pipefail

APP=/opt/soul_link
REPO=GreyKing/soul_link
CHECK=test   # the job in .github/workflows/deploy.yml that must have passed
RUBY=/root/.rbenv/shims

main() {
  exec 9>/run/soul-link-deploy.lock
  flock -n 9 || { echo "another deploy is running"; exit 0; }

  cd "$APP"
  git fetch --quiet origin main
  local cur new
  cur=$(git rev-parse HEAD)
  new=$(git rev-parse origin/main)

  if [ "${1:-}" != --force ]; then
    [ "$cur" = "$new" ] && exit 0

    # Public API, no token: this repo is public. A commit with no finished run
    # yet, or a failed one, is simply left for a later tick.
    local verdict
    verdict=$(curl -fsS --max-time 20 "https://api.github.com/repos/$REPO/commits/$new/check-runs" \
      | jq -r --arg name "$CHECK" '[.check_runs[] | select(.name == $name)] | sort_by(.started_at) | last | .conclusion // "pending"')
    if [ "$verdict" != success ]; then
      echo "origin/main ${new:0:7}: $CHECK is $verdict; not deploying"
      exit 0
    fi
  fi

  echo "deploying ${cur:0:7} -> ${new:0:7}"
  set -a; . /etc/soul_link/env; set +a

  git merge --ff-only --quiet origin/main
  "$RUBY/bundle" install --quiet
  "$RUBY/ruby" bin/rails db:migrate
  "$RUBY/ruby" bin/rails assets:precompile

  # p7zip is required by emulatorjs:install to extract the upstream release.
  command -v 7z >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y p7zip-full
  # Idempotent: downloads ~300MB on first install, no-op afterwards.
  "$RUBY/ruby" bin/rails emulatorjs:ensure_installed

  cp config/deploy/soul-link-web.service config/deploy/soul-link-bot.service \
     config/deploy/soul-link-jobs.service config/deploy/soul-link-deploy.service \
     config/deploy/soul-link-deploy.timer config/deploy/systemd-failure-notify@.service \
     /etc/systemd/system/
  install -m 755 config/deploy/notify-failure.sh /usr/local/bin/notify-failure
  install -m 755 config/deploy/pull-deploy.sh /usr/local/bin/soul-link-deploy
  systemctl daemon-reload
  systemctl enable --quiet soul-link-web soul-link-bot soul-link-jobs soul-link-deploy.timer

  local t0
  t0=$(date '+%Y-%m-%d %H:%M:%S')
  systemctl restart soul-link-jobs
  systemctl restart soul-link-bot
  systemctl restart soul-link-web

  # Fail the deploy (after web and bot are already restarted) unless the jobs
  # worker logged "Started Worker" since its restart without being auto-restarted.
  for _ in $(seq 1 12); do
    journalctl -u soul-link-jobs --since "$t0" -o cat --no-pager | grep -q "Started Worker" && break
    sleep 5
  done
  if ! journalctl -u soul-link-jobs --since "$t0" -o cat --no-pager | grep -q "Started Worker" \
     || [ "$(systemctl show -p NRestarts --value soul-link-jobs)" != "0" ]; then
    journalctl -u soul-link-jobs --since "$t0" -p warning -n 20 -o cat --no-pager
    echo "jobs worker did not start cleanly" >&2
    exit 1
  fi
  echo "deployed ${new:0:7}"
}

# Wrapped in a function so bash has read the whole file before a deploy
# replaces it on disk.
main "$@"
