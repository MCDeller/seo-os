# Handoff: build the two SEO Office portals

For a Claude Code session running **on the owner's PC, inside Ubuntu (WSL2)**,
started from a checkout of this branch. Read this whole file before acting.

## Goal

Two independent SEO Office installs ("portals"), each with several clients:

| Portal | Definition | Port | Portable home (D:) | Google account |
|---|---|---|---|---|
| AUTONOMY | `portals/autonomy.conf` | 3101 | `/mnt/d/AI-Tools/AIOS-Vault/SEO-Office` | manager@richardgrove.info |
| ThyselfEmpowered | `portals/thyselfempowered.conf` | 3102 | `/mnt/d/AI-Tools/Claude/TermsOfUs/Thyself_Empowered/SEO-Office` | thyselfempowered@gmail.com |

Clients — AUTONOMY: `autonomy` (richardgrove.org for now; getautonomy.info
redirects there), `grand-theft-world`, `tragedy-and-hope`. ThyselfEmpowered:
`tou`, `iwy`, `ttgoh` (domain not registered yet), `sos`. Full URLs are in the
`.conf` files.

Port 3000 is taken by the owner's IMAP MCP server — never use it.

## Design (already decided with the owner)

- **Portable on D:** client brains (`clients/<slug>/`), the owner's own
  documents (`source-docs/<slug>/`), keys (`config/portal.env`), OAuth client
  JSON, backups, start/backup scripts, README.
- **Inside Ubuntu (`~/seo-engines/<portal>`):** app code, `node_modules`,
  `index.db` + cache, and the portal's private gcloud sign-in (`.gcloud/`).
  SQLite and `node_modules` are unreliable/slow on `/mnt/d`.
- Isolation per portal comes from `config/portal.env` (symlinked as the
  engine's `.env.local`): `SEO_OFFICE_DATA_DIR`, `SEO_OFFICE_VAULTS_DIR`,
  `SEO_OFFICE_GCLOUD_CLIENT_ID_FILE`, `CLOUDSDK_CONFIG`.
- `scripts/portal/setup-portal.sh` does all of this and is safe to re-run.

## Hard rules

1. **Never modify the owner's existing brains:**
   `/mnt/d/AI-Tools/AIOS-Vault/AUTONOMY_AIOS` (an Obsidian vault) and
   `/mnt/d/AI-Tools/Claude/TermsOfUs/TOU_Claude_Code` (a project workspace).
   Read only. Do not point SEO Office at them.
2. Never delete anything under a portal's `clients/` by hand — use
   `DELETE /api/clients/<slug>?confirm=1`.
3. Never print, log or commit API keys or the contents of `config/`.
4. Do not type passwords or approve Google consent screens — the owner does
   those. Guide them step by step instead.
5. Don't put documents in `clients/<slug>/.raw/` — it is a cache purged after
   30 days.

## Steps

1. **Check tools:** `node -v` (must be 24+; if not: `nvm install 24 && nvm alias
   default 24`), `pnpm -v`, `python3 --version`, `git --version`,
   `gcloud version`. Confirm `/mnt/d/AI-Tools` exists.
2. **Build AUTONOMY:** `bash scripts/portal/setup-portal.sh portals/autonomy.conf`
   — read the output; every client should say "created".
3. **Build ThyselfEmpowered:**
   `bash scripts/portal/setup-portal.sh portals/thyselfempowered.conf`
4. **Verify isolation** (both must hold before telling the owner it's done):
   - Start both (`seo-autonomy` and `seo-thyselfempowered` in two Ubuntu
     windows, or `bash <home>/start.sh`). `curl -s localhost:3101/api/clients`
     lists only the three AUTONOMY clients; `:3102` only the four
     ThyselfEmpowered clients.
   - `grep -E '^(SEO_OFFICE_|CLOUDSDK_)' <home>/config/portal.env` (names
     only, no key values) shows different paths for the two portals.
5. **Google setup with the owner,** one portal at a time, following "Google
   setup" in each portal's `README.md`. After signing in on portal A, confirm
   portal B's `/setup` page still shows Google as **not** signed in.
6. **Source documents (optional, owner chooses):** copy — never move — files
   the owner selects from the existing brains into
   `<home>/source-docs/<slug>/`. Converting them into
   `clients/<slug>/wiki/sources/` notes (marketing-brain.v1 frontmatter) is a
   later, separate task the owner plans to do in a VS Code workspace.
7. Report back: what was created, the two URLs, what the owner still has to do.

## If something fails

- `the app did not start` → read `~/seo-engines/<portal>/.portal-setup.log`.
- `better-sqlite3` / native module errors → `cd ~/seo-engines/<portal> &&
  pnpm rebuild better-sqlite3`, then re-run setup.
- Port in use → another portal or a stale `next dev`; find it with
  `ss -ltnp | grep 310`.
- Google `S256:` / invalid `code_challenge_method` error during sign-in →
  likely a gcloud bug; `sudo snap refresh google-cloud-cli` (or install gcloud
  from Google's apt repo) and retry.
