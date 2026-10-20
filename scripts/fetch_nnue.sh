#!/bin/sh
# Copies Stockfish's two neural network files into the app bundle.
#
# Stockfish needs them to think, and they are too big for git (about 78 MB),
# so they are downloaded once into .nnue-cache and reused on later builds.
# Xcode runs this as a build phase (see project.yml).
#
# Usage: scripts/fetch_nnue.sh <destination-folder>
set -eu

DEST="${1:?Usage: fetch_nnue.sh <destination-folder>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/.nnue-cache"
mkdir -p "$CACHE" "$DEST"

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    sha256sum "$1" | cut -d ' ' -f 1
  fi
}

for NAME in nn-1111cefa1111 nn-37f18f62d772; do
  FILE="$CACHE/$NAME.nnue"
  if [ ! -s "$FILE" ]; then
    echo "Downloading $NAME.nnue"
    TMP="$FILE.download"
    curl -fsSL --retry 3 -o "$TMP" "https://raw.githubusercontent.com/official-stockfish/networks/master/$NAME.nnue" ||
      curl -fsSL --retry 3 -o "$TMP" "https://tests.stockfishchess.org/api/nn/$NAME.nnue" || {
        rm -f "$TMP"
        echo "error: could not download $NAME.nnue (a Stockfish network). Check your network connection, or copy the file into $CACHE." >&2
        exit 1
      }
    # The name is the start of the file's SHA-256, so a bad download is caught here.
    EXPECTED="${NAME#nn-}"
    ACTUAL="$(sha256 "$TMP")"
    case "$ACTUAL" in
      "$EXPECTED"*) mv "$TMP" "$FILE" ;;
      *) rm -f "$TMP"; echo "error: $NAME.nnue failed its checksum" >&2; exit 1 ;;
    esac
  fi
  if ! cmp -s "$FILE" "$DEST/$NAME.nnue" 2>/dev/null; then
    cp -f "$FILE" "$DEST/$NAME.nnue"
  fi
done
