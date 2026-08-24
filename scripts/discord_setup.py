#!/usr/bin/env python3
"""
디스코드 서버 구성 — 채널·권한·고정 메시지·자동조정을 한 번에 만듭니다.

이 스크립트가 존재하는 이유는 편의가 아니라 **재현성**입니다.
서버 설정이 코드로 남으면 「채널도 문서다」(CLAUDE.md)가 코드 수준에서 지켜지고,
설정이 바뀔 때마다 커밋에 이유가 남습니다.

  - 외부 라이브러리를 쓰지 않습니다 (표준 라이브러리만)
  - 여러 번 돌려도 안전합니다 (이미 있으면 건너뜁니다)
  - 봇 토큰은 .env 에서만 읽습니다. 인자로 받지 않습니다

문안의 원본은 docs/CHANNELS.md 입니다.
여기와 그 문서가 달라지면 그것도 「공지와 코드가 다른」 상태입니다.

실행:
  python scripts/discord_setup.py          # 무엇을 할지 보여주기만 함
  python scripts/discord_setup.py --apply  # 실제로 적용
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

API = "https://discord.com/api/v10"
GH = "https://github.com/Yumi-Token/yumi"

# ─── .env 에서 읽는 값 ────────────────────────────────────
#   DISCORD_BOT_TOKEN  봇 토큰. 개인키처럼 다루세요
#   DISCORD_GUILD_ID   서버 ID (디스코드에서 서버 우클릭 → 서버 ID 복사)


def load_env(path=".env"):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^([A-Z_]+)=(.*)$", line.rstrip("\n"))
            if m:
                out[m.group(1)] = m.group(2).strip()
    return out


def api(method, path, token, body=None):
    """디스코드 API 호출. 레이트리밋이 걸리면 기다렸다 다시 보냅니다."""
    url = API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bot {token}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "yumi-setup (https://github.com/Yumi-Token/yumi, 1.0)")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        if e.code == 429:
            wait = json.loads(raw).get("retry_after", 2)
            print(f"    레이트리밋 — {wait}초 대기")
            time.sleep(float(wait) + 0.5)
            return api(method, path, token, body)
        raise SystemExit(f"\n[{method} {path}] HTTP {e.code}\n{raw}\n")


# ─── 만들 것 ──────────────────────────────────────────────
# 채널은 셋뿐입니다. 늘리지 마세요 —
# 멤버 0명인데 채널이 많으면 죽은 프로젝트로 보이고,
# 관리 부담이 늘면 주간 기록을 밀어냅니다. (D-017 과 같은 논리)

SEND_MESSAGES = 1 << 11  # 메시지 보내기 권한 비트

CHANNELS = [
    {
        "name": "시작하기",
        "topic": "여기가 무엇인지. 먼저 읽어주세요. (읽기 전용)",
        "readonly": True,
    },
    {
        "name": "기록",
        "topic": "주간 기록. 발행 순서대로 쌓입니다. 여기서는 대화하지 않습니다 → #잡담",
        "readonly": True,
    },
    {
        "name": "잡담",
        "topic": "아무거나. 다만 가격·수익·상장 얘기는 답하지 않습니다 → #시작하기",
        "readonly": False,
    },
]

# ─── 역할 ────────────────────────────────────────────────
# 역할은 둘뿐이고, 둘 다 **신원 표시**가 목적입니다.
#
# 누가 DM으로 "운영자입니다"라고 해도 멤버 목록에 역할이 없으면 바로 들통납니다.
# 「공식 주소는 저장소 한 곳에만」과 같은 원리 — 진짜인지 한 곳에서만 확인되게 합니다.
#
# 보유량 등급(🐋/🦐)을 여기 추가하지 마세요.
# 등급표가 곧 「더 사라」는 신호가 되고, 누가 큰 홀더인지 공개되어
# 그 사람이 피싱 표적이 됩니다. #잡담에 지갑 주소를 못 쓰게 막아놓고
# 잔액 등급을 멤버 목록에 띄우면 앞뒤가 맞지 않습니다. (D-028)

ADMINISTRATOR = 1 << 3
MANAGE_MESSAGES = 1 << 13
MANAGE_THREADS = 1 << 34
MODERATE_MEMBERS = 1 << 40  # 타임아웃

ROLES = [
    {
        "name": "발행자",
        "color": 0xE07A5F,
        "permissions": ADMINISTRATOR,
        "note": "사용자 본인. 한 명뿐입니다",
    },
    {
        "name": "운영진",
        "color": 0x81B29A,
        # 추방·차단은 넣지 않습니다. 되돌리기 어려운 것은 발행자가 합니다.
        "permissions": MANAGE_MESSAGES | MANAGE_THREADS | MODERATE_MEMBERS,
        "note": "지금은 0명. 자리만 만들어 둡니다",
    },
]

MSG_START = [
    f"""# 여기가 무엇인지

