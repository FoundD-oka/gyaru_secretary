#!/usr/bin/env python3
"""Local, authenticated voice bridge. API keys never enter the application bundle."""
import base64
import io
import json
import os
from pathlib import Path
import secrets
import ssl
import threading
import urllib.error
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path.home() / 'Library/Application Support/GyaruSecretary/runtime.json'
TOKEN = secrets.token_urlsafe(32)
BUSY = threading.Lock()
PERSONA = '''あなたは成人のギャル秘書。明るくてハキハキ、お茶目で距離が近い、仕事のできる相棒です。
自然なギャル口調で日本語を話す。大げさなキャラ語尾や絵文字、見下し、過剰なお世辞は避ける。
一人称は「うち」。自分と利用者の名前は未設定。名前を発明せず、〇〇や[名前]などの穴埋め表記も絶対に使わない。
「させていただきます」「かしこまりました」などの営業敬語は使わない。
挨拶の例：「やっほ！ うちが秘書やるから、困ったことあったら言ってね。」
音声会話なので返答は原則1〜3文、150文字以内。わからないことは正直に言う。
今は会話と画面のリアクションだけが使える。カレンダー閲覧、検索、ファイル操作、送信は未接続。
できていない作業を「できた」と言わない。ユーザーの個人情報や予定を作り上げない。'''
PERSONA += '\nあなたは画面の中のAI秘書です。現実の家や場所へ出向く、実物を片づけるなど、身体が必要な行動を約束しない。相談や手順整理で手伝うと伝える。'

def api(model, body):
    key = os.environ.get('GEMINI_API_KEY')
    if not key:
        raise RuntimeError('GEMINI_API_KEY が未設定です。')
    try:
        import certifi
        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        context = ssl.create_default_context()
    request = urllib.request.Request(
        'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent',
        data=json.dumps(body).encode(),
        headers={'Content-Type': 'application/json', 'x-goog-api-key': key})
    try:
        with urllib.request.urlopen(request, timeout=90, context=context) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError('音声サービスが HTTP ' + str(error.code) + ' を返しました。') from None
    except urllib.error.URLError:
        raise RuntimeError('音声サービスへの安全な接続に失敗しました。') from None

def parts(result):
    candidates = result.get('candidates', [])
    return candidates[0].get('content', {}).get('parts', []) if candidates else []

def speak(text):
    style = ('明るくハキハキした成人女性の声。日本語の自然なお茶目なギャル口調。'
             '笑顔を感じる、親しみやすく軽快な声。演技を誇張せず、指示文は読まない。次の台詞だけを話す。\n台詞：')
    result = api(os.environ.get('GYARU_TTS_MODEL', 'gemini-2.5-flash-preview-tts'), {
        'contents': [{'parts': [{'text': style + text}]}],
        'generationConfig': {'responseModalities': ['AUDIO'], 'speechConfig': {
            'voiceConfig': {'prebuiltVoiceConfig': {'voiceName': os.environ.get('GYARU_VOICE', 'Kore')}}}}
    })
    audio = next((p['inlineData'] for p in parts(result) if 'inlineData' in p), None)
    if not audio or not audio.get('mimeType', '').startswith('audio/L16'):
        raise RuntimeError('音声データを取得できませんでした。')
    rate = 24000
    for field in audio['mimeType'].split(';'):
        if field.strip().startswith('rate='):
            rate = int(field.strip().split('=')[1])
    raw = base64.b64decode(audio['data'], validate=True)
    if len(raw) % 2:
        raise RuntimeError('音声データが不正です。')
    output = io.BytesIO()
    with wave.open(output, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(raw)
    return output.getvalue()

def chat(text, history, audio=True):
    contents = []
    for entry in history[-12:]:
        if isinstance(entry, dict) and entry.get('role') in ('user', 'model') and isinstance(entry.get('text'), str):
            contents.append({'role': entry['role'], 'parts': [{'text': entry['text'][:2000]}]})
    contents.append({'role': 'user', 'parts': [{'text': text}]})
    persona = PERSONA if audio else PERSONA.replace('音声会話なので返答は原則1〜3文、150文字以内。', 'テキストチャットです。必要な詳しさで、読みやすく具体的に返答する。').replace('今は会話と画面のリアクションだけが使える。', '今はテキスト会話だけが使える。音声と画面のリアクションは休止中。')
    result = api(os.environ.get('GYARU_CHAT_MODEL', 'gemini-2.5-flash'), {
        'systemInstruction': {'parts': [{'text': persona}]}, 'contents': contents,
        'generationConfig': {'maxOutputTokens': 1024, 'thinkingConfig': {'thinkingBudget': 0}}
    })
    answer = ''.join(p.get('text', '') for p in parts(result) if not p.get('thought')).strip()
    if not answer:
        raise RuntimeError('返答を取得できませんでした。')
    answer = answer[:800] if audio else answer
    response = {'text': answer}
    if not audio:
        return response
    try:
        response['audio'] = base64.b64encode(speak(answer)).decode()
    except RuntimeError as error:
        response['audioError'] = str(error)
    return response

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def authorized(self):
        return secrets.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + TOKEN)

    def do_GET(self):
        if not self.authorized():
            return self.reply(401, {'error': 'Unauthorized'})
        self.reply(200 if self.path == '/health' else 404, {'ready': bool(os.environ.get('GEMINI_API_KEY'))})

    def do_POST(self):
        if not self.authorized() or self.headers.get('Origin'):
            return self.reply(403, {'error': 'Forbidden'})
        if self.path != '/chat':
            return self.reply(404, {'error': 'Not found'})
        try:
            length = int(self.headers.get('Content-Length', 0))
            if not 0 < length < 40000:
                return self.reply(400, {'error': 'Invalid request'})
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError()
            text = body.get('text', '')
            history = body.get('history', [])
            audio = body.get('audio', True)
            if not isinstance(text, str) or not text.strip() or len(text) > 2000 or not isinstance(history, list):
                raise ValueError()
            if not isinstance(audio, bool):
                raise ValueError()
        except (ValueError, TypeError):
            return self.reply(400, {'error': 'Invalid request'})
        if not BUSY.acquire(blocking=False):
            return self.reply(429, {'error': '返答を準備中です。'})
        try:
            self.reply(200, chat(text.strip(), history, audio=audio))
        except RuntimeError as error:
            self.reply(502, {'error': str(error)})
        except Exception:
            self.reply(502, {'error': '音声処理に失敗しました。'})
        finally:
            BUSY.release()

def serve():
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    runtime = {'port': server.server_port, 'token': TOKEN, 'pid': os.getpid()}
    RUNTIME.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(RUNTIME, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as file:
        json.dump(runtime, file)
    print('Voice bridge ready on localhost; microphone remains off.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if RUNTIME.exists() and json.loads(RUNTIME.read_text()).get('token') == TOKEN:
            RUNTIME.unlink()

if __name__ == '__main__':
    serve()
