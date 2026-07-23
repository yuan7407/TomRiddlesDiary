<!-- L1 经验记忆 · 每次自动加载 · 保持 ≤200 行，细节移到 memory/topics/ -->
# Tom Riddle's Diary — 记忆文件（MEMORY.md）

## Project State（当前状态）

- **阶段**: Phase 1 前置骨架已落盘；标准 SwiftUI Xcode 工程已由用户创建，正在纳入根仓库。
- **仓库**: 私有 `git@github.com:yuan7407/TomRiddlesDiary.git`；首提交 `9c8f4a6` 已推送并验证本地/远端一致。
- **Xcode**: `/TomRiddlesDiary/TomRiddlesDiary.xcodeproj`，仅 iPad、iPadOS 17+，已由根仓库统一管理；Xcode 自动生成的嵌套 Git 已解除，原仓库备份在根 `.git/xcode-nested-repo-backup-8d5eca1`（不入库、可恢复）。项目文件 lint 与 Swift parse 通过；完整 build 待安装/启用 Xcode iOS 26.5 platform component 后复跑。
- **一句话愿景**: 成人向 iPad 情感反思日记 App——用户用 Apple Pencil 手绘涂鸦，「日记之魂」用文字 + AI 生成图像、以**逐笔生长的手绘笔触**回应。
- **情感北极星**: 里德尔日记「你写它回、墨水逐字浮现、与你建立关系」的魔法（仅灵感锚点，非可发售外观）。
- **核心分工**: AI 层（Oracle）决定「画什么」；本地笔画引擎决定「像不像手画的」。自然来自本地引擎，不靠模型吐 SVG。
- **模型**: 阿里 Qwen 为主（Qwen-VL 理解 + Qwen-Image 生成），Apache 2.0 开源权重可自部署托底；海外画质升级（Gemini/FLUX）留桩。

## Pending Decisions（未决 / 需问用户 — 见 topics/open-questions）

1. **阿里云百炼**: 当前定价 / 国际区覆盖 / 「国际节点从中国能否免翻墙直连」→ 定架构或签约前必须复核。
2. **笔画来源**: SVG 源 vs 抽骨架源 → 由 **Task 1 对比实验用眼睛定**，禁止提前拍板；用户稍后放入 10 组素材。
3. **.claude/agents/**: 四份提示词已按 Pangan 格式起草，待用户需要时继续校订。

## User Preferences（用户工作风格 — 必读）

- **Ultrathink**: 深度、全面、客观；追问「为什么」至少三层。
- **不替用户拍板**命名 / 技术方向 / 架构——不确定就先问。（曾因擅自起名 "InkEcho" 被批评。）
- **不静默兜底、不自行决断**；有阻塞就暴露出来。
- **不甩黑话**；用到就用大白话解释（例：skeletonize=把渲染出的图「瘦身」成单像素中心线再逐笔重画）。
- **重视诚实**: 拿不到的东西如实说；对就坚持并讲清理由，别一味附和。
- 回答常很简短（如 "1=a 2=b"）；**中文交流**。
- 沿用 Pangan 的记忆系统 + Agent Teams 约定。
- **Git 持续授权**: 每次实质任务收口，Agent 自动 fetch/检查 → 验证与门禁 → commit → push → 比较本地与远端 commit；不等用户再提醒。常规开发仍走 feature branch/PR，不使用保存/停止钩子盲推，不 force push。

## Known Pitfalls（踩坑）

- **kiro-pet 误放已迁走**：`kiro-pet/` + `.kiro/hooks/kiro-pet-*.json` + `.kiro/pet/` 已迁到 `110_KiroPet`。109 不得再含/跟踪 kiro-pet；当前会话若重建 `.kiro/pet/state.json` 也由 `.gitignore` 排除并删除。
- **Xcode 嵌套 Git**：Xcode 建项目时自动创建子仓库，会阻止根仓库跟踪源码。已把该 `.git` 备份到根 `.git/xcode-nested-repo-backup-8d5eca1`，以后项目只用根仓库。
- **大段 fs_write 会被中断**：大文件改用小块 edit/append。
- **IP 泄漏面**：华纳词绝不进被分发的用户可见面；测试 persona 名仅限 gitignored 本地配置 + 内部文档。
- **密钥泄漏面**：`DASHSCOPE_API_KEY` 等绝不进客户端二进制/流量/git；骨架期 dev key 直连是临时例外（消费上限 + gitignore + 此 build 不分发）。

## Architecture Quick Ref

- **管道三段**: 成页（PencilKit 抬笔静置 ~2.8s → 灰度 PNG）→ Oracle（Qwen-VL + 近几页记忆 → 文字流式 + Qwen-Image 并行）→ StrokeEngine（Skeletonizer[Zhang-Suen] → StrokeTracer → StrokeHumanizer → 逐笔重播）。
- **模块结构**: `App / Features(Canvas·Response·Diary) / Oracle(Provider·Router·Persona) / StrokeEngine / Data / DesignSystem`。
- **仓库根**: `.claude/agents/`、`.kiro/steering/`、`memory/`、`docs/`、`Config/`、`scripts/`、`TomRiddlesDiary/`。
- **12 步任务分解**: 见 `docs/architecture.md` 与 `memory/topics/task-breakdown.md`。

## Topic Index

- `topics/architecture-decisions.md` — 10 条关键决策 + 为什么
- `topics/compliance.md` — IP 防火墙 + 合规红线
- `topics/model-selection.md` — 为什么选 Qwen（含未核实项）
- `topics/stroke-engine.md` — 笔画引擎与 riddle 借鉴
- `topics/task-breakdown.md` — 12 步测试驱动任务
- `topics/risk-register.md` — 风险登记 + 已接受风险
- `topics/prompt-tuning.md` — prompt 调优（待填）
- `topics/cost.md` — token / 图像生成成本（待填）

## Session Log

### 2026-07-23
- GitHub 私有仓库已创建；首提交 `9c8f4a6` 推送成功并验证本地/远端哈希一致。
- Xcode 工程已创建；嵌套 Git 已可恢复地解除，准备由根仓库统一跟踪。
- 用户授权后续 Git 检查、提交、推送、版本同步由 Agent 自动负责；规则写入 CLAUDE.md + `.kiro/steering/git-sync.md`。
- kiro-pet 已迁到 `110_KiroPet`；109 永不跟踪其运行时/钩子。
- 详见 `memory/daily/2026-07-23.md`。

### 2026-07-15
- 完成 section 11 骨架落盘：`.gitignore`、`CLAUDE.md`、memory/、docs/、agents、Config/、scripts/、README.md。
- 首个本地 commit `9c8f4a6`；当时 GitHub 仓库尚未创建，后于 2026-07-23 推送。
- 详见 `memory/daily/2026-07-15.md`。
