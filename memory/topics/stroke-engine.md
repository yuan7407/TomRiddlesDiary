# 笔画引擎（StrokeEngine）

## 核心分工

- Oracle 决定“画什么”；StrokeEngine 决定“像不像手画的”。
- 铁律：不依赖模型直接输出稳定自然的最终笔画。

## 当前管道（单源）

```text
有序笔画 [Polyline]
  → StrokePipeline（唯一入口）
  → StrokeHumanizer（重采样 / 抖动 / 压感 / 收笔 / 时长）
  → StrokeReplayTimeline（严格串行进度）
  → Canvas 逐笔渲染
```

2026-08-25 起**只保留有序向量源**。原位图路线（Zhang–Suen Skeletonizer + 8 邻接 StrokeTracer）已整体删除，原因是实机线条质量明显差于有序向量；历史实现可在 Git `e08f4c3` 回溯。

## 关键实现约束

- `Point2D` / `Polyline` / `StrokeSample` / `TimedStroke` / `StrokeSequence` / `ReplayFrame` 全为 `nonisolated` 值类型，纯算法可脱离 MainActor 测试。
- Humanizer 用固定 seed 的 SplitMix64 + Box–Muller：同输入必同输出，否则手感回归无法断言。
- 抖动跳过首尾点：端点漂移会让笔画接头错位、闭合图形裂口。
- 压感 = 受限主体压力 × 起收笔线性包络；先夹紧再乘包络，避免越界。
- 时长按实际长度计算并加轻微扰动，另设最小时长，避免短笔“闪现”。
- 重播严格串行：前一笔未完成时后一笔进度恒为 0。
- 重播完成/切夹具/连点重播使用可取消 MainActor 任务 + 时间戳过期判定，播完即停止 60 Hz 刷新。

## 验证边界

当前证据：23 个 XCTest 全通过（Humanizer 9、Replay 8、Pipeline 3、LabViewModel 3）、Simulator build 成功、iPad Simulator 首屏人工确认。

这些**只证明**本地行为可运行可演示；**不证明**真机 Apple Pencil 手感、模型情绪理解、最终素材路线或产品级 Go/Kill。

## Magic Stroke Lab 定位

`Features/StrokeLab` 是开发者诊断界面，含 3 个离线夹具、统计和重播按钮，不接模型/网络/密钥。它**不是产品界面**：接入 PencilKit 后必须降级为 DEBUG-only 工具，最终用户只应看到逐笔重播的结果。
