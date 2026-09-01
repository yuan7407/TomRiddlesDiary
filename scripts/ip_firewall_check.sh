#!/usr/bin/env bash
# ============================================================
# ip_firewall_check.sh — 提交门禁（IP 防火墙 + 密钥泄漏）
#
# 作用：
#   1) 在可能进入产品/分发面的文本文件中扫描 IP 禁用词。
#   2) 对已登记的内部占位名给出警告，提醒分发前复核。
#   3) 确认密钥与本地 persona 文件没有被 Git 跟踪。
#
# 文件范围：Git 已跟踪文件 + 未被 .gitignore 排除的候选文件；跳过二进制、
# 构建产物和定义策略的内部知识面。这样既覆盖 staged/untracked 候选，也不会
# 遍历 xcuserdata 等被忽略的大目录。
#
# 退出码：0 = 通过；1 = 命中禁用词或检测到敏感文件入库。
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---- 内部知识面 / 构建产物（不属于用户可见分发面）----
# 2026-08-26 清理：删掉 docs / memory / .claude / kiro-pet / scripts/stroke_spike/out
# 五个已不存在的路径，以及 Pods / Carthage（本工程用 SPM，两个包管理器都不使用）。
# 保留 .kiro：那里是规则与流程文件，属定义策略的内部面。注意这意味着门禁不会扫描
# steering 文件，是已知的覆盖缺口，待决定是否收窄。
EXCLUDE_DIRS=(".kiro"
              "build" "DerivedData" ".build" ".swiftpm")

# ---- 定义策略本身 / 已 gitignore 的本地配置 ----
EXCLUDE_FILES=("AGENTS.md" "README.md" "MEMORY.md"
               "scripts/ip_firewall_check.sh"
               "Config/Persona.local.json" "Config/Persona.example.json")

# ---- 硬禁用词（未经授权不得进入分发面）----
BANNED=("Harry Potter" "Voldemort" "伏地魔" "Hogwarts" "霍格沃茨"
        "Horcrux" "魂器" "Dumbledore" "邓布利多" "Hermione"
        "Gryffindor" "Slytherin")

# ---- 已知情内部占位（仅警告，分发前必须复核）----
ACCEPTED=("Tom Riddle" "TomRiddlesDiary" "tomriddle")

# ---- gitignored 敏感文件（绝不可被 Git 跟踪）----
SENSITIVE=("Config/Secrets.xcconfig" "Config/Persona.local.json")

fail=0

