"""Decode the outfit playlist and render timed frames and actual transition pairs."""
import hashlib
import argparse
import io
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/outfit-change/review'
OUT.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest', type=Path, default=ROOT / 'docs/outfit-change/outfit-change.planned.json')
manifest = json.loads(parser.parse_args().manifest.read_text())
clips = manifest['sequence'] + manifest['idle'] + manifest['typing']


def frame(path, seconds):
    data = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(seconds), '-i', str(path),
                                    '-frames:v', '1', '-vf', 'scale=480:270', '-f', 'image2pipe', '-vcodec', 'png', '-'])
    return Image.open(io.BytesIO(data)).convert('RGB')


records, endpoints = [], {}
for clip in clips:
    path = ROOT / 'assets' / clip['file']
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(path)]))
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    duration = float(video['duration'])
    fps_n, fps_d = map(int, video['avg_frame_rate'].split('/'))
    fps = fps_n / fps_d
    assert clip['start'] == 0 and 0 < clip['end'] <= duration + 0.05
    assert not any(s['codec_type'] == 'audio' for s in info['streams'])
    subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'null', '-'], check=True)
    end = min(duration, clip['end']) - 1 / fps
    times = np.linspace(0, end, 12)
    frames = [frame(path, float(t)) for t in times]
    sheet = Image.new('RGB', (960, 6 * 298), '#202020')
    draw = ImageDraw.Draw(sheet)
    for i, (im, t) in enumerate(zip(frames, times)):
        x, y = (i % 2) * 480, (i // 2) * 298
        sheet.paste(im, (x, y))
        draw.text((x + 8, y + 275), f'{path.stem} / {t:.3f}s', fill='white')
    sheet.save(OUT / f'{path.stem}-contact.jpg', quality=90)
    endpoints[path.name] = (frames[0], frames[-1])
    records.append({'file': path.name, 'duration': duration, 'playback_end': clip['end'], 'fps': fps,
                    'width': video['width'], 'height': video['height'], 'audio_streams': 0,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'decode': 'passed'})

sequence = [c['file'] for c in manifest['sequence'] + manifest['idle']]
idle, typing = manifest['idle'][0]['file'], manifest['typing'][0]['file']
pairs = list(zip(sequence, sequence[1:])) + [(idle, idle), (idle, typing), (typing, idle), (typing, typing)]
for name in ('idle-variants.json', 'typing-variants.json'):
    for original in json.loads((ROOT / 'assets' / name).read_text()):
        path = ROOT / 'assets' / original['file']
        endpoints[path.name] = (frame(path, 0), frame(path, original['end'] - 1 / 24))
        pairs.append((path.name, sequence[0]))
joins = []
for i, (a, b) in enumerate(pairs):
    end, start = endpoints[a][1], endpoints[b][0]
    sheet = Image.new('RGB', (960, 298), '#202020'); draw = ImageDraw.Draw(sheet)
    sheet.paste(end, (0, 0)); sheet.paste(start, (480, 0))
    draw.text((8, 275), f'END {a}', fill='white'); draw.text((488, 275), f'START {b}', fill='white')
    sheet.save(OUT / f'join-{i:02}.jpg', quality=90)
    joins.append({'from': a, 'to': b, 'mean_absolute_pixel_difference_0_255':
                  round(float(np.abs(np.asarray(end, dtype=float) - np.asarray(start, dtype=float)).mean()), 4)})
(OUT / 'verification.json').write_text(json.dumps({'clips': records, 'joins': joins}, indent=2) + '\n')
print(json.dumps({'clips': records, 'joins': joins}, indent=2))
