"""站点发布服务：重新构建官网并同步上线。

为什么要独立成一个模块：
「发布站点」是**站点级系统操作**，不属于任何一个内容模块 ——
博客发布、将来的版本发布、以及系统管理里的手动发布，都走这里，
保证"构建 + 同步"只有一份实现（这也是本站发布流程的唯一执行者）。
"""

import datetime
import json
import os
import subprocess
import sys
import threading

SITE_DIR = os.environ.get("ZGJ_SITE_DIR", "/www/wwwroot/zhiguanjia-site")
WEB_ROOT = os.environ.get("ZGJ_WEB_ROOT", "/www/wwwroot/zhidongni.com.cn")
_CST = datetime.timedelta(hours=8)

# 构建必须**串行**：两次构建并发写同一个 dist/ 会互相覆盖，
# 轻则产物错乱、重则线上页面半新半旧。拿不到锁就如实告知"正在构建"。
_build_lock = threading.Lock()

# 最近一次发布的记录：**落盘**保存。
# 为什么不放内存：服务端是多 worker（uvicorn --workers 2），
# 内存里的记录只有写入它的那个 worker 能看到，状态查询落到别的 worker 就会读到空
# （实测踩过）；落盘后跨进程、跨重启都一致，而且记录的是"真实最近一次发布"。
_LAST_BUILD_FILE = os.path.join(SITE_DIR, ".last_build.json")


def get_last_build() -> dict | None:
    try:
        with open(_LAST_BUILD_FILE, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) and data else None
    except Exception:
        return None


def _save_last_build(result: dict) -> None:
    record = {
        "ok": result["ok"],
        "message": result["message"],
        "at": (datetime.datetime.utcnow() + _CST).isoformat(timespec="seconds"),
    }
    try:
        with open(_LAST_BUILD_FILE, "w", encoding="utf-8") as f:
            json.dump(record, f, ensure_ascii=False)
    except Exception:
        pass  # 记录失败不影响发布本身


def _tail(text: str, n: int = 500) -> str:
    text = (text or "").strip()
    return text[-n:] if len(text) > n else text


def rebuild_and_deploy() -> dict:
    """重新构建并同步到站点根目录；返回 {ok, message, busy?}"""
    if not os.path.isdir(SITE_DIR):
        return {"ok": False, "message": f"站点源码目录不存在：{SITE_DIR}"}
    if not _build_lock.acquire(blocking=False):
        return {"ok": False, "busy": True, "message": "另一个构建正在进行，请稍等几秒再试"}
    try:
        result = _rebuild_locked()
    finally:
        _build_lock.release()
    _save_last_build(result)
    return result


def _rebuild_locked() -> dict:
    for script, label in (("build.py", "构建"), ("sync_site.py", "部署")):
        try:
            proc = subprocess.run(
                [sys.executable, script],
                cwd=SITE_DIR,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "message": f"{label}异常：{exc}"}
        if proc.returncode != 0:
            return {"ok": False, "message": f"{label}失败：{_tail(proc.stderr or proc.stdout)}"}
    return {"ok": True, "message": "已重新构建并发布到官网"}
