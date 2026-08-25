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
# 遍历 .venv、out、xcuserdata 等被忽略的大目录。
#
# 退出码：0 = 通过；1 = 命中禁用词或检测到敏感文件入库。
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---- 内部知识面 / 构建产物（不属于用户可见分发面）----
EXCLUDE_DIRS=("docs" "memory" ".claude" ".kiro" "kiro-pet"
              "build" "DerivedData" ".build" ".swiftpm" "Pods" "Carthage"
              "scripts/stroke_spike/out")

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

  # 任意层级的虚拟环境、缓存和 Xcode 用户态目录都不扫描。
  case "/$f/" in
    *"/.venv/"*|*"/venv/"*|*"/__pycache__/"*|*"/xcuserdata/"*) return 0 ;;
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

echo "================================"
if [ "$fail" = "0" ]; then
  echo "✓ 门禁通过"
  exit 0
fi

echo "✗ 门禁失败：修复后重跑"
exit 1
