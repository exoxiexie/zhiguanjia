# 职管家 · 项目长期记忆

## 一、发版输出规范（用户 2026-10-05 定的硬性格式，每次改版必须照此输出）

固定 8 段结构，顺序不可变：

1. **交付声明**：`全部验证通过。交付 vX.Y.Z 安装包。`
2. **改动**：一句话主题（例："信息流头像与「我的」页统一"）。
3. **问题**：现状痛点，要点明"看着对、实际不一致"这类反直觉之处。
4. **改法**：核心是**从结构上消除不一致**，而不是"两处各改一遍"；分条列出关键决策。
5. **顺带的一致性收益**（有则写）。
6. **发版清单**：两列表格（项 | 状态），固定覆盖以下项：
   - 版本号：`pubspec X+Y`、`version.json X`（versionCode Y），远端已确认
   - analyze：`0 error / 0 warning`
   - 测试：`N/N 通过` + 新增用例名
   - APK：体积 + 实测 `versionCode / versionName / native-code`
   - **构建时间（必填，用户 2026-10-08 再次强调）**：写本次打包实测耗时（取 `build_apk.sh` 输出的「=== 构建完成（耗时 X）===」），并**与上版对比**（例："11 分 20 秒（上版 11 分 23 秒）"）。⚠️ **v1.0.28 / v1.0.29 连续两版漏了这一行，用户已指出 —— 此后每版必须出现在清单表格里，不得省略**。
   - 签名：`SHA-256 …与历次一致，可直接覆盖升级`
   - 双端 push：Gitee master、GitHub main + commit hash
   - Gitee Release：版本已建 + apk 已上传 + 字节数
   - 下载验证：`HTTP 200` + 字节数完整可下
   - 本地归档：`职管家-vX.Y.Z.apk`
7. **手机验证指引**：给用户一段可照着操作的手动验证步骤（"手机更新后：…"）。
8. **文件变更统计**：`已编辑 N 个文件` + `+X / -Y`，再逐文件列出（文件名 +N -M）。

措辞偏好：中文、直白、突出"结构性修复"而非打补丁；清单用表格。

**输出形态（用户 2026-10-05 追加要求）**：发版回复**不要用文件卡片列出 APK**（即不要调 present_files 呈现 `职管家-vX.Y.Z.apk`）；APK 的体积 / versionCode / 归档等信息仍照常写进「发版清单」表格。若需附链接，只附 Gitee Release 页面链接，不列 APK 文件卡片。

**输出形态补充（用户 2026-10-06，用户明确嫌烦）**：报告 / 回复**末尾一律不再附加 APK 文件**（路径、链接、产物卡片统统不要），也**不再附发版校验类链接**（Gitee Release 附件、Gitee version.json、GitHub raw version.json）。这些照常在后台执行验证，只是不展示给用户；APK 放项目根目录由用户自取。

## 二、版本号约定

- 默认只递增最后一位（`1.0.11 → 1.0.12`）；升第二位（次版本）必须等用户明确指令。
- 三处必须同步：`pubspec.yaml`（versionName+versionCode）、`version.json`（versionName+versionCode）、`CHANGELOG.md`。
- versionCode 单调递增，绝不回退。

## 三、关键工程事实（接手必读）

