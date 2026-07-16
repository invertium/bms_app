#!/usr/bin/env bash
# Upload the release AAB to a Google Play track via the Play Developer API.
#
# Usage: tools/play-upload.sh [track] [release-name]
#   track         internal (default) | alpha | beta | production
#   release-name  shown in the Console; default: pubspec versionName
#
# Release notes come from docs/play/release-notes.txt (edit per release).
#
# Needs android/keystore/play-api-key.json — a service-account JSON key whose
# email has been invited in Play Console (Users and permissions) with
# "Release apps to testing tracks" on this app. The keystore dir is gitignored.
#
# The release is created with status "draft": nothing rolls out until you
# press the button in the Console, so this is safe to run any time after
# `flutter build appbundle --release`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="io.github.invertium.bmsdash"
TRACK="${1:-internal}"
KEY="$ROOT/android/keystore/play-api-key.json"
AAB="$ROOT/build/app/outputs/bundle/release/app-release.aab"
NOTES_FILE="$ROOT/docs/play/release-notes.txt"

case "$TRACK" in
  internal|alpha|beta|production) ;;
  *) echo "Unknown track '$TRACK' (internal|alpha|beta|production)"; exit 1 ;;
esac

[ -f "$KEY" ] || { echo "Missing $KEY (service-account key)"; exit 1; }
[ -f "$AAB" ] || { echo "Missing $AAB — build it first:
  docker compose run --rm flutter flutter build appbundle --release"; exit 1; }
[ -f "$NOTES_FILE" ] || { echo "Missing $NOTES_FILE (per-release notes)"; exit 1; }

# The bundle-upload response carries only versionCode/sha, never a version
# name, so the name must come from pubspec (or the second argument).
PUBSPEC_VERSION=$(sed -n 's/^version: *//p' "$ROOT/pubspec.yaml" | head -n1)
NAME="${2:-${PUBSPEC_VERSION%%+*}}"
[ -n "$NAME" ] || { echo "Could not derive a release name from pubspec.yaml"; exit 1; }
NOTES=$(cat "$NOTES_FILE")

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# --- OAuth2 service-account flow (RS256 JWT -> access token) ---
IAT=$(date +%s)
HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
CLAIMS=$(jq -cn --arg iss "$(jq -r .client_email "$KEY")" --argjson iat "$IAT" \
  '{iss:$iss, scope:"https://www.googleapis.com/auth/androidpublisher",
    aud:"https://oauth2.googleapis.com/token", iat:$iat, exp:($iat+3600)}' | b64url)
SIG=$(printf '%s.%s' "$HEADER" "$CLAIMS" \
  | openssl dgst -sha256 -sign <(jq -r .private_key "$KEY") -binary | b64url)
TOKEN=$(curl -sS https://oauth2.googleapis.com/token \
  -d grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer \
  -d assertion="$HEADER.$CLAIMS.$SIG" | jq -r '.access_token // empty')
[ -n "$TOKEN" ] || { echo "Authentication failed (no access token)"; exit 1; }

API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PKG"
UPLOAD_API="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PKG"
EDIT=""

# req METHOD URL [CONTENT_TYPE BODY] -> sets RESPONSE; prints the API error
# body (never the token) and the open edit id on failure.
req() {
  local method=$1 url=$2 out code
  if [ $# -ge 4 ]; then
    out=$(curl -sS -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: $3" --data-binary "$4" -w $'\n%{http_code}' "$url")
  else
    out=$(curl -sS -X "$method" -H "Authorization: Bearer $TOKEN" \
      -w $'\n%{http_code}' "$url")
  fi
  code=${out##*$'\n'}
  RESPONSE=${out%$'\n'*}
  if [ "${code:0:1}" != 2 ]; then
    echo "API error $code from ${url#"$API"}:" >&2
    echo "$RESPONSE" >&2
    [ -n "$EDIT" ] && echo "(edit $EDIT left uncommitted; it expires on its own)" >&2
    exit 1
  fi
}

echo "Opening edit..."
req POST "$API/edits"
EDIT=$(jq -r '.id // empty' <<<"$RESPONSE")
[ -n "$EDIT" ] || { echo "No edit id in response: $RESPONSE"; exit 1; }

echo "Uploading $(du -h "$AAB" | cut -f1) AAB (this takes a while)..."
req POST "$UPLOAD_API/edits/$EDIT/bundles?uploadType=media" \
  application/octet-stream @"$AAB"
VC=$(jq -r '.versionCode // empty' <<<"$RESPONSE")
[ -n "$VC" ] || { echo "No versionCode in upload response: $RESPONSE"; exit 1; }
echo "Uploaded versionCode $VC"

echo "Assigning to '$TRACK' track as draft release '$NAME'..."
BODY=$(jq -n --arg name "$NAME" --arg vc "$VC" --arg notes "$NOTES" \
  '{releases:[{name:$name, versionCodes:[$vc], status:"draft",
     releaseNotes:[{language:"en-US", text:$notes}]}]}')
req PUT "$API/edits/$EDIT/tracks/$TRACK" application/json "$BODY"

echo "Committing edit..."
req POST "$API/edits/$EDIT:commit"

echo "Done: draft release '$NAME' (versionCode $VC) on the $TRACK track."
echo "Roll it out in the Play Console when ready."
