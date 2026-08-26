# Tom Riddle's Diary

iPad端手写式AI对话日记本（汤姆里德尔日记本）。用户用 Apple Pencil 手绘涂鸦或写字，一个「会回应的日记之魂」用**文字 + AI 生成文字**回应，且图像必须以**逐笔生长的手绘笔触**写出来，像有人正在纸上写字。

> 私有项目。开发规则见 [`AGENTS.md`](./AGENTS.md)，当前状态与决策见 [`MEMORY.md`](./MEMORY.md)。项目名与占位 bundle ID 是内部代号，分发前必须换成原创品牌。

## 核心分工

- **Oracle（AI 层）决定「画什么」**：读涂鸦与受控上下文，返回文字。
- **StrokeEngine（本地）决定「像不像手画的」**：手绘化、压感、收笔、速度、节奏、逐笔重播。
- 铁律：不指望模型直接输出稳定自然的最终笔画。

最终体验是「打开 → 引导 → 画 → 回应」。用户只应看到逐笔重播的结果，不应看到任何实验室控件。

## 目录结构

```text
AGENTS.md                 开发规则（唯一权威）
README.md                 本文件：项目说明、结构、验证、计划
MEMORY.md                 当前状态、决策、风险、未决项
.kiro/steering/           Kiro 专项规则（Git 同步流程）
TomRiddlesDiary.xcodeproj Xcode 工程
Sources/                  App 源码
  App 入口 / Features/StrokeLab / StrokeEngine
Tests/                    XCTest（与 Sources 同级，不打进 App）
Config/                   Secrets / Persona 模板，真实值被 gitignore
scripts/                  仓库工具：提交门禁（不属于 App，不会被打包）
```

`Sources/` 目标模块划分：`App / Features(Canvas·Response·Diary) / Oracle(Provider·Router·Persona) / StrokeEngine / Data / DesignSystem`。工程使用 Xcode 同步文件组，新增文件自动加入对应 target。

## 当前状态

| 项 | 状态 |
|---|---|
| Xcode / Simulator | ✅ iPadOS 17+、仅 iPad、无签名 Simulator build 通过 |
| 笔画引擎 | ✅ 有序向量单源：手绘化 + 压感 + 严格串行逐笔重播，23 个 XCTest 全通过 |
| Magic Stroke Lab | ✅ 可演示，但属开发者诊断界面，不是产品界面 |
| Task 1B 真实素材验证 | ⏳ 待手绘 PNG / 真实模型输出样本 |
| PencilKit / Oracle / Qwen / 网络 / 存储 / 后端 | ❌ 尚未接入 |

位图抽骨架路线（Skeletonizer + StrokeTracer）曾实现并通过测试，因实机线条质量差已整体删除，可在 Git `e08f4c3` 回溯。

## 运行与验证

打开 `TomRiddlesDiary.xcodeproj`，scheme 选 `TomRiddlesDiary`，选一个 iPad Simulator 后 Run。

```bash
# 测试（必须关闭并行：Xcode 26.6 并行 clone 会触发工具自身崩溃）
xcodebuild -project TomRiddlesDiary.xcodeproj -scheme TomRiddlesDiary \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<iPad Simulator UUID>' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test

# 构建
xcodebuild -project TomRiddlesDiary.xcodeproj -scheme TomRiddlesDiary \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# 提交门禁
bash scripts/ip_firewall_check.sh
```

预期 `23 tests, 0 failures` 与 `** BUILD SUCCEEDED **`。构建有一条非阻塞提示（未依赖 AppIntents，跳过其 metadata），属预期。

Simulator 能跑不等于体验通过：Apple Pencil 压感观感与节奏仍需 iPad 真机主观评审。

## 12 步开发计划

| 步骤 | 状态 | 内容 |
|---|---|---|
| 1A | ✅ | 项目骨架、护栏、离线确定性夹具 |
| 1B | ⏳ | 真实模型输出样本验证 + 最终素材路线确认 |
| 2–4 | ✅ | 笔画引擎：手绘化、压感、时序、严格串行逐笔重播 |
| 5 | ⏭️ | PencilKit 画布：抬笔约 2.8 秒成页、重新落笔取消、墨水淡入；同时把 Lab 降为 DEBUG-only |
| 6 | ⏭️ | `OracleProvider` 协议 + Mock，离线打通垂直切片 |
| 7 | ⏭️ | 真实 Qwen 视觉理解 |
| 8 | ⏭️ | 图像回应 + App 内完整 Go/Kill 魔法评审 |
| 9 | ⏭️ | 9A 原创 Persona/品牌；9B 分发前 IP/安全/合规检查 |
| 10 | ⏭️ | 端侧加密存档、时间线、召回、记忆开关、一键遗忘 |
| 11 | ⏭️ | 区域/端点/provider 路由与安全代理 |
| 12 | ⏭️ | 诚实降级、AI 披露、危机兜底、隐私删除、发布门禁 |

**Task 1B ≠ 第 8 步**：1B 在离线层判断素材能否进引擎并决定素材路线；第 8 步评审 App 内完整 Oracle + 引擎 + 节奏 + 降级体验。两者不能互相替代。

## Task 1B 素材规格

第一批手绘参考图：**PNG、2048×2048、sRGB 8-bit、白底黑线、线宽约 8–24 px、四周留 5–10% 空白、无阴影/填色/水印**。竖版可用 1536×2048 或 2048×2732。纸上手绘建议 300 DPI 扫描后裁成干净白底。不建议首批用 JPEG（压缩噪点干扰后续处理）。

建议 6–10 张，覆盖：简单单线、闭环、分叉、交叉、小点/短笔画、较复杂插图、最理想风格、故意潦草。

用户涂鸦（测试 AI 是否读懂情绪）与回应线稿（测试逐笔重播）是两组不同素材，需分开准备。
