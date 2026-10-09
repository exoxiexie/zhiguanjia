"""职业档案接口测试（P2，本地 SQLite 运行）

重点覆盖：
1. 未登录访问一律 401
2. 基础信息 / 自我评价的保存与读回
3. 经历的新增、更新（按 updated_at 做 last-write-wins）、删除
4. 批量补发（离线队列）
5. **跨账号隔离**：B 看不到 A 的档案与经历（这是本版的核心安全要求）
6. 实名：脱敏落库、同一证件不可绑多号
"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(
    tempfile.mkdtemp(), "test.db"
)
os.environ["ZGJ_JWT_SECRET"] = "profile-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

_client = TestClient(app)
_client.__enter__()

PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:220]) if extra and not cond else ""))


def register(phone, name):
    r = _client.post(
        "/auth/register",
        json={"phone": phone, "password": "test123456", "name": name},
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def hdr(token):
    return {"Authorization": "Bearer " + token}


print("── 1. 鉴权 ──")
check("未登录 GET /profile → 401", _client.get("/profile").status_code == 401)
check("未登录 PUT /profile/basic → 401",
      _client.put("/profile/basic", json={}).status_code == 401)

print("── 2. 账号准备 ──")
token_a = register("13800001111", "用户A")
token_b = register("13800002222", "用户B")
check("A/B 均注册成功并拿到令牌", bool(token_a) and bool(token_b))

print("── 3. 空档案初始态 ──")
r = _client.get("/profile", headers=hdr(token_a))
check("GET /profile → 200", r.status_code == 200, r.text)
body = r.json()
check("基础信息默认为空", body["basic"]["province"] == "" and body["basic"]["address"] == "")
check("自我评价默认为空", body["self_evaluation"] == "")
check("经历默认为空", body["experiences"] == [])
check("返回 server_time", bool(body.get("server_time")))

print("── 4. 基础信息保存与读回 ──")
r = _client.put("/profile/basic", headers=hdr(token_a), json={
    "province": "四川省", "city": "成都市", "district": "武侯区",
    "address": "科技园路 1 号", "work_status": "在职", "marital_status": "未婚",
})
check("保存基础信息 → 200", r.status_code == 200, r.text)
check("回显省市区", r.json()["basic"]["province"] == "四川省" and r.json()["basic"]["city"] == "成都市")
r = _client.get("/profile", headers=hdr(token_a))
check("再次拉取仍然是新值", r.json()["basic"]["address"] == "科技园路 1 号")

print("── 5. 自我评价 ──")
r = _client.put("/profile/evaluation", headers=hdr(token_a),
                json={"content": "十年产品经验，擅长从 0 到 1。"})
check("保存自我评价 → 200", r.status_code == 200 and "十年产品" in r.json()["self_evaluation"], r.text)
r = _client.put("/profile/evaluation", headers=hdr(token_a), json={"content": ""})
check("保存空串即清空", r.json()["self_evaluation"] == "")

print("── 6. 经历新增 / 更新 / 删除 ──")
exp = {"id": "exp-1", "kind_id": "work", "values": {"company": "某某科技", "title": "产品经理", "start": "2020-09"},
       "created_at": 1000, "updated_at": 1000}
r = _client.post("/profile/experiences", headers=hdr(token_a), json=exp)
check("新增经历 → 200", r.status_code == 200, r.text)
check("字段原样返回", r.json()["experience"]["values"]["company"] == "某某科技")

exp2 = dict(exp); exp2["values"] = {"company": "某某科技（改名后）", "title": "高级产品经理", "start": "2020-09"}; exp2["updated_at"] = 2000
r = _client.post("/profile/experiences", headers=hdr(token_a), json=exp2)
check("更新经历 → 200", r.status_code == 200, r.text)
r = _client.get("/profile", headers=hdr(token_a))
check("更新生效（last-write-wins）", r.json()["experiences"][0]["values"]["title"] == "高级产品经理", r.text)

stale = dict(exp); stale["values"] = {"company": "过期补发"}; stale["updated_at"] = 1500
_client.post("/profile/experiences", headers=hdr(token_a), json=stale)
r = _client.get("/profile", headers=hdr(token_a))
check("乱序补发的旧版本不覆盖新版本", r.json()["experiences"][0]["values"]["company"] == "某某科技（改名后）", r.text)

print("── 7. 批量补发（离线队列）──")
r = _client.post("/profile/experiences/batch", headers=hdr(token_a), json={
    "items": [
        {"id": "exp-2", "kind_id": "education", "values": {"school": "某大学"}, "created_at": 1, "updated_at": 1},
        {"id": "exp-3", "kind_id": "training", "values": {"course": "PMP"}, "created_at": 2, "updated_at": 2},
    ],
    "deleted_ids": ["exp-3"],
})
check("批量推送成功", r.status_code == 200 and r.json()["upserted"] == 2 and r.json()["deleted"] == 1, r.text)
r = _client.get("/profile", headers=hdr(token_a))
ids = [e["id"] for e in r.json()["experiences"]]
check("exp-2 已写入", "exp-2" in ids)
check("exp-3 同批删除生效", "exp-3" not in ids, ids)

print("── 8. 跨账号隔离（核心）──")
r = _client.get("/profile", headers=hdr(token_b))
b = r.json()
check("B 看不到 A 的基础信息", b["basic"]["province"] == "", b["basic"])
check("B 看不到 A 的经历", b["experiences"] == [], b["experiences"])
check("B 看不到 A 的评价", b["self_evaluation"] == "")
r = _client.delete("/profile/experiences/exp-1", headers=hdr(token_b))
check("B 删除 A 的经历 → 404", r.status_code == 404, r.text)
r = _client.get("/profile", headers=hdr(token_a))
check("A 的数据未被 B 影响", len(r.json()["experiences"]) == 2, r.text)

print("── 9. 实名认证 ──")
r = _client.put("/profile/identity", headers=hdr(token_a), json={
    "id_card": "510100199001011234", "real_name": "用户A",
    "gender": "男", "birthday": "1990-01-01", "province": "四川省",
})
check("实名保存 → 200", r.status_code == 200, r.text)
u = r.json()["user"]
check("身份证已脱敏", u["id_card_masked"] == "510100********1234", u.get("id_card_masked"))
check("已标记实名", u["is_verified"] is True)
check("响应不含明文身份证", "510100199001011234" not in r.text)
r = _client.put("/profile/identity", headers=hdr(token_b), json={
    "id_card": "510100199001011234", "real_name": "用户B",
})
check("同一证件绑第二个账号 → 409", r.status_code == 409, r.text)

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
for f in FAILED:
    print("    - " + f)
print("════════════════════════════════")
_client.__exit__(None, None, None)
sys.exit(1 if FAILED else 0)
