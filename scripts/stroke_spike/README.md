# Task 1 — 笔画方案对比实验（stroke spike）

**目的**：同一组素材，两条源各跑一遍，都套上压感/速度/抖动，**肉眼选源**。不提前拍板。

- **源 ①「直接 SVG」**：LLM 直接吐 SVG `<path>` 序列 → 解析 → 有序笔画。
- **源 ②「生成图抽骨架」**：Qwen-Image 生成干净线稿 → Zhang-Suen 抽骨架 → 理笔顺。

两条都送进同一个 humanizer（压感/速度/抖动）→ 输出「逐笔生长」的动画 SVG，浏览器打开对比。

> 这是 Python **spike**（探针），只为用眼睛比较，不是最终 Swift 实现。最终 StrokeEngine 在 App target 内用 Swift 重写。

## 环境

```bash
cd scripts/stroke_spike
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 准备素材

把素材放进 `input/`（`out/` 与 `.venv/` 已 gitignore）：

- 源 ②（抽骨架）：放线稿 PNG，如 `input/sad_flower.png`（干净黑线稿、白底最佳）。
- 源 ①（直接 SVG）：放 SVG，如 `input/sad_flower.svg`（可先手写/让模型产出占位）。

**Phase 0 目标**：画 10 张不同情绪的涂鸦（悲伤/焦虑/平静/愤怒/迷茫…），跑完整管道，看回应。至少 3–4 张让你「哦…」一下 → Go。

## 运行

```bash
python compare.py                 # 处理 input/ 下所有素材，输出到 out/
python compare.py --name sad_flower
```

对每个素材，`out/` 会生成 `*_svg.svg`（源①）和 `*_skeleton.svg`（源②）两个逐笔动画，并排打开比较手绘感。

## 待接（依赖尚未就绪，属阻塞项）

- 真实源①的 SVG、源②的线稿，需要接 LLM / Qwen-Image（key 在 `Config/Secrets.xcconfig`，骨架期直连）。
- 在此之前，脚本对**你手动放进 `input/` 的 PNG/SVG** 就能跑本地管道，用来验证「抽骨架→理笔顺→逐笔重播」这套本地引擎的手感。
