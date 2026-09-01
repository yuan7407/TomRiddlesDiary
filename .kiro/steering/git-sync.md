# Git 自动同步规则（始终适用）

用户已明确授权：今后每次实质任务完成后，由 Agent 自动处理 Git 同步、提交、推送和版本一致性核对，不等用户再次提醒。

## 安全流程

1. 开工前：`git fetch --prune origin`，检查 branch / status / ahead-behind；未知本地改动或远端分叉必须先暴露。
2. 默认 feature 分支开发并经 PR 合入 `main`；没有明确授权不得直接推 `main`，永不 force push。
3. 收口前：运行 `scripts/repo_check.sh` + 受影响范围的测试/构建（Xcode 用 `xcodebuild`；Swift Package 才用 `swift test`）。
4. 只 stage 本任务相关文件，先检查 staged diff；密钥（`Config/Secrets.xcconfig`）、xcuserdata、`.kiro/pet/` 永不入库。
5. 验证通过后自动 commit + push 当前分支；再 fetch，并比较 `HEAD` 与 `origin/<branch>`，哈希一致才报告同步完成。
6. push 被拒、远端领先、冲突、测试失败、需要重写历史时立即停止并告诉用户，不静默兜底。
7. 不创建 PostFileSave/Stop 自动推送钩子：避免半成品、用户私有文件或密钥被意外推送。
8. 版本：普通 commit 不升 marketing version；可分发 build 自动递增 build number，release 按实际范围使用语义化版本并记录 tag/changelog。

## 仓库

- 本地：`/Users/envision/Documents/Personal_Docs/109_TomRiddlesDiary`
- 远端：`git@github.com:yuan7407/TomRiddlesDiary.git`（private）
- kiro-pet 已迁到 `/Users/envision/Documents/Personal_Docs/110_KiroPet`，不得重新放入本仓库。
