"""Decode idle clips, record boundary differences, and render visual review sheets."""
import argparse
import hashlib
import io
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest', type=Path, default=ROOT / 'assets/idle-variants.json')
parser.add_argument('--output', type=Path, default=ROOT / 'docs/idle-shiro')
args = parser.parse_args()
OUT = args.output
OUT.mkdir(parents=True, exist_ok=True)


def frame(path, seconds):
    data = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(seconds), '-i', str(path),
                                    '-frames:v', '1', '-vf', 'scale=480:-1', '-f', 'image2pipe', '-vcodec', 'png', '-'])
    return Image.open(io.BytesIO(data)).convert('RGB')


records = []
endpoints = {}
for clip in json.loads(args.manifest.read_text()):
    path = ROOT / 'assets' / clip['file']
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)]))
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    duration = float(video['duration'])
    if abs(float(clip['end']) - duration) > 0.05:
        raise ValueError(f"Manifest duration mismatch: {path}")
    if float(clip['start']) != 0:
        raise ValueError(f"Review requires a zero-based clip: {path}")
    num, den = map(int, video['avg_frame_rate'].split('/'))
    fps = num / den
    subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'null', '-'], check=True)
    times = [0, 1 / fps, 1, 3, 5, 7, 9, 11, 13, duration - 3 / fps, duration - 2 / fps, duration - 1 / fps]
    frames = [frame(path, t) for t in times]
    w, h = frames[0].size
    sheet = Image.new('RGB', (w * 2, (h + 28) * 6), '#202020')
    draw = ImageDraw.Draw(sheet)
    for i, (im, t) in enumerate(zip(frames, times)):
        x, y = (i % 2) * w, (i // 2) * (h + 28)
        sheet.paste(im, (x, y))
        draw.text((x + 8, y + h + 5), f'{path.stem} / {t:.3f}s', fill='white')
    sheet.save(OUT / f'{path.stem}-contact.jpg', quality=90)
    endpoints[path.name] = (np.asarray(frames[0], dtype=float), np.asarray(frames[-1], dtype=float))
    records.append({'file': path.name, 'duration': duration, 'fps': fps, 'width': video['width'], 'height': video['height'],
                    'audio_streams': sum(s['codec_type'] == 'audio' for s in info['streams']),
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'decode': 'passed'})

joins = []
for a, (_, end) in endpoints.items():
    for b, (start, _) in endpoints.items():
        joins.append({'from': a, 'to': b, 'mean_absolute_pixel_difference_0_255': round(float(np.abs(end - start).mean()), 4)})
(OUT / 'verification.json').write_text(json.dumps({'clips': records, 'joins': joins}, indent=2) + '\n')
print(json.dumps({'clips': records, 'joins': joins}, indent=2))