- 双仓库：Gitee `master`（主发布，托管 APK + version.json）＋ GitHub `main`（源码），每次提交双端推送。
- 打包脚本 `build_apk.sh`，默认 arm64-v8a 单 ABI；`--universal` 出全 ABI。
- 发版后本地归档 APK 到项目根目录，命名 `职管家-vX.Y.Z.apk`。
- 文档三件套：`CHANGELOG.md`（每版实时维护）、`KNOWN_ISSUES.md`（缺陷台账）、`README.md`。
- 工程铁律：① 前端驱动后端 ② 模块最小化、文件夹硬隔离 ③ 契约层(contracts)与实现层(features)分离，UI 只依赖接口。
- 当前 APK 仍为 Android Debug 证书签名（P0-4，转工程版时换正式 keystore，首次需老用户卸载重装）。
- **用户上传图片的落盘铁律**：`image_picker` 返回的是系统临时缓存路径，**绝不能直接入库**，必须先用 Store 复制进应用私有目录再存绝对路径（否则系统清理后变裂图）。现成范式：头像 → `AvatarStore`（`avatars/<手机号>.<ext>`，一人一份覆盖式）；说说配图 → `PostImageStore`（`post_images/<微秒时间戳>_<随机>.<ext>`，每次新增唯一命名）；自主学习成果的图片与 PDF → `StudyFileStore`（`study_files/`，同套唯一命名，图片与文件通用）。展示侧统一用 `Image.file` + `errorBuilder` 回落占位，避免裂图。
- **PDF 处理**：项目内 `syncfusion_flutter_pdf` 只能提取文本、**无 `PdfPageRenderer`**，做不到内联渲染；内联预览需额外包且要联网解依赖（有构建风险）。当前做法 = 文件卡 + `OpenFilex.open(path)` 调系统阅读器（与 profile_tab 打开简历、local_data_detail_page 打开本地资料同一套机制，**零新依赖**）。
- 说说卡片是三处列表（推荐 / 关注 / 我的）与作者主页**共用的唯一展示单元**（`blog_post_card.dart`）；改说说展示规则只改这一个文件即全站一致。
- 母项目为 `../智懂你`（AI 管家集合，v1.2.x）；本项目是其"职业主体"垂类实例，两者共用同一套框架与后端代理，核心代码为复制关系（非共享包）。

## 五、应用内更新链路 & Gitee Release 发布（发版必做，可复用）

- **App 怎么检查更新**（`lib/features/update/update_service_impl.dart`）：依序读更新源的 `version.json` → 比对 `versionCode > 本地 buildNumber` → 按 version.json 的 `url` 字段下载 APK。两源：
  1. 主源 Gitee API：`https://gitee.com/api/v5/repos/laoxie2076/zhiguanjia/contents/version.json?ref=master`（返回 base64，需解码）
  2. 回退 GitHub raw：`https://raw.githubusercontent.com/exoxiexie/zhiguanjia/main/version.json`
- **所以「双端 push」只是第一步，发版必须再建 Gitee Release 并上传附件**；只 push 不建 Release，App 会发现新版本但下载 404。
- **命名铁律**：附件名 = `zhiguanjia-vX.Y.Z.apk`，必须与 version.json 中 `url`（`https://gitee.com/laoxie2076/zhiguanjia/releases/download/vX.Y.Z/zhiguanjia-vX.Y.Z.apk`）严格对应。
- **发布方法**（本机无 gitee CLI，用 OpenAPI；凭证 = `git remote get-url gitee` 里内嵌的 `用户名:令牌`）：
  - 建 Release：`POST https://gitee.com/api/v5/repos/laoxie2076/zhiguanjia/releases`，参数 `access_token` / `tag_name=vX.Y.Z` / `name=vX.Y.Z` / `target_commitish=<HEAD SHA>` / `body=<Markdown changelog>`（body 用 `--data-urlencode` 防中文换行出错）。
  - 传附件：`POST .../releases/{release_id}/attach_files`，`-F "file=@职管家-vX.Y.Z.apk;filename=zhiguanjia-vX.Y.Z.apk"`。
- **发布后三项验证**：① 下载 URL `HTTP 200` 且 size_download 与本地 APK 字节数一致；② Gitee API version.json 读到新 versionCode；③ GitHub raw version.json 一致。
- 凭证只经 `/tmp` 临时文件传递，用完立即 `rm`，任何输出都要 `sed` 脱敏。
- **网络坑（2026-10-06 实测）**：本机对 GitHub 的 HTTP/2 链路不稳，`git push github` 与 `curl` 取 `raw.githubusercontent.com` 均可能报 `Error in the HTTP2 framing layer`。解法：git 加 `-c http.version=HTTP/1.1`，curl 加 `--http1.1`。Gitee 侧不受影响。

## 六、职业任务域注册表（仅剩底层，界面层已于 v1.0.28 删除）

- ⚠️ **v1.0.28 起「专业智能体」整个界面层已删除**：首页（懂你）不再有智能体卡片、齿轮管理面板、也不再有 `BusinessAgentPage` 详情页。同期删掉的文件：`tabs/insight_tab.dart`（原首页）、`chat/business_agent_page.dart`、`data/business_agent_role.dart`、`data/business_context_service.dart`、`storage/business_domain_store.dart`、`tabs/files_tab.dart`（死代码）。
- **保留的只有底层注册表** `lib/features/data/business_domain.dart` 的 `kBusinessDomains`——它仍被两处引用，不可随手删：
  1. `storage/database/app_database.dart` 遍历它**建表**（改注册表要同步加 version 并在 `_onUpgrade` 补建）；
  2. `memory/memory_distiller.dart` 用它的 tag 集合做**记忆提炼的合法性校验**。
