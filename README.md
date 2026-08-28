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
    PageMetrics           毫米 ↔ 页面点，全工程唯一的物理换算点
    HandwritingFeel       手感参数 + 装配 HumanizerConfiguration 的唯一入口
    PageAppearance        纸色、墨色、墨线宽度
  Features/Canvas/        写字的那张纸
  Handwriting/            文字 → 纸上位置（纯逻辑，与 StrokeEngine 平级）
    TextLayout            CoreText 断行与定位，输出每个字的页面位置
  Features/Response/      魂的回应渲染
    HandwrittenTextView   用字体逐字显现（E8 脚手架）
    HandwritingReplayView 用笔画逐笔生长（E1 之后启用）
  Resources/Fonts/        打包字体（寒蝉手拙体 v2.500）
  StrokeEngine/           手绘化、生长几何与重播时序（纯逻辑，不依赖 UI 与配置）
    StrokeHumanizer       把几何折线变成带压感与节奏的笔画
    StrokeGrowth          一笔在某个进度下应该画到哪里（含生长中的半段）
    StrokeReplayTimeline  已过秒数 → 每笔进度，严格串行
Tests/                    XCTest（与 Sources 同级，不打进 App）
Config/                   Secrets / Persona 模板，真实值被 gitignore
scripts/                  仓库工具：提交门禁（不属于 App，不会被打包）
```

目标模块划分见 `AGENTS.md` 的「模块边界」。工程使用 Xcode 同步文件组，`Sources/` 与 `Tests/` 下新增文件自动加入对应 target，不需手改 pbxproj。

## 当前状态

| 项 | 状态 |
|---|---|
| Xcode / Simulator | ✅ iPadOS 27、仅 iPad、无签名 Simulator build 通过（需 Xcode 27） |
| 笔画引擎 | ✅ 手绘化 + 压感 + 严格串行逐笔重播，64 个 XCTest 全通过 |
| 单位契约 | ✅ 参数有物理含义，换字号自动同比例缩放，由测试守住 |
| 回应渲染层 | ✅ 可用（`HandwritingReplayView`），但目前没有调用方 |
| 手写识别 | ⬜ PencilKit 内建识别官方支持中文，但模拟器缺中文模型，只能真机验证 |
| 首屏 | ✅ 一段示例回应会用手写体逐字写在纸上（E8 脚手架，非最终效果） |
| 排版层 | ✅ CoreText 断行，中英混排，字位置可断言 |
| 手写体字体 | ✅ 寒蝉手拙体 v2.500 已打包（3.9 MB OTF） |
| 笔画输入源 | ✅ PencilKit 手写 → `[Polyline]`（`PencilStrokeReader`）。引擎第一次有真实输入 |
| 手写识别 / 字形笔画 / 排版 / Oracle / 后端 / 存储 | ❌ 尚未接入 |

已删除且不再回溯的路线：位图抽骨架（Skeletonizer + StrokeTracer，实机线条质量差，见 Git `e08f4c3`）、Magic Stroke Lab 诊断界面与离线夹具、图像生成与图像回应。

## 运行与验证

打开 `TomRiddlesDiary.xcodeproj`，scheme 选 `TomRiddlesDiary`，选一个 iPad Simulator 后 Run。当前会看到一张空白的暖米白纸，这是预期结果。

最低系统是 iPadOS 27，所以**构建必须用 Xcode 27**。命令行下用 `DEVELOPER_DIR` 指定，不必改全局 `xcode-select`：

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# 测试（必须关闭并行：并行 clone 会触发工具自身崩溃）
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

预期 `64 tests, 0 failures` 与 `** BUILD SUCCEEDED **`。构建有一条非阻塞提示（未依赖 AppIntents，跳过其 metadata），属预期。门禁会报若干占位品牌名的 ⚠，在白名单内，属预期。

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
| D1 | ✅ 坐标与单位契约（2026-08-27）：坐标统一用页面点；**只有字高用毫米声明**，其余长度全部表达为字高的比例。换字号时间距、抖动、速度、墨宽自动同比例变化 |
| D2 | ✅ 经验性常量全部收进 `Configuration`（2026-08-27）：`HandwritingFeel` 持有手感参数、`PageAppearance` 持有纸墨、`PageMetrics` 是唯一的毫米↔点换算点。引擎与视图里已无手感字面量；引擎的默认参数整套删除，构造配置必须交代参照尺度 |
| D3 | ✅ 不变量落进类型（2026-08-27）：`TimedStroke` 构造时校验时长非负且有限，删掉三处消费方各自的 `max(0, ...)` |
| D4 | ✅ 时钟统一（2026-08-27）：重播计时改用单调时钟 `ContinuousClock`，不再用会跳变的 `Date` |
| D5 | ✅ 纸色与墨色收敛到唯一一处（2026-08-26 完成） |
| D6 | ✅ 几何提取并补测（2026-08-27）：把「一笔画到哪里」从视图私有方法提成 `StrokeEngine/StrokeGrowth`，补 15 个测试覆盖半段插值、进度落在采样点上、进度越界、单调生长、笔尖不越段；去掉纯算法测试上多余的 `@MainActor` |

### E 手写文字通道

| 编号 | 内容 |
|---|---|
输出侧分两个阶段：先用手写体字体把链路跑通（E8），再换成字形笔画实现真正的逐笔生长（E1）。编号保持原意不变，执行先后见「执行顺序」。

| 编号 | 内容 |
|---|---|
| E1 | **字形笔顺资产**（输出侧第二阶段，真正的逐笔生长）：文字 → 笔画中线。含数据集覆盖不到的标点、数字、拉丁字母。做完后取代 E8 的字体渲染 |
| E2 | ✅ 排版层完成（2026-08-27）：`Handwriting/TextLayout` 用 CoreText 断行与定位，输出每个字的页面位置与字宽。E8 与 E1 共用这一层。仍待做：字与字的自然不齐（大小起伏、基线抖动），属手写感范畴 |
| E3 | 拆成四小步。**PencilKit 本身 iOS 13 起就有，不需要等 Xcode 27**，只有识别要等 |
| E3a（画布） | ✅ 2026-08-28。`HandwritingCanvas` 嵌入 `PKCanvasView`，与回应层共用纸色和页面坐标系；关掉滚动缩放（一页就是一页） |
| E3b（读笔画） | ✅ 2026-08-28。`PencilStrokeReader` 把 `PKDrawing` 读成 `[Polyline]`，用 `.distance` 等距采样；力度如实报告有无，不编造压感 |
| E3c（成页触发） | ⬜ 长停顿 + 终止标点加速 + 可撤销预告 + Pencil 悬停。**阈值必须先用真实书写数据量出**，不能拍数字 |
| E3d（落笔中断） | ⬜ 用户新落笔即中断接管重播，半截字留在页上 |
| E4 | 手写识别接入。拉丁字母可在模拟器跑通；**中文可用性与准确率必须真机验证**（iPad 装 iPadOS 27 + Apple Pencil，中英混写样张） |
| E5 | 端侧提取字迹指标 |
| E6 | `OracleProvider` 协议 + Mock，离线打通完整闭环；失败只做诚实硬提示，绝不返回 Mock 冒充成功 |
| E7 | 魔法生死评审：手写文字回应的 Go/Kill 判断（原 12 步计划第 8 步，对象由图像换成文字，评审本身保留）。**必须在 E1 之后**——E8 的字体版本无法逐笔生长，不能用它判生死 |
| E8 | ✅ **手写体字体脚手架完成**（2026-08-27）：寒蝉手拙体 v2.500 打包 + CoreText 排版 + 逐字显现，中英混排均为手写体。明确的临时方案：字体是轮廓不是笔迹，给不出笔顺，因此这一步**不验证逐笔生长**，也完全不经过 `StrokeEngine`。E1 完成后取代它 |

### F 工程与工具链

| 编号 | 内容 |
|---|---|
| F1 | ✅ Xcode 27.0 beta 已装（2026-08-27，`Xcode-beta.app`，与 26.6 并存） |
| F2 | ✅ 最低系统 iPadOS 27.0（2026-08-27）。构建必须用 Xcode 27，见「运行与验证」 |
| F3 | ✅ **通过：PencilKit 手写识别官方支持中文**（简体、繁体、粤语，另有日韩阿俄等共 29 种，见 [WWDC 2026 session 203](https://developer.apple.com/videos/play/wwdc2026/203/?time=205)）。**但模拟器上验证不了**——详见「关于手写识别的模拟器限制」 |
| F4 | ✅ 升 Swift 6 语言模式（2026-08-28）。App 代码零错误，测试目标三处隔离标注修正 |
| F5 | ✅ 门禁加纯逻辑层 import 白名单（2026-08-28）。`StrokeEngine` 只许 Foundation，`Handwriting` 只许 Foundation/CoreGraphics/CoreText；已反向验证会红字失败 |
| F6 | ✅ AGENTS.md 补硬编码规则与 `Handwriting` 模块（2026-08-26 完成） |
| F7 | ✅ 合并进 `main`（2026-08-27，`d5641c8`）。此前 main 停在最初的工程集成提交，落后 10 个 |
| F8 | `Package.resolved` 被 gitignore 与「依赖必须锁定版本」规则冲突 |
| F9 | 跑一次 `gh auth login`（交互式，需用户本人操作），之后可走真正的 PR 流程 |
| F10 | 分支名 `feature/magic-stroke-lab` 已与内容不符（该分支最终删掉了 Magic Stroke Lab）。后续开名字对得上的新分支 |

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
| H8 | ✅ 删除陈旧分支 `chore/pre-development-readiness`（2026-08-27，本地与远端；删除前已确认它是 `main` 的祖先，不丢提交） |

### 关于手写识别的模拟器限制

**结论：PencilKit 手写识别官方支持中文，但中文识别只能在真机上验证，模拟器不行。**

实测与证据链（2026-08-27，iOS 27.0 beta 6 模拟器）：

1. `PKStrokeRecognizer.supportedLanguages` 只返回 20 种，全是拉丁字母文字：`cs, da, de, en, es, fi, fr, hi-Latn, id, it, ms, nb, nl, nn, no, pl, pt, ro, sv, tr`（`recognitionVersion = 9`）。显式 `PKStrokeRecognizer(preferredLanguages: ["zh-Hans"])` 的 `languages` 返回空数组。
2. 把模拟器系统语言改成 `zh-Hans-CN`、装上中文手写键盘并重启，结果不变。
3. 但运行时内部的 `CoreHandwriting.framework` 里，中文的码表 `ctc_zh.codemap` **在**（日韩阿俄泰越天城文的码表也都在），而**只有拉丁字母有本地模型权重** `ctc_latn.bundle`。
4. 非拉丁文字的手写模型是按需下载的系统资产（`com.apple.MobileAsset.UAF.Handwriting.*`），模拟器运行时不带。

所以这是**运行环境缺模型**，不是平台不支持。官方 session 的支持语言列表包含中文简繁与粤语。

对开发的影响：

- 拉丁字母的识别**现在就能在模拟器里测**，可以先把画布与识别的接线做完、跑通。
- 中文识别的可用性与准确率**必须等真机**（iPad 装 iPadOS 27）。在那之前不得声称中文识别已验证。
- 代码必须处理「当前设备没有某语言模型」这一真实情况：按 AGENTS.md 不静默兜底，要如实告知而不是假装识别成功。

备选路线（万一真机上中文准确率不够）：Vision 的 `RecognizeTextRequest`，`.accurate` 实测支持 `zh`、`zh-TW`、`yue`、`yue-CN` 共 30 种语言（`.fast` 只有 6 种拉丁语）。做法是把 `PKDrawing` 渲染成图再识别。代价是丢掉笔画顺序信息，而且 Vision 面向印刷体与照片文字。

顺带查到：`PKDrawing.erasePath` / `erasingPath` 是 iOS 27 新增，对「魂的笔画可被橡皮擦掉」（决策 18）有帮助。

### 手写体字体选型（E8）

**iOS 内置字体里没有任何中文楷体或手写体**——实测 iOS 27 运行时只有 `PingFangUI.ttc`（现代黑体，看起来是印刷 UI 文字），macOS 上那些手札体、翩翩体、楷体在 iOS 上都没有。所以必须自带字体。

| 候选 | 风格 | 授权 | 说明 |
|---|---|---|---|
| **霞鹜文楷 GB（LXGW WenKai GB）** | 楷体，像用钢笔认真写 | SIL OFL 1.1 | 首选。派生自 Fontworks Klee One，字形与**笔顺遵循大陆国家标准（G 源字形）**，覆盖通用规范汉字表与 GB 18030-2022 二级。已进 Adobe Fonts 与 CTAN，社区口碑与成熟度最好。与将来的字形笔顺数据同为楷体系，从 E8 切到 E1 时观感落差最小 |
| 寒蝉手拙体（ChillShouZhuo） | 真正的随手写，刻意保留手拙感 | 待复核 | 视觉上更像日记随手写，但成熟度与字数覆盖需确认 |

取舍是审美问题：楷体是「认真写字」的感觉，手拙体是「随手涂写」的感觉。中文免费商用字体的横向索引可参考 [猫啃网](https://www.maoken.com/all-fonts)。

### 执行顺序

不依赖 Xcode 27 的部分（绝大多数）先做：

```
H 清理 + F7 合并 main            ← 已完成
D1 → D2 → D3 → D4 → D6           地基：单位契约、配置集中、不变量、时钟、测试
E2 + E8                          排版层 + 手写体字体：第一次看到回应出现在纸上
E3                               PencilKit 画布（不需要升级工具链）
A1 → A8                          笔触结构修复
A10                              用 E3 采到的真人笔迹校准数值
E5                               端侧字迹指标
E6                               Mock 闭环：离线跑通一次完整对话
```

依赖 Xcode 27 的部分：

```
F1 → F2 → F3 中文识别硬门禁       ← 需要用户先装 Xcode 27
F4 → F5
E4                               识别接入 + 真机准确率验证
```

两条汇合之后：

```
E1                               字形笔顺数据，取代 E8，真正的逐笔生长
E7                               魔法生死评审（必须在 E1 之后）
G1 → G4                          后端 + 接真模型
B1 → B4                          用真实规模优化性能
C1 → C3                          情绪
```

F3 是整条产品路线的押注点（PencilKit 中文手写识别），所以工具链一到手就先打掉它。但它不再卡住其他工作——`PencilKit` 画布、排版、字体脚手架、地基、笔触修复都不需要 iPadOS 27。
