#!/usr/bin/env bash
# =============================================================================
# SEO Office — portal setup
# =============================================================================
# Builds (or refreshes) one self-contained SEO Office "portal" from a portal
# definition file, e.g.:
#
#   bash scripts/portal/setup-portal.sh portals/autonomy.conf
#
# A portal is split in two:
#
#   PORTAL_HOME (portable, e.g. on D:)     ENGINE_DIR (fast, inside Ubuntu)
#   ├── clients/<slug>/   client brains     ├── app code + node_modules
#   ├── source-docs/<slug>/  your originals ├── .seo-office/index.db + cache
#   ├── config/portal.env    keys/settings  ├── .gcloud/  (Google sign-in)
#   ├── config/gcp-oauth-client.json        └── .env.local -> portal.env
#   ├── backups/             index.db copies
#   ├── start.sh  backup.sh  README.md
#   └── config/portal.conf   copy of the definition
#
# Safe to re-run: it never deletes or overwrites client brains, your keys, or
# backups. Re-running on a new PC rewrites only the machine-specific settings.
# =============================================================================
set -euo pipefail

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ✓ %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*"; }
die()  { printf '    ✗ %s\n' "$*" >&2; exit 1; }

CONF="${1:-}"
[ -n "$CONF" ] && [ -f "$CONF" ] || die "usage: bash scripts/portal/setup-portal.sh portals/<name>.conf"
CONF="$(cd "$(dirname "$CONF")" && pwd)/$(basename "$CONF")"

# shellcheck disable=SC1090
source "$CONF"
for v in PORTAL_NAME PORTAL_TITLE PORT PORTAL_HOME ENGINE_DIR GOOGLE_ACCOUNT OWNER; do
  [ -n "${!v:-}" ] || die "$v is not set in $CONF"
done
[ "${#CLIENTS[@]}" -gt 0 ] || die "CLIENTS is empty in $CONF"

SOURCE_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_URL="${REPO_URL:-$(git -C "$SOURCE_REPO" remote get-url origin 2>/dev/null || true)}"
REPO_BRANCH="${REPO_BRANCH:-$(git -C "$SOURCE_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
CONFIG_ENV="$PORTAL_HOME/config/portal.env"
MARK="# --- managed by setup-portal.sh ($PORTAL_NAME) ---"

# -----------------------------------------------------------------------------
say "Pre-flight ($PORTAL_TITLE)"
# -----------------------------------------------------------------------------
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm use 24 >/dev/null 2>&1 || true
fi
command -v node >/dev/null || die "node not found — install Node 24 (nvm install 24)"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 24 ] || die "node $(node -v) is too old — run: nvm install 24 && nvm alias default 24"
ok "node $(node -v)"
command -v pnpm >/dev/null || die "pnpm not found — run: npm install -g pnpm"
ok "pnpm $(pnpm -v)"
for bin in git curl python3; do
  command -v "$bin" >/dev/null || die "$bin not found — run: sudo apt install -y $bin"
done
ok "git, curl, python3"
command -v gcloud >/dev/null && ok "gcloud $(gcloud version 2>/dev/null | head -1 | awk '{print $NF}')" \
  || warn "gcloud not found — Search Console/GA4 sign-in needs it later"
[ -n "$REPO_URL" ] || die "cannot work out the repo URL — set REPO_URL in $CONF"

PARENT="$(dirname "$PORTAL_HOME")"
[ -d "$PARENT" ] || die "$PARENT does not exist — is the D: drive mounted? (ls /mnt/d)"
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  die "port $PORT is already in use — stop whatever is running there (another portal?) and re-run"
fi
ok "port $PORT is free"

# -----------------------------------------------------------------------------
say "Portal folders → $PORTAL_HOME"
# -----------------------------------------------------------------------------
mkdir -p "$PORTAL_HOME"/{clients,config,backups,source-docs}
for entry in "${CLIENTS[@]}"; do
  IFS='|' read -r slug _ _ <<<"$entry"
  mkdir -p "$PORTAL_HOME/source-docs/$slug"
done
cp "$CONF" "$PORTAL_HOME/config/portal.conf"
ok "clients/, source-docs/, config/, backups/"

# -----------------------------------------------------------------------------
say "Engine → $ENGINE_DIR"
# -----------------------------------------------------------------------------
if [ -d "$ENGINE_DIR/.git" ]; then
  ok "existing checkout ($(git -C "$ENGINE_DIR" rev-parse --abbrev-ref HEAD)) — not touching it"
