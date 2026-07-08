#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures
Tools/bin/ffmpeg -y -f lavfi -i "testsrc=duration=2:size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest Fixtures/clip-2s.mp4
Tools/bin/ffmpeg -y -f lavfi -i "testsrc=duration=8:size=1920x1080:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=8" \
  -c:v libx264 -b:v 8M -pix_fmt yuv420p -c:a aac -shortest Fixtures/clip-8s-1080p.mp4
echo done
