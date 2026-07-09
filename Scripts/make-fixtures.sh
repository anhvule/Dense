#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures
Tools/bin/ffmpeg -y -f lavfi -i "testsrc=duration=2:size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -c:v libx264 -b:v 6M -minrate 6M -maxrate 6M -bufsize 12M -x264-params nal-hrd=cbr \
  -pix_fmt yuv420p -c:a aac -shortest Fixtures/clip-2s.mp4
Tools/bin/ffmpeg -y -f lavfi -i "testsrc=duration=8:size=1920x1080:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=8" \
  -c:v libx264 -b:v 8M -pix_fmt yuv420p -c:a aac -shortest Fixtures/clip-8s-1080p.mp4

# Noisy high-quality still images for ImageCompressor tests. testsrc2 carries
# more high-frequency detail than testsrc, so quality/downsample settings
# produce meaningfully different output sizes instead of trivially collapsing.
# photo.jpg is re-encoded from the lossless PNG via sips at max JPEG quality
# (~400KB) rather than straight out of ffmpeg's mjpeg encoder, so it's large
# enough that even a "good" quality re-encode (q=0.9) still shrinks it.
Tools/bin/ffmpeg -y -f lavfi -i "testsrc2=size=1600x1200:rate=1" -frames:v 1 -update 1 Fixtures/photo.png
sips -s format jpeg -s formatOptions 100 Fixtures/photo.png --out Fixtures/photo.jpg >/dev/null
sips -s format heic Fixtures/photo.jpg --out Fixtures/photo.heic >/dev/null
echo done
