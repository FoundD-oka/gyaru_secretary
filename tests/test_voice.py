import base64
import importlib.util
import io
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import wave

spec = importlib.util.spec_from_file_location('voice', Path(__file__).resolve().parents[1] / 'server/voice.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)

class VoiceTests(unittest.TestCase):
    def test_pcm_rate_is_preserved(self):
        pcm = b'\x00\x00' * 160
        result = {'candidates': [{'content': {'parts': [{'inlineData': {
            'mimeType': 'audio/L16;codec=pcm;rate=16000', 'data': base64.b64encode(pcm).decode()}}]}}]}
        with patch.object(voice, 'api', return_value=result):
            wav = wave.open(io.BytesIO(voice.speak('テスト')))
            self.assertEqual(wav.getframerate(), 16000)
            self.assertEqual(wav.readframes(160), pcm)

    def test_missing_audio_does_not_claim_success(self):
        with patch.object(voice, 'api', return_value={'candidates': []}):
            with self.assertRaises(RuntimeError): voice.speak('テスト')

    def test_tts_failure_preserves_text(self):
        result = {'candidates': [{'content': {'parts': [{'text': 'おつかれ！'}]}}]}
        with patch.object(voice, 'api', return_value=result), patch.object(voice, 'speak', side_effect=RuntimeError('TTS unavailable')):
            response = voice.chat('こんにちは', [])
            self.assertEqual(response['text'], 'おつかれ！')
            self.assertNotIn('audio', response)
            self.assertIn('audioError', response)

    def test_http_rejects_unauthorized_and_invalid_requests(self):
        server = voice.ThreadingHTTPServer(('127.0.0.1', 0), voice.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        url = 'http://127.0.0.1:' + str(server.server_port)
        try:
            cases = [({}, b'{"text":"hi"}', 403),
                     ({'Authorization': 'Bearer '+voice.TOKEN, 'Origin':'https://example.com'}, b'{"text":"hi"}', 403),
                     ({'Authorization': 'Bearer '+voice.TOKEN}, b'{"text":""}', 400),
                     ({'Authorization': 'Bearer '+voice.TOKEN}, b'[]', 400)]
            with patch.object(voice, 'chat') as chat:
                for headers, body, expected in cases:
                    req = urllib.request.Request(url+'/chat', data=body, headers=headers)
                    with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(req)
                    self.assertEqual(error.exception.code, expected)
                chat.assert_not_called()
        finally:
            server.shutdown(); server.server_close(); thread.join()

if __name__ == '__main__': unittest.main()
