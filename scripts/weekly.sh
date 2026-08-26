#!/usr/bin/env bash
#
# 주간 기록 수집기 — 읽기 전용입니다.
#
# 이 스크립트가 하는 일은 **숫자를 모으는 것**뿐입니다.
# 「무슨 뜻인가」는 사람이 씁니다. 게시도 사람이 합니다. (D-033)
#
#   ./scripts/weekly.sh draft                    체인·저장소를 읽어 초안을 만듭니다
#   ./scripts/weekly.sh anchor log/2026-W35.md   검사 후 cast send 명령을 출력합니다
#
# 🔴 이 스크립트는 트랜잭션을 보내지 않습니다.
#    .env 를 읽지 않고, 키·니모닉·키스토어를 참조하지 않습니다.
#    anchor 는 명령을 텍스트로 출력만 하고, 붙여넣어 실행하는 것은 사람입니다.
#    그 3초가 되돌릴 수 없는 행위의 마지막 관문입니다.
#
# 왜 Node 가 아니라 bash + cast 인가 — forge 와 cast 는 이미 있습니다.
# Node 를 붙이면 node_modules 가 생기고, 매주 돌리는 스크립트에 공급망 위험이 붙습니다.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONF="$HERE/weekly.conf"
TEMPLATE="$ROOT/log/_TEMPLATE.md"
UNKNOWN="(확인 필요)"

die() { printf '\n%s\n\n' "$1" >&2; exit 1; }

[ -f "$CONF" ] || die "scripts/weekly.conf 가 없습니다."
# shellcheck disable=SC1090
. "$CONF"

# 값을 못 구하면 추측하지 않고 (확인 필요)로 둡니다.
# 자동화의 실패 방식은 「안 도는 것」이 아니라 「틀린 숫자를 아주 빠르게 반복하는 것」입니다.
try() { "$@" 2>/dev/null || printf '%s' "$UNKNOWN"; }

# wei -> 사람이 읽는 단위. 실패하면 원값을 그대로 둡니다.
human() {
    local v="${1:-}"
    case "$v" in
        ""|"$UNKNOWN") printf '%s' "$UNKNOWN"; return ;;
    esac
    v="${v%% *}"                       # cast 가 붙이는 [1.0e18] 같은 꼬리 제거
    cast from-wei "$v" 2>/dev/null || printf '%s' "$v"
}

call() { try cast call "$@" --rpc-url "$RPC_URL" --block "$BLOCK"; }

