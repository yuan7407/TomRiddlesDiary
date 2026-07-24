# 正式开发任务分解（12 步，逐步验证、每步可演示）

> **当前状态**：用户已选择 **B 并行路线**。Task 1A 与 Swift Tasks 2–4 已完成；Task 1B 真实模型预检继续保持待办，不因本地 Lab 跑通而视为最终源已选或魔法体验已通过。

## 当前证据边界

### Task 1A — 机械管道预检（已完成）

- 10 组 GPT-5.6 编写的确定性夹具，每组由同一批有序线条生成 SVG + PNG。
- 两条本地 Python 管道均可运行：SVG 解析路径；PNG 抽骨架/理笔顺。
- 20 个动画 SVG 均非空；输入 ID、尺寸、path 和输出数已验证。
- Python humanizer 只有重采样、固定种子抖动和按长度/扰动计算时长；输出固定线宽，**没有压感或收笔模拟**。
- 这些结果只证明机械 smoke test，不证明视觉手感、情绪理解或 Qwen 效果。

### Task 1B — 真实模型预检（待做，不阻塞本地 Route B）

- 输入：至少 10 张不同表达的真实用户涂鸦。
- 输出：真实视觉理解 + 图像生成回应，分别经过可比较的笔画源。
- 判断：由用户肉眼比较；至少 3–4 组产生明确“哦……”感才算初步 Go。
- 前置：用户创建 Qwen Key 并确定区域；永久 Key 仅限本地非分发 DEBUG，TestFlight 前必须切到安全后端。

### 第 8 步 — App 内完整 Go/Kill（与 1B 不同）

Task 1B 比较离线/脚本层的真实模型素材；第 8 步评审的是 App 内完整 Oracle + StrokeEngine + 节奏 + 降级体验。两者不能互相替代。

## 12 步计划

1. **项目骨架、护栏与笔画对比实验**：Task 1A 已完成；Task 1B 真实模型预检待做。
2. ✅ **Skeletonizer**：Swift Zhang–Suen 纯逻辑实现完成；验证尺寸、不新增前景与幂等性。
3. ✅ **StrokeTracer**：确定性 8 邻接无向图实现完成；端点/交叉/环/孤立点与每条边恰好一次均有测试。
4. ✅ **StrokeHumanizer + 逐笔重播**：固定 seed 重采样与抖动、端点不漂移、压感 taper、长度时序和严格串行 replay 完成；Magic Stroke Lab 可切换 raster/ordered 双源。
5. ⏭️ **PencilKit 画布**：抬笔静置成页、重新落笔取消、墨水淡入。
6. **OracleProvider + Mock**：离线打通首个 App 垂直切片，不依赖真实 Key。
7. **真实视觉理解**：接 Qwen provider；本地非分发 DEBUG 可受限实验，任何分发前改为安全后端/短期凭证。
8. **真实图像回应 + App 内 Go/Kill**：Qwen 线稿进入 StrokeEngine，评审完整魔法时刻。
9. **Persona 包 + IP 防火墙**：配置可替换、环境门控、公开品牌原创化。
10. **本地加密存档**：时间线、召回旧页、记忆开关、一键遗忘/删除。
11. **端点路由**：区域配置、provider 留桩与可观测性，不预设未经核实的网络/驻留结论。
12. **收口与发布门禁**：诚实降级、AI 披露、危机兜底、隐私/删除、分发安全与真实设备验证。

## 已选择的执行路线

### B. 并行路线（已选择）

先用确定性工程夹具完成 Tasks 2–4 Magic Stroke Lab，同时等待真实 Qwen 素材。实现保持 `StrokeSourcePayload.raster` / `.ordered` 可插拔；此选择可逆，不提前拍板最终笔画源。

### A. 严格路线（未选择，保留为历史备选）

原方案是先完成 Task 1B，再进入 Swift 开发。当前不回退已完成的本地引擎，但 Task 1B 的证据要求仍完整保留。

## Route B 当前验证证据

- 正式 `TomRiddlesDiaryTests` XCTest bundle 与共享 scheme 已建立。
- Skeletonizer 9 tests、Tracer 8 tests、Humanizer 9 tests、Replay 8 tests、Pipeline 3 tests、Lab ViewModel 4 tests；全量 41 tests、0 failures。
- generic iOS Simulator build 成功；App 已在 iPad Simulator 安装/启动并人工检查首屏。
- Lab 仅使用 app-native 离线夹具；未接入 Oracle provider、Qwen、API Key、网络或生产密钥处理。
- 以上只证明本地工程行为可演示；真实设备手感、真实模型情绪相关性、最终源与第 8 步 Go/Kill 均未验证。
