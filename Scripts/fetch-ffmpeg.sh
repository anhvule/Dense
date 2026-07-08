#!/bin/bash
# Scripts/fetch-ffmpeg.sh — download static ffmpeg/ffprobe for both arches, lipo into universal binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Tools/bin Tools/tmp
for tool in ffmpeg ffprobe; do
  # arm64 static builds
  curl -L -o "Tools/tmp/${tool}-arm64.zip" "https://www.osxexperts.net/${tool}71arm.zip"
  # x86_64 static builds
  curl -L -o "Tools/tmp/${tool}-x86.zip" "https://evermeet.cx/ffmpeg/getrelease/${tool}/zip"
  unzip -o "Tools/tmp/${tool}-arm64.zip" -d "Tools/tmp/arm64-${tool}"
  unzip -o "Tools/tmp/${tool}-x86.zip" -d "Tools/tmp/x86-${tool}"
  lipo -create "Tools/tmp/arm64-${tool}/${tool}" "Tools/tmp/x86-${tool}/${tool}" -output "Tools/bin/${tool}"
  chmod +x "Tools/bin/${tool}"
done
rm -rf Tools/tmp
echo "Universal binaries ready:" && lipo -archs Tools/bin/ffmpeg