- 已注册两条（v1.0.15）：`学习`（id `skill_learning`，表 `skill_learning_data`）、`招聘`（id `recruit`，表 `recruit_data`）。tag 用短名，与 `data_tags.dart` 的 `DataBusinessTag` 一致。
- 若将来要**重新**做智能体界面，先想清楚：卡片入口放哪、是否复用 `BusinessAgentPage`（已删，需从 git 历史取回）。当前产品方向是「对话即首页」，不再走「多智能体卡片」路线。

## 六之二、底栏五格 & 懂你首页 = 对话首页（v1.0.28 起改造，v1.0.29 定稿为 5 格）

- **底栏 5 格，顺序固定**：`对话 / 数据 / 懂你 / 发现 / 我的`（index 0..4）。`shell/shell_page.dart` 的 `_titles` 与之对应。
  - ① **对话** = 对话首页（Agent 模式）：`chat_page.dart`（`showBackButton=false`、`title='职管家'`），body 为 `tabs/home_tab.dart`（真流式，`onDelta` → `_streamBuffer`）。顶栏自带，壳不给。
  - ② **数据** = `tabs/database_tab.dart`。**唯一由壳提供 AppBar 的页**（`appBar: _index == 1 ? ... : null`）。
  - ③ **懂你** = `tabs/insight_tab.dart`（`InsightTab`）：v1.0.29 新建的**占位页**（顶栏「懂你」+ 居中淡提示「功能建设中」），自带 AppBar。与「对话」职责分开——一个干活、一个懂你；后续在此做职业画像 / 洞察。
  - ④ 发现 = `discover/discover_tab.dart`；⑤ 我的 = `tabs/profile_tab.dart`。两者自带 AppBar。
- **常驻刷新钩子按新位置对齐**（`onDestinationSelected`）：`i == 1` → `_databaseTabKey.refresh()`；`i == 4` → `_profileTabKey.refresh()`。**改动底栏顺序时必须同步这两个下标**，否则会刷错页。
- 默认落地仍是 index 0（对话）。
- **术语**：用户口中的「首页」＝现在的「对话」Tab（v1.0.29 之前叫「懂你」）；「懂你」现在是独立的占位 Tab，别再混用。
- 图标分配：对话＝`chat_bubble_outline/chat_bubble`，懂你＝`lightbulb_outline/lightbulb`（灯泡由原 Tab 挪来）。
- 回归测试 `test/shell_tabs_test.dart`：断言 5 格标签顺序、默认 selectedIndex、点懂你切到 index 2。**改底栏务必先看它**。

### 底栏高度（v1.0.31）

- **唯一事实来源 = `lib/main.dart` 的 `kNavigationBarHeight = 56`**，经 `buildAppTheme()` 的 `navigationBarTheme.height` 下发；`ShellPage` 不自带高度。
- **为何 56**：M3 `NavigationBar` 默认内容高 **80dp**，明显高于业界主流（M2 = 56、iOS UITabBar = 49pt、国内 App 普遍 49~56），用户实测觉得高。压到 56 后真机总高 114dp → **约 90dp**（省 24dp）。56 仍 ≥ Material 最小触摸目标 48。
- **安全区不可控**：真机总高 = 56 + 底部系统安全区（手势约 34 / 三键 48）。实测数据：无安全区 80（改前）→ 56（改后）；+34 → 114 → 90；+48 → 128 → 104。
- `buildAppTheme()` 是抽出来的**主题函数**（原为 main.dart 内联），目的：让测试能吃**同一份**配置做回归断言，避免"测试另写一套主题、改坏了测不出来"。**以后新增主题项都写进 `buildAppTheme()`**。
- 回归测试 `test/nav_bar_height_test.dart`（4 例）：常量=56 且 ≥48、实测高度=56（≠80）、总高=56+安全区、压矮后不溢出。

### 底栏项 = 自绘（v1.0.32）

