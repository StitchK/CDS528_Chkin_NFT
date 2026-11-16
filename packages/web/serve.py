from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class SpaRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        request_path = self.path.split("?", 1)[0]
        if request_path != "/" and not Path(f".{request_path}").is_file():
            self.path = "/index.html"
        super().do_GET()


if __name__ == "__main__":
    print("CheckIn Web: http://127.0.0.1:4173")
    ThreadingHTTPServer(("127.0.0.1", 4173), SpaRequestHandler).serve_forever()
