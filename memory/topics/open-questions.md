# 尚未解决 / 需要问用户的开放问题

## 未决

1. **`.claude/agents/*` 四份系统提示词**（ios-dev / ai-pipeline-dev / backend-dev / qa-reviewer）已按 Pangan 格式起草，待用户需要时继续校订。
2. **阿里云百炼**当前定价 / 国际区覆盖 / 中国免翻墙直连 → 定架构或签约前复核。
3. **笔画来源**（SVG 源 vs 抽骨架源）最终由 Task 1 实验用眼睛定，**不要提前拍板**；用户稍后放入 10 组素材。
4. **正式 bundle id**：当前 Xcode 生成值为 `TomRiddlesDiary.TomRiddlesDiary`（含已接受 IP 名）；需要团队/主体域名后再决定是否改为标准反向域名，分发前复核。

## 已解决

- GitHub：私有 `yuan7407/TomRiddlesDiary`，SSH remote 已配置并首推成功。
- Xcode：工程已由用户创建并纳入根仓库；Xcode 自动创建的嵌套 Git 已解除并可恢复备份。
- Git 同步：用户已授权 Agent 在每次实质任务收口自动验证、commit、push 并比较本地/远端哈希。

## 参考物料索引

- 源想法：`docs/sketch_diary_launch_plan.md`（原 `~/Downloads/sketch_diary_launch_plan (1).md`）
- 结构母版：Pangan Quant 的 CLAUDE.md
- 技术参考：github.com/maximerivest/riddle（+ 兄弟库 quill）