- **为什么自绘**：官方 M3 `NavigationDestination` 把三件事写死在私有代码里，外部改不了 ——
  ① 选中"药丸"（`NavigationIndicator`，`64×32` 圆角底，尺寸是源码常量）；
  ② 图标-文字 8dp 间隙（= 图标盒内空隙 4 + 文字写死上边距 4）；
  ③ 两者相对位置由私有 `MultiChildLayoutDelegate` 计算。
- **做法**：仍用官方 `NavigationBar` 当**外壳**（高度 56 / 背景 / 底部安全区 / 横向均分全白拿），
  只把 `destinations` 换成自绘的 `AppNavDestination`。官方对该参数只断言 `length >= 2`，不限元素类型（已核实 `navigation_bar.dart:102`）。
- **文件** `lib/features/common/app_nav_bar.dart`：
  - `AppNavItem(icon, selectedIcon, label)`；常量 `kNavIconLabelGap = 4` / `kNavIconSize = 24` / `kNavSelectedIconColor = Color(0xFF1A1B1C)`；
  - `AppNavDestination`（`InkWell` + `SizedBox(height: double.infinity)` + `Column(center)`，图标 + gap + 文字；文字用 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` 防系统字号撑破）；
  - `buildAppNavDestinations({items, selectedIndex, onSelected})` 一键铺满。
  - 选中：图标切实心 + 近黑，文字 `onSurface`；未选中：`onSurfaceVariant`（与官方默认一致）。
- **五格定义 = `shell_page.dart` 的 `kShellNavItems`**（顺序：对话/数据/懂你/发现/我的）。改底栏内容只改这一处。
- **实测几何（56dp 底栏，自绘后）**：图标 550..574、文字 578..594、间隙 **4dp**（原 8dp）。
- 回归测试 `test/app_nav_bar_test.dart`（10 例）：无 `NavigationIndicator` / 无 `NavigationDestination` / 间隙=4（选中与未选中）/ 选中实心近黑 / 切换互换 / 点击回调 index / 顺序与图标配置自检。
  `test/shell_tabs_test.dart` 的 `_labels()` 已改为读 `AppNavDestination.item.label`（原读 `NavigationDestination.label`）。

## 六之四、对话链路：走 Agent，且**必须真流式**（v1.0.33 修复）

- **懂你页发消息走的是 Agent 分支**：`home_tab.dart` 里只要 `agentService != null` 就走它（它永不为空），
  即 `HttpAgentService.run()`（`features/agent/agent_service_impl.dart`）。
  `HttpChatService.sendMessage()`（`features/chat/chat_service_impl.dart`）**在实际聊天中不会被调用**。
- **Agent 的每一轮都是真流式**（v1.0.33 起）：请求带 `stream: true` + `stream_options.include_usage`，
  正文/思考片段到达即 `onDelta` 上屏；工具调用以**分片**下发（`index` / `id` / `function.name` /
  `function.arguments` 增量），由 `_streamModelRound` 按 `index` 拼装回完整 `tool_calls`。
  私有类 `_StreamRound` 承载一轮结果（content / reasoning / toolCalls / tokens）。
- ⚠️ **历史坑（v1.0.33 前）**：Agent 的模型请求**没开流式**，等整段生成完再按 3 字符「回放」
  —— 即"假流式"，用户等待期一个字都看不到，主观上比官方 App 慢很多。
  **绝不能退回那种写法**：`test/agent_stream_test.dart` 已锁住"正文必须逐片回调（不是一次给完）"。
- **改动边界**：上下文组装（`_buildMessages`：个人档案 + system prompt + 历史）、工具注册与执行、
  工具结果回填、搜索数据沉淀、stepLogs 全部保留。**改流式 ≠ 绕开 Agent**。
- `home_tab.dart` 的 `onToolStart` 会重置流式状态（`_streamingReasoning = true` + `_streamBuffer.clear()`），
  避免工具执行期间还挂着"决定调工具前吐出的半截过渡文字"。

### 网络链路：代理已迁至成都（v1.0.34 完成）

- **当前地址（成都，v1.0.34 起）**：`https://zhidongk-api-cd-nknkhdghnt.cn-chengdu.fcapp.run`
  （旧新加坡 `https://zhidongek-proxy-ocspgrobnt.ap-southeast-1.fcapp.run` 已停用，勿再引用）
- **唯一配置点**：`contracts/api_config.dart` 的 `proxyBaseUrl`。全项目只有它引用域名，
  派生 `chatCompletionsUrl` = `$proxyBaseUrl/chat/completions`、
  `anthropicMessagesUrl` = `$proxyBaseUrl/anthropic/v1/messages`。
