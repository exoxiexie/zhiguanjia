# 职管家 · AI 职业管家

> 每个人，都值得一个终身陪伴的 AI 职业管家。

职管家是一款基于 Flutter 开发的安卓应用，定位为**面向个人用户的全职业生涯 AI 管家**。以个人实名身份为锚点，围绕职业规划、简历求职、技能成长、薪酬谈判、职场法律、职业健康等场景，提供主动式、全生命周期的智能服务。

职管家与「智懂你」（AI 企业管家，面向企业主体）共用同一套技术框架与产品架构，差异在于服务主体：智懂你铆定企业（统一社会信用代码），职管家铆定个人（手机号 + 实名认证）。

## 产品理念

- **身份铆定**：以个人实名身份为锚点，构建持续沉淀的个人职业上下文宇宙（UniText），让 AI 越来越懂你。
- **先做垂直，再做通用**：在职业这一高价值身份上做深做透，任务智能体按职业域逐个落地。
- **主动式管家**：不止于问答，未来基于个人数据主动生成职业洞察、机会提醒与行动建议。

## 功能特性

### 已实现（v1.0.0）

- **个人账号**：手机号 + 姓名 + 密码注册登录，按手机号做多租户本地数据隔离
- **实名认证**：登录后做身份证实名认证，GB11643 校验码本地校验，自动解析性别 / 生日 / 籍贯；身份证号脱敏存储，不向大模型发送完整号码
- **通用对话**：多模型代理、流式输出、附件上传、联网搜索、对话记忆自动提炼
- **历史会话**：多会话管理、左侧抽屉切换、标题自动生成、新建空会话去重
- **四个主 Tab**：懂你（通用对话 + 洞察 + 任务智能体）、数据、发现、我的
- **应用内更新**：Gitee Release 为主、GitHub raw 为回退，下载进度实时显示

### 规划中

- 职业任务智能体：职业规划、简历优化、求职面试、技能学习、薪酬谈判、职场法律、职业健康
- 个人职业数据宇宙（按来源 / 按任务域组织）
- AI 驱动的职业机会与服务发现
- 权威二要素实名认证、独立对话代理

## 技术栈

| 层级 | 技术 |
|------|------|
| 前端框架 | Flutter 3.16.9 (Dart >=3.2.6) |
| 平台 | Android (minSdk 21, targetSdk 34) |
| 状态管理 | Flutter 原生 StatefulWidget |
| 网络请求 | Dio（统一代理访问大模型） |
| 本地存储 | SQLite (sqflite) + SharedPreferences + 文件存储 |
| 架构 | contracts 契约层 + features 实现层，服务定位器 DI |
| 分发 | Gitee Release（APK / version.json）+ GitHub 源码同步 |

## 项目结构

```
lib/
├── contracts/        # 接口契约（模型无关、框架无关）
├── core/             # 依赖注入（服务定位器）
└── features/         # 业务模块（文件夹硬隔离）
    ├── personal/     # 个人账号、登录注册、实名认证、身份证工具
    ├── shell/        # 主框架（底部 4 Tab + 抽屉）
    ├── tabs/         # 懂你 / 数据 / 发现 / 我的
    ├── chat/         # 通用对话
    ├── agent/        # 任务智能体
    ├── data/         # 任务域注册表、上下文组装、标签体系
    ├── memory/       # 对话记忆自动提炼
    ├── storage/      # SQLite、记忆 / 文件 / 搜索存储、多租户隔离
    ├── discover/     # 发现页
    └── update/       # 应用内更新
```

**工程铁律**：
1. 前端驱动后端
2. 模块最小化，文件夹硬隔离，修改不产生连带效应
3. 契约层（contracts）与实现层（features）分离，模型无关、框架无关

## 快速开始

### 环境要求

- Flutter 3.16.9 / Dart >=3.2.6
- Android Studio / VS Code
- Android SDK (API 21+)、JDK 17

### 构建

```bash
flutter pub get
flutter build apk --release --no-tree-shake-icons
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 使用 `--no-tree-shake-icons` 规避本机环境字体 / 图标 tree-shaking 偶发的 Gradle 卡死；若中途强停过构建导致资源合并异常，执行 `cd android && ./gradlew clean` 后再构建。

## 工程信息

- 应用名：职管家
- 工程名 / 包名：`zhiguanjia` / `com.zhiguanjia.zhiguanjia`
- 版本：见 `pubspec.yaml` 与根目录 `version.json`（两者保持同步，独立于智懂你的版本序列）

## 版本历史

详见 [Gitee Releases](https://gitee.com/laoxie2076/zhiguanjia/releases)

| 版本 | 主要内容 |
|------|----------|
| v1.0.0 | 个人账号与实名认证、通用对话、4 Tab 框架、应用内更新 |

## 双仓库同步

- **Gitee**：主发布平台，国内访问快，APK 下载、应用内更新 —— https://gitee.com/laoxie2076/zhiguanjia
- **GitHub**：代码同步、开源背书 —— https://github.com/exoxiexie/zhiguanjia

每次提交同步推送到两个平台（Gitee master 分支、GitHub main 分支）。

## 隐私与安全

- 个人数据按手机号租户在本地隔离存储。
- 身份证号仅用于实名认证，界面与对话上下文均脱敏，不向大模型发送完整号码。
- 实名认证当前为本地校验，后续可按需接入权威二要素核验。

## 许可证

MIT License