# ─────────────────────────────────────────────────────────────
# draft — 체인과 저장소를 읽습니다
# ─────────────────────────────────────────────────────────────
do_draft() {
    local week out
    week="$(date -u +%G-W%V)"          # ISO 주차. 직접 세지 않습니다 (D-026)
    out="$ROOT/log/_draft-$week.md"

    # 사람이 쓴 완성본을 지우는 것이 이 스크립트의 유일한 파괴 경로입니다.
    [ -e "$ROOT/log/$week.md" ] && die "log/$week.md 가 이미 있습니다. 초안을 만들지 않았습니다."
    [ -f "$TEMPLATE" ] || die "log/_TEMPLATE.md 가 없습니다."
    grep -q 'AUTO:START' "$TEMPLATE" || die "log/_TEMPLATE.md 에 <!-- AUTO:START --> 마커가 없습니다."

    # 기준 블록을 먼저 고정합니다. 항목마다 다른 블록을 읽으면 숫자끼리 어긋납니다.
    BLOCK="$(cast block-number --rpc-url "$RPC_URL")" || die "RPC 에 연결하지 못했습니다: $RPC_URL"
    local btime bstamp
    bstamp="$(try cast block "$BLOCK" --field timestamp --rpc-url "$RPC_URL")"
    btime="$(date -u -d "@${bstamp}" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || printf '%s' "$UNKNOWN")"

    local week_blocks from_block
    week_blocks=$(( 7 * 24 * 3600 / 2 ))          # Base 는 2초 블록
    from_block=$(( BLOCK > week_blocks ? BLOCK - week_blocks : 0 ))

    printf '기준 블록 %s (%s) · %s 에서 읽는 중...\n' "$BLOCK" "$btime" "$NETWORK" >&2

    # ① 토큰
    local supply burned
    supply="$(human "$(call "$TOKEN" 'totalSupply()(uint256)')")"
    burned="$(human "$(call "$TOKEN" 'balanceOf(address)(uint256)' 0x000000000000000000000000000000000000dEaD)")"

    # ② 베스팅 둘 — owner() 를 매주 눈에 보이는 자리에 둡니다.
    #    D-021 종료 절차가 발동하면 이 값이 0x…dEaD 가 됩니다.
    local f_bal f_rel f_own i_bal i_rel i_own
    f_bal="$(human "$(call "$TOKEN" 'balanceOf(address)(uint256)' "$FOUNDER_VESTING")")"
    f_rel="$(human "$(call "$FOUNDER_VESTING" 'releasable(address)(uint256)' "$TOKEN")")"
    f_own="$(call "$FOUNDER_VESTING" 'owner()(address)')"
    i_bal="$(human "$(call "$TOKEN" 'balanceOf(address)(uint256)' "$INVENTORY_VESTING")")"
    i_rel="$(human "$(call "$INVENTORY_VESTING" 'releasable(address)(uint256)' "$TOKEN")")"
    i_own="$(call "$INVENTORY_VESTING" 'owner()(address)')"

    # ③ 근거리 물량
    local safe_bal trea_bal tl_bal
    safe_bal="$(human "$(call "$TOKEN" 'balanceOf(address)(uint256)' "$SAFE")")"
    trea_bal="$(human "$(call "$TOKEN" 'balanceOf(address)(uint256)' "$TREASURY")")"
    tl_bal="$(human "$(call "$TOKEN" 'balanceOf(address)(uint256)' "$TIMELOCK")")"

    # ④ 타임락 — 이번 주에 생긴 일
    local sig_sched sig_exec sig_canc n_sched n_exec n_canc pending
    sig_sched='CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)'
    sig_exec='CallExecuted(bytes32,uint256,address,uint256,bytes)'
    sig_canc='Cancelled(bytes32)'
    n_sched="$(count_logs "$sig_sched" "$from_block")"
    n_exec="$(count_logs "$sig_exec" "$from_block")"
    n_canc="$(count_logs "$sig_canc" "$from_block")"

    # 살아 있는 예약을 매주 눈에 띄게 하는 것이 이 항목의 존재 이유입니다 (D-024).
    # 실행이 revert 해도 작업은 Ready 로 남고 executors=address(0) 이라 누구든 실행할 수 있습니다.
    pending=""
    local id ts
    for id in $(scheduled_ids "$sig_sched" "$from_block"); do
        ts="$(call "$TIMELOCK" 'getTimestamp(bytes32)(uint256)' "$id")"
        ts="${ts%% *}"
        case "$ts" in
            0|1|"$UNKNOWN") ;;                       # 0=없음 1=실행완료
            *) pending="${pending}
