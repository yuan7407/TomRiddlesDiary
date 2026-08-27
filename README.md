# Tom Riddle's Diary

iPad 端手写式 AI 对话日记本（汤姆里德尔日记本）。用户用 Apple Pencil 手写文字，一个「会回应的日记之魂」用**文字**回应，且这些文字必须以**逐笔生长的手绘笔触**写出来，像有人正在纸上写字。

> 私有项目。开发规则见 [`AGENTS.md`](./AGENTS.md)，当前状态与决策见 [`MEMORY.md`](./MEMORY.md)。项目名与占位 bundle ID 是内部代号，分发前必须换成原创品牌。

## 核心分工

- **Oracle（AI 层）决定「说什么」**：读识别出的文字与字迹指标，返回文字回应。
- **Handwriting 层决定「写哪些笔画」**：把文字查成字形笔画中线，排版到页面坐标。
- **StrokeEngine（本地）决定「像不像手写的」**：压感、收笔、加减速、笔间停顿、抖动、逐笔重播。

铁律：不指望模型直接输出稳定自然的最终笔画。模型只给字符；字符变笔画是本地查表与排版的结果。

最终体验是「翻开 → 手写 → 放下笔 → 收到逐笔写出的回应」。用户只应看到回应本身，看不到任何实验室控件。

## 目录结构

```text
AGENTS.md                 开发规则（唯一权威）
README.md                 本文件：项目说明、结构、验证、计划
MEMORY.md                 当前状态、决策、风险、未决项
.kiro/steering/           Kiro 专项规则（Git 同步流程）
TomRiddlesDiary.xcodeproj Xcode 工程
Sources/                  App 源码
  TomRiddlesDiaryApp      入口
  Configuration/          集中配置（经验性常量的唯一定义处）
  Features/Canvas/        写字的那张纸
  Features/Response/      魂的回应渲染（逐笔重播）
  StrokeEngine/           手绘化与重播时序（纯逻辑，不依赖 UI）
Tests/                    XCTest（与 Sources 同级，不打进 App）
Config/                   Secrets / Persona 模板，真实值被 gitignore
scripts/                  仓库工具：提交门禁（不属于 App，不会被打包）
```

目标模块划分见 `AGENTS.md` 的「模块边界」。工程使用 Xcode 同步文件组，`Sources/` 与 `Tests/` 下新增文件自动加入对应 target，不需手改 pbxproj。

## 当前状态

| 项 | 状态 |
|---|---|
| Xcode / Simulator | ✅ iPadOS 17+、仅 iPad、无签名 Simulator build 通过 |
| 笔画引擎 | ✅ 手绘化 + 压感 + 严格串行逐笔重播，20 个 XCTest 全通过 |
| 回应渲染层 | ✅ 可用（`HandwritingReplayView`），但目前没有调用方 |
| 首屏 | ⬜ 刻意的空白日记页。手写输入未接入，纸上不会有任何反应 |
| 笔画输入源 | ❌ 无。引擎只吃 `[Polyline]`，而 PencilKit 与字形笔画都还没接 |
| 手写识别 / 字形笔画 / 排版 / Oracle / 后端 / 存储 | ❌ 尚未接入 |

已删除且不再回溯的路线：位图抽骨架（Skeletonizer + StrokeTracer，实机线条质量差，见 Git `e08f4c3`）、Magic Stroke Lab 诊断界面与离线夹具、图像生成与图像回应。

## 运行与验证

打开 `TomRiddlesDiary.xcodeproj`，scheme 选 `TomRiddlesDiary`，选一个 iPad Simulator 后 Run。当前会看到一张空白的暖米白纸，这是预期结果。

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

预期 `20 tests, 0 failures` 与 `** BUILD SUCCEEDED **`。构建有一条非阻塞提示（未依赖 AppIntents，跳过其 metadata），属预期。门禁会报若干占位品牌名的 ⚠，在白名单内，属预期。

Simulator 能跑不等于体验通过：压感、书写节奏与手写识别准确率都必须 iPad 真机 + Apple Pencil 主观评审。

## 计划

计划字母是**名字，不是顺序**。执行顺序见下方单独一节。

### A 笔触修复计划

| 编号 | 内容 |
|---|---|
| A1 | 抖动改成沿笔画的相关噪声，位移打在笔画法线方向（现为每点独立白噪声，出来是绒毛线） |
| A2 | 压感改成平滑变化并与曲率挂钩（现为白噪声，线看起来串珠） |
| A3 | 加入起收笔的加减速（现在一笔之内严格匀速） |
| A4 | 给 `TimedStroke` 加笔间停顿（现在笔尖「传送」到下一笔立刻开画） |
| A5 | 收笔真的收到零宽（现在两端各留一个圆钝头） |
| A6 | 修抖动在端点的统计突变（端点不动、相邻点满额噪声，形成小折角） |
| A7 | 单点墨点改成生长（现在瞬间全尺寸出现） |
| A8 | 修 `resample` 末尾的近零长度尾段 |
| A9 | ✅ 刷新率跟随屏幕，不锁死 60（2026-08-26 完成） |
| A10 | 用真人笔迹校准全部数值（依赖 E3）。A1–A8 是改对结构，A10 是调对数值，顺序不能反 |

### B 性能优化计划

