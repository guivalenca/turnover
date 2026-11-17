#!/bin/zsh
# Regenerates every committed test fixture in Tests/TurnoverTestSupport/Fixtures.
#
# You rarely need this: the fixtures are committed because CI runners may lack HEIC/HEVC
# encoders. Run it only to add or change a fixture, then commit the files it writes.
# Needs: Xcode (swift), Homebrew ffmpeg (with libx264 and libx265) and cwebp (brew install webp).
set -euo pipefail

root=${0:A:h:h}
out=$root/Tests/TurnoverTestSupport/Fixtures
mkdir -p $out
cd $out

swift $root/scripts/make-image-fixtures.swift $out

# photo.webp: lossy WebP of the opaque picture.
cwebp -quiet -q 70 opaque.png -o photo.webp && echo "wrote photo.webp"
rm opaque.png

# Two seconds of the ffmpeg test pattern with a 440 Hz tone, 160×90 at 30 fps.
video=(-f lavfi -i testsrc2=size=160x90:rate=30:duration=2)
audio=(-f lavfi -i sine=frequency=440:sample_rate=44100:duration=2)
aac=(-c:a aac -b:a 32k -ac 1)
ff=(ffmpeg -hide_banner -loglevel error -y)

# clip-h264.mov: H.264 + AAC in QuickTime, like a screen recording or a "Most Compatible" iPhone clip.
$ff $video $audio -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 32 -tag:v avc1 $aac \
  -movflags +faststart -f mov clip-h264.mov && echo "wrote clip-h264.mov"

# clip-h264.mp4: the same streams remuxed into MPEG-4 (the format that must not be offered MP4).
$ff -i clip-h264.mov -c copy -movflags +faststart -f mp4 clip-h264.mp4 && echo "wrote clip-h264.mp4"

# clip-hevc-hdr.mov: 10-bit HEVC, HLG BT.2020 (HDR), recorded in portrait like an iPhone:
# stored 160×90 with a 90° clockwise display matrix, so it plays as 90×160. The matrix is added
# by a second, copy-only pass: on an encoding pass ffmpeg would rotate the pixels instead.
$ff $video $audio \
  -c:v libx265 -pix_fmt yuv420p10le -profile:v main10 -tag:v hvc1 \
  -x265-params "log-level=error:crf=30:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc" \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc -color_range tv \
  $aac -f mov hevc-landscape.tmp.mov
$ff -display_rotation -90 -i hevc-landscape.tmp.mov -c copy -movflags +faststart+write_colr \
  -f mov clip-hevc-hdr.mov && echo "wrote clip-hevc-hdr.mov"
rm hevc-landscape.tmp.mov

# notes.txt: plain text, another file Turnover cannot convert.
print "This is not a picture." > notes.txt && echo "wrote notes.txt"

ls -l $out
du -ch $out/* | tail -1
