<!-- L1 经验记忆 · 每次自动加载 · 保持 ≤200 行，细节移到 memory/topics/ -->
# Tom Riddle's Diary — 记忆文件（MEMORY.md）

## Project State（当前状态）

- **阶段**: 骨架搭建期（Phase 1 前置）。仓库脚手架落盘中，Xcode 工程尚未由用户创建。
- **一句话愿景**: 成人向 iPad 情感反思日记 App——用户用 Apple Pencil 手绘涂鸦，「日记之魂」用文字 + AI 生成图像、以**逐笔生长的手绘笔触**回应。
- **情感北极星**: 里德尔日记「你写它回、墨水逐字浮现、与你建立关系」的魔法（仅灵感锚点，非可发售外观）。
- **核心分工**: AI 层（Oracle）决定「画什么」；本地笔画引擎决定「像不像手画的」。自然来自本地引擎，不靠模型吐 SVG。
- **模型**: 阿里 Qwen 为主（Qwen-VL 理解 + Qwen-Image 生成），Apache 2.0 开源权重可自部署托底；海外画质升级（Gemini/FLUX）留桩。

## Pending Decisions（未决 / 需问用户 — 见 topics/open-questions）

1. **GitHub 仓库**: 确认私有 + 仓库名（建议 `yuan7407/TomRiddlesDiary`）→ 未确认，暂不 commit/push。
2. **阿里云百炼**: 当前定价 / 国际区覆盖 / 「国际节点从中国能否免翻墙直连」→ 定架构或签约前必须复核。
3. **笔画来源**: SVG 源 vs 抽骨架源 → 由 **Task 1 对比实验用眼睛定**，禁止提前拍板。
4. **.claude/agents/* 四份系统提示词**: 已起草，待用户过目。
5. **Xcode 工程**: 用户手建（名 TomRiddlesDiary，iPadOS 17+，SwiftUI，bundle id 含 tomriddle）；需协调「文件加入 target」时机。

## User Preferences（用户工作风格 — 必读）

- **Ultrathink**: 深度、全面、客观；追问「为什么」至少三层。
- **不替用户拍板**命名 / 技术方向 / 架构——不确定就先问。（曾因擅自起名 "InkEcho" 被批评。）
- **不静默兜底、不自行决断**；有阻塞就暴露出来。
- **不甩黑话**；用到就用大白话解释（例：skeletonize=把渲染出的图「瘦身」成单像素中心线再逐笔重画）。
- **重视诚实**: 拿不到的东西（实时时间/定位/真 agent teams）如实说，用户认可坦诚。
- **会挑战也接受被纠正**（如 SVG vs 抽骨架那次）；对就坚持并讲清理由，别一味附和。
- 回答常很简短（如 "1=a 2=b"）；**中文交流**。
- 沿用 Pangan 的记忆系统 + Agent Teams 约定。

## Known Pitfalls（踩坑）

- **kiro-pet 误放已迁走**：kiro-pet（Kiro 虚拟宠物：`kiro-pet/` + `.kiro/hooks/kiro-pet-*.json` + `.kiro/pet/`）曾被误放进 109，2026-07-15 已整体迁到 `110_KiroPet`。**109 不得再含 kiro-pet**；若再现属误放，删除或迁回 110。其钩子每次工具调用触发 node，曾致一条 bash 输出串扰。
- **大段 fs_write 会被中断**：CLAUDE.md 首次整体写入被 abort 两次；改用「小块 fs_write + fs_append」成功。以后写大文件分块。
- **IP 泄漏面**：`Harry Potter / Voldemort / 霍格沃茨 / Hogwarts / 魂器` 等华纳词绝不进被分发的用户可见面。`Tom Riddle` 名仅限 gitignored 本地文件 + 内部文档，不进可分发代码。
- **密钥泄漏面**：`DASHSCOPE_API_KEY` 等绝不进客户端二进制/流量/git；骨架期 dev key 直连是已接受的临时例外（设消费上限 + gitignore + 此 build 不分发）。

## Architecture Quick Ref

- **管道三段**: 成页（PencilKit 抬笔静置 ~2.8s → 灰度 PNG）→ Oracle（Qwen-VL + 近几页记忆 → 文字流式 + Qwen-Image 并行）→ StrokeEngine（Skeletonizer[Zhang-Suen] → StrokeTracer → StrokeHumanizer → 逐笔重播）。
- **模块结构**: `App / Features(Canvas·Response·Diary) / Oracle(Provider·Router·Persona) / StrokeEngine / Data / DesignSystem`。
- **仓库根**: `.claude/agents/`、`memory/`、`docs/`、`Config/`、`scripts/`。
- **12 步任务分解**: 见 `docs/architecture.md` 与 `memory/topics/task-breakdown.md`。

## Topic Index

- `topics/architecture-decisions.md` — 10 条关键决策 + 为什么（决策日志）
- `topics/compliance.md` — IP 防火墙 + 合规红线细节
- `topics/model-selection.md` — 为什么选 Qwen（含未核实项）
- `topics/stroke-engine.md` — 笔画引擎与 riddle 借鉴的分工
- `topics/task-breakdown.md` — 12 步测试驱动任务
- `topics/risk-register.md` — 风险登记 + 已接受风险
- `topics/prompt-tuning.md` — prompt 调优（待填）
- `topics/cost.md` — token / 图像生成成本（待填）

## Session Log

### 2026-07-15
- 接手规划交接文档，启动骨架落盘（section 11 kickoff）。
- 已完成：`.gitignore`（防泄漏优先）、`CLAUDE.md`（Pangan 拷贝 → Tom Riddle's Diary 版）。
- 进行中：memory/、docs/、.claude/agents/、Config/、scripts/、README.md。
- 待用户确认后：git init → commit → GitHub 私有仓库 → push。
- 详见 `memory/daily/2026-07-15.md`。
