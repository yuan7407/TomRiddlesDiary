#!/usr/bin/env bash
# ============================================================
# check_oracle_key.sh — 验一下 key、端点、模型名对不对（计划 E6d）
#
# 为什么单独一个脚本：App 里跑不通的时候，得先分清是「key/端点/模型名不对」
# 还是「我们的代码不对」。这个脚本只碰前者——它不用 App 的任何代码，
# 直接按 OpenAI 兼容格式发一次最小请求。
#
# ── 它绝不会打印你的 key ──
# key 只进环境变量和请求头。输出里只有状态码和模型说的那句话。
#
# ── 发出去的内容 ──
# 一句写死的测试话（不是你的日记内容）。运行它意味着向供应商发一次请求，
# 会消耗一点额度。
#
# 用法：bash scripts/check_oracle_key.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SECRETS="Config/Secrets.xcconfig"

if [ ! -f "$SECRETS" ]; then
  echo "✗ 没有 $SECRETS"
  echo "  新建这个文件，里面写一行："
  echo "      ORACLE_API_KEY = sk-你的真key"
  echo "  它已经被 .gitignore 挡住，不会提交。"
  exit 1
fi

# 端点默认值（host / path / model）写在 Xcode 工程的 Debug 配置里，
# Secrets.xcconfig 里的同名值会覆盖它们。
# **从工程里读而不是在这儿抄一份**：抄一份就是同一个值有两个来源，
# 迟早出现「脚本说通了、App 里却是另一个端点」。代价是慢十秒左右。
echo "== 从 Xcode 工程读配置（慢十秒）=="
SETTINGS=$(xcodebuild -project TomRiddlesDiary.xcodeproj -target TomRiddlesDiary \
             -configuration Debug -showBuildSettings 2>/dev/null)

setting() { printf '%s' "$SETTINGS" | grep -E "^ +$1 = " | head -1 | sed "s/^[^=]*= *//"; }

HOST="$(setting ORACLE_HOST)"
CHAT_PATH="$(setting ORACLE_CHAT_PATH)"
MODEL="$(setting ORACLE_MODEL)"
KEY="$(setting ORACLE_API_KEY)"

echo
echo "== 配置 =="
echo "  host    : ${HOST:-（空）}"
echo "  path    : ${CHAT_PATH:-（空）}"
echo "  model   : ${MODEL:-（空）}"
if [ -z "$KEY" ]; then
  echo "  key     : ✗ 没读到"
  echo
  echo "在 $SECRETS 里写一行（变量名必须完全一致）："
  echo "      ORACLE_API_KEY = sk-你的真key"
  exit 1
fi
case "$KEY" in
  *在这里粘贴*|REPLACE*)
    echo "  key     : ✗ 还是占位值"
    exit 1 ;;
esac
echo "  key     : ✓ 已读到（${#KEY} 字符，不显示内容）"
echo

URL="https://${HOST}${CHAT_PATH}"
echo "== 发一次最小请求 → $URL =="

BODY=$(cat <<JSON
{
  "model": "$MODEL",
  "messages": [
    {"role": "system", "content": "只回四个字，不要多说。"},
    {"role": "user", "content": "在吗"}
  ],
  "max_tokens": 32,
  "stream": false
}
JSON
)

RESPONSE=$(curl -sS -w '\n%{http_code}' \
  -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d "$BODY" 2>&1)

STATUS=$(printf '%s' "$RESPONSE" | tail -1)
PAYLOAD=$(printf '%s' "$RESPONSE" | sed '$d')

echo "  HTTP $STATUS"
case "$STATUS" in
  200)
    SAID=$(printf '%s' "$PAYLOAD" | python3 -c 'import sys,json;print(json.load(sys.stdin)["choices"][0]["message"]["content"])' 2>/dev/null)
    if [ -n "$SAID" ]; then
      echo "  模型说：「$SAID」"
      echo
      echo "✓ key、端点、模型名都对。App 现在会用真的魂。"
      exit 0
    fi
    echo "  ⚠️ 200 但取不出内容。响应："
    printf '%s\n' "$PAYLOAD" | head -20
    exit 1 ;;
  401|403) echo "  → key 不对或没权限" ;;
  404) echo "  → 地址或模型名不对。去账号页面看实际可用的模型名，填进 ORACLE_MODEL" ;;
  429) echo "  → 超了速率或额度" ;;
  5*) echo "  → 服务端的问题，可以再试" ;;
  *) echo "  → 没见过的状态码" ;;
esac
echo "  响应（可能含端点细节，别整段贴到公开地方）："
printf '%s\n' "$PAYLOAD" | head -10
exit 1
