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
SECRETS="$ROOT/Config/Secrets.xcconfig"
ORACLE="$ROOT/Config/Oracle.xcconfig"

if [ ! -f "$SECRETS" ]; then
  echo "✗ 没有 $SECRETS"
  echo "  先做这一步： cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig"
  echo "  然后在那个副本里填你的真 key。"
  exit 1
fi

# 从 xcconfig 里取值。只取等号右边，去掉前后空格。
read_setting() {
  local name="$1" file="$2"
  [ -f "$file" ] || return 0
  grep -E "^[[:space:]]*$name[[:space:]]*=" "$file" 2>/dev/null \
    | tail -1 | sed "s/^[^=]*=[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

# Secrets 里的值覆盖 Oracle 里的默认值（和构建时的顺序一致）。
HOST="$(read_setting ORACLE_HOST "$ORACLE")"
[ -n "$(read_setting ORACLE_HOST "$SECRETS")" ] && HOST="$(read_setting ORACLE_HOST "$SECRETS")"
CHAT_PATH="$(read_setting ORACLE_CHAT_PATH "$ORACLE")"
MODEL="$(read_setting ORACLE_MODEL "$ORACLE")"
[ -n "$(read_setting ORACLE_MODEL "$SECRETS")" ] && MODEL="$(read_setting ORACLE_MODEL "$SECRETS")"
KEY="$(read_setting ORACLE_API_KEY "$SECRETS")"

echo "== 配置 =="
echo "  host    : ${HOST:-（空）}"
echo "  path    : ${CHAT_PATH:-（空）}"
echo "  model   : ${MODEL:-（空）}"
if [ -z "$KEY" ]; then
  echo "  key     : ✗ 没有"
  echo
  echo "在 $SECRETS 里加一行（变量名必须完全一致）："
  echo "  ORACLE_API_KEY = sk-你的真key"
  echo
  echo "注意：那个文件里现在的 DASHSCOPE_API_KEY / GEMINI_API_KEY / FLUX_API_KEY"
  echo "是更早版本留下的，代码不读它们。"
  exit 1
fi
case "$KEY" in
  *在这里粘贴*|REPLACE*)
    echo "  key     : ✗ 还是模板占位值"
    exit 1 ;;
esac
echo "  key     : ✓ 已填（${#KEY} 字符，不显示内容）"
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
