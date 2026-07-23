<!-- L1 动态记忆；会话开始/“继续”时读取；保持 ≤200 行，细节移到 topics/ -->
# Tom Riddle's Diary — 项目记忆

## Project State（当前状态）

- **阶段**：正式功能开发前准备已基本完成，正在最终验证与 Git 同步；必须等用户确认并选择开发路线后才修改 App 功能。
- **App 现状**：`ContentView.swift` 仍为 Xcode 默认 `Hello, world!`，尚未开始正式功能开发。
- **仓库**：private `git@github.com:yuan7407/TomRiddlesDiary.git`；`main` 远端基线为 `e8cb486`，本轮准备工作在 feature 分支收口，不直接推 main。
- **Xcode**：`TomRiddlesDiary/TomRiddlesDiary.xcodeproj`；仅 iPad、iPadOS 17+、Automatic signing、占位 bundle ID `TomRiddlesDiary.TomRiddlesDiary`、未设置 Development Team。安装 iOS platform/runtime 后，无签名 Simulator Debug 构建已 `BUILD SUCCEEDED`；之前的 platform blocker 已解除。
- **Task 1A 机械预检**：Python 3.10.6 + 精确锁定依赖；10 组 GPT-5.6 编写的确定性同源 SVG/PNG 夹具生成完成，20 个非空动画输出验证通过。当前 spike 只有重采样、速度扰动和抖动，固定线宽，不模拟压感/收笔。
- **Task 1B 真实模型预检**：未完成。夹具不是 Qwen-Image 输出，也不能证明 AI 理解情绪；仍需真实用户涂鸦 + Qwen 回应后肉眼选源。
- **规则架构**：根 `AGENTS.md` 是 Kiro/GPT/Claude 共用的详细权威规则；`CLAUDE.md` 仅兼容入口；`.kiro/steering/git-sync.md` 只管 Git 专项流程；不创建 `GPT.md`。
- **Qwen Key**：当前本地笔画预检不需要。真实 Qwen 测试前由用户登录阿里云创建；永久 Key 不进入可分发客户端，TestFlight 前必须接安全后端或最小权限短期凭证。
- **Apple 账号**：现在不需要购买 $99/年会员，也不需要 TestFlight；Simulator 与免费 Personal Team 足够当前阶段。正式 bundle ID、主体和公开品牌尚未决定。

## Product North Star

- 成人向 iPad 情感反思日记：用户用 Apple Pencil 涂鸦，“日记之魂”以文字和 AI 图像、通过逐笔生长的手绘笔触回应。
- AI/Oracle 决定“画什么”；本地 StrokeEngine 决定“像不像手画的”。
- 情感检验：换一张涂鸦，回应必须明显不同；技术跑通不等于魔法体验通过。

## Next User Decisions（正式开发前必须询问）

1. 选择开发路线：
   - **严格路线**：先申请 Qwen Key、准备真实用户涂鸦，完成 Task 1B 后再写 App；
   - **并行路线**：先批准用现有夹具开发 Task 2–4 本地 Magic Stroke Lab，同时等待真实模型素材。
2. 到签名/发布阶段前决定正式 bundle ID、个人或组织主体与原创公开品牌。
3. 到真实 Oracle 接入前决定阿里云区域/Workspace，并重新核对模型可用性、价格、网络和数据条款。

## User Preferences

- 中文交流；用大白话解释术语，不甩黑话。
- 深度、全面、客观；区分已验证事实、假设与待用户决定。
- 不替用户拍板命名、正式 bundle ID、商业品牌、付费或架构方向。
- 不静默兜底；阻塞、测试失败、远端分叉和未知信息必须暴露。
- 用户要求“准备完成后先确认”，所以不得提前开发正式 App 功能。
- 每次实质任务收口自动执行安全 Git fetch/验证/commit/push/hash 核对；默认 feature 分支/PR，不 force push。

## Known Pitfalls

- **kiro-pet** 已迁到 `/Users/envision/Documents/Personal_Docs/110_KiroPet`；本仓库不得重新跟踪相关运行时或钩子。
- **Xcode 嵌套 Git** 已解除，备份位于根 `.git/xcode-nested-repo-backup-8d5eca1`；项目只使用根仓库。
- **密钥口径**：禁止的是永久 Key 进入可分发客户端/Git；本地非分发 DEBUG 例外仍必须 gitignored、最小权限/额度/监控，并绝不分发。
- **隐私承诺**：“读完即删”“不用于训练”“数据不出境”必须由区域、合同和实际实现证明，不能因选择备案模型而预先承诺。
- **门禁扫描**：`scripts/ip_firewall_check.sh` 使用 Git tracked + non-ignored 候选文本，跳过内部策略、二进制、`.venv` 和构建产物；修改扫描规则后要验证不会超时或误报 `AGENTS.md`。
- **IP**：内部占位不代表商业授权；公开/分发前必须换原创品牌并人工复核。

## Architecture Quick Ref

- 三段：成页 → Oracle（文字流式 + 图像并行）→ StrokeEngine（Skeletonizer → StrokeTracer → StrokeHumanizer → 重播）。
- 模块：`App / Features / Oracle / StrokeEngine / Data / DesignSystem`。
- 12 步计划与 1A/1B/第 8 步三层验证见 `topics/task-breakdown.md`。

## Topic Index

- `topics/task-breakdown.md` — 12 步计划、当前门槛与两条启动路线
- `topics/architecture-decisions.md` — 核心决策与原因
- `topics/model-selection.md` — Qwen、区域/Key 与未核实项
- `topics/stroke-engine.md` — 笔画引擎与 Task 1 证据边界
- `topics/compliance.md` — IP、密钥、隐私与发布合规
- `topics/risk-register.md` — 风险与缓解
- `topics/open-questions.md` — 等用户决定的问题
- `topics/prompt-tuning.md`、`topics/cost.md` — 后续填充

## Session Log

### 2026-07-23

- GitHub/Xcode 工程纳入根仓库，嵌套 Git 可恢复地解除；远端基线已同步。
- iOS platform/runtime 安装后，无签名 Simulator Debug 构建成功，旧环境阻塞解除。
- 完成 10 组确定性 SVG+PNG 工程夹具与 20 个动画输出的机械预检；未冒充 Qwen/情绪评审结果。
- README 补齐 Qwen Key、区域安全、bundle ID、Development Team、免费 Personal Team、$99 会员和 TestFlight 时机。
- 规则迁移至 `AGENTS.md`；审核并统一旧 Agent/架构文档的密钥和数据证据口径。
- 修复 IP 门禁遍历 `.venv`/二进制和误报 `AGENTS.md` 的问题；门禁重新通过。

### 2026-07-15

- 完成初始骨架、memory/docs/agents/Config/scripts/README 和首个本地 commit；详见 `daily/2026-07-15.md`。
