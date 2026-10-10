# App 工程参考（**现行文档 · 按需阅读**）

> **状态**：现行（L1）　**本次核对日期**：2026-10-10
> **维护规则**：只保留**能被当前代码验证**的内容。条目一旦过期 → 删除并移入 `docs/archive/`。
> 项目现状、决策、待办以 **`项目台账.md`** 为准；本文件只讲 App 内部怎么改。

## 1. 仓库与发版

- 双仓库：Gitee `master`（主发布，托管 APK + version.json）＋ GitHub `main`（源码），每次双端推送
- 打包：`./build_apk.sh` 默认 **arm64-v8a 单 ABI**（`--universal` 出全 ABI），日志末行「=== 构建完成（耗时 X）===」是发版报告必填项
- 签名：Android **debug 证书**，SHA-256 `91d4926d…`（历次一致 → 可覆盖升级）。转正式 keystore 属 P0 风险事项
- 发版动作见台账「发版与交付规范」；Gitee Release 附件名必须 = `zhiguanjia-vX.Y.Z.apk`，与 `version.json` 的 `url` 严格对应，否则"能发现新版本但下载 404"
- 网络坑：本机对 GitHub 的 HTTP/2 不稳，`git push`/`curl` 加 `-c http.version=HTTP/1.1` / `--http1.1`

## 2. 架构铁律

- ① 前端驱动后端　② 模块最小化、文件夹硬隔离　③ **契约层 `lib/contracts/` 与实现层 `lib/features/` 分离，UI 只依赖接口**
- 新增功能先看有没有现成约定：通栏入口用 `features/common/plain_group.dart`（**不要自写 `_XxxGroup`**）

## 3. 易踩的结构性约定（改动前必看）

| 主题 | 唯一事实来源 | 注意 |
|---|---|---|
| 底栏五格 | `shell/shell_page.dart` 的 `kShellNavItems` | 改顺序必须**同步** `onDestinationSelected` 里 `i==1`/`i==4` 两个刷新下标；回归 `test/shell_tabs_test.dart` |
| 底栏高度 56 | `lib/main.dart` 的 `kNavigationBarHeight`（经 `buildAppTheme()` 下发） | 新增主题项一律写进 `buildAppTheme()`，测试才吃同一份配置 |
| 顶栏导航自绘 | `features/common/app_nav_bar.dart` | 官方 `NavigationDestination` 把药丸/8dp 间隙写死在私有代码，故自绘 |
| 输入栏行数 | `features/chat/chat_input_bar.dart` 顶部常量 | 未聚焦 1 行 / 聚焦 2 行 / 最多 5 行 |
| 卡片边距 | `kCardSideMargin` / `kCardMargin` | 页面滚动容器**不带**左右内边距，卡片自带 margin |
| 年月选择 | `features/common/month_picker.dart` 的 `showMonthPicker` | 未接 flutter_localizations，系统 picker 是英文 |
| 说说卡片 | `blog_post_card.dart` | 三处列表 + 作者主页共用；改展示只改这一个文件 |
| 经历类型 | `features/data/experience_models.dart` 的 `ExperienceKind.all` | 注册一条即自动派生卡片/详情/表单/校验；`id` 与存储键不可动，`label` 随便改 |
| 业务域注册表 | `features/data/business_domain.dart` 的 `kBusinessDomains` | 界面层已删（v1.0.28），底层仍被"建表"与"记忆提炼校验"引用，**不可随手删** |

## 4. 文件与数据落盘

- **图片落盘铁律**：`image_picker` 返回系统临时缓存路径，**绝不能直接入库**，必须先复制进应用私有目录（`AvatarStore` / `PostImageStore` / `StudyFileStore`），否则系统清理后裂图；展示统一 `Image.file` + `errorBuilder`
- **PDF**：`syncfusion_flutter_pdf` 只能提文本、无渲染器 → 用 `OpenFilex.open()` 调系统阅读器（零新依赖）
- **自主学习成果的孤儿文件**：编辑时移出的旧文件登记后**保存成功才删**；新加未保存的在 dispose 回收

## 5. 对话链路（**必须真流式**）

- 走 Agent：`home_tab.dart` 里 `agentService != null`（永真）→ `HttpAgentService.run()`；`HttpChatService.sendMessage()` 在实际聊天中**不会被调用**
- 真流式：`stream: true` + `onDelta` 即上屏；工具调用按 `index` 分片拼装（`_streamModelRound`）
- ⚠️ **绝不能退回"假流式"**（生成完再逐字回放）—— `test/agent_stream_test.dart` 已锁住"正文必须逐片回调"
- 流式 ≠ 绕开 Agent：上下文组装、工具注册执行、结果回填、搜索沉淀全保留
- 网络链路：代理在**阿里云函数计算（成都）**，唯一配置点 `lib/contracts/api_config.dart` 的 `proxyBaseUrl`
- **DeepSeek 密钥只在函数计算的环境变量里**（2026-10-10 核实：仓库与 APK 内均无明文）；App 侧只有调用中转用的 `proxyToken`
- DeepSeek 思考模式**不支持 `tool_choice:"required"`**，项目用 `auto`

## 6. 应用内更新链路

`features/update/update_service_impl.dart`：读 `version.json` → 比对 `versionCode > buildNumber` → 按 `url` 下载。
两源：① Gitee API `contents/version.json?ref=master`（base64）② 回退 GitHub raw。
`receiveTimeout` 是**空闲超时**（30s 无新数据才失败），不是总时长 → 慢下载能成功，卡住才失败。

## 7. 测试与构建

- **widget 测试三坑**：① `Container` 的 `getSize` 含 margin，量本体要取内层 `DecoratedBox`；② 页面 `_load()` **别 await 真实磁盘 I/O**（fake-async 下不完成会卡死）；③ **量尺寸的临时测试文件跑完必须删**（否则虚增用例数）
- **构建性能**：本机 8 GB 内存是硬约束。`android/gradle.properties` 用 `-Xmx2G -XX:MaxMetaspaceSize=512m` + `kotlin.daemon.jvmargs=-Xmx1G`（原 4G 会疯狂换页：10 分 8 秒 → 2 分 14 秒）
  - 纪律：构建前**不要并发**跑 `flutter test`/`analyze`；感觉越跑越慢先 `cd android && ./gradlew --stop`
- 当前测试基线：`flutter test` **280 项**、服务端 **364 项**、后台冒烟 **15 项**，`flutter analyze` 0 error / 0 warning

## 8. 母项目关系

`../智懂你`（AI 管家集合 v1.2.x）与本项目**同源分叉**，共用框架与后端代理，但核心代码是**复制关系（非共享包）** → 存在同步漂移风险，改共用部分时两边都要看。
