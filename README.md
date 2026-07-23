# Tom Riddle's Diary

成人向 iPad 情感反思日记 App：用户用 Apple Pencil 手绘涂鸦，一个「会回应的日记之魂」用文字与 AI 生成图像、以**逐笔生长的手绘笔触**画/写回来。载体为 iPad + 类纸膜。

> 私有项目，当前处于**正式功能开发前的准备阶段**。模型无关的权威开发规则见 [`AGENTS.md`](./AGENTS.md)；[`CLAUDE.md`](./CLAUDE.md) 仅作为兼容入口。

## 当前状态（2026-07-23）

| 项目 | 状态 | 说明 |
|---|---|---|
| Xcode / iOS Simulator | ✅ 就绪 | iPadOS 17+、仅 iPad；无签名 Simulator 构建已显示 `BUILD SUCCEEDED` |
| App 功能 | ⏸️ 尚未开始 | 仍是 Xcode 默认 `Hello, world!`；这是按用户要求暂停，不是遗漏 |
| Task 1 本地笔画预检 | ✅ 机械 smoke test 完成 | 10 组确定性 SVG+PNG 夹具生成了 20 个非空动画；尚未证明视觉手感或选定笔画源 |
| Task 1 真实魔法评审 | ⏳ 待做 | 夹具不是 Qwen-Image 输出，也不能证明 AI 读懂情绪；仍需真实用户涂鸦 + Qwen 回应 |
| Qwen API Key | 当前不阻塞 | 本地笔画预检不需要；真实 Qwen 测试前由用户登录阿里云申请，Agent 无法代办 |
| Apple 付费会员 / TestFlight | 现在不需要 | 当前 Simulator 与个人真机开发可先使用免费 Apple Account |
| 正式开发 | 等用户确认 | 完成本页所述准备与 Git 同步后，再由用户选择从 12 步计划的哪一步开始 |

最近一次构建只有一条非阻塞提示：工程没有依赖 `AppIntents.framework`，因此跳过 App Intents metadata extraction。空白脚手架阶段这是预期行为。

## 核心分工

- **AI 层（Oracle）决定「画什么」**：视觉模型读涂鸦和有限上下文，返回文字与生成图像。
- **本地笔画引擎决定「像不像手画的」**：抽骨架 → 理笔顺 → 压感/收笔/速度/抖动 → 逐笔重播。
- 铁律：自然感来自本地引擎，不指望模型直接吐出稳定、自然的最终笔画。

## 仓库结构

```text
AGENTS.md               所有模型/Agent 共用的权威项目规则
CLAUDE.md               Claude 类工具的兼容入口，只指向 AGENTS.md
.claude/agents/         角色提示词（ios / AI pipeline / backend / QA）
.kiro/steering/         Kiro 自动加载的专项规则（当前含安全 Git 同步）
memory/                 跨会话状态、决策、专题与工作日志
docs/                   技术架构与原始规划
Config/                 Secrets / Persona 模板；真实值由 .gitignore 排除
scripts/                 IP/密钥门禁 + stroke_spike Task 1 实验
TomRiddlesDiary/         Xcode 工程（iPadOS 17+ / SwiftUI）
```

目标 App 模块结构为 `App / Features(Canvas·Response·Diary) / Oracle(Provider·Router·Persona) / StrokeEngine / Data / DesignSystem`，详见 [`docs/architecture.md`](./docs/architecture.md)。

## 本地环境与验证

### 1. Xcode 工程

打开 `TomRiddlesDiary/TomRiddlesDiary.xcodeproj`，scheme 选择 `TomRiddlesDiary`。当前工程设置：

- Deployment target：iPadOS 17.0
- Targeted device family：iPad
- Code signing：Automatic
- 当前占位 bundle ID：`TomRiddlesDiary.TomRiddlesDiary`
- `DEVELOPMENT_TEAM`：尚未设置

无需登录 Apple 账号即可运行无签名 Simulator 构建：

