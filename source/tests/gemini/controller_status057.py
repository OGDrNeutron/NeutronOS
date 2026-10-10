"""Disposable loopback fixture for the existing controller status bridge contract."""
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs
import json,time
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  device=parse_qs(urlparse(self.path).query).get('device',[''])[0]
  if device=='event59':time.sleep(2)
  data=json.dumps({'transport':'usb' if device in ('event57','event59') else 'bluetooth'}).encode()
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers()
  try:self.wfile.write(data)
  except BrokenPipeError:pass
 def log_message(self,*args):pass
ThreadingHTTPServer(('127.0.0.1',48174),Handler).serve_forever()