else
  [ -e "$ENGINE_DIR" ] && die "$ENGINE_DIR exists but is not a git checkout — move it aside first"
  mkdir -p "$(dirname "$ENGINE_DIR")"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$ENGINE_DIR"
  ok "cloned $REPO_URL ($REPO_BRANCH)"
fi
(cd "$ENGINE_DIR" && pnpm install)
ok "dependencies installed"
mkdir -p "$ENGINE_DIR/.gcloud" "$ENGINE_DIR/.seo-office"
chmod 700 "$ENGINE_DIR/.gcloud"

# -----------------------------------------------------------------------------
say "Settings → $CONFIG_ENV"
# -----------------------------------------------------------------------------
if [ ! -f "$CONFIG_ENV" ]; then
  cp "$ENGINE_DIR/.env.example" "$CONFIG_ENV"
  ok "created from .env.example (add your API keys here or in the /setup wizard)"
else
  ok "kept existing settings and keys"
fi

# Set KEY=VALUE in the managed block, replacing any earlier uncommented line.
set_kv() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  grep -v -E "^${key}=" "$CONFIG_ENV" >"$tmp" || true
  cat "$tmp" >"$CONFIG_ENV"
  rm -f "$tmp"
  grep -qxF "$MARK" "$CONFIG_ENV" || printf '\n%s\n' "$MARK" >>"$CONFIG_ENV"
  printf '%s=%s\n' "$key" "$value" >>"$CONFIG_ENV"
}
set_kv SEO_OFFICE_DATA_DIR "$ENGINE_DIR/.seo-office"
set_kv SEO_OFFICE_VAULTS_DIR "$PORTAL_HOME/clients"
set_kv SEO_OFFICE_GCLOUD_CLIENT_ID_FILE "$PORTAL_HOME/config/gcp-oauth-client.json"
set_kv CLOUDSDK_CONFIG "$ENGINE_DIR/.gcloud"
ok "data, vault, OAuth-client and gcloud paths are isolated to this portal"

if [ -e "$ENGINE_DIR/.env.local" ] && [ ! -L "$ENGINE_DIR/.env.local" ]; then
  mv "$ENGINE_DIR/.env.local" "$ENGINE_DIR/.env.local.before-portal"
  warn "moved an existing .env.local to .env.local.before-portal"
fi
ln -sfn "$CONFIG_ENV" "$ENGINE_DIR/.env.local"
ok "$ENGINE_DIR/.env.local → portal.env"

# -----------------------------------------------------------------------------
say "Scripts and README"
# -----------------------------------------------------------------------------
cat >"$PORTAL_HOME/backup.sh" <<EOF
#!/usr/bin/env bash
# Copy the $PORTAL_TITLE portal database (index.db) into backups/. Keeps 20.
set -euo pipefail
export NVM_DIR="\${NVM_DIR:-\$HOME/.nvm}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh" && nvm use 24 >/dev/null 2>&1 || true
DB="$ENGINE_DIR/.seo-office/index.db"
DEST="$PORTAL_HOME/backups"
[ -f "\$DB" ] || { echo "no index.db yet — nothing to back up"; exit 0; }
OUT="\$DEST/index-\$(date +%Y%m%d-%H%M%S).db"
cd "$ENGINE_DIR"
node -e 'const D=require("better-sqlite3");const db=new D(process.argv[1],{readonly:true});db.backup(process.argv[2]).then(()=>{db.close();console.log("backup: "+process.argv[2])}).catch(e=>{console.error(e);process.exit(1)})' "\$DB" "\$OUT"
ls -1t "\$DEST"/index-*.db 2>/dev/null | tail -n +21 | xargs -r rm -f
EOF

cat >"$PORTAL_HOME/start.sh" <<EOF
#!/usr/bin/env bash
# Start the $PORTAL_TITLE portal at http://localhost:$PORT  (stop with Ctrl+C)
set -euo pipefail
export NVM_DIR="\${NVM_DIR:-\$HOME/.nvm}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh" && nvm use 24 >/dev/null 2>&1 || true
bash "$PORTAL_HOME/backup.sh" || echo "backup skipped"
cd "$ENGINE_DIR"
echo "$PORTAL_TITLE portal → http://localhost:$PORT"
exec pnpm exec next dev --turbopack -p $PORT
EOF
ok "start.sh, backup.sh"

