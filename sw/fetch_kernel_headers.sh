#!/usr/bin/env bash
# Downloads Ubuntu kernel headers into sw/kernel-headers for clangd and clang-tidy.
# Usage: sw/fetch_kernel_headers.sh <version>
# Pass the output of `uname -r` from the server without the -generic suffix.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>, for example 6.8.0-40" >&2
  exit 1
fi

VERSION="${1%-generic}"
SERIES="$(cut -d. -f1,2 <<<"$VERSION")"
ROOT="https://archive.ubuntu.com/ubuntu/pool/main/l"
SW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SW_DIR/kernel-headers"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pool=""
common=""
generic=""
available=""
for candidate in "linux-hwe-$SERIES" linux; do
  listing="$(curl -fsSL "$ROOT/$candidate/" || true)"
  available+="$(grep -oE "linux-headers-${SERIES}\.[0-9]+-[0-9]+-generic_" <<<"$listing" || true)"$'\n'
  common="$(grep -oE "(linux-hwe-${SERIES}-headers|linux-headers)-${VERSION}_[^\"<>]*_all\.deb" <<<"$listing" | sort -u | tail -1 || true)"
  generic="$(grep -oE "linux-headers-${VERSION}-generic_[^\"<>]*_amd64\.deb" <<<"$listing" | sort -u | tail -1 || true)"
  if [[ -n "$common" && -n "$generic" ]]; then
    pool="$ROOT/$candidate"
    break
  fi
done

if [[ -z "$pool" ]]; then
  echo "No Ubuntu headers found for $VERSION." >&2
  echo "Available $SERIES versions (newest last):" >&2
  sed -E 's/linux-headers-//; s/-generic_//' <<<"$available" | grep . | sort -uV | tail -10 >&2 || echo "  none" >&2
  exit 1
fi

extract() {
  local deb="$1" dest="$2"
  mkdir -p "$dest"
  curl -fsSL -o "$TMP/$deb" "$pool/$deb"
  (cd "$dest" && ar x "$TMP/$deb" && zstd -dc data.tar.zst | tar -xf -)
}

extract "$common" "$TMP/common"
extract "$generic" "$TMP/generic"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$TMP"/common/usr/src/*/. "$OUT/"
(cd "$TMP/generic/usr/src/linux-headers-$VERSION-generic" && find . -type f | tar -cf - -T -) | tar -xf - -C "$OUT"

echo "Installed $VERSION headers in $OUT"