- 🔴 살아 있는 예약 \`${id:0:18}…\` — 실행 가능 시각 $(date -u -d "@$ts" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || printf '%s' "$ts")" ;;
        esac
    done

    # ⑤ 풀 — POOL 이 비어 있으면 절 전체를 건너뜁니다
    local pool_block=""
    if [ -n "${POOL:-}" ] && [ -n "${USDC:-}" ]; then
        local wall
        wall="$(call "$USDC" 'balanceOf(address)(uint256)' "$POOL")"
        pool_block="
### 풀

- 풀의 USDC 잔고(매수벽): **${wall%% *}** (6 decimals)
- 풀 주소: [\`$POOL\`]($EXPLORER/address/$POOL)

> 이 값에는 **미수령 수수료가 포함**되고, 다른 사람이 유동성을 넣으면
> **그 사람 몫도 포함**됩니다. 정확히 「우리 매수벽」은 아닙니다."
    fi

    # ⑥ 저장소
    local commits diffstat tests
    commits="$(cd "$ROOT" && git log --since='7 days ago' --oneline 2>/dev/null | wc -l | tr -d ' ')"
    diffstat="$(cd "$ROOT" && git diff --shortstat '@{7 days ago}' HEAD -- . ':!log/' 2>/dev/null || printf '%s' "$UNKNOWN")"
    tests="$(cd "$ROOT" && forge test 2>/dev/null | grep -oE '[0-9]+ tests passed' | tail -1 || true)"
    [ -n "$tests" ] || tests="$UNKNOWN"

    # 제목의 「N번째 기록」 — log/ 안의 20??-W??.md 개수 + 1
    local n
    n=$(( $(ls "$ROOT"/log/[0-9][0-9][0-9][0-9]-W[0-9][0-9].md 2>/dev/null | wc -l | tr -d ' ') + 1 ))

    local auto
    auto="$(cat <<EOF
$pending

### 체인 (기준 블록 $BLOCK · $btime)

| | |
|---|---|
| 총 발행량 | $supply |
| 소각 주소 잔고 | $burned |
| 창업자 베스팅 잔고 / 해제 가능 | $f_bal / $f_rel |
| 창업자 베스팅 \`owner()\` | \`$f_own\` |
| 장기 재고 잔고 / 해제 가능 | $i_bal / $i_rel |
| 장기 재고 \`owner()\` | \`$i_own\` |
| 타임락 잔고 | $tl_bal |
| Safe 잔고 | $safe_bal |
| 트레저리 잔고 | $trea_bal |

**타임락 이벤트 (최근 7일 = $week_blocks 블록)** — 예약 $n_sched · 실행 $n_exec · 취소 $n_canc
$pool_block

### 저장소

| | |
|---|---|
| 커밋 (7일) | $commits |
| 변경 | ${diffstat:-없음} |
| 테스트 | $tests |

### 모으지 않는 것 — 직접 보셔야 합니다

- 홀더 수: $UNKNOWN → $EXPLORER/token/$TOKEN#balances
- 누적 거래량: $UNKNOWN — 집계 기준이 여러 개라 스크립트가 고르면 그게 곧 왜곡입니다
- 채널 반응: $UNKNOWN — API 키가 필요합니다. 매주 도는 스크립트에 키를 붙이지 않습니다
EOF
)"

    # 템플릿을 그대로 복사하고 AUTO 마커 사이만 바꿉니다.
    # 템플릿의 다른 부분은 한 글자도 건드리지 않습니다.
    awk -v repl="$auto" '
        /AUTO:START/ { print; print repl; skip = 1; next }
        /AUTO:END/   { skip = 0 }
        !skip        { print }
    ' "$TEMPLATE" > "$out.tmp"

    {
        printf '> ⚠️ **자동 수집 초안입니다. 이대로 올리지 마세요.**\n'
        printf '> 채워진 것은 「일어난 일」뿐이고, **「무슨 뜻인가」는 비어 있습니다.**\n'
        printf '> 기준: 블록 %s (%s) · 네트워크 %s\n' "$BLOCK" "$btime" "$NETWORK"
        printf '> 마무리하면 `log/%s.md` 로 이름을 바꾸고 이 줄을 지우세요.\n\n' "$week"
        sed "1s|^# .*|# 기록 #$n — (한 줄 제목)|" "$out.tmp"
    } > "$out"
    rm -f "$out.tmp"

    printf '\n초안을 만들었습니다: log/_draft-%s.md\n' "$week"
    printf '이제 「안 된 것」과 「무슨 뜻인가」를 직접 쓰세요. 여기가 본 작업입니다.\n\n'
}

# cast logs 출력에서 이벤트 개수를 셉니다. 못 세면 (확인 필요).
count_logs() {
    local sig="$1" from="$2" n
    n="$(cast logs "$sig" --address "$TIMELOCK" --from-block "$from" --to-block "$BLOCK" \
         --rpc-url "$RPC_URL" 2>/dev/null | grep -c '^- address' || true)"
    [ -n "$n" ] && printf '%s' "$n" || printf '%s' "$UNKNOWN"
}

# CallScheduled 로그의 두 번째 topic(=id)만 뽑습니다.
scheduled_ids() {
    local sig="$1" from="$2"
    cast logs "$sig" --address "$TIMELOCK" --from-block "$from" --to-block "$BLOCK" \
        --rpc-url "$RPC_URL" 2>/dev/null \
    | awk '
        /topics:/ { inside = 1; n = 0; next }
        inside && /0x[0-9a-fA-F]{64}/ {
            n++
            if (n == 2) { match($0, /0x[0-9a-fA-F]{64}/); print substr($0, RSTART, RLENGTH) }
        }
        /\]/ { inside = 0 }
    ' || true
}

# REQUIRED 마커가 있는 절의 본문. HTML 주석은 내용으로 치지 않습니다 —
# 템플릿의 안내 주석을 그대로 둔 것을 「썼다」고 세면 관문이 뚫립니다.
required_body() {
    awk '
        /<!-- REQUIRED -->/ { on = 1; next }
        on && /^#{2,3} /    { exit }
        on                  { print }
    ' "$1" 2>/dev/null | sed '/<!--/,/-->/d' | tr -d '[:space:]'
}

# ─────────────────────────────────────────────────────────────
# anchor — 관문입니다. 하나라도 걸리면 명령을 출력하지 않습니다.
# ─────────────────────────────────────────────────────────────
do_anchor() {
    local file="${1:-}"
    [ -n "$file" ] || die "사용법: ./scripts/weekly.sh anchor log/2026-W35.md"
    [ -f "$file" ] || die "파일이 없습니다: $file"

    case "$(basename "$file")" in
        _draft-*) die "초안 파일입니다. log/<ISO주차>.md 로 이름을 바꾼 뒤에 다시 실행하세요." ;;
    esac

    grep -q '자동 수집 초안입니다' "$file" && \
        die "맨 위의 「⚠️ 자동 수집 초안입니다」 줄이 아직 남아 있습니다. 지우고 다시 실행하세요."

    grep -q '<!-- REQUIRED -->' "$file" || \
        die "<!-- REQUIRED --> 마커가 없습니다. log/_TEMPLATE.md 에서 복사해 오세요."

    # REQUIRED 마커가 있는 절의 내용을 봅니다. 절 이름을 스크립트에 박지 않습니다 —
    # 템플릿에서 마커를 옮기면 검사 대상도 따라 옮겨집니다.
    local section body
    section="$(grep -B5 '<!-- REQUIRED -->' "$file" | grep -E '^#{2,3} ' | tail -1)"
    section="${section:-(REQUIRED 절)}"
    body="$(required_body "$file")"

    if [ "${#body}" -lt 20 ]; then
        die "「${section#\#\# }」이 비어 있습니다.

이 칸은 스크립트가 채울 수 없습니다. 이번 주에 아무것도 못 했으면
「이번 주는 아무것도 못 했다, 이유는 이거다」라고 쓰셔도 됩니다. 그것도 기록입니다.
비워둔 채로는 앵커 명령이 나오지 않습니다."
    fi

    # 자리표시자를 그대로 둔 채 발행하는 것을 막습니다.
    local tbody
    tbody="$(required_body "$TEMPLATE")"
    if [ -n "$tbody" ] && [ "$body" = "$tbody" ]; then
        die "「${section#\#\# }」가 템플릿 문구 그대로입니다. 직접 쓰신 내용이 필요합니다."
    fi

    if grep -q '(확인 필요)' "$file"; then
        printf '\n⚠️ %s 에 「(확인 필요)」가 남아 있습니다. 그대로 올리셔도 되지만 한 번 보세요.\n' "$file" >&2
    fi

    # 앵커는 Base 메인넷에만 남깁니다. 테스트넷 앵커는 판정에 들어가지 않고,
    # 테스트넷이 종료되면 근거가 함께 사라집니다 (docs/RECORD.md).
    # 막지는 않습니다 — 리허설은 정당한 용도입니다. 다만 조용히 지나가지 않게 합니다.
    case "$RPC_URL" in
        *sepolia*|*goerli*|*127.0.0.1*|*localhost*)
            printf '\n🔴 지금 RPC 는 테스트넷입니다 — %s\n' "$RPC_URL" >&2
            printf '   이대로 보내면 판정에 들어가지 않습니다. 리허설이면 그대로 진행하세요.\n' >&2
            printf '   본 발행이면 scripts/weekly.conf 의 NETWORK·RPC_URL·EXPLORER 를 먼저 바꾸세요.\n' >&2
            ;;
    esac

    local hash data
    # 파일명이 아니라 내용을 파이프로 넘깁니다.
    # 경로에 역슬래시가 있으면 sha256sum 이 줄 앞에 \ 를 붙여 이스케이프하고,
    # 그걸 그대로 잘라 쓰면 해시가 「\<hash>」가 됩니다. 실제로 그렇게 나왔습니다.
    hash="$(sha256sum < "$file" | cut -d' ' -f1)"
    data="$(cast from-utf8 "LOG $(basename "$file") sha256:$hash")"

    cat <<EOF

────────────────────────────────────────────
sha256  $hash

아래를 붙여넣어 직접 실행하세요. 이 스크립트는 실행하지 않습니다.

  cast send $ANCHOR_WALLET $data \\
    --value 0 \\
    --account weekly-anchor \\
    --rpc-url $RPC_URL

⚠️ 지금부터 이 파일을 한 글자도 고치지 마세요. 해시가 달라집니다.
⚠️ --account 로 키스토어를 씁니다. --private-key 를 명령에 넣으면 키가 셸 히스토리에 남습니다.
⚠️ 보내기 전에 확인 — cast wallet address --account weekly-anchor
   그 주소가 위 $ANCHOR_WALLET 과 달라지면 그 주는 판정에 안 들어갑니다. (D-034)

트랜잭션이 확정되면 log/ANCHORS.md 에 아래 줄을 추가하세요.
(기록 파일이 아니라 ANCHORS.md 입니다 — 파일 안에 자기 tx 를 넣으면 해시가
 자기 자신을 가리키게 됩니다. D-026)

  | $(basename "$file" .md) | $hash | [<txhash>]($EXPLORER/tx/<txhash>) |
────────────────────────────────────────────

EOF
}

case "${1:-}" in
    draft)  do_draft ;;
    anchor) shift; do_anchor "${1:-}" ;;
    *)      die "사용법:
  ./scripts/weekly.sh draft                    초안 생성
  ./scripts/weekly.sh anchor log/2026-W35.md   검사 후 앵커 명령 출력" ;;
esac
