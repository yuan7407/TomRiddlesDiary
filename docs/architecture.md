# 技术架构（Architecture）

> 权威规则在 `CLAUDE.md`；本文件是「我们在建什么」的技术参考。决策的「为什么」见 `memory/topics/architecture-decisions.md`。

## 核心分工

| 层 | 职责 |
|----|------|
| **AI 层（Oracle）** | 决定「**画什么**」：读用户涂鸦 + 记忆 → 文字 + AI 生成图像 |
| **本地笔画引擎（StrokeEngine）** | 决定「**像不像手画的**」：压感 / 收笔 / 速度 / 抖动 / 笔顺 → 逐笔重播 |

> 铁律：自然来自本地引擎，**不指望大模型直接吐好看的笔画**。

## 管道三段

```
① 成页
   PencilKit 捕获 → 抬笔静置 ~2.8s 自动成页 → 灰度 PNG（"墨水淡入纸里" 过渡）
        │
        ▼
② Oracle
   Qwen-VL 读涂鸦 + 近几页记忆
        ├── 文字（流式，先落笔）
        └── Qwen-Image 生成线稿（并行，盖住延迟）
        │
        ▼
③ StrokeEngine
   Skeletonizer(Zhang-Suen)  → 瘦成单像素中心线
   → StrokeTracer            → 中心线转有序笔画（理笔顺）
   → StrokeHumanizer         → 压感 / 收笔 / 速度 / 抖动
   → CAShapeLayer strokeEnd  → 逐笔重播
```

## 模型通道：Qwen 为主 + 可选海外升级

- **主力**：阿里巴巴通义 Qwen 家族
  - Qwen-VL / Qwen3-VL：视觉理解（读涂鸦）
  - Qwen-Image：图像输出 + 编辑（生成回应线稿；极简风格 + Canny 边缘契合抽骨架）
  - 交付：阿里云百炼（Model Studio / DashScope）——中国区（免翻墙、备案友好）+ 国际区
  - Apache 2.0 开源权重 → **可自部署托底**，摆脱地区限制与厂商锁定
- **可选海外画质升级**：Gemini 原生图像 / FLUX，仅海外通道，藏在同一 `OracleProvider` 接口后（骨架期留桩）
- **路由**：`OracleRouter` 按区域选端点（中国区 / 国际区 / 自部署），按分层选是否走海外升级
- **合规**：中国区用备案 Qwen、数据不出境
- **线稿提示词**：统一「干净的黑色线稿、白底、无阴影」以利抽骨架

## Persona 包（可替换 / IP 防火墙）

- Persona = 名称 + systemPrompt + 风格；集中在**单一 gitignored 配置**（`Config/Persona.local.json`）+ DEBUG flag 门控
- 测试期用 "Tom Riddle"（仅本地、不分发）；原创 persona 并行设计，替换只换名不重构人设

## 数据隐私架构（day 1 设计）

- 日记内容默认**端侧加密**
- 只有成页灰度 PNG 会发给所配置模型端点，**读完即删**
- 近几页作为上下文随请求带上；一键遗忘；页数上限；可整体关闭记忆

## 模块结构

```
App target:
  App/                     应用入口 / 依赖注入
  Features/
    Canvas/                PencilKit 画布 + 抬笔成页
    Response/              逐笔重播 + 墨水淡入
    Diary/                 时间线 / 召回旧页
  Oracle/
    Provider/              OracleProvider 协议 + QwenProvider + Mock + 海外升级桩
    Router/                OracleRouter 端点/分层路由
    Persona/               Persona 加载（读 gitignored 配置）
  StrokeEngine/            Skeletonizer / StrokeTracer / StrokeHumanizer / 重播
  Data/                    端侧加密存档 / 记忆
  DesignSystem/            主题 / 配色 / 组件

仓库根:
  .claude/agents/          Agent 系统提示词
  memory/                  跨会话记忆
  docs/                    文档
  Config/                  Secrets / Persona 配置（真值 gitignored）
  scripts/                 门禁 + Task 1 实验
```

## 隔离原则

修改时确保**画布 / Oracle / 笔画引擎 / 数据层 / persona / 端点路由**相互独立。共享代码（抽骨架、笔画模型、provider 调用）的修改需验证所有调用方。

## 关键设计原则

矢量笔画非位图；不指望模型直吐好看笔画；体验优先于技术炫技；情感真实性（换一张涂鸦回应必须明显不同）；数据端侧加密、只发灰度 PNG、读完即删、一键遗忘。
