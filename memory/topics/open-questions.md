# 尚未解决 / 需要问用户的问题

## 当前未决事项

1. **真实测试涂鸦 / Task 1B**：10 组确定性工程夹具与 Route B Lab 已完成，但真实用户涂鸦尚未准备；两者不能互相冒充。
2. **Qwen 区域/Workspace**：到真实模型测试前决定，并重新核对模型可用性、价格、网络和数据条款。Key 当前不阻塞本地笔画开发。
3. **正式 bundle ID / 主体 / 公开品牌**：当前为 Xcode 占位 `TomRiddlesDiary.TomRiddlesDiary`。在注册 App ID/App Store 记录前，由用户决定个人或组织主体、长期可控反向域名与原创品牌。
4. **笔画源最终选择**：ordered vector 与 raster 抽骨架已通过同一 Swift Pipeline 可比较，但最终选择仍须等真实模型素材和主观评审；机械跑通不等于选型完成。
5. **真实设备手感**：Simulator 已验证构建、启动与首屏显示；Apple Pencil 压感观感、节奏和“魔法感”仍需 iPad 真机主观评审。

## 后续但现在不阻塞

- 何时购买 Apple Developer Program：需要 TestFlight/远程 beta/分发时再决定。
- Qwen 当前价格、国际覆盖、大陆网络可达性与数据处理条款：签约/接入前复核。
- `.claude/agents/*` 已按 `AGENTS.md` 统一安全口径；实际启用角色协作时再按任务细化。

## 已解决

- 用户已选择 **B 并行路线**；无需再次询问是否可以开始 Tasks 2–4。
- Swift Tasks 2–4 与可演示 Magic Stroke Lab 已完成，且保持 raster/ordered 源可插拔。
- GitHub private remote、根仓库与 Xcode 工程已统一管理并同步。
- iOS platform/runtime 安装完成；iPadOS 17+ 无签名 Simulator Debug build 成功。
- 10 组同源 SVG/PNG 机械夹具与 20 个 Python 动画输出已验证。
- Kiro/GPT 规则使用根 `AGENTS.md`；不创建 `GPT.md`，`CLAUDE.md` 只作兼容入口。
- Git 收口流程由 `.kiro/steering/git-sync.md` 管理，Agent 自动安全同步，不使用保存/停止盲推钩子。

## 参考索引

- 当前 12 步计划：`memory/topics/task-breakdown.md`
- 模型与 Key 边界：`memory/topics/model-selection.md`
- 技术架构：`docs/architecture.md`
- 历史源想法：`docs/sketch_diary_launch_plan.md`（非当前执行权威）
