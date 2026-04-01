#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <video-file.(mp4|webm|...)>" >&2
  exit 1
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe not found. Install ffmpeg/ffprobe first." >&2
  exit 1
fi

FFPROBE_JSON="$(ffprobe -v error \
  -show_entries \
stream=index,codec_type,codec_name,codec_long_name,profile,width,height,pix_fmt,r_frame_rate,avg_frame_rate,bit_rate,duration,nb_frames,color_space,color_transfer,color_primaries,field_order,level,codec_tag_string,display_aspect_ratio,sample_aspect_ratio,channels,channel_layout,sample_rate \
  -show_entries \
format=filename,format_name,format_long_name,duration,size,bit_rate,probe_score,tags \
  -of json "$FILE")"

PYCODE=$(cat <<'PY'
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
    print("Error: no ffprobe output", file=sys.stderr)
    sys.exit(1)

data = json.loads(raw)
streams = data.get("streams", [])
fmt = data.get("format", {})

video = next((s for s in streams if s.get("codec_type") == "video"), None)
audio = next((s for s in streams if s.get("codec_type") == "audio"), None)

def to_float(x):
    try:
        return float(x)
    except Exception:
        return None

def fmt_bps(v):
    f = to_float(v)
    if f is None:
        return "N/A"
    return f"{int(round(f)):,} bps (~{f/1_000_000:.2f} Mbps)"

def fmt_audio_bps(v):
    f = to_float(v)
    if f is None:
        return "N/A"
    return f"{int(round(f)):,} bps (~{f/1000:.1f} kbps)"

def fmt_dur(v):
    f = to_float(v)
    return f"{f:.4f} s" if f is not None else "N/A"

def parse_ratio(r):
    if not r or r == "0/0":
        return None
    try:
        a, b = r.split("/")
        a = float(a)
        b = float(b)
        if b == 0:
            return None
        return a / b
    except Exception:
        return None

def fmt_fps(r):
    f = parse_ratio(r)
    return f"{f:.2f} fps ({r})" if f is not None else "N/A"

def fmt_size(v):
    f = to_float(v)
    if f is None:
        return "N/A"
    mb = f / 1_000_000
    return f"{int(f):,} bytes (~{mb:.2f} MB)"

print(f"File: {fmt.get('filename', 'N/A')}")
print("\nContainer")
print(f"- Format: {fmt.get('format_name', 'N/A')}")
print(f"- Long name: {fmt.get('format_long_name', 'N/A')}")
print(f"- Duration: {fmt_dur(fmt.get('duration'))}")
print(f"- Size: {fmt_size(fmt.get('size'))}")
print(f"- Overall bitrate: {fmt_bps(fmt.get('bit_rate'))}")
print(f"- Probe score: {fmt.get('probe_score', 'N/A')}")

print("\nVideo")
if video:
    print(f"- Codec: {video.get('codec_long_name', video.get('codec_name', 'N/A'))} ({video.get('codec_name', 'N/A')})")
    print(f"- Profile: {video.get('profile', 'N/A')}")
    print(f"- Level: {video.get('level', 'N/A')}")
    w = video.get('width', 'N/A')
    h = video.get('height', 'N/A')
    print(f"- Resolution: {w}x{h}")
    print(f"- SAR / DAR: {video.get('sample_aspect_ratio', 'N/A')} / {video.get('display_aspect_ratio', 'N/A')}")
    print(f"- Pixel format: {video.get('pix_fmt', 'N/A')}")
    print(f"- Scan type: {video.get('field_order', 'N/A')}")
    print(f"- Color: space={video.get('color_space', 'N/A')}, transfer={video.get('color_transfer', 'N/A')}, primaries={video.get('color_primaries', 'N/A')}")
    print(f"- FPS (nominal): {fmt_fps(video.get('r_frame_rate'))}")
    print(f"- FPS (avg): {fmt_fps(video.get('avg_frame_rate'))}")
    print(f"- Video bitrate: {fmt_bps(video.get('bit_rate'))}")
    print(f"- Duration: {fmt_dur(video.get('duration'))}")
    print(f"- Frames: {video.get('nb_frames', 'N/A')}")
else:
    print("- No video stream found")

print("\nAudio")
if audio:
    print(f"- Codec: {audio.get('codec_long_name', audio.get('codec_name', 'N/A'))} ({audio.get('codec_name', 'N/A')})")
    print(f"- Profile: {audio.get('profile', 'N/A')}")
    print(f"- Sample rate: {audio.get('sample_rate', 'N/A')} Hz")
    print(f"- Channels: {audio.get('channels', 'N/A')} ({audio.get('channel_layout', 'N/A')})")
    print(f"- Audio bitrate: {fmt_audio_bps(audio.get('bit_rate'))}")
    print(f"- Duration: {fmt_dur(audio.get('duration'))}")
    print(f"- Frames: {audio.get('nb_frames', 'N/A')}")
else:
    print("- No audio stream found")

if video and audio:
    vd = to_float(video.get('duration'))
    ad = to_float(audio.get('duration'))
    if vd is not None and ad is not None and abs(vd - ad) > 0.25:
        print("\n⚠ Note: video/audio stream durations differ noticeably.")
PY
)

python3 -c "$PYCODE" <<<"$FFPROBE_JSON"