```bash
xcodebuild \
  -project TomRiddlesDiary/TomRiddlesDiary.xcodeproj \
  -scheme TomRiddlesDiary \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

若 Xcode 报 platform/runtime 缺失，在 **Xcode → Settings → Components** 安装对应 iOS platform 与 Simulator runtime 后重试。

### 2. Task 1 笔画实验

本机预检环境使用 Python 3.10.6；依赖已精确锁定。首次设置：

```bash
cd scripts/stroke_spike
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
.venv/bin/python generate_test_assets.py
.venv/bin/python compare.py
```

`.venv/` 和 `out/` 均被 Git 忽略。素材来源、10 种表达覆盖、运行方式与限制见 [`scripts/stroke_spike/README.md`](./scripts/stroke_spike/README.md)。

### 3. 提交门禁

```bash
bash scripts/ip_firewall_check.sh
```

它扫描 Git 已跟踪和未被 `.gitignore` 排除的候选文本，检查分发面的 IP 禁用词，并确认敏感本地配置未被跟踪；二进制、构建产物和内部策略文档会跳过。它不能代替人工检查 staged diff。

## Qwen API Key：在哪里申请、现在怎么处理

### 申请步骤

1. 登录或创建阿里云账号。
2. 打开阿里云百炼 / Model Studio，阅读并接受服务条款以开通服务；控制台若要求实名认证，需要由账号持有人完成。
3. 按阿里云官方的 [Qwen 首次 API 调用指南](https://help.aliyun.com/en/model-studio/first-api-call-to-qwen) 进入 **API Key** 页面。
4. 点击 **Create API key**，选择实际要调用模型所在的区域/工作空间，然后保存密钥。
5. 不要把密钥发到聊天、截图、Issue 或 Git。若怀疑泄露，立即在控制台撤销并重建。

### 区域为什么重要

- API Key 按区域区分，不能假定跨区域通用。
- 官方指南说明，北京、新加坡、东京、法兰克福等部分区域的兼容接口 Base URL 还需要包含 `WorkspaceId`。
- 模型可用性、价格、网络可达性和数据处理条款可能随区域不同；接入真实模型时必须针对最终区域再次核对，不能只改一个 URL 就假定合规。

### 永久 Key 与临时 Key

- **永久 API Key 不得放入可分发 iOS App。** 即使文件被 `.gitignore` 排除，编译进 App 后仍可能被逆向或从流量中提取。
- `Config/Secrets.example.xcconfig` 只是模板；真实值可放入被忽略的 `Config/Secrets.xcconfig`，仅供不分发的本地 DEBUG/实验使用。当前空白 App 尚未接线读取它。
- TestFlight 与正式分发前必须使用安全后端：永久 Key 只留在服务端，客户端通过后端业务接口调用；或者由后端按需签发短期凭证。
- 阿里云官方的 [临时 API Key 指南](https://help.aliyun.com/en/model-studio/application-obtain-temporary-authentication-token) 明确建议浏览器/移动 App 等不可信环境由安全后端生成临时 Key。临时 Key 默认 60 秒，可配置 1–1800 秒，并继承用于签发它的永久 Key 权限，因此服务端仍需做最小权限、速率限制和滥用防护。

如果现在只做本地笔画引擎，不必先创建或填写 Qwen Key；到真实 Oracle 接入步骤前再申请即可。

## Bundle ID、Development Team、$99 与 TestFlight

### 四个概念的大白话解释

| 概念 | 是什么 | 当前是否需要 |
|---|---|---|
| **Bundle ID** | App 的唯一技术身份证，常用反向域名格式，如 `com.yourcompany.diary`；会关联签名、能力、Keychain 与 App Store 记录 | Simulator 可先用占位值；正式注册 App ID 前应确定 |
| **Development Team** | Xcode 用哪个 Apple 账号/组织为 App 签名；不是开发人员名单，也不是 bundle ID | 无签名 Simulator 不需要；真机安装时选择 |
| **免费 Personal Team** | 普通 Apple Account 登录 Xcode 后提供的个人签名队伍 | 足够当前学习、Simulator 和短期个人真机测试 |
| **Apple Developer Program** | 用于 App Store Connect、TestFlight 与正式分发的付费会员 | 现在不必购买；准备发 beta 时再买 |

当前 `TomRiddlesDiary.TomRiddlesDiary` 是 Xcode 生成的**占位 bundle ID**，不是已确认的商业标识。正式值通常应采用团队可长期控制的反向域名；在用户确定个人/公司主体与命名之前，Agent 不会擅自改成 `com.<team>.tomriddlesdiary`。

### 现在要不要付 99 美元？

**不用。** Apple 官方的 [会员对比](https://developer.apple.com/support/compare-memberships/) 说明：免费 Apple Account 可使用 Xcode、Simulator，也可做个人真机测试。Xcode 的免费 Personal Team 有限制：最多 10 个同时有效的 App ID、每个平台最多 3 台测试设备，App ID/设备注册和 provisioning profile 通常 7 天到期，需要重新构建安装。

Apple Developer Program 为 **99 USD/会员年度**（部分地区以当地货币计价；符合条件的非营利、教育或政府机构可能可申请减免）。它提供 Certificates/Identifiers/Profiles、App Store Connect、TestFlight 和分发能力；参见 Apple 的 [Programs overview](https://developer.apple.com/help/account/membership/programs-overview/)。

### 什么时候才进入 TestFlight？

建议满足以下条件后再购买会员并上传 TestFlight：

1. 本地笔画引擎与离线垂直切片已能稳定演示；
2. 正式 bundle ID、签名主体和原创公开品牌已确认；
3. 永久模型 Key 已移到安全后端，分发包不含永久密钥；
4. AI 披露、删除数据、危机兜底、隐私说明等发布门禁已具备；
5. 用户明确需要邀请其他人远程测试。

Apple [TestFlight 官方页](https://developer.apple.com/testflight/) 当前说明：每个开发团队最多可添加 100 名符合角色要求的内部测试者、最多 10,000 名外部测试者；外部测试组的首个 build 需先通过 TestFlight App Review。现在仍是默认 `Hello, world!`，没有上传 TestFlight 的价值。

## 正式开发计划（12 步）

1. 项目骨架、护栏与笔画源对比实验；
2. `Skeletonizer`（Zhang-Suen）纯逻辑实现；
3. `StrokeTracer`：骨架转有序笔画；
4. `StrokeHumanizer` + 逐笔重播；
5. PencilKit 画布、抬笔成页与墨水淡入；
6. `OracleProvider` 协议 + Mock，完成离线垂直切片；
7. Qwen 视觉理解层；
8. Qwen 图像回应与完整 Go/Kill 魔法评审；
9. Persona 包与 IP 防火墙；
10. 本地加密存档、时间线与召回旧页；
11. 区域端点路由与可选海外 provider 留桩；
12. 降级体验、AI 披露与发布前门禁收口。

完整说明见 [`memory/topics/task-breakdown.md`](./memory/topics/task-breakdown.md)。目前只完成了**开发环境与 Task 1 的机械预检**，尚未开始第 2 步的 Swift 功能开发，也尚未用真实 Qwen 回应完成第 1 步最终“肉眼选源/魔法 Go-Kill”。下一步必须由用户确认：

- **严格路线**：先取得 Qwen Key + 真实用户涂鸦，把 Task 1 的真实对比做完再写 App；或
- **并行路线**：先用现有夹具开发第 2–4 步本地 Magic Stroke Lab，同时等待真实 Qwen 素材。

## 安全、IP 与合规底线

- 永久模型 Key 不进入 Git、可分发客户端二进制或客户端可直接提取的请求；TestFlight 前安全后端是硬门槛。
- 公开/分发面不得出现未经授权的华纳 IP 名称、图标、截图、关键词或营销话术；项目内部占位不等于获得商业使用许可。
- 商业版需要原创「会回应的日记」品牌与世界观。
- 成人定位、AI 身份披露、危机兜底、一键删除、AI 生成内容标识与区域数据处理要求必须在发布前验证。
- 任何“数据不出境”“读完即删”等结论都必须以最终供应商区域、合同和实际实现为证据，不在设计文档里提前承诺。

## 规则文件说明

- Kiro/GPT-5.6 使用根目录 [`AGENTS.md`](./AGENTS.md) 作为模型无关的唯一详细规则，不需要创建 `GPT.md`。
- Kiro 专项规则放在 [`.kiro/steering/`](./.kiro/steering/)；当前 `git-sync.md` 只负责 Git 收口流程，不重复整份项目规范。参见 [Kiro Steering 文档](https://kiro.dev/docs/steering) 与 [Kiro Models 文档](https://kiro.dev/docs/models)。
- `CLAUDE.md` 保留给会主动读取该文件名的工具，但它不再维护第二份规则全文，避免两份内容逐渐冲突。

## 更多资料

- 技术架构：[`docs/architecture.md`](./docs/architecture.md)
- 架构决策：[`memory/topics/architecture-decisions.md`](./memory/topics/architecture-decisions.md)
- 模型选型与未决项：[`memory/topics/model-selection.md`](./memory/topics/model-selection.md)
- 风险登记：[`memory/topics/risk-register.md`](./memory/topics/risk-register.md)
- 合规与 IP：[`memory/topics/compliance.md`](./memory/topics/compliance.md)

Content was rephrased for compliance with licensing restrictions.