| 编号 | 内容 |
|---|---|
| B1 | 渲染分层：画完的笔烧进静态层，每帧只重画正在生长的那一笔 |
| B2 | 别每帧重建时间轴（现在每帧 new 一个 `StrokeReplayTimeline` 并线性扫全部笔画） |
| B3 | 半透明墨水在分段接头处叠加变深的问题 |
| B4 | 手绘化搬到后台线程（一页 200 字约 1600 笔，主线程会卡；依赖 F4） |

### C 情绪识别计划

| 编号 | 内容 |
|---|---|
| C1 | 先定评测集再调 prompt：8–10 张手写样张，每张先写下期望读出什么、绝对不该说什么 |
| C2 | 把字迹指标（力度、速度、停顿、涂改、字大小、占页比例）作为情绪输入 |
| C3 | 用评测集验收：回应是否因样张而明显不同、是否只在复述、是否越界给医疗或心理建议 |

### D 地基计划

| 编号 | 内容 |
|---|---|
| D1 | 定坐标与单位契约：坐标统一用页面点，参数按物理含义声明（线宽用毫米、间距与抖动用相对比例、速度用每秒字数） |
| D2 | 把全部经验性常量收进 `Configuration`，删掉从未验证过的引擎默认参数 |
| D3 | 不变量落进类型：`TimedStroke.duration` 允许负数导致三处重复夹取 |
| D4 | 时钟统一：`Date`（会跳）与 `Task.sleep`（非墙上时钟）混用，改单调时钟，并定清后台返回行为 |
| D5 | ✅ 纸色与墨色收敛到唯一一处（2026-08-26 完成） |
| D6 | 补渲染层测试：半段插值、单点墨点目前零测试；去掉纯算法测试上多余的 `@MainActor` |

### E 手写文字通道

| 编号 | 内容 |
|---|---|
| E1 | 字形笔顺资产：文字 → 笔画中线。含数据集覆盖不到的标点、数字、拉丁字母 |
| E2 | 排版层：一串字形 → 页面坐标（字号、行宽、行距、换行、边距、字与字的自然不齐） |
| E3 | PencilKit 画布：手写捕获、成页触发、落笔中断接管、魂的笔画落定进 `PKDrawing`（用户可擦） |
| E4 | 真机验证手写识别准确率（Apple Pencil，中英混写） |
| E5 | 端侧提取字迹指标 |
| E6 | `OracleProvider` 协议 + Mock，离线打通完整闭环；失败只做诚实硬提示，绝不返回 Mock 冒充成功 |
| E7 | 魔法生死评审：手写文字回应的 Go/Kill 判断（原 12 步计划第 8 步，对象由图像换成文字，评审本身保留） |

### F 工程与工具链

| 编号 | 内容 |
|---|---|
| F1 | 装 Xcode 27 beta（与现有 26.6 并存，不覆盖） |
| F2 | 工程改 iOS 27 SDK 与最低系统 |
| F3 | **验证 PencilKit 手写识别是否支持中文** — 硬门禁，不通过则输入端整体换路 |
| F4 | 升 Swift 6 语言模式 |
| F5 | 门禁加 import 白名单，保护 `StrokeEngine` 只依赖 Foundation |
| F6 | ✅ AGENTS.md 补硬编码规则与 `Handwriting` 模块（2026-08-26 完成） |
| F7 | `main` 落后 8 个提交且从未合过 PR，决定是否合一次 |
| F8 | `Package.resolved` 被 gitignore 与「依赖必须锁定版本」规则冲突 |

### G 后端与密钥安全

| 编号 | 内容 |
|---|---|
| G1 | 腾讯云转发服务：持永久 Key、鉴权、限速、防重放、日志不记日记内容 |
| G2 | 客户端只调自建后端，永不接触模型 Key |
| G3 | xcconfig 接线（放后端地址，不放模型 Key） |
| G4 | 区域与出境按实际账号和端点复核，不提前承诺 |

### H 清理计划

| 编号 | 内容 |
|---|---|
| H1 | ✅ 删除 Lab 诊断面 4 个文件 |
| H2 | ✅ 渲染层搬家瘦身，删除自动缩放与卡片外观 |
| H3 | ✅ 删除从未验证的引擎默认参数中随 Lab 消失的那套；剩余部分并入 D2 |
| H4 | ✅ 删除 pbxproj 的 iPhone 方向死设置 |
| H5 | ✅ 清理门禁脚本 5 个死路径、`.gitignore` 陈旧条目、Secrets 模板图像 key |
| H6 | ✅ 文档去掉图像回应与素材规格，12 步计划换成 A–H |
| H7 | ✅ 图像相关占位 key 删除 |
| H8 | 删除陈旧分支 `chore/pre-development-readiness` |

### 执行顺序

```
H 清理                          ← 已完成（H8 待办）
F1 → F2 → F3 中文识别硬门禁      ← 需要用户先装 Xcode 27 beta
F4 → F5
D1 → D2 → D3 → D4 → D6
E1 → E2                         ← 第一次看到真实文字被逐笔写出来
A1 → A8
E3 → E4 → E5 → A10
E6 → E7 魔法生死评审
G1 → G4
B1 → B4
C1 → C3
```

F3 排这么前，是因为整条产品路线押在 PencilKit 中文手写识别上。先打掉最大的不确定性，再做确定的事。
