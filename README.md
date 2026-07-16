# Tom Riddle's Diary

成人向 iPad 情感反思日记 App：用户用 Apple Pencil 手绘涂鸦，一个「会回应的日记之魂」用文字 + AI 生成的图像、以**逐笔生长的手绘笔触**画/写回来。载体 iPad + 类纸膜。

> 私有项目 · 骨架搭建期。权威开发规范见 [`CLAUDE.md`](./CLAUDE.md)。

## 核心分工

- **AI 层（Oracle）决定「画什么」**：Qwen-VL 读涂鸦 + 记忆 → 文字 + Qwen-Image 生成线稿。
- **本地笔画引擎决定「像不像手画的」**：抽骨架 → 理笔顺 → 压感/收笔/速度/抖动 → 逐笔重播。
- 铁律：自然来自本地引擎，不指望模型直吐好看笔画。

## 仓库结构

```
CLAUDE.md              项目开发规范（L0，权威规则）
.claude/agents/        Agent 系统提示词（ios-dev / ai-pipeline-dev / backend-dev / qa-reviewer）
memory/                跨会话记忆（MEMORY.md + topics/ + daily/ + archives/）
docs/                  架构 / riddle 参考 / 源想法文档
Config/                Secrets 与 Persona 配置（真值 gitignored）
scripts/               ip_firewall_check.sh 门禁 + stroke_spike/（Task 1 实验）
（Xcode 工程 TomRiddlesDiary/ 由用户手建：iPadOS 17+ / SwiftUI / PencilKit）
```

App target 目标结构：`App / Features(Canvas·Response·Diary) / Oracle(Provider·Router·Persona) / StrokeEngine / Data / DesignSystem`（见 [`docs/architecture.md`](./docs/architecture.md)）。

## 快速开始

1. **密钥**：`cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig`，填入阿里云百炼 DashScope key。`Secrets.xcconfig` 已 gitignore。
2. **Persona（本地测试）**：`cp Config/Persona.example.json Config/Persona.local.json`，`Persona.local.json` 已 gitignore。
3. **提交门禁**：`bash scripts/ip_firewall_check.sh`（IP 禁用词 + 密钥入库检查）。
4. **Task 1 笔画实验**：见 [`scripts/stroke_spike/README.md`](./scripts/stroke_spike/README.md)。
5. **Xcode 工程**：由用户手建（名 `TomRiddlesDiary`），agent 填 `.swift` 源码。

## ⚠️ 安全红线

- 模型 API Key **绝不进客户端二进制/流量/git**。
- 骨架期客户端直连是**已知情的临时例外**：dev key 必须①设消费上限 ②gitignore ③**此 build 绝不分发**。
- 补瘦代理是 TestFlight/上架前的**硬门槛**。

## IP 与合规

- 华纳禁用词（`Harry Potter / Voldemort / Hogwarts / 霍格沃茨 / 魂器` 等）**不得进入被分发的用户可见面**。
- 已知情接受项（登记在案）：项目名、bundle id、私有仓库名、本地 persona 占位 —— 仅限不公开面，分发前须复核。
- 商业版必须自建原创「会回应的日记」世界观。详见 [`memory/topics/compliance.md`](./memory/topics/compliance.md)。

## 更多

- 决策日志（为什么这么定）：[`memory/topics/architecture-decisions.md`](./memory/topics/architecture-decisions.md)
- 12 步任务分解：[`memory/topics/task-breakdown.md`](./memory/topics/task-breakdown.md)
- 风险登记：[`memory/topics/risk-register.md`](./memory/topics/risk-register.md)
