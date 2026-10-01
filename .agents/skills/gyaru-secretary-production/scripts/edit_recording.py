#!/usr/bin/env python3
"""Plan, preview, render, or verify the project's panel-blur/chat-zoom edit."""
import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

PRESET = Path(__file__).resolve().parents[1] / 'assets/outfit-recording-edit.json'


def probe(path):
    return json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)
    ]))


def video(meta):
    return next(s for s in meta['streams'] if s['codec_type'] == 'video')


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError('Configuration numbers must be finite.')
    return format(value, '.12g')


def filters(cfg, meta):
    width, height = cfg['resolution']
    v = video(meta)
    if [v['width'], v['height']] != [width, height]:
        raise ValueError('Recording dimensions differ from the preset; inspect and adapt the rectangles first.')
    fps = cfg['fps']
    if fps <= 0:
        raise ValueError('fps must be positive')
    duration = float(meta['format']['duration'])
    regions = cfg['blur_regions']
    graph, base = [], '0:v'
    if regions:
        graph.append('[0:v]split=' + str(len(regions) + 1) + '[base]' + ''.join(f'[r{i}]' for i in range(len(regions))))
        base = 'base'
    for i, rect in enumerate(regions):
        x, y, w, h = [rect[k] for k in ('x', 'y', 'width', 'height')]
        if not all(isinstance(a, int) for a in (x, y, w, h)) or min(x, y) < 0 or min(w, h) <= 0 or x+w > width or y+h > height:
            raise ValueError('Blur rectangle lies outside the source or has invalid coordinates.')
        sigma, steps = rect['sigma'], rect.get('steps', 3)
        if sigma <= 0 or not isinstance(steps, int) or not 1 <= steps <= 6:
            raise ValueError('Invalid Gaussian blur settings.')
        graph.append(f'[r{i}]crop={w}:{h}:{x}:{y},gblur=sigma={number(sigma)}:steps={steps}[b{i}]')
        graph.append(f'[{base}][b{i}]overlay={x}:{y}[base{i}]')
        base = f'base{i}'
    z = cfg['zoom']
    factor = z['factor']
    if factor <= 1:
        raise ValueError('Zoom factor must exceed 1; use an empty windows list for blur only.')
    px, py = z['crop_origin']
    if not (0 <= px <= width-width/factor and 0 <= py <= height-height/factor):
        raise ValueError('Full-zoom crop is outside the source.')
    weights, previous_end = [], 0
    for window in z['windows']:
        a, b = window['in']
        if not 0 <= previous_end <= a < b <= duration:
            raise ValueError('Zoom windows must be ordered, non-overlapping and within the recording.')
        rise = f'(1-cos(PI*(in_time-{number(a)})/{number(b-a)}))/2'
        tail = '1'
        if 'out' in window:
            c, d = window['out']
            if not b <= c < d <= duration:
                raise ValueError('Zoom out must follow zoom in and fit within the recording.')
            fall = f'(1+cos(PI*(in_time-{number(c)})/{number(d-c)}))/2'
            tail = f'if(lt(in_time,{number(c)}),1,if(lt(in_time,{number(d)}),{fall},0))'
            previous_end = d
        else:
            previous_end = duration
        weights.append(f'if(lt(in_time,{number(a)}),0,if(lt(in_time,{number(b)}),{rise},{tail}))')
    zoom = '1' if not weights else '1+' + number(factor-1) + '*(' + '+'.join(weights) + ')'
    # Keep the ratio as a fraction: rounding it first can shift a crop by one pixel.
    x = '(iw-iw/zoom)*' + number(px) + '/' + number(width-width/factor)
    y = '(ih-ih/zoom)*' + number(py) + '/' + number(height-height/factor)
    graph.append(f"[{base}]setpts=PTS-STARTPTS,fps={number(fps)},zoompan=z='{zoom}':x='{x}':y='{y}':d=1:s={width}x{height}:fps={number(fps)},setsar=1[out]")
    return ';'.join(graph)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'preview', 'render', 'verify'])
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--config', type=Path, default=PRESET)
    parser.add_argument('--at', type=float, help='Source timestamp for preview')
    parser.add_argument('--encoder', choices=['h264_videotoolbox', 'libx264'], default='h264_videotoolbox')
    args = parser.parse_args()
    cfg = json.loads(args.config.read_text())
    meta = probe(args.input)
    graph = filters(cfg, meta)
    if args.action == 'plan':
        print(json.dumps({'source_duration': meta['format']['duration'], 'filter': graph, 'config': cfg}, ensure_ascii=False, indent=2))
        return
    if args.output is None:
        parser.error('--output is required for preview/render/verify')
    if args.input.resolve() == args.output.resolve():
        raise ValueError('The source recording cannot be overwritten.')
    if args.action == 'verify':
        result = probe(args.output)
        if [video(result)['width'], video(result)['height']] != cfg['resolution']:
            raise ValueError('Output resolution differs from the edit configuration.')
        delta = abs(float(result['format']['duration']) - float(meta['format']['duration']))
        if delta > max(0.1, 3/cfg['fps']):
            raise ValueError(f'Unexpected duration change: {delta:.6f} seconds')
        audio_count = lambda m: sum(s['codec_type'] == 'audio' for s in m['streams'])
        if audio_count(meta) != audio_count(result):
            raise ValueError('Audio stream count changed.')
        subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-i', str(args.output), '-f', 'null', '-'], check=True)
        print(json.dumps({'full_decode': 'passed', 'duration_delta_seconds': delta, 'video': video(result), 'audio_streams': audio_count(result)}, ensure_ascii=False, indent=2))
        return
    if args.output.exists():
        raise FileExistsError('Output exists; choose a new name instead of overwriting it.')
    command = ['ffmpeg', '-n', '-hide_banner', '-loglevel', 'warning']
    if args.action == 'preview':
        if args.at is None or not math.isfinite(args.at) or not 0 <= args.at < float(meta['format']['duration']):
            parser.error('--at must be a valid source timestamp for preview')
        graph = graph.replace('in_time', number(args.at)).replace('setsar=1[out]', 'setsar=1,scale=2048:-1[out]')
        command += ['-ss', number(args.at)]
    command += ['-i', str(args.input), '-filter_complex', graph, '-map', '[out]']
    if args.action == 'preview':
        command += ['-frames:v', '1', '-update', '1']
    else:
        command += ['-map', '0:a?', '-c:v', args.encoder]
        command += ['-b:v', cfg.get('bitrate', '32M'), '-profile:v', 'high'] if args.encoder == 'h264_videotoolbox' else ['-crf', '18', '-preset', 'medium']
        command += ['-pix_fmt', 'yuv420p', '-c:a', 'copy', '-map_metadata', '-1', '-movflags', '+faststart']
    subprocess.run(command + [str(args.output)], check=True)
    print(args.output.resolve())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, FileNotFoundError, FileExistsError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
