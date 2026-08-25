<!-- L1 动态记忆；会话开始或“继续”时先读本文件；保持 ≤120 行，细节进 topics/ -->
# Tom Riddle's Diary — 项目记忆

## 当前状态

- **阶段**：B 并行路线。Tasks 2–4 已完成并**单源化**（只保留有序向量），离线 Magic Stroke Lab 可演示。分支 `feature/magic-stroke-lab`，不直接推 main。
- **App 现状**：`ContentView` 承载 Magic Stroke Lab，可切换 3 个离线夹具并逐笔重播（压感线宽、严格串行）。这是开发者诊断界面，不是产品界面。
- **StrokeEngine**：`StrokePipeline → StrokeHumanizer → StrokeReplayTimeline`。位图路线（Skeletonizer/Tracer）已于 2026-08-25 整体删除，原因是实机效果差。
- **验证**：23 个 XCTest 全通过；generic Simulator build 成功；iPad (A16) Simulator 首屏人工确认。测试必须加 `-parallel-testing-enabled NO`（Xcode 26.6 并行 clone 工具崩溃）。
- **未接入**：PencilKit 用户绘画、Oracle/Qwen、任何网络或密钥、加密存储、后端、TestFlight。
- **规则**：根 `AGENTS.md` 唯一权威（含强制注释与修改原因规则）；`CLAUDE.md` 只作入口；`.kiro/steering/git-sync.md` 管 Git。

## 产品北极星

成人向 iPad 情感反思日记：用户用 Apple Pencil 涂鸦，日记之魂用文字与 AI 图像、以逐笔生长的手绘笔触回应。最终体验是「打开→引导→画→回应」，用户不应看到任何实验室控件。换一张涂鸦，回应必须明显不同；技术跑通不等于魔法通过。

## 下一步（等用户决定）

1. Task 5 PencilKit 真实画布（并把 Lab 降为 DEBUG-only），还是 Task 1B 真实模型输出样本验证。
2. 是否提供第一批手绘 PNG 素材（2048×2048、白底黑线、无阴影）。
3. 正式 bundle ID、签名主体、原创公开品牌与 Persona。
4. Qwen 区域/Workspace 及相关条款复核。

## 用户偏好

- 中文交流，大白话解释术语，需要类比和详细但易懂的说明。
- 区分「已验证事实 / 合理假设 / 待用户决定」，不混写。
- 不替用户拍板命名、bundle ID、品牌、付费与架构方向。
- 不静默兜底：阻塞、测试失败、远端分叉必须暴露。
- 用户会明确要求「先不要进行下一步」，必须停住等确认。
- 重视真实可演示，不接受把命令 exit 0 当成体验通过。
- 每次实质任务收口自动执行安全 Git 同步（fetch/验证/commit/push/hash 核对）。

## 已知陷阱

- Xcode 26.6 并行 test clone 触发 `DVTiPhoneSimulator` assertion → 测试关闭并行。
- Xcode 曾自动建嵌套 Git，已可恢复地移到根 `.git/xcode-nested-repo-backup-8d5eca1`。
- 工程用 objectVersion 77 + 同步文件组，新增 Swift 文件不需手改 pbxproj。
- kiro-pet 已迁至 `110_KiroPet`，不得放回本仓库。
- 密钥口径：禁止永久 Key 进入可分发客户端/Git；本地非分发 DEBUG 例外须 gitignored + 最小权限 + 监控。
- 隐私承诺（读完即删/不出境）必须有区域、合同与实现证据。

## 索引

- `topics/task-breakdown.md` — 12 步计划、当前状态、素材规格
- `topics/stroke-engine.md` — 引擎实现约束与验证边界
- `topics/decisions.md` — 决策表、模型/Key 边界、风险、合规、未决项

## 历史（精简）

- **2026-07-15**：仓库骨架、memory/scripts/Config/README 与首个本地 commit。
- **2026-07-23**：GitHub 私有远端建立并同步；Xcode 工程纳入根仓库（解除嵌套 Git）；工程修正为 iPadOS 17+ / 仅 iPad；无签名 Simulator build 通过；建立 `AGENTS.md` 统一规则；修复 IP 门禁扫描范围；完成 Python 位图/向量对比 spike（后已删除）。
- **2026-07-24**：用户选定 B 路线；完成 Tasks 2–4 与 iPad Magic Stroke Lab，41 个测试通过并推送 `e08f4c3`；语义审阅修复边界细化与 60 Hz 空转问题。
- **2026-08-25**：写入强制注释与修改原因规则（`d05d613`）；按用户判断整体删除位图路线；补齐全部 Swift 文件中文文件头与关键“为什么”注释；合并/删除 11 个冗余文档（4 个角色文件、3 个 docs、2 个 daily、2 个空 topic）与已废弃 Python spike；测试收敛为 23 个并全部通过。