1인이 코인 하나를 만들어가는 과정을 **매주 공개 기록**으로 남기는 곳입니다.
기록이 주(主)이고 토큰은 종(從)입니다. 기록은 무료이고, 토큰이 없어도 전부 볼 수 있습니다.

**약속은 하나뿐입니다 — 멈추지 않는 것.**

8주 연속 확인 가능한 기록이 없으면 종료합니다. 예외 조항은 없습니다.
판정은 제가 하지 않습니다. 매주 기록의 해시를 체인에 남기고,
마지막 트랜잭션이 8주 이상 전이면 누가 봐도 종료입니다.

**7일은 자물쇠가 아니라 경보기입니다.** 못 열게 막는 게 아니라
열리기 전에 반드시 소리가 나게 하는 장치입니다.""",
    f"""## ⚠️ 먼저 읽어주세요

**1) 메인넷 토큰은 아직 없습니다.**
지금 있는 것은 **테스트넷(Base Sepolia) 컨트랙트뿐**이고 아무 가치가 없습니다.
주소는 전부 공개돼 있습니다 → {GH}/blob/main/docs/WALLETS.md

어디선가 「유미 코인」이라며 주소를 건네는 사람이 있다면 **전부 사칭입니다.**
메인넷에 올리면 여기와 저장소에 동시에 올립니다. 그 전에는 어떤 주소도 공식이 아닙니다.

**2) 심볼은 신원이 아닙니다. 주소가 신원입니다.**
`YUMI`라는 심볼은 이미 다른 체인에 여러 개 있습니다. 누구나 같은 심볼로
토큰을 만들 수 있고, 등록소 같은 건 존재하지 않습니다.
**공식 주소는 저장소 한 곳에만 올립니다.** DM·검색 결과·다른 사이트에서 받은 주소는 믿지 마세요.

**3) 사전 판매를 하지 않습니다.**
개별 판매 요청은 받지 않습니다. **예외 없습니다.**
사고 싶은데 방법을 모르시겠다면 **방법은 얼마든지 도와드립니다.**
다만 제가 돈을 받고 토큰을 보내드리는 일은 하지 않습니다.

**4) 제가 여러분의 지갑에 접근할 일은 절대 없습니다.**
시드 문구·개인키·비밀번호를 묻는 사람은 **전부 사기입니다. 저를 사칭해도 마찬가지입니다.**""",
    f"""## 이 채널에서 하지 않는 것

· **가격 얘기** — 얼마까지 오를지, 언제 사야 할지는 여기서 다루지 않습니다
· **수익 약속** — 수익률·원금·「N배」 같은 말은 쓰지 않습니다
· **상장 얘기** — 계획도 예정도 말하지 않습니다
· **날짜가 박힌 로드맵** — 지키지 못한 계획은 나중에 불리한 기록이 됩니다

가격 얘기를 하시는 분을 막지는 않지만 **제가 답하지는 않습니다.**
그리고 수익을 약속하는 글은 지웁니다 — 제가 쓴 게 아니어도요.

## 대신 여기서 하는 것

· 이번 주에 **뭘 했고 뭐가 안 됐는지**
· 틀린 계산, 잘못 쓴 문서, 되돌린 결정
· 숫자와 주소 — **누구나 직접 확인할 수 있는 것들**

**실패 기록이 이 프로젝트에서 가장 값진 콘텐츠입니다.**
성공담은 지어낼 수 있지만 구체적인 실패는 겪어야만 씁니다.

## 제가 가진 물량과 움직일 수 있는 범위

숨기지 않습니다. 전부 문서에 있습니다.

