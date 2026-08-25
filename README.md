# Tom Riddle's Diary

成人向 iPad 情感反思日记 App：用户用 Apple Pencil 手绘涂鸦，一个「会回应的日记之魂」用文字与 AI 生成图像、以**逐笔生长的手绘笔触**回应。

> 私有项目。权威开发规则见 [`AGENTS.md`](./AGENTS.md)；[`CLAUDE.md`](./CLAUDE.md) 只是兼容入口。项目名与占位 bundle ID 是内部代号，分发前必须换成原创品牌。

## 核心分工

- **Oracle（AI 层）决定「画什么」**：读涂鸦与受控上下文，返回文字与生成图像。
- **StrokeEngine（本地）决定「像不像手画的」**：手绘化、压感、收笔、速度、节奏、逐笔重播。
- 铁律：不指望模型直接输出稳定自然的最终笔画。

## 当前状态（2026-08-25）

| 项 | 状态 |
|---|---|
| Xcode / Simulator | ✅ iPadOS 17+、仅 iPad、无签名 Simulator build 通过 |
| 笔画引擎 | ✅ 有序向量单源：手绘化 + 压感 + 严格串行逐笔重播，23 个 XCTest 全通过 |
| Magic Stroke Lab | ✅ 可演示，但属开发者诊断界面，不是产品界面 |
| Task 1B 真实素材验证 | ⏳ 待用户提供手绘 PNG / 真实模型输出样本 |
| PencilKit / Oracle / Qwen / 网络 / 存储 / 后端 | ❌ 尚未接入 |

位图抽骨架路线（Skeletonizer + StrokeTracer）曾实现并通过测试，因实机线条质量差已整体删除，可在 Git `e08f4c3` 回溯。

## 结构

```text
AGENTS.md                 权威项目规则（含强制注释与修改原因）
CLAUDE.md                 兼容入口
.kiro/steering/           Kiro 专项规则（Git 同步）
memory/                   跨会话状态 + 3 个专题
Config/                   Secrets / Persona 模板（真实值被 gitignore）
scripts/ip_firewall_check.sh   IP 与密钥提交门禁
TomRiddlesDiary/          Xcode 工程（SwiftUI / iPadOS 17+）
```

App 目标模块：`App / Features(Canvas·Response·Diary) / Oracle(Provider·Router·Persona) / StrokeEngine / Data / DesignSystem`。

## 运行与验证

打开 `TomRiddlesDiary/TomRiddlesDiary.xcodeproj`，scheme 选 `TomRiddlesDiary`，选一个 iPad Simulator 后 Run。

```bash
# 测试（必须关闭并行：Xcode 26.6 并行 clone 会触发工具自身崩溃）
xcodebuild -project TomRiddlesDiary/TomRiddlesDiary.xcodeproj -scheme TomRiddlesDiary \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<iPad Simulator UUID>' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test

# 构建
xcodebuild -project TomRiddlesDiary/TomRiddlesDiary.xcodeproj -scheme TomRiddlesDiary \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# 提交门禁
bash scripts/ip_firewall_check.sh
```

预期：`23 tests, 0 failures` 与 `** BUILD SUCCEEDED **`。构建有一条非阻塞提示（未依赖 AppIntents，跳过其 metadata），属预期。

## 安全底线

- 永久模型 API Key 绝不进入 Git、可分发客户端二进制或客户端可提取流量；TestFlight 前必须走安全后端或最小权限短期凭证。
- 不读取或提交 `Config/Secrets.xcconfig`、`Config/Persona.local.json`、`.env*`、签名资产、`xcuserdata`。
- 公开/分发面不得出现未经授权的第三方 IP 名称、图标、截图或关键词；内部占位不等于商业授权。
- 「数据不出境」「读完即删」等结论必须由最终区域、供应商合同与实现证据支持。
- 现在不需要购买 Apple Developer Program；Simulator 与免费 Personal Team 足够当前阶段。

## 更多

- 12 步计划与素材规格：[`memory/topics/task-breakdown.md`](./memory/topics/task-breakdown.md)
- 引擎实现与验证边界：[`memory/topics/stroke-engine.md`](./memory/topics/stroke-engine.md)
- 决策、风险、合规与未决项：[`memory/topics/decisions.md`](./memory/topics/decisions.md)
