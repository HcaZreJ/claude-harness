#!/usr/bin/env bash
# 回归测试：用两份已知答案的语料，量出 check.pl 的召回率与误报率。
#   should-flag.txt  必须命中 -> 量召回，守「抓得到」
#   should-pass.txt  必须放过 -> 量误报，守「不乱抓」
# 用法: bash run.sh
# 退出码: 0 达标 / 1 未达标
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$DIR/../scripts/check.pl"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

MIN_RECALL="${MIN_RECALL:-85}"
MAX_FP="${MAX_FP:-5}"

# 抽有效行：去空行与纯行。句子在 # 前，期望规则名在 # 后
extract() {
  awk 'BEGIN{FS="#"}
       /^[[:space:]]*$/{next} /^[[:space:]]*#/{next}
       { s=$1; r=(NF>1)?$2:"";
         sub(/[[:space:]]+$/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",r);
         print s "\t" r }' "$1"
}

# 跑 check.pl，吐出「行号<TAB>命中的规则名」
hits() {
  perl "$CHECK" "$1" 2>/dev/null | awk '
    /^\[/ { r=$0; gsub(/^\[|\]$/,"",r); next }
    /^  L[0-9]+:[0-9]+: / { split($1,a,":"); n=substr(a[1],2); print n "\t" r }'
}

extract "$DIR/should-flag.txt" > "$TMP/flag.tsv"
extract "$DIR/should-pass.txt" > "$TMP/pass.tsv"
cut -f1 "$TMP/flag.tsv" > "$TMP/flag.txt"
cut -f1 "$TMP/pass.tsv" > "$TMP/pass.txt"

hits "$TMP/flag.txt" > "$TMP/flag.hits"
hits "$TMP/pass.txt" > "$TMP/pass.hits"

FLAG_TOTAL=$(wc -l < "$TMP/flag.tsv" | tr -d ' ')
PASS_TOTAL=$(wc -l < "$TMP/pass.tsv" | tr -d ' ')
FLAG_HIT=$(cut -f1 "$TMP/flag.hits" | sort -un | wc -l | tr -d ' ')
grep -v '待判' "$TMP/pass.hits" > "$TMP/pass.hard" || true
grep '待判' "$TMP/pass.hits" > "$TMP/pass.warn" || true
PASS_HIT=$(cut -f1 "$TMP/pass.hard" | sort -un | wc -l | tr -d ' ')
PASS_WARN=$(cut -f1 "$TMP/pass.warn" | sort -un | wc -l | tr -d ' ')

RECALL=$(( FLAG_TOTAL ? FLAG_HIT * 100 / FLAG_TOTAL : 0 ))
FPRATE=$(( PASS_TOTAL ? PASS_HIT * 100 / PASS_TOTAL : 0 ))

echo "════ check.pl 回归测试 ════"
echo "召回  ${FLAG_HIT}/${FLAG_TOTAL} = ${RECALL}%   （下限 ${MIN_RECALL}%）"
echo "误报  ${PASS_HIT}/${PASS_TOTAL} = ${FPRATE}%   （上限 ${MAX_FP}%，只算硬命中档）"
[ "${PASS_WARN:-0}" -gt 0 ] && echo "待判  ${PASS_WARN}/${PASS_TOTAL}       （正则分不出，交人判，不计误报）"

# 漏检清单：该抓没抓到的
echo
echo "── 漏检（该抓没抓到）──"
MISS=0
while IFS=$'\t' read -r sent rule; do
  MISS=$((MISS+1))
  n=$MISS
  if ! cut -f1 "$TMP/flag.hits" | grep -qx "$n"; then
    printf '  漏 [%s] %s\n' "$rule" "$sent"
  fi
done < "$TMP/flag.tsv"
[ "$FLAG_HIT" -eq "$FLAG_TOTAL" ] && echo "  （无）"

# 规则错配：抓到了但命中的不是期望那条
echo
echo "── 规则错配（抓到了，但命中的不是期望规则）──"
MIS=0; i=0
while IFS=$'\t' read -r sent rule; do
  i=$((i+1))
  got=$(awk -F'\t' -v n="$i" '$1==n{print $2}' "$TMP/flag.hits" | paste -sd, -)
  if [ -n "$got" ] && [ -n "$rule" ] && ! echo "$got" | grep -q "$rule"; then
    MIS=$((MIS+1)); printf '  期望[%s] 实际[%s] %s\n' "$rule" "$got" "$sent"
  fi
done < "$TMP/flag.tsv"
[ "$MIS" -eq 0 ] && echo "  （无）"

# 误报清单：不该抓却抓了的
echo
echo "── 误报（不该抓却抓了）──"
if [ "$PASS_HIT" -eq 0 ]; then echo "  （无）"; else
  i=0
  while IFS=$'\t' read -r sent _; do
    i=$((i+1))
    got=$(awk -F'\t' -v n="$i" '$1==n{print $2}' "$TMP/pass.hard" | paste -sd, -)
    [ -n "$got" ] && printf '  误 [%s] %s\n' "$got" "$sent"
  done < "$TMP/pass.tsv"
fi

# 结构性检查：代码块与行内代码不是给人读的散文，不该进检测
echo
echo "── 结构性（代码块跳过）──"
STRUCT_FAIL=0
STRUCT_OUT=$(perl "$CHECK" "$DIR/fixtures/codeblock.md" 2>/dev/null || true)
if echo "$STRUCT_OUT" | grep -q '否定-转折'; then
  echo "$STRUCT_OUT" | grep -E '^  L[0-9]+:' | sed 's/^/  被误查: /'
  STRUCT_FAIL=1
else
  echo "  （无）"
fi

echo
if [ "$STRUCT_FAIL" -eq 0 ] && [ "$RECALL" -ge "$MIN_RECALL" ] && [ "$FPRATE" -le "$MAX_FP" ]; then
  echo "结论：达标"; exit 0
else
  echo "结论：未达标（召回 ${RECALL}% / 误报 ${FPRATE}% / 结构性失败 ${STRUCT_FAIL}）"; exit 1
fi
