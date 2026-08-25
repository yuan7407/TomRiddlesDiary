# Claude 兼容入口

本项目的模型无关、权威开发规范位于 [`AGENTS.md`](./AGENTS.md)。任何读取 `CLAUDE.md` 的 Agent 或工具都必须先读取并遵循 `AGENTS.md`；本文件不维护第二份规则全文，以免两份规范逐渐冲突。

## 强制代码质量入口

开始新增、修改或审阅代码前，必须执行 `AGENTS.md` 中的“注释与修改原因（强制）”：逐个检查所有受影响及新增的手写源代码/测试文件是否具有文件职责、模块边界和设计原因的文件头；核心算法、状态切换、并发与取消逻辑是否解释了“为什么”；本次行为或架构调整的原因是否同步记录到 memory。这里仅提供不可跳过的入口检查，具体标准仍以 `AGENTS.md` 为唯一事实源。

补充入口：

- Git 自动同步专项规则：[`.kiro/steering/git-sync.md`](./.kiro/steering/git-sync.md)
- 当前项目状态与跨会话记忆：[`memory/MEMORY.md`](./memory/MEMORY.md)
- 12 步开发计划：[`memory/topics/task-breakdown.md`](./memory/topics/task-breakdown.md)
- 技术架构：[`docs/architecture.md`](./docs/architecture.md)

规则关系：

1. 系统与用户的明确指令优先。
2. `AGENTS.md` 是通用项目规则的唯一事实源。
3. `.kiro/steering/` 可为特定工作流增加更具体约束；Git 操作以 `git-sync.md` 为准。
4. `CLAUDE.md` 只提供不可跳过的兼容入口检查，不建立第二套独立标准，也不复制 `AGENTS.md` 的规则全文。

Kiro/GPT-5.6 不需要 `GPT.md`；根目录 `AGENTS.md` 才是本仓库选定的统一规则文件。
