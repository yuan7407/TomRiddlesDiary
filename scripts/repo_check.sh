#!/usr/bin/env bash
# ============================================================
# repo_check.sh — 提交前的两项机器检查
#
# 2026-09-01 从原来的 ip_firewall_check.sh 精简而来。
# 用户明确取消了 IP 门禁（个人项目，出现 IP 引用是惊喜不是风险），
# 所以那一整块（禁用词表、已接受占位项、每次跑刷十几行警告）删掉了。
#
# 留下的两项都和 IP 无关，而且各有具体理由：
#
#   1) 密钥有没有被 Git 跟踪
#      不是假想风险。2026-09-01 就发生过一次：真 key 被写进了
#      `Secrets.example.xcconfig`（那个文件是被跟踪的），差一步就进 GitHub。
#      这一项如果早跑一次就能当场拦住。
#
#   2) 纯逻辑层有没有偷偷依赖 UI
#      `Sources/` 下所有文件编进同一个模块，文件夹本身不产生任何编译约束——
#      没人阻止在 StrokeEngine 里 import SwiftUI。一旦发生，
#      「引擎不依赖 UI、可独立测试、换渲染实现手感不漂移」这条铁律就悄悄破了，
#      而且很难发现：代码看起来还在那个文件夹里。
#
# 退出码：0 = 通过；1 = 有问题。
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

# ---- 1) 密钥不得被 Git 跟踪 ----
echo "== 密钥检查 =="

# 明确点名的敏感文件。
SENSITIVE=("Config/Secrets.xcconfig")
for s in "${SENSITIVE[@]}"; do
  if git ls-files --error-unmatch "$s" >/dev/null 2>&1; then
    echo "  ✗ $s 被 Git 跟踪了，必须移除"
    echo "      修复: git rm --cached \"$s\""
    fail=1
  fi
done

# 更要紧的一条：任何**被跟踪的**文件里都不该出现真 key 的形状。
# 这条抓的正是上次那种情况——key 写进了一个名字看起来像模板、但其实被跟踪的文件。
# 只匹配「sk- 后面跟至少 20 位」，所以模板里的示例文字不会误报。
LEAKED=$(git grep -nIE 'sk-[A-Za-z0-9_-]{20,}' -- . 2>/dev/null || true)
if [ -n "$LEAKED" ]; then
  echo "  ✗ 被跟踪的文件里出现了像真 key 的字符串："
  # 只报文件与行号，**不打印内容**。
  printf '%s\n' "$LEAKED" | cut -d: -f1,2 | sed 's/^/      /'
  echo "      把它移到 Config/Secrets.xcconfig（那个文件已被 .gitignore 挡住）"
  fail=1
fi

[ "$fail" = "0" ] && echo "  ✓ 没有密钥进库"

# ---- 2) 纯逻辑层的依赖边界 ----
echo "== 纯逻辑层依赖边界 =="
check_layer_imports() {
  local layer="$1" allowed="$2" f line module bad=0
  [ -d "$layer" ] || return 0
  while IFS= read -r f; do
    while IFS= read -r line; do
      module="${line#*import }"
      module="${module%% *}"
      case " $allowed " in
        *" $module "*) ;;
        *)
          echo "  ✗ $layer 不允许依赖 $module  →  ${f#./}"
          bad=1
          ;;
      esac
    done < <(grep -h '^ *@\{0,1\}[a-z]*[[:space:]]*import ' "$f" 2>/dev/null | sed 's/^ *//')
  done < <(find "$layer" -name '*.swift')
  return $bad
}

# StrokeEngine：手绘化与重播时序。只许 Foundation——它要能脱离 Apple 平台单独测。
if check_layer_imports "Sources/StrokeEngine" "Foundation"; then
  echo "  ✓ StrokeEngine 只依赖 Foundation"
else
  fail=1
fi

# Handwriting：文字 → 纸上位置。允许 CoreText/CoreGraphics——中文断行规则与字体度量
# 必须靠系统的文字排版引擎，自己写必然漏。它们属文字排版，不是 UI 框架。
if check_layer_imports "Sources/Handwriting" "Foundation CoreGraphics CoreText"; then
  echo "  ✓ Handwriting 未引入 UI 依赖"
else
  fail=1
fi

# Calibration：用真人笔迹量参数（计划 A10）。一旦让它 import PencilKit 或 SwiftUI，
# 「量尺」就退化成「只能在 App 里跑的东西」，测不了也没法离线分析采样。
if check_layer_imports "Sources/Calibration" "Foundation"; then
  echo "  ✓ Calibration 只依赖 Foundation"
else
  fail=1
fi

# Oracle：「说什么」那一侧。只许 Foundation，两个理由：
# 一、能 import PencilKit 就会有人把 PKDrawing 直接发给模型，而该发的只有文字；
# 二、能 import SwiftUI 就给「模型只决定说什么、不决定怎么写」留了绕过的口子。
if check_layer_imports "Sources/Oracle" "Foundation"; then
  echo "  ✓ Oracle 只依赖 Foundation"
else
  fail=1
fi

echo "================================"
if [ "$fail" = "0" ]; then
  echo "✓ 检查通过"
  exit 0
fi
echo "✗ 检查失败：修复后重跑"
exit 1