· **예고 없이 움직일 수 있는 양은 총량의 1%**이고 시간이 지나도 그대로입니다
· 그 1%가 시장에서 어떤 크기인지는 **직접 계산하실 수 있게** 해뒀습니다 —
  수량(1,000,000)과 초기 유동성 구간표가 전부 공개돼 있습니다.
  제 계산을 믿는 것보다 그쪽이 낫습니다
· 나머지는 전부 **7일 사전 예약**을 거칩니다. 무엇을 하든 7일 전에 보입니다
· 테스트넷에서 이미 확인했습니다 — 베스팅 수령 주소가 타임락인지,
  배포 지갑에 예약 권한이 없는지. 주소로 직접 보실 수 있습니다

## 링크

· 약속과 안 하는 약속 → {GH}/blob/main/PROMISE.md
· 배분과 근거 → {GH}/blob/main/docs/TOKENOMICS.md
· 결정 기록 → {GH}/blob/main/docs/DECISIONS.md
· 주소 목록 → {GH}/blob/main/docs/WALLETS.md
· 주간 기록 → {GH}/tree/main/log""",
]

MSG_LOG = [
    f"""아직 발행된 기록이 없습니다.
첫 기록이 올라가면 여기에 링크와 앵커 트랜잭션이 함께 올라옵니다.

