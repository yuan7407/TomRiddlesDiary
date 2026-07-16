# 合规与 IP 防火墙

## IP 防火墙

### 禁用词（不得进入被分发的用户可见面）

面向：文案 / 图标 / 截图 / 关键词 / 营销 / 客服话术。

`Harry Potter / Voldemort / 霍格沃茨 / Hogwarts / 魂器`（Horcrux）等华纳 IP 元素。

### 已知情接受项（登记在案，非疏漏）

- 本地 persona 占位 "Tom Riddle"
- 项目名（TomRiddlesDiary / 显示名 "Tom Riddle's Diary"）
- bundle id（含 tomriddle）
- 私有仓库名

**仅限不公开面；分发前须复核并评估替换。**

### 门禁

- `scripts/ip_firewall_check.sh` 为提交门禁：放行上述接受项，拦其余面。
- 扫描范围排除内部知识面（`docs/`、`memory/`、`.claude/`、`CLAUDE.md`、`README.md`、脚本自身）——这些是定义策略的地方，必然含禁用词。
- 附带检查：gitignored 的 `Config/Secrets.xcconfig`、`Config/Persona.local.json` 若被 git 跟踪 → 失败。
- 商业版必须自建原创「会回应的日记」世界观。

## 合规红线

- 成人定位 **17+**，加年龄门槛。
- **AI 身份披露**（叙事化）：由「日记之魂」以世界观口吻自述非人属性，把合规变成叙事的一部分，而非省略披露。
- **自残/危机兜底**流程。
- **一键删除全部数据**（GDPR/COPPA 的 "eraser button"）。
- **AI 生成内容标识**（尤其国行：显式 + 隐式标识）。
- 通道合规：中国区用**备案的 Qwen**、数据不出境。

## 监管背景（源文档 2026.07 信息，签约/上架前复核官方最新版）

- 情感陪伴 AI 是 2026 全球监管最高压类目。核心策略：成人定位 + 清晰 AI 披露 + 危机兜底，把自己划出「面向未成年人的 companion chatbot」射程。
- 苹果 App Review 2.3（误导性营销）：视频/素材必须与 App 真实体验一致（震撼来自体验，不来自欺骗）。
- 分发市场排序建议：先海外或先国行，不要一上来全球；先做单一语言、单一市场的最小合规版本试水。