CLIENT_ROWS=""
for entry in "${CLIENTS[@]}"; do
  IFS='|' read -r slug name url <<<"$entry"
  CLIENT_ROWS+="| \`$slug\` | $name | $url |"$'\n'
done
sed -e "s#{{PORTAL_TITLE}}#$PORTAL_TITLE#g" \
    -e "s#{{PORTAL_NAME}}#$PORTAL_NAME#g" \
    -e "s#{{PORT}}#$PORT#g" \
    -e "s#{{PORTAL_HOME}}#$PORTAL_HOME#g" \
    -e "s#{{ENGINE_DIR}}#$ENGINE_DIR#g" \
    -e "s#{{GOOGLE_ACCOUNT}}#$GOOGLE_ACCOUNT#g" \
    "$SOURCE_REPO/scripts/portal/README.template.md" \
  | awk -v rows="$CLIENT_ROWS" '{ if ($0 == "{{CLIENT_ROWS}}") printf "%s", rows; else print }' \
  >"$PORTAL_HOME/README.md"
ok "README.md"

ALIAS="alias seo-$PORTAL_NAME='bash \"$PORTAL_HOME/start.sh\"'"
if ! grep -qF "alias seo-$PORTAL_NAME=" "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# SEO Office portal: %s\n%s\n' "$PORTAL_TITLE" "$ALIAS" >>"$HOME/.bashrc"
  ok "added shortcut: seo-$PORTAL_NAME (open a new Ubuntu window to use it)"
else
  ok "shortcut seo-$PORTAL_NAME already in ~/.bashrc"
fi

# -----------------------------------------------------------------------------
say "Clients"
# -----------------------------------------------------------------------------
PENDING=()
for entry in "${CLIENTS[@]}"; do
  IFS='|' read -r slug _ _ <<<"$entry"
  if [ -d "$PORTAL_HOME/clients/$slug" ]; then ok "$slug — brain already exists, left as is"
  else PENDING+=("$entry"); fi
done

# The app is started briefly to (a) re-index brains already on disk — needed
# after a restore or on a new PC, where index.db is fresh — and (b) create any
# missing clients through the same API the UI uses.
LOG="$ENGINE_DIR/.portal-setup.log"
echo "    starting the app briefly on port $PORT…"
(cd "$ENGINE_DIR" && exec setsid pnpm exec next dev --turbopack -p "$PORT" >"$LOG" 2>&1) &
SERVER_PID=$!
stop_server() {
  local pgid
  pgid="$(ps -o pgid= -p "$SERVER_PID" 2>/dev/null | tr -d ' ')"
  [ -n "$pgid" ] && kill -- "-$pgid" 2>/dev/null
  kill "$SERVER_PID" 2>/dev/null || true
}
trap stop_server EXIT

for _ in $(seq 1 120); do
  curl -sf -m 60 "http://localhost:$PORT/api/clients" >/dev/null 2>&1 && break
  sleep 2
done
curl -sf -m 60 "http://localhost:$PORT/api/clients" >/dev/null \
  || die "the app did not start — see $LOG"

reindex="$(curl -s -m 120 -X POST "http://localhost:$PORT/api/brain/reindex")"
ok "re-indexed brains on disk: $reindex"

if [ "${#PENDING[@]}" -gt 0 ]; then

  for entry in "${PENDING[@]}"; do
    IFS='|' read -r slug name url <<<"$entry"
    body="$(python3 -c 'import json,sys;print(json.dumps({"slug":sys.argv[1],"clientName":sys.argv[2],"siteUrl":sys.argv[3],"owner":sys.argv[4]}))' "$slug" "$name" "$url" "$OWNER")"
    resp="$(curl -s -m 300 -X POST "http://localhost:$PORT/api/clients" -H 'Content-Type: application/json' -d "$body")"
    if printf '%s' "$resp" | python3 -c 'import json,sys;sys.exit(0 if json.load(sys.stdin).get("ok") else 1)' 2>/dev/null; then
      ok "$slug — created ($url)"
    else
      warn "$slug — failed: $resp"
    fi
  done
fi
stop_server
trap - EXIT

# -----------------------------------------------------------------------------
say "Done — $PORTAL_TITLE"
# -----------------------------------------------------------------------------
cat <<EOF
    Start it:   seo-$PORTAL_NAME        (or: bash "$PORTAL_HOME/start.sh")
    Open:       http://localhost:$PORT/setup
    Keys:       $CONFIG_ENV
    Google:     sign in as $GOOGLE_ACCOUNT — see README.md "Google setup"
EOF
