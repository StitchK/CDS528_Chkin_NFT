from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import re

WEB_ROOT = Path(__file__).resolve().parent


class SpaRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def do_GET(self):
        request_path = urlsplit(self.path).path.rstrip("/")
        if request_path in {"/create", "/dashboard", "/my-nfts"} or re.fullmatch(r"/challenges/\d+", request_path):
            self.path = "/index.html"
        super().do_GET()


if __name__ == "__main__":
    print("CheckIn Web: http://127.0.0.1:4173")
    ThreadingHTTPServer(("127.0.0.1", 4173), SpaRequestHandler).serve_forever()
