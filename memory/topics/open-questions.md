# 尚未解决 / 需要问用户的问题

## 正式开发前的当前确认

1. **路线选择**：
   - A 严格路线：先申请 Qwen Key + 准备真实用户涂鸦，完成 Task 1B；
   - B 并行路线：先批准 Task 2–4 Magic Stroke Lab，同时等待真实 Qwen 素材。
   在用户明确选择前，不开始 App 功能开发。
2. **真实测试涂鸦**：10 组确定性工程夹具已完成，但真实用户涂鸦尚未准备；两者不能互相冒充。
3. **Qwen 区域/Workspace**：到真实模型测试前决定，并核对模型、价格、网络和数据条款。Key 当前不阻塞本地笔画开发。
4. **正式 bundle ID / 主体 / 公开品牌**：当前为 Xcode 占位 `TomRiddlesDiary.TomRiddlesDiary`。在注册 App ID/App Store 记录前，由用户决定个人或组织主体、长期可控反向域名与原创品牌。
5. **笔画源最终选择**：SVG 与图像抽骨架须等真实模型素材和主观评审；Task 1A 机械跑通不等于选型完成。

## 后续但现在不阻塞

- 何时购买 Apple Developer Program：需要 TestFlight/远程 beta/分发时再决定。
- Qwen 当前价格、国际覆盖、大陆网络可达性与数据处理条款：签约/接入前复核。
- `.claude/agents/*` 已按 `AGENTS.md` 统一安全口径；实际启用角色协作时再按任务细化。

## 已解决

- GitHub private remote、根仓库与 Xcode 工程已统一管理并同步。
- iOS platform/runtime 安装完成；iPadOS 17+ 无签名 Simulator Debug build 成功。
- 10 组同源 SVG/PNG 机械夹具与 20 个动画输出已验证。
- Kiro/GPT 规则使用根 `AGENTS.md`；不创建 `GPT.md`，`CLAUDE.md` 只作兼容入口。
- Git 收口流程由 `.kiro/steering/git-sync.md` 管理，Agent 自动安全同步，不使用保存/停止盲推钩子。

## 参考索引

- 当前 12 步计划：`memory/topics/task-breakdown.md`
- 模型与 Key 边界：`memory/topics/model-selection.md`
- 技术架构：`docs/architecture.md`
- 历史源想法：`docs/sketch_diary_launch_plan.md`（非当前执行权威）
