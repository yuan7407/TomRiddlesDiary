# 技术架构（Architecture）

> 权威规则在根目录 `AGENTS.md`；本文件只说明“我们在建什么”。决策的“为什么”见 `memory/topics/architecture-decisions.md`。

## 核心分工

| 层 | 职责 |
|---|---|
| **AI 层（Oracle）** | 决定“画什么”：读用户涂鸦与受控上下文，生成文字和图像 |
| **本地笔画引擎（StrokeEngine）** | 决定“像不像手画的”：笔顺、压感、收笔、速度、抖动与逐笔重播 |

> 铁律：自然来自本地引擎，不依赖大模型直接吐出稳定、自然的最终笔画。

## 三段管道

```text
① 成页
   PencilKit 捕获 → 抬笔静置约 2.8 秒 → 灰度页面图像 → 墨水淡入
        │
        ▼
② Oracle
   视觉模型读取涂鸦 + 有限上下文
        ├── 文字流式返回
        └── 图像并行生成
        │
        ▼
③ StrokeEngine
   Skeletonizer（Zhang-Suen）→ 单像素中心线
   → StrokeTracer → 有序笔画
   → StrokeHumanizer → 压感 / 收笔 / 速度 / 抖动
   → 逐笔重播
```

## 模型通道

- 主力方向：Qwen 视觉理解 + Qwen 图像生成，封装在 `OracleProvider` 后。
- 可选升级：Gemini/FLUX 等只能作为同一协议后的可替换 provider，不侵入 UI、数据或笔画引擎。
- `OracleRouter` 按显式配置选择区域、端点和 provider；模型名、Base URL、Workspace ID、区域和风格不得散落在业务代码。
- 模型可用性、价格、网络可达性、备案、供应商留存和数据驻留必须在确定最终区域时按官方条款/合同复核。
- 选择国内区域或备案模型不自动等于“所有数据不出境”；请求、日志、备份和支持链路都要有证据。
- 线稿 prompt 方向为“干净黑线、白底、无阴影”，最终效果必须经真实涂鸦验证。

## Persona 包

- Persona = 名称 + system prompt + 风格，集中在可替换配置中并由 DEBUG/环境门控。
- 内部测试占位只限私有、非分发面；商业版必须使用原创公开品牌和世界观。

## 数据隐私设计目标

- 日记内容默认端侧加密，提供记忆开关、上下文页数上限、一键遗忘和删除全部数据。
- 只向配置的受控接口发送完成请求所需的最少数据，默认不上传完整 PencilKit 历史。
- 客户端发出请求后不额外保留临时导出；供应商是否留存、训练或跨区域处理，必须按最终服务条款和后端实现验证。
- 生产日志不得包含日记图像、提示词全文、永久标识或凭证。

## 模块结构

```text
App target:
  App/                     应用入口 / 依赖注入
  Features/
    Canvas/                PencilKit 画布 + 抬笔成页
    Response/              逐笔重播 + 墨水淡入
    Diary/                 时间线 / 召回旧页
  Oracle/
    Provider/              OracleProvider + Mock + 模型 provider
    Router/                区域 / provider 路由
    Persona/               可替换 persona 加载
  StrokeEngine/            Skeletonizer / StrokeTracer / StrokeHumanizer / 重播模型
  Data/                    端侧加密存档 / 记忆
  DesignSystem/            主题 / 配色 / 组件

仓库根:
  AGENTS.md                模型无关权威规则
  .claude/agents/          角色职责参考
  .kiro/steering/          Kiro 专项规则
  memory/                  跨会话状态与决策
  docs/                    架构与历史规划
  Config/                  Secrets / Persona 示例与本地配置
  scripts/                 门禁 + Task 1 实验
```

## 隔离原则

画布、Oracle、笔画引擎、数据层、persona 与端点路由相互隔离。共享抽骨架、笔画模型或 provider 调用时，必须验证所有调用方。

## 关键设计原则

矢量笔画优先；体验优先于技术炫技；回应必须与当前涂鸦强相关；隐私承诺以实现和供应商证据为准；失败必须诚实暴露并提供可理解降级。
