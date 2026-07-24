<!-- L1 动态记忆；会话开始/“继续”时读取；保持 ≤200 行，细节移到 topics/ -->
# Tom Riddle's Diary — 项目记忆

## Project State（当前状态）

- **阶段**：用户已明确选择 B 并行路线；Swift Tasks 2–4 与离线 Magic Stroke Lab 已完成，正在 feature 分支 `feature/magic-stroke-lab` 做最终门禁与同步，不直接推 main。
- **App 现状**：`ContentView.swift` 已从默认占位改为 iPad Magic Stroke Lab；可切换 `01_weary_flower`、`04_anger_cage`、`05_crossroads_maze`，比较 Vector/Raster 源并逐笔重播。
- **StrokeEngine**：纯 Swift `Skeletonizer → StrokeTracer → StrokeHumanizer → StrokeReplayTimeline` 已落地；固定 seed、端点不漂移、压感 taper、长度时序和 raster/ordered 双源均有 XCTest。全量 41 tests、0 failures。
- **演示验证**：generic iOS Simulator build 成功；App 已安装并启动到 iPad (A16)，首屏截图确认控件、统计和线稿正常显示。该检查不等于真实设备手感或情绪质量通过。
- **Xcode**：`TomRiddlesDiary/TomRiddlesDiary.xcodeproj`；仅 iPad、iPadOS 17+、Automatic signing、占位 bundle ID `TomRiddlesDiary.TomRiddlesDiary`、未设置 Development Team。Xcode 26.6 并行 test clone 存在工具崩溃，测试须使用 `-parallel-testing-enabled NO`。
- **Task 1A 机械预检**：Python 3.10.6 + 精确锁定依赖；10 组 GPT-5.6 编写的确定性同源 SVG/PNG 夹具和 20 个动画输出已验证。Python spike 固定线宽；Swift Lab 新增压感/收笔时序，但仍不能替代真实素材评审。
- **Task 1B 真实模型预检**：未完成。夹具不是 Qwen-Image 输出，也不能证明 AI 理解情绪；仍需真实用户涂鸦 + Qwen 回应后肉眼选源。
- **规则架构**：根 `AGENTS.md` 是 Kiro/GPT/Claude 共用的详细权威规则；`CLAUDE.md` 仅兼容入口；`.kiro/steering/git-sync.md` 只管 Git 专项流程；不创建 `GPT.md`。
- **Qwen Key**：当前 Route B Lab 不需要，也未接入任何模型/网络。真实 Qwen 测试前由用户登录阿里云创建；永久 Key 不进入可分发客户端，TestFlight 前必须接安全后端或最小权限短期凭证。
- **Apple 账号**：现在不需要购买 $99/年会员，也不需要 TestFlight；Simulator 与免费 Personal Team 足够当前阶段。正式 bundle ID、主体和公开品牌尚未决定。

## Product North Star

- 成人向 iPad 情感反思日记：用户用 Apple Pencil 涂鸦，“日记之魂”以文字和 AI 图像、通过逐笔生长的手绘笔触回应。
- AI/Oracle 决定“画什么”；本地 StrokeEngine 决定“像不像手画的”。
- 情感检验：换一张涂鸦，回应必须明显不同；技术跑通不等于魔法体验通过。

## Next User Decisions

1. Route B Tasks 2–4 收口后，确认下一步是第 5 步 PencilKit 画布，还是先补 Task 1B 真实模型素材与初步 Go/Kill。
2. Task 1B 前准备至少 10 张不同表达的真实用户涂鸦；离线工程夹具不能替代。
3. 到签名/发布阶段前决定正式 bundle ID、个人或组织主体与原创公开品牌。
4. 到真实 Oracle 接入前决定阿里云区域/Workspace，并重新核对模型可用性、价格、网络和数据条款。

## User Preferences

- 中文交流；用大白话解释术语，不甩黑话。
- 深度、全面、客观；区分已验证事实、假设与待用户决定。
- 不替用户拍板命名、正式 bundle ID、商业品牌、付费或架构方向。
- 不静默兜底；阻塞、测试失败、远端分叉和未知信息必须暴露。
- 用户已选择 B 并行路线；本轮授权范围为 Tasks 2–4 Magic Stroke Lab。完成并同步后，应让用户确认下一步是 Task 5 还是 Task 1B，而不是自动接入真实模型。
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
- 用户选择 B 并行路线；完成 Swift Tasks 2–4、41 个 XCTest 与可启动的 iPad Magic Stroke Lab，保持 raster/ordered 双源可插拔且未接入模型或网络。

### 2026-07-15

- 完成初始骨架、memory/docs/agents/Config/scripts/README 和首个本地 commit；详见 `daily/2026-07-15.md`。
