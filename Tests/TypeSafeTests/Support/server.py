"""Loopback-only server for HTTPClient tests; never contacts the TypeSafe API."""
import json
import signal
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Foundation Process can inherit blocked signals from a Swift worker on Linux.
# Restore the mask so Process.terminate() can stop this test server.
signal.pthread_sigmask(signal.SIG_SETMASK, [])

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path.startswith('/stall/'):
            time.sleep(30)
        if self.path.startswith('/retry/') and not self.headers.get('x-typesafe-retry-count'):
            self.respond(429, {'message': 'retry'}, {'retry-after-ms': '0'})
            return
        if self.path.startswith('/large/'):
            self.respond(200, {'models': [], 'padding': 'x' * 8192})
            return
        self.respond(200, {'models': [{'name': 'loopback', 'description': 'test', 'release_date': '2026-09-18'}]}, slow=self.path.startswith('/slowbody/'))
    def do_POST(self):
        if self.headers.get('transfer-encoding', '').lower() == 'chunked':
            chunks = []
            while True:
                size = int(self.rfile.readline().split(b';')[0], 16)
                if size == 0:
                    while self.rfile.readline() != b'\r\n':
                        pass
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.read(2)
            data = b''.join(chunks)
        else:
            data = self.rfile.read(int(self.headers.get('content-length', 0)))
        body = json.loads(data)
        answers = {}
        for key, question in body['questions'].items():
            if question['type'] == 'noul':
                answers[key] = {'type': 'noul', 'noul': 0.75}
            elif question['type'] == 'choice':
                labels = list(question['criteria'])
                answers[key] = {'type': 'choice', 'choice': labels[0], 'confidence': 1, 'probabilities': {k: int(k == labels[0]) for k in labels}}
            else:
                rubric = question['criteria']
                answers[key] = {'type': 'score', 'score': 0, 'confidence': 1, 'legend': {str(i): c for i, c in enumerate(rubric)}, 'probabilities': {str(i): int(i == 0) for i in range(len(rubric))}}
        self.respond(200, {'model': body['model'], 'usage': {}, 'answers': answers})
    def respond(self, status, body, extra=None, slow=False):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('x-typesafe-request-id', 'loopback-request')
        self.send_header('x-seen-authorization', self.headers.get('authorization', ''))
        self.send_header('x-seen-retry', self.headers.get('x-typesafe-retry-count', ''))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if slow:
            self.wfile.write(data[:1])
            self.wfile.flush()
            time.sleep(30)
        try:
            self.wfile.write(data[1:] if slow else data)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