- **实测对比（2026-10-09，本机）**：TLS 握手 **0.736s → 0.040s**，建连 0.269s → 0.056s。
  这是 B 方案的核心收益（A 方案 = 真流式，见上一节）。
- **成都端完整验收（2026-10-09，全部 200）**：`/ping`（`configured:true`）、非流式、流式 SSE
  （含 `stream_options.include_usage`）、流式 + tools 分片（`finish_reason:tool_calls`，13 片）、
  Anthropic `/anthropic/v1/messages` —— **功能与旧端完全等价**。
- **服务端源码三份同源**（sha256 `ede96a19449e`）：`桌面/zhidongni-api/app.py` ==
  `智懂你/tools/deepseek_proxy/app.py` == `职管家/tools/deepseek_proxy/app.py`。
  零依赖（仅标准库 http.server + urllib），读 `FC_SERVER_PORT`、`DEEPSEEK_API_KEY`、`PROXY_TOKEN`。
- **部署两个坑（已解决，记住即可）**：
  1. **zip 多套一层目录** → FC 解压成 `/code/zhidongni-api/app.py`，而启动命令是 `python app.py`
     → `CAExited: can't open file '/code/app.py'`。正解：`cd 目录 && zip -X -j out.zip app.py`
     （`-j` 压平、`-X` 去 macOS 扩展属性），使 `app.py` 位于包根。
  2. **新函数不继承环境变量** → 必须重新配 `PROXY_TOKEN`（须与 App 内置一致）与 `DEEPSEEK_API_KEY`。
- **自检端点**：`GET /ping` 免令牌，返回 `{"ok":true,"service":"zhidongni-deepseek-proxy","configured":<bool>}`。
  `configured = bool(DEEPSEEK_API_KEY) && bool(PROXY_TOKEN)` —— 改完环境变量先看它。
  鉴权顺序：先判 `PROXY_TOKEN`（错了返 **401**），再判 `DEEPSEEK_API_KEY`（缺了返 **500**）；
  **据此可区分是哪个变量没配**。
- ⚠️ **DeepSeek 思考模式不支持 `tool_choice:"required"`**（报
  `Thinking mode does not support this tool_choice`）。项目用的是 `auto`，测工具时别用 required。

### 测试技巧：如何在单测里 mock 网络（dio）

- **`Dio` 只有工厂构造、无法 `extends`**（会报 `no_generative_constructors_in_superclass`
  与一堆 `Missing concrete implementations`）。正确做法是注入 `HttpClientAdapter`：

  ```dart
  final dio = Dio();
  dio.httpClientAdapter = _ScriptedAdapter(...);   // implements HttpClientAdapter
  // fetch(RequestOptions, Stream<Uint8List>?, Future<void>?) → Future<ResponseBody>
  ```

- `ResponseBody(stream, 200, headers: {...})`；用 `Stream<Uint8List>` 喂 SSE 文本，
  **故意按 7 字节打碎**以验证"不被分片边界影响"。适配器里 `await for (chunk in requestStream)`
  可读到请求体，用来断言 `stream: true` / `tools` 是否存在。范本见 `test/agent_stream_test.dart`。

- **为什么自绘**：官方 M3 `NavigationDestination` 把三件事写死在私有代码里，外部改不了 ——
  ① 选中"药丸"（`NavigationIndicator`，`64×32` 圆角底，尺寸是源码常量）；
  ② 图标-文字 8dp 间隙（= 图标盒内空隙 4 + 文字写死上边距 4）；
  ③ 两者相对位置由私有 `MultiChildLayoutDelegate` 计算。
- **做法**：仍用官方 `NavigationBar` 当**外壳**（高度 56 / 背景 / 底部安全区 / 横向均分全白拿），
  只把 `destinations` 换成自绘的 `AppNavDestination`。官方对该参数只断言 `length >= 2`，不限元素类型（已核实 `navigation_bar.dart:102`）。
