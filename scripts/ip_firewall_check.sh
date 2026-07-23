#!/usr/bin/env bash
# ============================================================
# ip_firewall_check.sh — 提交门禁（IP 防火墙 + 密钥泄漏）
#
# 作用：
#   1) 在「被分发的用户可见面」扫描华纳 IP 禁用词 → 命中即失败。
#   2) 已知情接受项（Tom Riddle / 项目名 / bundle id）→ 仅警告，登记在案，分发前复核。
#   3) 确认 gitignored 的密钥 / 本地 persona 文件没有被 git 跟踪 → 被跟踪即失败。
#
# 扫描范围排除「内部知识面」（docs/ memory/ .claude/ CLAUDE.md README.md 脚本自身），
# 因为那里必然含禁用词（它们定义策略本身）。门禁保护的是会分发出去的面。
#
# 退出码：0 = 通过；1 = 命中禁用词或检测到密钥入库。
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---- 排除目录（内部知识面 / 构建产物）----
EXCLUDE_DIRS=(".git" "docs" "memory" ".claude" ".kiro" "kiro-pet"
             "build" "DerivedData" ".build" ".swiftpm" "Pods" "Carthage"
             ".venv" "venv" "__pycache__" "scripts/stroke_spike/out")

# ---- 排除文件（定义策略本身 / 已 gitignore 的本地文件）----
EXCLUDE_FILES=("./CLAUDE.md" "./README.md"
              "./scripts/ip_firewall_check.sh"
              "./Config/Persona.local.json" "./Config/Persona.example.json")

# ---- 硬禁用词（华纳 IP，命中即失败）----
BANNED=("Harry Potter" "Voldemort" "伏地魔" "Hogwarts" "霍格沃茨"
        "Horcrux" "魂器" "Dumbledore" "邓布利多" "Hermione"
        "Gryffindor" "Slytherin")

# ---- 已知情接受项（仅警告，分发前复核）----
ACCEPTED=("Tom Riddle" "TomRiddlesDiary" "tomriddle")

# ---- gitignored 敏感文件（绝不可被 git 跟踪）----
SENSITIVE=("Config/Secrets.xcconfig" "Config/Persona.local.json")

fail=0

# 构建待扫描文件列表（find + 排除）
build_list() {
  local args=(. -type f)
  local d
  for d in "${EXCLUDE_DIRS[@]}"; do
    args+=(-not -path "./$d/*")
  done
  # Xcode 用户态文件不会入库，也可能是二进制；无论嵌套层级都跳过。
  args+=(-not -path "*/xcuserdata/*")
  find "${args[@]}"
}

is_excluded_file() {
  local f="$1" e
  for e in "${EXCLUDE_FILES[@]}"; do
    [ "$f" = "$e" ] && return 0
  done
  return 1
}

echo "== IP 防火墙扫描（分发面）=="
FILES="$(build_list)"

# 1) 硬禁用词
while IFS= read -r f; do
  is_excluded_file "$f" && continue
  for term in "${BANNED[@]}"; do
    if LC_ALL=C grep -nF "$term" "$f" >/dev/null 2>&1 || grep -nF "$term" "$f" >/dev/null 2>&1; then
      echo "  ✗ 禁用词命中: \"$term\"  →  $f"
      grep -nF "$term" "$f" 2>/dev/null | sed 's/^/      /' || true
      fail=1
    fi
  done
done <<< "$FILES"

# 2) 已接受项（警告）
accepted_hits=0
while IFS= read -r f; do
  is_excluded_file "$f" && continue
  for term in "${ACCEPTED[@]}"; do
    if grep -nF "$term" "$f" >/dev/null 2>&1; then
      echo "  ⚠ 已接受项（登记在案，分发前复核）: \"$term\"  →  $f"
      accepted_hits=1
    fi
  done
done <<< "$FILES"
[ "$accepted_hits" = "0" ] && echo "  （分发面未发现已接受 IP 名）"

# 3) 密钥 / 本地 persona 是否被 git 跟踪
echo "== 密钥泄漏检查 =="
if [ -d ".git" ]; then
  for s in "${SENSITIVE[@]}"; do
    if git ls-files --error-unmatch "$s" >/dev/null 2>&1; then
      echo "  ✗ 敏感文件被 git 跟踪，必须移除: $s"
      echo "      修复: git rm --cached \"$s\""
      fail=1
    fi
  done
  [ "$fail" = "0" ] && echo "  ✓ 未发现敏感文件入库"
else
  echo "  （尚未 git init，跳过跟踪检查；.gitignore 已含敏感文件）"
fi

echo "================================"
if [ "$fail" = "0" ]; then
  echo "✓ 门禁通过"
  exit 0
else
  echo "✗ 门禁失败：修复后重跑"
  exit 1
fi
