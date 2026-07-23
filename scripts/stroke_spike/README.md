# Task 1 — 笔画方案对比实验（stroke spike）

**目的**：同一组素材，两条源各跑一遍，都套上速度/抖动，**肉眼选源**。不提前拍板。

- **源 ①「直接 SVG」**：LLM 直接吐 SVG `<path>` 序列 → 解析 → 有序笔画。
- **源 ②「生成图抽骨架」**：线稿 PNG → Zhang-Suen 抽骨架 → 理笔顺。

两条都送进同一个 humanizer → 输出「逐笔生长」的动画 SVG，浏览器打开对比。

> 这是 Python **spike**（探针），只为比较管道，不是最终 Swift 实现。最终 StrokeEngine 在 App target 内用 Swift 重写。

## 当前素材的性质（不要误读）

`generate_test_assets.py` 中的 10 组素材是 **GPT-5.6 编写的确定性工程预检夹具**：每组从同一批有序线条同时输出 SVG + PNG，覆盖有机隐喻、抽象纠缠、极简风景、尖锐几何、迷宫、静物、自然韧性、双主体场景、动态符号和人物姿态。

它们能回答：

- 两条本地管道能否稳定跑通？
- 同一结构经「直接 SVG」与「PNG 抽骨架」后，笔画数量、顺序和手感有何差异？

它们**不能**回答：

- Qwen-Image 生成的回应是否动人？
- AI 是否真正读懂了用户涂鸦？
- 项目是否通过最终 Go/Kill 魔法评审？

真实结论仍需接入 Qwen 后，用不同用户涂鸦生成回应，并由用户主观评审。

## 环境（本地隔离，不污染系统 Python）

依赖均精确锁定在 `requirements.txt`：

```bash
cd scripts/stroke_spike
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

`.venv/` 与 `out/` 已 gitignore。

## 生成 10 组预检素材

```bash
.venv/bin/python generate_test_assets.py
```

产物位于 `input/`：

- `01_*.svg` … `10_*.svg`：直接有序矢量源
- 同名 `.png`：干净黑线稿、白底的抽骨架源
- `manifest.json`：情绪、表达类型、提示词和限制说明

生成器只覆盖自己的 10 个固定文件，不删除用户以后放入的素材。

## 运行对比

```bash
.venv/bin/python compare.py
.venv/bin/python compare.py --name 01_weary_flower
```

对每组素材，`out/` 会生成：

- `*_svg.svg`：直接 SVG → humanizer → 逐笔动画
- `*_skeleton.svg`：PNG → 抽骨架/理笔顺 → humanizer → 逐笔动画

浏览器并排打开比较。`out/` 是可再生实验结果，不提交 Git。

## Task 1B 初步 Go 标准（不替代 App 内最终 Go/Kill）

接入真实理解/图像模型后，用至少 10 张不同情绪的**用户输入涂鸦**生成回应：至少 3–4 组让用户产生明确的「哦……」感，才算脚本/素材层的初步 Go；否则继续调整 prompt、模型或笔画源。

这一步只决定是否值得继续集成，不能替代 12 步计划第 8 步对 App 内完整 Oracle + StrokeEngine + 节奏 + 降级体验的最终 Go/Kill 评审。
