#!/usr/bin/env bash
#
# Push the SHIPPING SUBSET of this repo into Transport Fever 2's staging area.
#
# The game reads mods from the staging folder, and the Workshop uploader ships
# whatever it finds there -- so development files must not live in it. Keeping
# the repo separate and copying only what ships is what keeps .git/, tools/ and
# PLAN.md out of published builds.
#
#   ./deploy.sh          copy into staging
#   ./deploy.sh --dry    show what would change, copy nothing
#
set -euo pipefail

DEST="${HOME}/.steam/steam/userdata/24778163/1066780/local/staging_area/RightClickDetailsMod_1"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --delete matters: it removes files from staging that were deleted in the repo,
# so the two cannot silently drift apart.
ARGS=(-a --delete)
[[ "${1:-}" == "--dry" ]] && ARGS+=(--dry-run --itemize-changes)

# EXCLUDES -- development-only, must never reach the Workshop.
#   .git/ .gitignore   version control
#   tools/             icon generators; need Python + PIL, useless to players
#   PLAN.md            internal notes
#   .luarc.json        editor config
#   deploy.sh          this script
#   *.DAMAGED.lua      recovery leftovers
#
# README.md and LICENSE are excluded too: the Workshop page carries that text,
# and the licence is about the SOURCE rather than the published mod.
# changelog.txt IS shipped -- players read it.
rsync "${ARGS[@]}" \
  --exclude '.git/' \
  --exclude '.gitignore' \
  --exclude 'tools/' \
  --exclude 'PLAN.md' \
  --exclude 'README.md' \
  --exclude 'LICENSE' \
  --exclude '.luarc.json' \
  --exclude 'deploy.sh' \
  --exclude '*.DAMAGED.lua' \
  --exclude '__pycache__/' \
  "$SRC/" "$DEST/"

if [[ "${1:-}" == "--dry" ]]; then
  echo "(dry run -- nothing copied)"
else
  echo "deployed -> $DEST"
fi
