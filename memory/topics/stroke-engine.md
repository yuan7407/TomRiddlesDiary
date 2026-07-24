# 笔画引擎与 Task 1 证据边界

## 核心分工

- Oracle 决定“画什么”：理解涂鸦并生成文字/图像内容。
- StrokeEngine 决定“像不像手画的”：骨架、笔顺、压感、收笔、速度、抖动和重播。
- 不依赖模型直接吐出稳定、自然的最终笔画。

## 可复用的交互机制

1. AI 返回内容，本地确定性算法负责逐笔呈现。
2. 文字/离线反馈先出现，图像并行生成，盖住延迟。
3. 抬笔静置约 2.8 秒自动成页，重新落笔取消，无“发送”键。
4. 错误以清楚、符合世界观但不掩盖事实的方式呈现。
5. 本地优先的有限上下文、召回、记忆开关与一键遗忘。
6. 笔是主要界面，按钮从简。

## 目标 StrokeEngine 管道（最终 Swift 实现）

```text
线稿 / 路径
  → Skeletonizer（需要时，Zhang-Suen）
  → StrokeTracer（中心线 → 有序笔画）
  → StrokeHumanizer（压感 / 收笔 / 速度 / 抖动）
  → 逐笔重播
```

## Task 1A 机械预检（已完成）

- 10 组确定性工程夹具，每组由同一批有序线条同时生成 SVG 与 640×640 PNG。
- SVG 路径直接解析；PNG 经 skeletonize + 简化 tracer。
- Python `humanize()` 目前只做约 2 px 重采样、固定种子高斯抖动、按长度和速度扰动计算每笔时长。
- 输出 `stroke-width="2.2"` 固定，**没有压感或收笔模拟**。
- 20 个动画均非空，只证明两条机械管道可运行以及 PNG 抽骨架会如何改变结构。

## Task 1B 真实模型预检（待做）

- **SVG 源**：真实模型/方案输出有序路径。
- **图像源**：真实图像模型生成干净线稿，再抽骨架和理笔顺。
- 使用至少 10 张不同表达的真实用户涂鸦；由用户肉眼比较结构、节奏和情感相关性。
- 不能用同源确定性夹具提前拍板最终源，也不能把第 8 步 App 内完整体验评审省略。

## 关键设计原则

源可插拔；算法可单测；手感必须在真实设备上主观评审；固定夹具用于回归，不用于证明情感质量；隐私和供应商处理结论由 `AGENTS.md` 的证据规则约束。
## Swift Route B 实现（Tasks 2–4 已完成）

- `StrokeModels`：`BinaryMask`、`GridPoint`、`Point2D`、`Polyline` 等纯值类型。
- `Skeletonizer`：标准 Zhang–Suen 两阶段细化；不改变尺寸、不新增前景、结果幂等。
- `StrokeTracer`：确定性 8 邻接无向图；端点优先、junction 分段、degree-two cycle fallback，每条边恰好访问一次，孤立像素保留为 dot stroke。
- `StrokeHumanizer`：固定 seed 可复现；等距重采样、端点不漂移、高斯抖动、压感范围与起落笔 taper、按长度计算时长。
- `StrokeReplayTimeline`：每笔严格串行，前一笔完成前后一笔进度保持 0。
- `StrokePipeline`：`.raster(BinaryMask)` 走 Skeletonizer + Tracer，`.ordered([Polyline])` 直接进入共享 Humanizer；最终真实源仍可替换。
- XCTest 共 41 个：Skeletonizer 9、Tracer 8、Humanizer 9、Replay 8、Pipeline 3、Lab ViewModel 4；当前全量通过。
- `Features/StrokeLab` 使用 3 个代表性离线夹具演示双源、压力线宽与逐笔重播；不包含模型、网络或密钥。

这些证据证明 Swift 本地管道行为与演示可运行，不证明真实设备手感、模型情绪理解、最终源选择或完整产品 Go/Kill。