앵커 목록 → {GH}/blob/main/log/ANCHORS.md"""
]

# ─── 자동조정 ─────────────────────────────────────────────
# 크립토 서버에는 사기 봇이 반드시 옵니다. 손으로 막을 수 없습니다.
# 세 번째 규칙이 핵심 — 채널에 지갑 주소를 아무도 못 쓰게 합니다.
# 공식 주소는 저장소 한 곳에만 있다는 규칙과 정확히 맞습니다.

AUTOMOD = [
    {
        "name": "지갑 주소 차단",
        "event_type": 1,
        "trigger_type": 1,
        "trigger_metadata": {
            "regex_patterns": ["0x[a-fA-F0-9]{40}"],
            "allow_list": [],
        },
        "actions": [
            {
                "type": 1,
                "metadata": {
                    "custom_message": "주소는 여기에 올리지 않습니다. 공식 주소는 저장소 한 곳에만 있습니다."
                },
            }
        ],
        "enabled": True,
    },
    {
        "name": "사기 문구 차단",
        "event_type": 1,
        "trigger_type": 1,
        "trigger_metadata": {
            "keyword_filter": [
                "에어드랍",
                "airdrop",
                "claim",
                "민팅",
                "whitelist",
                "화이트리스트",
                "프리세일",
                "presale",
                "1:1 문의",
                "디엠주세요",
                "dm me",
            ],
            "allow_list": [],
        },
        "actions": [
            {
                "type": 1,
                "metadata": {"custom_message": "사기에 자주 쓰이는 문구라 자동 차단됩니다."},
            }
        ],
        "enabled": True,
    },
    {
        "name": "멘션 스팸",
        "event_type": 1,
        "trigger_type": 5,
        "trigger_metadata": {"mention_total_limit": 5},
        "actions": [{"type": 1, "metadata": {"custom_message": "멘션이 너무 많습니다."}}],
        "enabled": True,
    },
]


def main():
    apply = "--apply" in sys.argv
    env = load_env()
    token = env.get("DISCORD_BOT_TOKEN") or os.environ.get("DISCORD_BOT_TOKEN", "")
    guild = env.get("DISCORD_GUILD_ID") or os.environ.get("DISCORD_GUILD_ID", "")

    if not token or not guild:
        raise SystemExit(
            "\n.env 에 두 값이 필요합니다:\n"
            "  DISCORD_BOT_TOKEN=...\n"
            "  DISCORD_GUILD_ID=...\n\n"
            "만드는 법은 docs/CHANNELS.md 「디스코드 봇으로 설정하기」를 보세요.\n"
        )

    me = api("GET", "/users/@me", token)
    g = api("GET", f"/guilds/{guild}", token)
    print(f"\n봇   : {me.get('username')}")
    print(f"서버 : {g.get('name')}  (id {guild})")
    print(f"모드 : {'적용' if apply else '미리보기 — 아무것도 바꾸지 않습니다'}\n")

    everyone = guild  # @everyone 역할 id 는 길드 id 와 같습니다

    # ─ 역할 ─
    have_roles = {r["name"]: r for r in api("GET", f"/guilds/{guild}/roles", token)}
    for spec in ROLES:
        name = spec["name"]
        if name in have_roles:
            print(f"  = @{name} 이미 있음")
            continue
        if not apply:
            print(f"  + @{name} 생성 예정 — {spec['note']}")
            continue
        api(
            "POST",
            f"/guilds/{guild}/roles",
            token,
            {
                "name": name,
                "color": spec["color"],
                "permissions": str(spec["permissions"]),
                "hoist": True,  # 멤버 목록 상단에 따로 표시
                "mentionable": False,  # 멘션 스팸 방지
            },
        )
        print(f"  + @{name} 생성됨")
    print()

    # ─ 채널 ─
    existing = {c["name"]: c for c in api("GET", f"/guilds/{guild}/channels", token)}

    made = {}
    for spec in CHANNELS:
        name = spec["name"]
        if name in existing:
            print(f"  = #{name} 이미 있음")
            made[name] = existing[name]
            continue
        if not apply:
            print(f"  + #{name} 생성 예정 (읽기전용={spec['readonly']})")
            continue
        body = {"name": name, "type": 0, "topic": spec["topic"]}
        if spec["readonly"]:
            body["permission_overwrites"] = [
                {"id": everyone, "type": 0, "deny": str(SEND_MESSAGES)}
            ]
        made[name] = api("POST", f"/guilds/{guild}/channels", token, body)
        print(f"  + #{name} 생성됨")

    def post_and_pin(chan_name, messages):
        ch = made.get(chan_name)
        if not ch:
            # 미리보기라 채널이 아직 없는 경우
            print(f"  + #{chan_name} 생성 후 메시지 {len(messages)}개 게시·고정 예정")
            return

        # 미리보기에서도 실제 상태를 조회합니다.
        # 안 그러면 이미 게시됐는데 「예정」이라고 찍혀 잘못 읽게 됩니다.
        pinned = api("GET", f"/channels/{ch['id']}/pins", token)
        # 디스코드 API 버전에 따라 리스트 또는 {"items": [...]} 로 옵니다
        if isinstance(pinned, dict):
            pinned = pinned.get("items", [])
        n_pinned = len(pinned or [])
        if n_pinned:
            print(f"  = #{chan_name} 고정 메시지 {n_pinned}개 이미 있음 — 건너뜀")
            return
        if not apply:
            print(f"  + #{chan_name} 에 메시지 {len(messages)}개 게시·고정 예정")
            return
        for body in messages:
            m = api("POST", f"/channels/{ch['id']}/messages", token, {"content": body})
            api("PUT", f"/channels/{ch['id']}/pins/{m['id']}", token)
            print(f"  + #{chan_name} 메시지 게시·고정 ({len(body)}자)")
            time.sleep(0.6)

    post_and_pin("시작하기", MSG_START)
    post_and_pin("기록", MSG_LOG)

    have = {r["name"] for r in api("GET", f"/guilds/{guild}/auto-moderation/rules", token)}
    for rule in AUTOMOD:
        if rule["name"] in have:
            print(f"  = 자동조정 「{rule['name']}」 이미 있음")
            continue
        if not apply:
            print(f"  + 자동조정 「{rule['name']}」 생성 예정")
            continue
        api("POST", f"/guilds/{guild}/auto-moderation/rules", token, rule)
        print(f"  + 자동조정 「{rule['name']}」 생성됨")

    print(
        "\n완료.\n"
        if apply
        else "\n미리보기였습니다. 실제로 적용하려면 --apply 를 붙이세요.\n"
    )
    print("손으로 해야 하는 것 (API 로 안 되거나 권한이 필요합니다):")
    print("  - 서버 아이콘 : assets/yumi-logo-256.png")
    print("  - 규칙 동의 화면 : 서버 설정 → 커뮤니티 활성화 후 「규칙 심사」")
    print("  - DM 스팸 필터 : 서버 설정 → 안전 설정 → 최고")
    print("  - 초대 링크 : 저장소를 Public 으로 바꾼 뒤에 만드세요\n")


if __name__ == "__main__":
    main()
