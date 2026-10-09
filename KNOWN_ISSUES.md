# 职管家 · 已知问题与工程版待办清单

> **用途**：本文件是 **demo 阶段的缺陷台账**。
> 产品当前策略是「**先快速出 demo → demo 稳定后再统一转工程版（或直接重写）**」，
> 因此在 demo 期**有意不修**下列问题，统一在本文件登记，转工程版时照单施工。
>
> **审计基线**：v1.0.7（commit `ed932ee`）｜**审计方式**：全量只读代码审计 + 关键路径人工复核 + APK 签名实测
> **审计日期**：2026-10-05

---

## 目录

- [一、P0（数据泄漏 / 数据损坏 / 信任链）](#一p0数据泄漏--数据损坏--信任链)
- [二、P1（功能正确性与合规）](#二p1功能正确性与合规)
- [三、P2（健壮性，当前可触发）](#三p2健壮性当前可触发)
- [四、潜伏缺陷（当前不可达，下一步开发即引爆）](#四潜伏缺陷当前不可达下一步开发即引爆)
- [五、工程债](#五工程债)
- [六、测试覆盖缺口](#六测试覆盖缺口)
- [七、转工程版的施工程序（建议顺序）](#七转工程版的施工程序建议顺序)

---

## 一、P0（数据泄漏 / 数据损坏 / 信任链）

### P0-1 换账号后能看到上一账号的全部聊天记录
- **位置**：`lib/features/chat/chat_session_service_impl.dart:25-27`、`:99-114`；`lib/features/tabs/profile_tab.dart:56-63`；`lib/main.dart:23`
- **根因**：`ChatSessionServiceImpl` 是 `main.dart:23` 注册的**进程级单例**，会话缓存在实例字段 `_conversations` 上；`init()` **只在"新租户有历史会话"分支才 `_conversations.clear()`**，新账号无历史会话时直接沿用上一个账号的内存列表（`else` 分支还把 `_conversations.first.id` 写进新账号的库）。退出登录只调 `clearAuth()`，不重置任何服务。
- **复现**：A 登录 → 对话页聊几句 → 「我的」退出登录 → 同机注册/登录 B（B 本地无会话）→ 打开对话页 → **直接显示 A 的全部会话标题与消息正文**；B 继续发消息会写进 A 的会话 id。
- **修法**：`init()` 开头无条件 `_conversations.clear(); _currentIndex = 0;`；新增 `reset()` 并在 `ProfileTab._logout` 调用。

### P0-2 联网搜索沉淀写入上一账号的租户目录
- **位置**：`lib/features/tabs/home_tab.dart:66-70`、`:95-98`；`lib/features/chat/chat_service_impl.dart:291`；`lib/features/agent/agent_service_impl.dart:227`
- **根因**：未实名时 `_setupPersonContext` 只清 `personContext` 就早退，**不清 tenantId**；全仓库 `setTenantId(null)` 从未被调用（4 处调用全是 `set`）。
- **复现**：A 实名并触发过联网搜索 → 退出 → B 登录但未实名 → 对话页提一个需要联网搜索的问题 → 结果沉淀到 `tenants/A/` 下，A 在数据页能读到 B 的提问与信源。
- **修法**：所有 `setPersonContext(null)` 分支同步 `setTenantId(null)`；退出登录显式清空。

### P0-3 联网搜索数据：改权重生成重复文件，删除删错文件
- **位置**：`lib/features/storage/search_data_store.dart:245-251`（create）、`:123`（读取 id）、`:280-303`（update）、`:316-324`（delete）；调用点 `lib/features/data/search_data_history_page.dart:125`、`lib/features/data/search_data_edit_page.dart:91`
- **根因**：落盘名为 `{id}_{slug}.md`，但读取时 `_parseFile` 用 `p.basenameWithoutExtension()` 把 id 还原成**整段文件名**（即 `{id}_{slug}`），而 `update`/`delete` 又按 `'${item.id}_'` 前缀匹配 → **永远匹配不到原文件**。
- **复现**：数据页 → 联网搜索数据 → 把某条权重从 30 调到 60（或进编辑页改标题保存）→ 原文件不更新，**新建一个重复文件**，列表出现两条同标题不同权重记录；随后删除任一条会删掉重复的那个、原文件残留。
- **修法**：统一以文件名（不含 `.md`）为唯一 id，`update`/`delete` 精确匹配 `'$id.md'`。

### P0-4 已发布的 APK 使用 Android Debug 证书签名
- **位置**：`android/app/build.gradle:53-58`（`signingConfig signingConfigs.debug` + TODO）
- **实测证据**（对根目录已发布的 `职管家-v1.0.7.apk` 执行 `apksigner verify --print-certs`）：
  ```
  V2 Signer: certificate DN: C=US, O=Android, CN=Android Debug
  V2 Signer: certificate SHA-256 digest: 91d4926dea885d36928ee3d0402eae932efd98ba28273570353293833b6992a9
  ```
- **后果**：
  1. 签名绑死本机 `~/.android/debug.keystore`（创建于 2026-04-24）。该文件一旦丢失/重建或换开发机，**后续版本无法覆盖安装**，用户必须卸载 → 本地账号、会话、记忆、博客全部清零。
  2. debug 私钥是公开的（标准口令 `android`），任何人都可签出可覆盖安装的伪造更新包。
  3. 无法上架任何应用商店。
- **决策记录（2026-10-05，产品负责人）**：**demo 阶段暂不迁移**，仅记录风险；转工程版时随发布链路一并处理。
- **修法（转工程版时）**：生成正式 release keystore（`.jks`，`key.properties` 已在 `.gitignore`），配置 `signingConfigs.release`；**首次切换需老用户卸载重装一次**，代价随用户量单调上升，宜尽早。

---

## 二、P1（功能正确性与合规）

### P1-1 密码与完整身份证号明文落盘，与 README 宣称矛盾
- **位置**：`lib/features/personal/personal_model.dart:13-15`（注释即写明"明文存储"）、`:71-81`（toJson 原样写出）；`lib/features/personal/personal_auth_service.dart`（登录态整包落盘）；`android/app/src/main/AndroidManifest.xml`（**未设 `android:allowBackup`，Android 默认 true**）
- **现状**：`zhiguanjia.personal.users` 存有全部账号的**明文密码与完整 18 位身份证号**；`zhiguanjia.personal.auth` 再存一份完整身份证号。`maskedIdCard` 仅用于界面展示。
- **对照**：`README.md:110-111` 宣称"身份证号仅用于实名认证……脱敏存储"——**该宣称当前不成立**。
- **正面结论**：《不向大模型发送完整身份证号》这一条在代码层面**成立**（已核查上下文组装路径）。
- **进展（v1.0.36）**：**明文密码一项已消除** —— 注册/登录改为服务端校验后，服务端认证成功即把本机密码字段置空（`_mergeLocalUser(password: '')`），老版本地明文密码仅在"首次登录自动迁移"时用于证明身份、迁移后立即清除。**完整身份证号明文落盘仍在**（P2 上云时一并处理）。
- **修法（剩余部分）**：身份证号落盘脱敏或迁移到 `flutter_secure_storage`（Android Keystore 加密）+ 服务端只存脱敏号与哈希；Manifest 补 `android:allowBackup="false"`。

### P1-2 流式回复中切换/新建会话 → 回答落进另一个会话
- **位置**：`lib/features/tabs/home_tab.dart:107`（`_messages` 每次读当前索引）、`:130-138`、`:385-390`；`lib/features/chat/chat_session_service_impl.dart:166`
- **复现**：会话 A 提问、回复未结束时打开抽屉切换会话（或点右上角新建对话）→ 流结束后回答 append 到**当前（新）会话**并按当前索引落库。A 永久只有提问没有回答，B 会话出现无来源回答；`_triggerDistill` 也拿错会话文本提炼记忆。
- **修法**：发送时冻结目标会话 id（或切换/新建时用 CancelToken 中止并丢弃在途回复），落库与提炼全用冻结 id。

### P1-3 身份问题误拦截，大量正常提问被替换成固定话术
- **位置**：`lib/features/tabs/home_tab.dart:318`、`:434-449`
- **根因**：`_isIdentityQuestion` 要求含「你/您」且命中**任一宽泛子串**即本地拦截、**完全不调模型**；关键词表含 `介绍`、`能做什么`、`ai`、`什么模型` 等。
- **实测命中**：「你能做什么」「你能帮我介绍下这个岗位吗」「你能给我推荐一个 AI 产品经理的岗位吗」→ 三句都返回同一句身份介绍。
- **修法**：改为「整句归一化后严格相等」的白名单匹配（或 `^...$` 锚定），删除宽泛子串。

### P1-4 实名认证成功后「我的」Tab 不刷新
- **位置**：`lib/features/shell/shell_page.dart:88-94`（5 页全部常驻 `IndexedStack`，`ProfileTab` 无 key 无刷新钩子）、`lib/features/tabs/profile_tab.dart:44-47`（`_authFuture` 只在 initState 取一次）、`lib/features/tabs/database_tab.dart:67-72`（认证页无 `onVerified`）
- **复现**：「数据」Tab → 去认证 → 提交成功返回 → 切「我的」→ 仍显示"未认证"。反方向（我的→认证→切数据）因 shell 主动 `refresh()` 正常。
- **修法**：`ProfileTab` 加 `GlobalKey`，切到 index 4 时 `refresh()`；或认证成功走全局通知。

### P1-5 「全部提炼」实际执行增量提炼
- **位置**：`lib/features/tabs/home_tab.dart:192-199`、`:214`
- **根因**：弹窗两个按钮都 `pop(true)`，而执行处按 `incremental: hasExtracted` → 已提炼过的会话无论点哪个都只做增量，**全量提炼不可达**，弹窗文案承诺的全量行为永不触达。
- **修法**：两按钮返回不同值（如 `'inc'`/`'all'`），据此传 `incremental`。

### P1-6 多文件 / 文件夹附件无总量上限
- **位置**：`lib/features/chat/attachment_parser.dart:16`（仅单文件 8000 字符上限）、`:57-59`；`lib/features/tabs/home_tab.dart:528-579`、`:672-688`
- **复现**：多选 30 个 PDF/DOCX/TXT，或"选择文件夹"指向上百文档目录 → 合并结果无封顶，整体拼成一个 system 消息发给模型 → 超上下文/超时失败；解析期把全部文件字节读进内存。
- **修法**：合并后按总字符上限（如 20000）截断并提示；`withData: true` 改为按文件读取 + 单文件大小校验。

### P1-7 `usesCleartextTraffic="true"`
- **位置**：`android/app/src/main/AndroidManifest.xml`
- **原始现状（v1.0.35 及以前）**：对外接口均为 HTTPS，无明文需求，却显式允许明文流量。
- **变化（v1.0.36）**：新增的**自建业务 API 目前是 HTTP**（`http://8.137.71.241/api`，域名备案未通过、无法上证书），因此该属性**暂时是必需的**，属有意保留。
- **修法（备案通过后必须执行）**：`contracts/api_config.dart` 的 `apiBaseUrl` 改为 `https://zhidongni.com.cn/api`，随后删除该属性或置 `false`。**这是商用发布前的硬性前置条件**（明文传输登录口令与令牌不可接受）。

### P1-8 更新包无完整性校验
- **位置**：`lib/features/update/update_service_impl.dart:110-129`；`lib/features/tabs/profile_tab.dart:168`
- **现状**：`version.json` 的 `url` 字段被直接交给 `_dio.download` 再交系统安装器，无 sha256、无签名校验、无域名白名单。
- **修法**：`version.json` 增加 `sha256` 字段并下载后校验；限定 URL 必须属于 `gitee.com` / `github.com`。

---

## 三、P2（健壮性，当前可触发）

| 编号 | 问题 | 位置 | 说明 |
|---|---|---|---|
| P2-1 | `BlogStore` 解析无 try/catch | `lib/features/blog/blog_store.dart:54-62`；`lib/features/tabs/blog_tab.dart:54-57` | 任一元素非合法 JSON/map 即抛异常 → 「我的」停在空态且无提示；列表只 append 无上限 |
| P2-2 | YAML front matter 未转义 | `lib/features/storage/memory_store.dart:96-107`；`lib/features/storage/search_data_store.dart:189-211` | 标题来自模型输出或用户输入，含 `\n` / `---` 即破坏文件结构 |
| P2-3 | 退出登录不关库；DAO 不校验租户 | `lib/features/storage/database/app_database.dart:27-41,55-59`；`lib/features/storage/database/dao/session_dao.dart:9` | 全仓 `close()` 唯一调用点在 `open()` 内部；DAO 只取 `appDatabase.db`，不校验「连接租户 == 查询租户」 |
| P2-4 | 消息主键可碰撞 + 静默覆盖 | `lib/features/chat/chat_session_service_impl.dart:169`、`:288-298`；`lib/features/storage/database/dao/message_dao.dart:12-18` | `id = '${now}_${role}_${content.length}'`；冲突用 `ConflictAlgorithm.replace` 覆盖。若被覆盖的是 `last_extracted_message_id` 那条，`indexWhere` 找不到 → **该会话增量提炼永久失效** |
| P2-5 | 记忆无限堆积 + 提炼提示词无上限 | `lib/features/memory/memory_distiller.dart:61-62`、`:167-192`；`lib/features/storage/memory_store.dart:111-117` | 去重完全依赖模型回填 `update_id`，代码层无兜底；`safeId` 前置毫秒时间戳 → 每次新文件；`existingInfo` 把全部历史记忆无截断拼进提示词 |
| P2-6 | SSE 流内 `error` 事件被吞 | `lib/features/agent/agent_service_impl.dart:315-317`（主链路）、`lib/features/chat/chat_service_impl.dart:250-251` | 上游下发 `{"error":{...}}`（限流/超限/内容安全）→ `continue` → 最终报"模型未返回内容"，与真实原因无关 |
| P2-7 | SSE 畸形分片以裸 TypeError 冒泡 | `lib/features/agent/agent_service_impl.dart:309-317`；`lib/features/chat/chat_service_impl.dart:244-252` | try 只包 `jsonDecode`，`choices`/`choices[0]` 的 `as` 断言未保护；catch 只处理 DioException → UI 显示 `type 'String' is not a subtype of type 'Map'` |
| P2-8 | Agent 超时落库空消息 | `lib/features/agent/agent_service_impl.dart:81-82`、`:263-269`；`lib/features/tabs/home_tab.dart:383-390` | 多步工具循环累计超 90s 时 `break`，`reply` 仍为 `''`，却被当回答入库 → 空白气泡 |
| P2-9 | 无重试、无取消 | `lib/features/agent/agent_service_impl.dart:281-296`；`lib/features/tabs/home_tab.dart:382`、`:313` | (a) 流式中途失败清空已输出内容、整轮作废，无重试；(b) 流式期间返回上一页 → `!mounted` 早退，回答永不落库，而提问已落库 → 该会话永久只有提问 |
| P2-10 | `setState` after dispose | `lib/features/personal/personal_verify_page.dart:36-42` | `await getAuth()` 后无 `mounted` 检查，进实名页立刻返回即触发 |
| P2-11 | `agent_enabled_*` 缺租户前缀 | `lib/features/tabs/insight_tab.dart:39`、`:66` | 换账号后沿用上一账号的任务智能体开关（对比 `blog_store.dart:44-51` 已带手机号前缀） |
| P2-12 | `MemoryDistiller.lastError` 静态共享 | `lib/features/memory/memory_distiller.dart:32`、`:58`、`:116-124`；`lib/features/tabs/home_tab.dart:228` | 自动提炼与手动提炼并发时互相覆盖，错误提示张冠李戴 |
| P2-13 | 生产代码 `print` 泄漏租户手机号 | `lib/features/agent/agent_service_impl.dart:228-260` | 5 处 `print` 把手机号（租户ID）、搜索结果写进 logcat |
| P2-14 | 死代码 | `lib/features/tabs/files_tab.dart`（全文件 18 行无人引用）；`lib/features/tabs/home_tab.dart:717` `_buildFeatureButton` 未使用 | `dart analyze` 报 `unused_element` |
| P2-15 | 流式渲染 O(n²) 正则 | `lib/features/tabs/home_tab.dart:869` | 每帧对流式缓冲整体跑 `mdToCnText`（约 10 条正则），长回复下有性能隐患 |
| P2-16 | `init()` 失败被吞且置 `_ready=true` | `lib/features/chat/chat_session_service_impl.dart:116-119`、`:164-165` | DB 打开失败时仍标记就绪，此后每轮对话静默不落库，历史全丢且无任何提示 |

---

## 四、潜伏缺陷（当前不可达，下一步开发即引爆）

| 编号 | 问题 | 位置 | 引爆条件 |
|---|---|---|---|
| L-1 | `SessionEntity.copyWith` 丢失 `businessTag`，`SessionDao.update` 又全字段覆盖 | `lib/features/storage/database/models/session_entity.dart:49-65` | 任何一次改会话标题即把 `business_tag` 写 NULL → 业务智能体会话从 `findByTenantAndBusiness` 结果中消失。**注册第一个职业任务域前必修** |
| L-2 | `business_agent_page` 持久化在 try 之外 → 发送键永久变灰 | `lib/features/chat/business_agent_page.dart:409-471` | DB 抛错一次即 `_isLoading` 永真；另有附件不落库（`:428-434` 未写 `attachment_type/path`）、无流式（`:438` 未传 `onDelta`）、`agent as HttpAgentService` 使契约/DI 失效（`home_tab.dart:346`）、文件夹解析无逐文件 try（`:378`） |
| L-3 | `discover_tab` 空值越界 | `lib/features/discover/discover_tab.dart:340` | `job.hrName.substring(0, 1)` 无空值保护，接真实职位接口后必现 RangeError |
| L-4 | 环境曾因沙箱受限 | — | 已解决：当前会话为 `danger-full-access`，`flutter build apk` 正常 |

---

## 五、工程债

| 项 | 现状 | 转工程版动作 |
|---|---|---|
| CHANGELOG 缺失 | 只记录了 `1.0.0`，`1.0.1～1.0.7` 共 7 次迭代（人脉→博客、发现页改造、数据页实名卡…）均未记录 | 按 git log 逐版补全，并从本版起保持实时维护 |
| README 过期 | 仍写"4 个主 Tab"（实际 5 个：懂你/数据/博客/发现/我的）；版本历史只到 1.0.0；"规划中"未随迭代更新 | 全文校准 |
| 架构检查报告过期 | `架构检查报告.html` 称 54 文件 / 12,606 行（实际 57 / 13,606）；所列问题全部仍在 | 重新生成并跟踪 |
| 单文件超 500 行 | `home_tab.dart` 1115、`business_agent_page.dart` 891、`agent_service_impl.dart` 627、`insight_tab.dart` 526 | 按报告 P0/P1 建议拆分 |
| 循环依赖 | `personal_login_page` → `shell_page` → `profile_tab` → `personal_login_page` | 改路由表/回调解耦 |
| 发版全手工 | 无 git tag；versionName/versionCode/`version.json`/Release 上传全靠手敲，无校验脚本 | 写 `release.sh`：bump → 校验三处版本一致 → build → tag → 上传 |
| 依赖声明缺失 | `test/session_archive_test.dart:11-12` 依赖未在 pubspec 声明的 `path_provider_platform_interface`/`plugin_platform_interface`（靠传递依赖，pubspec 变动即碎） | 显式声明为 dev_dependencies |

---

## 六、测试覆盖缺口

`flutter test` 19/19 通过，但覆盖面极小：`test/widget_test.dart:10-12` 名为 widget 测试，实为 `expect(1 + 1, 2)`。

**零覆盖模块**：`PersonalAuthService`（注册/登录/实名/重复身份证）、`IdCardUtil`、`BlogStore`、`MemoryStore`（front matter 往返）、`SearchDataStore`（**P0-3 所在层**）、`LocalFileStore`、`AppDatabase`/DAO、`ChatSessionServiceImpl`（**P0-1 路径完全无测试**）、`UpdateService`（versionCode 比较与多源回退）、各 Tab 页面。

**转工程版时优先补 3 个用例**：
1. 同一 `ChatSessionServiceImpl` 实例连续 `init()` 两个租户（先"有会话"、后"无会话"），断言 `conversations` 不含上一租户数据（对应 P0-1）；
2. `SearchDataStore.create → listAll → updateWeight → listAll/delete` 往返（对应 P0-3）；
3. `SessionEntity.copyWith` 保留 `businessTag`（对应 L-1）。

**已核查无缺陷（正面结论，避免重复劳动）**：SSE 分包/半包与多字节 UTF-8 处理正确（`LineSplitter` + `await for` 自动 cancel）；两个对话页的 Controller 均成对 dispose，无订阅/Timer 泄漏；所有 async 分支均有 `mounted` 守卫（除 P2-10）；`_isLoading` 同步置位，连点发送被拦截；`IdCardUtil` 的 GB11643 校验（校验码/日期回比/性别/籍贯）逻辑正确；`DataTags`/`SessionArchive.read`/`MemoryStore.listAll`/`SearchDataStore._parseFile` 均有 try/catch 容错；全仓无敏感文件误提交（`.apk`/`local.properties`/`dsh/`/`tools/bin/` 均已 gitignore）。

---

## 七、转工程版的施工程序（建议顺序）

| 顺序 | 批次 | 内容 | 发版 |
|---|---|---|---|
| 1 | **A · 数据安全** | P0-1、P0-2、P0-3 + 上述 3 个回归测试 | v1.0.x |
| 2 | **B · 发布信任链** | P0-4 正式 keystore、P1-7、P1-8、`allowBackup=false` | v1.0.x（首次需老用户卸载重装） |
| 3 | **C · 对话正确性** | P1-2、P1-3、P1-4、P1-5、P1-6 | v1.0.x |
| 4 | **D · 隐私存储** | P1-1 密码加盐哈希 + 身份证脱敏/`flutter_secure_storage` | v1.0.x |
| 5 | **E · 健壮性** | P2-1 ~ P2-16 逐条清理 | v1.0.x |
| 6 | **F · 工程债** | CHANGELOG/README 补齐、死代码清理、文件拆分、循环依赖解耦、`release.sh` | — |

> **转工程版触发条件**（产品负责人定义）：demo 功能面稳定、不再大幅增删页面后启动。