- **文件** `lib/features/common/app_nav_bar.dart`：
  - `AppNavItem(icon, selectedIcon, label)`；常量 `kNavIconLabelGap = 4` / `kNavIconSize = 24` / `kNavSelectedIconColor = Color(0xFF1A1B1C)`；
  - `AppNavDestination`（`InkWell` + `SizedBox(height: double.infinity)` + `Column(center)`，图标 + gap + 文字；文字用 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` 防系统字号撑破）；
  - `buildAppNavDestinations({items, selectedIndex, onSelected})` 一键铺满。
  - 选中：图标切实心 + 近黑，文字 `onSurface`；未选中：`onSurfaceVariant`（与官方默认一致）。
- **五格定义 = `shell_page.dart` 的 `kShellNavItems`**（顺序：对话/数据/懂你/发现/我的）。改底栏内容只改这一处。
- **实测几何（56dp 底栏，自绘后）**：图标 550..574、文字 578..594、间隙 **4dp**（原 8dp）。
- 回归测试 `test/app_nav_bar_test.dart`（10 例）：无 `NavigationIndicator` / 无 `NavigationDestination` / 间隙=4（选中与未选中）/ 选中实心近黑 / 切换互换 / 点击回调 index / 顺序与图标配置自检。
  `test/shell_tabs_test.dart` 的 `_labels()` 已改为读 `AppNavDestination.item.label`（原读 `NavigationDestination.label`）。

## 六之三、对话输入栏尺寸（`lib/features/chat/chat_input_bar.dart`）

- **行数规则（v1.0.30 起）**：未聚焦 `minLines = 1` / 聚焦 `minLines = 2` / `maxLines = 5`（超过在框内滚动）。常量 `_kMinLinesIdle` / `_kMinLinesFocused` / `_kMaxLines` 在文件顶部。
  - 动因：原先 `minLines` 写死 2，输入栏平时一直顶着 2 行、显得太高。
  - 实现：组件为 `StatefulWidget` + 内部 `FocusNode`，焦点变化 `setState` 切换最小行数。**对外参数与调用方零改动**。
- **实测高度（文本缩放默认、dp）**：整条输入栏 —— 1 行 **≈142**、2 行 **165**（实测）、5 行 **≈234**。
  圆角框 1 行 91 / 2 行 114 / 5 行 183；文字区每行 ≈23，2 行即 54。
  组成：外上 8 + 工具行 ≈29 + 间距 6 + 圆角框 + 外下 8。
- **高度是活的**，没有写死像素；`showTopBar: false` 可省掉工具行（约 −35dp）。
- 量高度的办法：写个临时 widget 测试用 `tester.getSize(find.byType(TextField))` / `find.byType(ChatInputBar)` 打印即可（**不要只看代码推算**，圆角框与按钮行会带来误差）。

## 七、职业经历模块：字段描述表（新增经历类型只改一处）

- 数据页的经历卡片（学历教育 / 工作经历 / 技能培训）由 `lib/features/data/experience_models.dart` 的 `ExperienceKind.all` 驱动：注册一条即自动派生 **数据页通栏卡片 + 详情页 + 编辑表单 + 必填校验 + 卡片摘要**，页面与存储零改动。
- **label 是纯展示文案，v1.0.22 已改**：「教育经历」→「学历教育」、「培训经历」→「技能培训」；`id`（`education` / `training`）与存储键不变，改文案不要动 id。
- 新增一类经历 = 在 `ExperienceKind.all` 加一条 `ExperienceKind`（id / label / icon / color / subtitle / fields），并给 `ExperienceField.primary = true` 标出主字段（卡片标题）。
- 字段控件由 `ExperienceFieldType` 决定：`text` 单行 / `multiline` 多行 / `select` 选项芯片（必须给 `options`）/ `month` 年月滚轮。**优先复用这四种，不要随意扩枚举**。
- 约定：`month` 类型存 `yyyy-MM`；按字段顺序取**第一个** month 字段为起始时间、**第二个**为结束时间（`startField` / `endField` 靠这个顺序识别，加字段时注意别插到时间字段前面）。
- 存储 `lib/features/data/experience_store.dart`：按账号隔离（`experience_{手机号}`），三类共用一个键、按 `kind` 过滤；排序按 `sortKey`（起始时间）倒序，未填的排最后。

## 八、通栏卡片公共组件（PlainGroup）

- `lib/features/common/plain_group.dart`：白底圆角卡片 + 每行「图标 + 名称 +（可选）右侧说明 + 右箭头」，发现页与数据页共用。
- 新增任何「通栏入口」页面**一律用 `PlainGroup` / `PlainGroupEntry`**，不要再自写一套 `_XxxGroup` 私有组件 —— v1.0.19 之前发现页就是自写的，已统一。
- **卡片宽度唯一事实来源 = `kCardSideMargin` / `kCardMargin`**（v1.0.21 起，同在 `plain_group.dart`）：全站约定「**页面滚动容器不带左右内边距，所有卡片自带 `kCardMargin`**」（发现页 / 首页 / 数据页 / 我的页统一）。
  - 反面教材：数据页曾经 `ListView` 给 `fromLTRB(12,…)` 而 `PlainGroup` 又自带 12 → 卡片左右各缩进 24，比同页实名卡窄一圈。**新页面加卡片时，容器只给上下内边距**。
  - 新增卡片（哪怕不是 `PlainGroup`，如渐变卡）也要用 `margin: kCardMargin`，不要写死 12。
- 年月选择器 `lib/features/common/month_picker.dart`：项目未接入 `flutter_localizations`，**系统 `showDatePicker` 会显示英文**，凡需要「年月」输入一律用 `showMonthPicker`。

## 九、widget 测试两个必踩的坑（v1.0.21 实测）

1. **`Container` 的 `tester.getSize` 含 margin**：`Container(margin: …)` 的渲染盒含外边距，直接量永远得到整屏宽（400），量不出「卡片比别的窄」。要量卡片本体必须取内层 `DecoratedBox`（`find.descendant(...).first`）。
2. **页面 `_load()` 里不要 `await` 真实磁盘 I/O**：`AutomatedTestWidgetsFlutterBinding` 跑在 fake-async 区，`dart:io`（如 `MemoryStore.listAll` 读 MD 文件）的 future **不会完成**，会把 `await` 卡死 → `setState` 永不执行 → `_loading` 一直 true、页面降级成空卡、用例莫名失败且不报异常。解法：磁盘 I/O 用 `unawaited(...)` 单独异步刷新，首屏只等 SharedPreferences。
3. **量尺寸的临时测试文件跑完必须删**（v1.0.32 踩过）：想量真实尺寸时，写 `test/_measure_xxx_tmp_test.dart` 用 `tester.getSize(...)` 打印最准（**别只读代码推算**）。但**极易漏删** —— 漏了会被 `flutter test` 全量跑进去，导致用例总数虚高（曾误报 185，删后 184）。收尾时务必 `ls test/_*.dart` 确认清空。

## 十、数据页结构（v1.0.22 起）

数据页（`lib/features/tabs/database_tab.dart`）自上而下固定 6 张卡片，前三张经历与后两张资源卡均为 `PlainGroup` 通栏卡：

实名认证卡 → **自我评价** → 学历教育 → 工作经历 → 技能培训 → **自主学习** → 对话记忆

- **自我评价**：`self_evaluation_store.dart` 存**单段文本**（键 `self_evaluation_{手机号}`，存空串即删键）；`self_evaluation_page.dart` 进来即编辑态（无列表），多行输入 + 右上角保存，上限 500 字。
- **自主学习**：`study_output_store.dart`（`StudyOutput` = 标题 / 正文 / 图片 / PDF 附件，键 `study_output_{手机号}`，按 `updatedAt` 倒序）+ `study_output_list_page.dart`（列表 / 空态 / 全屏图片查看）+ `study_output_edit_page.dart`（标题必填；图片九宫格与写说说同形态：88 方块 + 等大加号）。附件落盘走 `study_file_store.dart`。
- **孤儿文件处理比写说说多一种情况**：编辑已有成果时移出的旧文件只登记、**保存成功后才删**（否则用户中途放弃编辑，原成果引用的文件已没了）；本次新加未保存的在 dispose 回收。
- 数据页 `_load()` 只 await SharedPreferences（自我评价 / 成果条数），**不 await 磁盘 I/O**（原因见「widget 测试坑」）。

## 四、待办 / 风险

- 仓库凭证明文暴露待处理：`git remote` 内嵌 Gitee 口令 + GitHub PAT；`lib/contracts/api_config.dart` 硬编码代理令牌；`dsh/README.md` 含真实 DeepSeek Key。建议尽快轮换，且与智懂你共用同一令牌。- KNOWN_ISSUES 台账已过期（基线 v1.0.7），其中 P0-3 / P1-3 / P1-4 已随 v1.0.8 修复，需回填校准。
