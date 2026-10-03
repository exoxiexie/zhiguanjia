#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
智懂你 · DeepSeek 服务端代理（阿里云函数计算 FC Web 函数）

零依赖版本：仅使用 Python 标准库（http.server + urllib），
无需 pip install 任何第三方包，确保函数计算环境直接可跑。

职责：
  - 接收智懂你 App 的请求（OpenAI 兼容 /chat/completions 与 Anthropic 兼容 /anthropic/v1/messages）
  - 校验调用令牌（X-Proxy-Token），防止随意滥用
  - 注入真实 DeepSeek API Key（仅存于服务端环境变量），转发到上游
  - 流式（SSE）逐块透传，保持与直连完全一致的体验
"""

import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

# ── 环境变量（在函数计算控制台配置）──
DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
PROXY_TOKEN = os.environ.get("PROXY_TOKEN", "")
DEEPSEEK_BASE = os.environ.get("DEEPSEEK_BASE", "https://api.deepseek.com")

# 透传给客户端的响应头白名单
_PASSTHROUGH_HEADERS = {
    "content-type",
    "content-encoding",
    "x-request-id",
    "x-ds-trace-id",
    "cache-control",
    "expires",
    "retry-after",
    "transfer-encoding",
}

# 需要透传到上游的请求头
_FORWARD_HEADERS = ("Content-Type", "Accept", "anthropic-version", "anthropic-beta")


class ProxyHandler(BaseHTTPRequestHandler):
    # 静默默认日志（避免函数日志被刷屏）
    def log_message(self, format, *args):
        pass

    # ── 统一处理所有 HTTP 方法 ──
    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def do_PUT(self):
        self._handle()

    def do_DELETE(self):
        self._handle()

    def do_PATCH(self):
        self._handle()

    def do_OPTIONS(self):
        # 简单 CORS 预检
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()

    def _handle(self):
        # 1) 健康检查
        if self.path == "/ping":
            configured = bool(DEEPSEEK_API_KEY) and bool(PROXY_TOKEN)
            self._send_json(200, {
                "ok": True,
                "service": "zhidongni-deepseek-proxy",
                "configured": configured,
            })
            return

        # 2) 鉴权：校验调用令牌
        token = self.headers.get("X-Proxy-Token", "")
        if not PROXY_TOKEN or token != PROXY_TOKEN:
            self._send_json(401, {"error": {"message": "unauthorized: invalid proxy token"}})
            return
        if not DEEPSEEK_API_KEY:
            self._send_json(500, {"error": {"message": "server not configured: DEEPSEEK_API_KEY missing"}})
            return

        # 3) 读取请求体
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        # 4) 组装上游请求
        url = f"{DEEPSEEK_BASE}{self.path}"
        req = urllib.request.Request(url, data=body, method=self.command)
        req.add_header("Authorization", f"Bearer {DEEPSEEK_API_KEY}")
        req.add_header("x-api-key", DEEPSEEK_API_KEY)
        for h in _FORWARD_HEADERS:
            v = self.headers.get(h)
            if v:
                req.add_header(h, v)

        # 5) 转发并流式透传
        try:
            resp = urllib.request.urlopen(req, timeout=300)
        except urllib.error.HTTPError as e:
            # 上游返回错误（如 401/400/500），原样透传状态码和响应体
            self.send_response(e.code)
            self.send_header("Content-Type", e.headers.get("Content-Type", "application/json"))
            self.end_headers()
            self.wfile.write(e.read())
            return
        except Exception as e:  # noqa: BLE001
            self._send_json(502, {"error": {"message": f"upstream error: {e}"}})
            return

        # 流式透传上游响应
        self.send_response(resp.status)
        for k, v in resp.headers.items():
            if k.lower() in _PASSTHROUGH_HEADERS:
                self.send_header(k, v)
        self.end_headers()
        try:
            while True:
                chunk = resp.read(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            resp.close()

    def _send_json(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    # FC Web 函数通过 FC_SERVER_PORT 环境变量指定监听端口；本地调试默认 9000
    port = int(os.environ.get("FC_SERVER_PORT", "9000"))
    server = HTTPServer(("0.0.0.0", port), ProxyHandler)
    print(f"zhidongni-deepseek-proxy listening on 0.0.0.0:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
