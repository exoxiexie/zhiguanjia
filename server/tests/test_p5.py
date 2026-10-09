"""P5 商业能力测试：设备上报 / 运营统计 / 下发配置 / 数据导出 / 账号注销"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "p5-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_UPLOAD_DIR"] = tempfile.mkdtemp()

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.db import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import AppConfig, Device, User  # noqa: E402

_client = TestClient(app)
_client.__enter__()

PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:200]) if extra and not cond else ""))


def register(phone, name):
    r = _client.post("/auth/register", json={"phone": phone, "password": "test123456", "name": name})
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def h(t):
    return {"Authorization": "Bearer " + t}


A = register("13800001111", "用户A")
B = register("13800002222", "用户B")

print("── 1. 设备上报 ──")
check("未登录上报 → 401",
      _client.post("/device/report", json={"device_id": "d1"}).status_code == 401)
r = _client.post("/device/report", headers=h(A), json={
    "device_id": "dev-a1", "platform": "android", "brand": "Xiaomi",
    "model": "Mi 14", "os_version": "14", "app_version": "1.0.40", "version_code": 41})
check("首次上报 → 200 且 is_new_device=true", r.status_code == 200 and r.json()["is_new_device"] is True, r.text)

r = _client.post("/device/report", headers=h(A), json={
    "device_id": "dev-a1", "app_version": "1.0.41", "version_code": 42})
check("同设备重复上报 → is_new_device=false（不重复计数）",
      r.json()["is_new_device"] is False, r.text)
check("版本信息被更新为最新", r.json()["device"]["app_version"] == "1.0.41", r.json())

r = _client.post("/device/report", headers=h(B), json={
    "device_id": "dev-b1", "platform": "android", "app_version": "1.0.40", "version_code": 41})
check("另一用户另一设备 → is_new_device=true", r.json()["is_new_device"] is True, r.text)

with SessionLocal() as db:
    check("devices 表恰好 2 台设备", len(db.scalars(select(Device)).all()) == 2)

print("── 2. 运营统计（管理员鉴权）──")
r = _client.get("/admin/stats", headers=h(A))
check("普通用户访问统计 → 403", r.status_code == 403, r.text)
check("403 code=forbidden", r.json().get("error", {}).get("code") == "forbidden", r.text)

with SessionLocal() as db:
    u = db.scalar(select(User).where(User.phone == "13800001111"))
    u.is_admin = 1
    db.commit()

r = _client.get("/admin/stats", headers=h(A))
check("管理员访问统计 → 200", r.status_code == 200, r.text)
stats = r.json()
check("装机设备数 = 2", stats["devices"]["total"] == 2, stats["devices"])
check("用户数 = 2", stats["users"]["total"] == 2, stats["users"])
check("活跃设备（1 日）≥ 2", stats["devices"]["active_1d"] >= 2, stats["devices"])
versions = {v["version"]: v["devices"] for v in stats["versions"]}
check("版本分布正确（1.0.41:1, 1.0.40:1）",
      versions.get("1.0.41") == 1 and versions.get("1.0.40") == 1, stats["versions"])
check("含内容量统计", "messages" in stats["content"], stats["content"])

print("── 3. 下发配置（无需登录）──")
r = _client.get("/app/config")
check("未登录可读配置 → 200", r.status_code == 200, r.text)
cfg = r.json()
check("默认无公告", cfg["announcement"]["enabled"] is False, cfg)
check("默认不强制更新", cfg["min_version"]["version_code"] == 0, cfg)

with SessionLocal() as db:
    row = db.get(AppConfig, 1) or AppConfig(id=1)
    row.announcement_enabled = 1
    row.announcement_id = "a1"
    row.announcement_title = "重要公告"
    row.announcement_body = "今晚 23:00 维护"
    row.min_version_code = 42
    row.min_version_name = "1.0.41"
    row.update_url = "https://gitee.com/x"
    db.add(row)
    db.commit()

r = _client.get("/app/config")
cfg = r.json()
check("公告下发生效", cfg["announcement"]["enabled"] is True and cfg["announcement"]["title"] == "重要公告", cfg)
check("强制更新最低版本下发生效", cfg["min_version"]["version_code"] == 42, cfg)

print("── 4. 数据导出 ──")
_client.put("/profile/basic", headers=h(A), json={"province": "四川省", "address": "某地"})
_client.put("/profile/evaluation", headers=h(A), json={"content": "自我评价内容"})
_client.post("/content/posts", headers=h(A), json={"id": "p1", "title": "说说", "content": "内容", "created_at": 1})
_client.post("/sync/push", headers=h(A), json={
    "conversations": [{"id": "c1", "title": "会话", "created_at": 1, "updated_at": 1}],
    "messages": [{"id": "m1", "conversation_id": "c1", "role": "user", "content": "你好", "created_at": 1}],
})

r = _client.get("/me/export", headers=h(A))
check("导出 → 200", r.status_code == 200, r.text)
data = r.json()
check("导出含账号信息", data["account"]["phone"] == "13800001111", data.get("account"))
check("导出含档案", data["profile"]["province"] == "四川省", data.get("profile"))
check("导出含自我评价", data["self_evaluation"] == "自我评价内容", data.get("self_evaluation"))
check("导出含说说", len(data["posts"]) == 1, data.get("posts"))
check("导出含会话与消息", len(data["conversations"]) == 1 and len(data["messages"]) == 1, data)
check("导出含设备", len(data["devices"]) == 1, data.get("devices"))
check("导出不含密码哈希", "password_hash" not in str(data), "泄漏风险")

# ════════════════════════════════════════════════════════════
# 管理后台：快照扩展 + 按天趋势
# 重点验证：库里存在两种时间列（DateTime 存 UTC / 毫秒时间戳），按中国日历日分桶必须都对
# ════════════════════════════════════════════════════════════
import datetime as _dt  # noqa: E402

from app.models import Conversation, Message  # noqa: E402

_db = SessionLocal()
try:
    _uid = _db.scalar(select(User.id).where(User.phone == "13800001111"))
finally:
    _db.close()

_now_ms = int(_dt.datetime.now(_dt.timezone.utc).timestamp() * 1000)
_db = SessionLocal()
try:
    _db.add(Conversation(
        id="trend-conv-1", user_id=_uid, title="趋势校验", business_tag="",
        message_count=1, last_extracted_message_id="", created_at=_now_ms,
        updated_at=_now_ms, seq=0,
    ))
    _db.add(Message(
        id="trend-msg-1", user_id=_uid, conversation_id="trend-conv-1",
        role="user", content="趋势校验消息", attachment_type="",
        attachment_path="", created_at=_now_ms, seq=0,
    ))
    _db.commit()
finally:
    _db.close()

r = _client.get("/admin/stats", headers=h(A))
stats = r.json()
check("快照含活跃窗口 active_7d/active_30d",
      "active_7d" in stats["devices"] and "active_30d" in stats["devices"],
      stats.get("devices"))
check("快照含新增窗口 new_1d/new_7d",
      "new_1d" in stats["devices"] and "new_7d" in stats["devices"], stats.get("devices"))
check("实名用户字段存在", "verified" in stats["users"], stats.get("users"))
check("版本分布带占比 share",
      all("share" in v for v in stats["versions"]), stats.get("versions"))
check("使用深度：人均消息 / 对话转化率",
      "messages_per_conversation" in stats["engagement"]
      and "conversion" in stats["engagement"], stats.get("engagement"))

r = _client.get("/admin/trend?days=3", headers=h(A))
check("趋势接口 200", r.status_code == 200, r.text[:200])
trend = r.json()
# generated_at 是 UTC（带时区），趋势按**中国日历日**分桶 —— 必须换算后再比日期，
# 否则在 UTC 16:00~24:00 这段（北京已是次日）会误判
_today = (_dt.datetime.fromisoformat(stats["generated_at"])
          + _dt.timedelta(hours=8)).date().isoformat()
check("趋势返回 3 天且最后一天是今天",
      len(trend["items"]) == 3 and trend["items"][-1]["date"] == _today, trend["items"])
check("趋势项字段齐全",
      all(k in trend["items"][0] for k in
          ("date", "new_devices", "new_users", "messages", "conversations", "posts")),
      trend["items"][0])
check("今天有新增装机（DateTime 列分桶正确）",
      trend["items"][-1]["new_devices"] >= 1, trend["items"][-1])
check("今天有新增消息（毫秒时间戳列分桶正确）",
      trend["items"][-1]["messages"] >= 1, trend["items"][-1])
check("今天有新增会话（毫秒时间戳列分桶正确）",
      trend["items"][-1]["conversations"] >= 1, trend["items"][-1])

# 反向校验：把这条消息挪到 3 天前，今天应减 1、那天应加 1
_three_days_ago = _now_ms - 3 * 86400000
_db = SessionLocal()
try:
    _m = _db.scalar(select(Message).where(Message.id == "trend-msg-1"))
    _m.created_at = _three_days_ago
    _db.add(_m)
    _db.commit()
finally:
    _db.close()

r = _client.get("/admin/trend?days=5", headers=h(A))
moved = r.json()
_by_date = {i["date"]: i for i in moved["items"]}
_target = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=8)
           - _dt.timedelta(days=3)).date().isoformat()
check("改到 3 天前：这天计到 1 条消息",
      _by_date.get(_target, {}).get("messages", 0) >= 1, moved["items"])
check("改到 3 天前：今天不再计这条消息",
      _by_date.get(_today, {}).get("messages", 0) == trend["items"][-1]["messages"] - 1,
      _by_date.get(_today))

# ── 权限：非管理员访问管理接口一律 403 ──
check("非管理员看趋势 → 403",
      _client.get("/admin/trend", headers=h(B)).status_code == 403)
check("非管理员看快照 → 403",
      _client.get("/admin/stats", headers=h(B)).status_code == 403)


print("── 5. 账号注销 ──")
r = _client.delete("/me", headers=h(A))
check("未二次确认 → 400", r.status_code == 400, r.text)
check("400 code=confirm_required", r.json().get("error", {}).get("code") == "confirm_required", r.text)

r = _client.delete("/me?confirm=DELETE", headers=h(A))
check("确认后注销 → 200", r.status_code == 200, r.text)
check("返回删除明细", r.json()["deleted"]["conversations"] >= 1, r.json())

r = _client.post("/auth/login", json={"phone": "13800001111", "password": "test123456"})
check("注销后无法登录 → 401", r.status_code == 401, r.text)
r = _client.get("/me", headers=h(A))
check("注销后旧令牌失效 → 401", r.status_code == 401, r.text)
r = _client.get("/me/export", headers=h(A))
check("注销后导出也 401", r.status_code == 401, r.text)

with SessionLocal() as db:
    check("users 表已无该账号", db.scalar(select(User).where(User.phone == "13800001111")) is None)
    check("devices 表已清空该用户设备",
          len(db.scalars(select(Device).where(Device.user_id == "x")).all()) == 0)
    check("另一用户设备未被误删",
          len(db.scalars(select(Device).where(Device.device_id == "dev-b1")).all()) == 1)

r = _client.get("/admin/stats", headers=h(A))
check("已注销账号的管理员令牌也失效 → 401", r.status_code == 401, r.text)


print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
