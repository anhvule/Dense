#!/bin/bash
# Scripts/fetch-ffmpeg.sh — download PINNED static ffmpeg/ffprobe for both arches, verify, lipo universal.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Tools/bin Tools/tmp

# Pinned 2026-07-14. To bump: update URL+SHA together (see docs block below).
# NOTE: macOS ships bash 3.2 (no `declare -A` / associative arrays), so pins are
# kept as three parallel indexed arrays, matched positionally by index.
KEYS=(ffmpeg-arm64 ffprobe-arm64 ffmpeg-x86 ffprobe-x86)
URLS=(
  "https://www.osxexperts.net/ffmpeg71arm.zip"
  "https://www.osxexperts.net/ffprobe71arm.zip"
  "https://evermeet.cx/ffmpeg/ffmpeg-7.1.zip"
  "https://evermeet.cx/ffmpeg/ffprobe-7.1.zip"
)
SHAS=(
  "0878f3313311c2c1b2c818e7c955c0bd828c97b357fa86211b42a5c36d01e36f"
  "156a2c4da546e7d86877dd204df026eeda79aee8a80af8f04cd00f9b02687aa0"
  "5a1303c7babaffff3c32c141ff49c7f44bd3b3b3e7dcea992fd7d04b6558ef43"
  "fc289c963346d7dc0891cbaed02ba270e8abec54df9259e22d59559018b25709"
)

# All four pinned to ffmpeg/ffprobe 7.1 — matches the binary this app currently bundles
# and passes the full test suite against. Do not bump one URL without the others; verify
# the new binary still passes `swift test --package-path DenseCore` before re-pinning.
# To bump: pick the new versioned URL(s), `curl -L --fail -o /tmp/pin.zip "<url>" && shasum -a 256 /tmp/pin.zip`,
# then update both the URL and SHA above together (keeping KEYS/URLS/SHAS aligned by index).

for i in "${!KEYS[@]}"; do
  key="${KEYS[$i]}"
  curl -L --fail -o "Tools/tmp/${key}.zip" "${URLS[$i]}"
  echo "${SHAS[$i]}  Tools/tmp/${key}.zip" | shasum -a 256 -c - \
    || { echo "ERROR: checksum mismatch for ${key} — upstream changed, re-pin deliberately" >&2; exit 1; }
  unzip -o "Tools/tmp/${key}.zip" -d "Tools/tmp/${key}"
done
for tool in ffmpeg ffprobe; do
  lipo -create "Tools/tmp/${tool}-arm64/${tool}" "Tools/tmp/${tool}-x86/${tool}" -output "Tools/bin/${tool}"
  chmod +x "Tools/bin/${tool}"
done
rm -rf Tools/tmp
echo "Universal binaries ready:" && lipo -archs Tools/bin/ffmpeg
