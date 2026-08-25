<!-- 动态状态与决策。会话开始或用户说“继续”时先读本文件。规则见 AGENTS.md，项目说明与计划见 README.md。保持 ≤120 行。 -->
# 项目记忆

## 当前状态

- **阶段**：Tasks 2–4 完成并单源化（只保留有序向量）。分支 `feature/magic-stroke-lab`，不直接推 main。
- **App**：`ContentView` 承载 Magic Stroke Lab，3 个离线夹具可逐笔重播（压感线宽、严格串行）。这是开发者诊断界面，接 PencilKit 后须降级为 DEBUG-only。
- **引擎**：`StrokePipeline → StrokeHumanizer → StrokeReplayTimeline`。位图路线（Skeletonizer/Tracer）2026-08-25 整体删除，原因是实机线条质量差；历史实现在 `e08f4c3`。
- **验证**：23 个 XCTest 全通过；Simulator build 成功；iPad (A16) 首屏人工确认。测试必须加 `-parallel-testing-enabled NO`。
- **未接入**：PencilKit 绘画、Oracle/Qwen、任何网络或密钥、加密存储、后端、TestFlight。
- **目录**：2026-08-25 拉平为单层 `TomRiddlesDiary.xcodeproj` + `Sources/` + `Tests/`，消除原来三层同名嵌套。

## 决策表

| # | 决策 | 结论 | 为什么 |
|---|---|---|---|
| 1 | 核心交互 | 纯涂鸦，不做文字聊天复制品 | 笔画与逐笔节奏是差异化内核 |
| 2 | 手感来源 | 本地引擎负责，不靠模型输出最终笔画 | 模型笔画不稳定，节奏与压感必须可控 |
| 3 | 笔画源 | 仅有序向量 | 位图抽骨架实机效果差；双源只留无人用的分支 |
| 4 | 模型通道 | Qwen 视觉 + 图像，藏在 `OracleProvider`/`OracleRouter` 后 | 避免供应商锁定 |
| 5 | 模型鉴权 | 本地非分发 DEBUG 可受限实验；分发前必须安全后端 | `.gitignore` 挡不住客户端逆向 |
| 6 | Persona | 内部占位可替换、环境门控；公开版原创 | 体验探索与 IP 风险隔离 |
| 7 | Apple 账号 | 现在用 Simulator/免费账号 | 当前不需要 TestFlight |
| 8 | bundle ID | Xcode 占位值，非正式决定 | 主体、域名与品牌未定，须用户拍板 |
| 9 | 规则源 | 根 `AGENTS.md` 唯一 | 避免多份规则漂移；已删除 `CLAUDE.md` 指针文件 |
| 10 | 文档层级 | `AGENTS.md`(规则) + `README.md`(说明/计划) + `MEMORY.md`(状态) | 三份各有唯一职责，不再有 topics 分散 |

已排除：位图路线（实现过、测试过、效果差，已删且不留死代码）；Python 位图/向量对比 spike（源单一化后失去意义）。

## 风险

| 风险 | 处置 / 状态 |
|---|---|
| 魔法体验不动人（生死项） | Task 1B 真实素材验证 + 第 8 步 App 内评审仍待做 |
| 把离线夹具误称为模型/情绪证据 | 报告只称机械验证，夹具与真实模型输出严格区分 |
| 图像生成延迟/成本 | 文字先反馈、图像并行；价格与延迟选区后实测 |
| 永久 Key 泄露 | 见 `AGENTS.md` 红线；本地 DEBUG 例外须最小权限+额度+监控 |
| 无证据承诺“不出境/读完即删” | 设计目标与供应商事实分开，逐项验证 |
| 内部 IP 占位进入公开面 | 门禁 + staged diff 人工审查；分发前原创化 |
| 真机手感未验证 | Simulator 只证明可运行；Apple Pencil 观感需真机评审 |

已接受但受限：项目名、仓库名、占位 bundle ID、本地 persona 只限私有非分发面，不代表商业授权。

## 模型与 Key 边界（2026-07-23 核对官方说明）

- Key 按区域区分；部分区域（北京、新加坡、东京、法兰克福等）调用需把 Workspace ID 放进 Base URL，接入时以实际账号页面为准。
- 移动端正式调用经安全后端；官方建议由后端为不可信环境签发临时 Key（默认 60 秒，可配 1–1800 秒，继承签发 Key 权限）。
- 参考：[Qwen 首次 API 调用](https://help.aliyun.com/en/model-studio/first-api-call-to-qwen)、[临时 API Key](https://help.aliyun.com/en/model-studio/application-obtain-temporary-authentication-token)。
- 未核实：模型实时可用性/配额/价格、大陆到端点的可达性与延迟、供应商对请求/日志/备份/训练/删除的条款、"数据不出境"的合同与全链路证据、自部署版本许可证与运维责任。

## 待用户决定

1. 下一步：Task 5 PencilKit 真实画布（并把 Lab 降为 DEBUG-only），还是 Task 1B 真实素材验证。
2. 是否提供第一批手绘 PNG（规格见 `README.md`）。
3. 正式 bundle ID、签名主体、原创公开品牌与 Persona 方向。
4. Qwen 区域/Workspace 及条款复核；何时购买 Apple Developer Program。

## 用户偏好

- 中文交流，大白话解释术语，需要类比与详细但易懂的说明。
- 区分「已验证事实 / 合理假设 / 待用户决定」，不混写。
- 不替用户拍板命名、bundle ID、品牌、付费与架构方向。
- 不静默兜底：阻塞、测试失败、远端分叉必须暴露。
- 用户会明确要求「先不要进行下一步」，必须停住等确认。
- 重视真实可演示，不接受把命令 exit 0 当成体验通过。
- 每次实质任务收口自动执行安全 Git 同步。

## 已知陷阱

- Xcode 26.6 并行 test clone 触发 `DVTiPhoneSimulator` assertion → 测试关闭并行。
- Xcode 曾自动建嵌套 Git，已可恢复地移到 `.git/xcode-nested-repo-backup-8d5eca1`。
- 工程用 objectVersion 77 同步文件组：`Sources/`、`Tests/` 下新增文件自动入 target，不需手改 pbxproj。
- kiro-pet 已迁至 `110_KiroPet`，不得放回本仓库。

## 历史（精简）

- **2026-07-15**：仓库骨架、规则/记忆/脚本/Config 与首个本地 commit。
- **2026-07-23**：GitHub 私有远端同步；Xcode 工程纳入根仓库（解除嵌套 Git）；修正为 iPadOS 17+ / 仅 iPad；无签名 Simulator build 通过；建立 `AGENTS.md`；完成后来被删除的 Python 对比 spike。
- **2026-07-24**：完成 Tasks 2–4 与 Magic Stroke Lab，41 测试通过（`e08f4c3`）；语义审阅修复边界细化与 60 Hz 空转。
- **2026-08-25**：写入强制注释规则（`d05d613`）；删除位图路线，补齐全部 Swift 中文文件头与「为什么」注释，测试收敛为 23（`66eb88b`）；文档从 20 个 md 精简到 3 个，目录拉平为单层。
