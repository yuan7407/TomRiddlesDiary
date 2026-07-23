# Claude 兼容入口

本项目的模型无关、权威开发规范位于 [`AGENTS.md`](./AGENTS.md)。任何读取 `CLAUDE.md` 的 Agent 或工具都必须先读取并遵循 `AGENTS.md`；本文件不维护第二份规则全文，以免两份规范逐渐冲突。

补充入口：

- Git 自动同步专项规则：[`.kiro/steering/git-sync.md`](./.kiro/steering/git-sync.md)
- 当前项目状态与跨会话记忆：[`memory/MEMORY.md`](./memory/MEMORY.md)
- 12 步开发计划：[`memory/topics/task-breakdown.md`](./memory/topics/task-breakdown.md)
- 技术架构：[`docs/architecture.md`](./docs/architecture.md)

规则关系：

1. 系统与用户的明确指令优先。
2. `AGENTS.md` 是通用项目规则的唯一事实源。
3. `.kiro/steering/` 可为特定工作流增加更具体约束；Git 操作以 `git-sync.md` 为准。
4. `CLAUDE.md` 不增加独立要求，也不应复制 `AGENTS.md`。

Kiro/GPT-5.6 不需要 `GPT.md`；根目录 `AGENTS.md` 才是本仓库选定的统一规则文件。
