# 任务分解（12 步，测试驱动、每步可演示）

1. **项目骨架 + 护栏 + 笔画对比实验（定架构）**：同 10 组素材两条源各跑一遍（①直接 SVG ②生成图抽骨架），都套压感/速度，肉眼选源。
2. **抽骨架 Skeletonizer**（Zhang-Suen，纯逻辑 TDD）。
3. **骨架 → 有序笔画 StrokeTracer**（TDD）。
4. **人性化 + 逐笔重播**（压感/收笔/速度/抖动，strokeEnd 动画）。魔法视觉内核，先于 AI。
5. **PencilKit 画布 + 抬笔成页 + 墨水淡入**。
6. **OracleProvider 协议 + Mock + 离线全链路**（首个垂直切片）。
7. **真实理解层**（QwenProvider 用 Qwen-VL，客户端直连，key 在 gitignored Secrets.xcconfig）。
8. **真实图像回传**（Qwen-Image 生成线稿，提示词强约束「干净黑线稿、白底、无阴影」利于抽骨架）。完整 Go/Kill 魔法时刻。
9. **Persona 包 + IP 防火墙门禁**。
10. **本地加密存档 + 时间线 + 召回旧页**。
11. **端点路由 + 海外升级 provider 留桩**。
12. **骨架收口 + 世界观内降级 + 发布前门禁 + AI 披露**。

## 落盘顺序（kickoff, section 11）

1. `.gitignore`（防泄漏优先）✅
2. 整体替换 `CLAUDE.md` ✅
3. 建骨架：`.claude/agents/*`、`memory/`、`docs/`、`Config/`、`scripts/`、`README.md`（进行中）
4. GitHub：yuan7407 下新建私有仓库 → git init → 确认无密钥入库 → 首次提交 → 加 SSH remote → push → 回填 remote 进 CLAUDE.md（**待用户确认**）
5. Task 1：Python venv 装 scikit-image/Pillow/numpy/svgpathtools，跑笔画对比实验
6. Xcode 工程由用户手建，agent 填源码
