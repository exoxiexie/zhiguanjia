#!/usr/bin/env python3
"""职管家 · DeepSeek 对话代理

把 App 的对话请求转发到 DeepSeek API，API Key 只保存在本机，不进入 App。
用法：POST /chat  {"model": "...", "messages": [{"role":"user","content":"..."}]}
返回：{"reply": "..."}
"""
import json
import os
import re
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8001
DEFAULT_MODEL = "deepseek-v4-flash-vision-exp"
DEEPSEEK_URL = "https://api.deepseek.com/chat/completions"


def load_api_key():
    """从 ~/.zshrc 读取 DEEPSEEK_API_KEY（匹配 sk- 开头的真实密钥），避免硬编码在脚本里。"""
    try:
        with open(os.path.expanduser("~/.zshrc"), encoding="utf-8") as f:
            for line in f:
                m = re.search(r'DEEPSEEK_API_KEY\s*=\s*[\"\']?(sk-[A-Za-z0-9_-]+)', line)
                if m:
                    return m.group(1)
    except Exception:
        pass
    return os.environ.get("DEEPSEEK_API_KEY", "")


API_KEY = load_api_key()

# 中文序号（一到三十），用于把有序列表 "1. " 转成 "一、 "
_CN_NUMS = [
    "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
    "二十一", "二十二", "二十三", "二十四", "二十五", "二十六", "二十七", "二十八", "二十九", "三十",
]


def md_to_cn_text(text):
    """把模型输出的 Markdown 转成符合中文阅读习惯的纯文本。

    - 去掉 # / * / ` / > 等 Markdown 标记
    - 有序列表 "1. 2." → "一、 二、"
    - 无序列表 "- *" → "·"
    - 链接 [文字](url) → 文字
    """
    lines = text.split("\n")
    out = []
    for raw in lines:
        line = raw
        # 跳过代码块围栏 ``` / ~~~
        if re.match(r"^\s*(```+|~~~+)", line):
            continue
        # 去掉引用标记 "> "
        line = re.sub(r"^\s*>\s?", "", line)
        # 去掉标题标记 "#### " / "### " / ...
        line = re.sub(r"^\s*#{1,6}\s*", "", line)
        # 有序列表 "1. " / "1、 " / "1) " → "一、 "
        m = re.match(r"^\s*(\d{1,2})[.、)）]\s*", line)
        if m:
            num = int(m.group(1))
            rest = line[m.end():]
            if 1 <= num <= len(_CN_NUMS):
                line = _CN_NUMS[num - 1] + "、" + (rest if rest else " ")
            else:
                line = rest
        else:
            # 无序列表 "- " / "* " / "• " → "· "
            m2 = re.match(r"^\s*[-*•]\s+", line)
            if m2:
                line = "· " + line[m2.end():]
        # 去掉加粗 / 斜体 / 删除线
        line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)
        line = re.sub(r"__([^_\n]+?)__", r"\1", line)
        line = re.sub(r"\*([^*\n]+)\*", r"\1", line)
        line = re.sub(r"~~([^~\n]+?)~~", r"\1", line)
        # 去掉行内代码 `code`
        line = re.sub(r"`([^`\n]+?)`", r"\1", line)
        # 图片 / 链接 → 保留文字
        line = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", line)
        line = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", line)
        out.append(line)
    result = "\n".join(out)
    # 连续空行压成一个
    result = re.sub(r"\n{3,}", "\n\n", result)
    return result.strip()


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        if self.path != "/chat":
            self._send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b"{}"
            req = json.loads(raw or b"{}")
            messages = req.get("messages", [])
            model = req.get("model", DEFAULT_MODEL)
            max_tokens = req.get("max_tokens", 1024)

            if not messages:
                self._send_json(400, {"error": "messages required"})
                return

            payload = {
                "model": model,
                "messages": messages,
                "max_tokens": max_tokens,
            }
            r = urllib.request.Request(
                DEEPSEEK_URL,
                data=json.dumps(payload).encode(),
                headers={
                    "Content-Type": "application/json",
                    "Authorization": "Bearer " + API_KEY,
                },
            )
            with urllib.request.urlopen(r, timeout=180) as resp:
                data = json.loads(resp.read())
            msg = data["choices"][0]["message"]
            # 该模型会先输出思考(reasoning_content)再输出正文(content)；
            # 极少数情况 content 为空时兜底返回思考内容，避免用户看到空白。
            reply = msg.get("content") or msg.get("reasoning_content") or ""
            if not reply:
                reply = "（模型未返回内容，请重试）"
            # 把 Markdown 转成符合中文阅读习惯的纯文本
            reply = md_to_cn_text(reply)
            self._send_json(200, {"reply": reply, "model": data.get("model", model)})
        except Exception as e:
            self._send_json(500, {"error": str(e)})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"职管家 DeepSeek 代理启动: 端口 {PORT}, 模型 {DEFAULT_MODEL}, Key {'已配置' if API_KEY else '未配置'}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