is_excluded_path() {
  local f="${1#./}" d e

  # Xcode 用户态目录任意层级都不扫描（也绝不入库）。
  # 2026-08-26 移除 .venv / venv / __pycache__：Python spike 已删除，工程无 Python。
  case "/$f/" in
    *"/xcuserdata/"*) return 0 ;;
  esac

  for d in "${EXCLUDE_DIRS[@]}"; do
    case "$f" in
      "$d"|"$d"/*) return 0 ;;
    esac
  done

  for e in "${EXCLUDE_FILES[@]}"; do
    [ "$f" = "$e" ] && return 0
  done

  return 1
}

is_text_file() {
  local f="$1"
  [ -f "$f" ] && LC_ALL=C grep -Iq . "$f"
}

# 使用 NUL 分隔，安全处理空格；--exclude-standard 自动尊重 .gitignore。
FILES=()
while IFS= read -r -d '' f; do
  f="${f#./}"
  is_excluded_path "$f" && continue
  is_text_file "$f" || continue
  FILES+=("$f")
done < <(git ls-files --cached --others --exclude-standard -z)

echo "== IP 防火墙扫描（已跟踪 + 非 ignored 候选文本）=="

# 1) 硬禁用词
for f in "${FILES[@]}"; do
  for term in "${BANNED[@]}"; do
    if LC_ALL=C grep -nF "$term" "$f" >/dev/null 2>&1; then
      echo "  ✗ 禁用词命中: \"$term\"  →  $f"
      LC_ALL=C grep -nF "$term" "$f" 2>/dev/null | sed 's/^/      /' || true
      fail=1
    fi
  done
done

# 2) 已接受占位项（警告）
accepted_hits=0
for f in "${FILES[@]}"; do
  for term in "${ACCEPTED[@]}"; do
    if LC_ALL=C grep -nF "$term" "$f" >/dev/null 2>&1; then
      echo "  ⚠ 已接受项（登记在案，分发前复核）: \"$term\"  →  $f"
      accepted_hits=1
    fi
  done
done
[ "$accepted_hits" = "0" ] && echo "  （候选分发面未发现已接受 IP 名）"

# 3) 密钥 / 本地 persona 是否被 Git 跟踪
echo "== 密钥泄漏检查 =="
sensitive_fail=0
for s in "${SENSITIVE[@]}"; do
  if git ls-files --error-unmatch "$s" >/dev/null 2>&1; then
    echo "  ✗ 敏感文件被 Git 跟踪，必须移除: $s"
    echo "      修复: git rm --cached \"$s\""
    sensitive_fail=1
    fail=1
  fi
done
[ "$sensitive_fail" = "0" ] && echo "  ✓ 未发现敏感文件入库"

# 4) 纯逻辑层的依赖边界
# 为什么要机器检查：Sources/ 下所有文件编进同一个模块，文件夹本身不产生任何
# 编译约束。也就是说没人阻止在 StrokeEngine 里 import SwiftUI，一旦发生，
# 「引擎不依赖 UI、可独立测试、换渲染实现手感不漂移」这条铁律就悄悄破了，
# 而且很难发现——代码看起来还在那个文件夹里。这里用白名单把它变成硬错误。
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

if check_layer_imports "Sources/StrokeEngine" "Foundation"; then
  echo "  ✓ StrokeEngine 只依赖 Foundation"
else
  fail=1
fi

# Handwriting 允许 CoreText/CoreGraphics：中文断行规则与字体度量必须靠系统的
# 文字排版引擎，自己写必然漏。它们属文字排版，不是 UI 框架。
if check_layer_imports "Sources/Handwriting" "Foundation CoreGraphics CoreText"; then
  echo "  ✓ Handwriting 未引入 UI 依赖"
else
  fail=1
fi

# Calibration 是开发期的量尺（计划 A10）：读真人笔迹算出该配什么参数。
# 它必须和引擎一样纯——一旦让它 import PencilKit 或 SwiftUI，
# 「量尺」就会退化成「只能在 App 里跑的东西」，测不了、也没法离线分析采样。
# 「怎么从 PencilKit 读出这些数」属画布层（`PenTraceReader`）。
if check_layer_imports "Sources/Calibration" "Foundation"; then
  echo "  ✓ Calibration 只依赖 Foundation"
else
  fail=1
fi

# Oracle 是「说什么」那一侧（计划 E6）：把这一页的文字交出去、拿回一段话。
# 它必须只依赖 Foundation，两个理由：
# 一、一旦它能 import PencilKit，就有人会顺手把 PKDrawing 直接发给模型——
#    而 AGENTS.md 要求「只发送完成任务所需的最少数据，默认不上传原始 PencilKit
#    全量历史」。协议层面拿不到笔画，比靠实现方自觉可靠。
# 二、一旦它能 import SwiftUI，「模型只决定说什么、不决定怎么写」这条铁律就有了
#    可以被绕过的口子。手感必须完全由本地引擎决定。
if check_layer_imports "Sources/Oracle" "Foundation"; then
  echo "  ✓ Oracle 只依赖 Foundation（拿不到笔画，也碰不到 UI）"
else
  fail=1
fi

echo "================================"
if [ "$fail" = "0" ]; then
  echo "✓ 门禁通过"
  exit 0
fi

echo "✗ 门禁失败：修复后重跑"
exit 1
