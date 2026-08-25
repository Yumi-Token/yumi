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
        "topic": "여기가 무엇인지. 먼저 읽어주세요. (읽기 전용) · Start here — read the pinned messages first. Read-only.",
        "readonly": True,
    },
    {
        "name": "기록",
        "topic": "주간 기록. 발행 순서대로 쌓입니다. 여기서는 대화하지 않습니다 → #잡담 · Weekly records, in order. Read-only — discussion goes to #잡담.",
        "readonly": True,
    },
    {
        "name": "잡담",
        "topic": "아무거나. 다만 가격·수익 얘기는 답하지 않습니다 → #시작하기 · Anything goes, but price and returns questions will not be answered.",
        "readonly": False,
    },
]

# ─── 서버 보안 설정 ──────────────────────────────────────
# 크립토 서버에 오는 사기 봇은 대부분 「막 만든 계정」입니다.
# 가입 후 일정 시간을 요구하는 것만으로 상당수가 걸러집니다.
#
# 여기 없는 것 두 가지는 API 로 안 됩니다 — 아래 「손으로」 안내에 있습니다.
#   · 2단계 인증 요구 (mfa_level) — 서버 소유자만 바꿀 수 있습니다
#   · 커뮤니티 활성화 · 규칙 동의 화면

GUILD_SETTINGS = {
    # 3 = 높음: 서버에 가입하고 10분이 지나야 글을 쓸 수 있습니다.
    #     4(전화 인증)는 정상 이용자도 많이 막혀 쓰지 않습니다.
    "verification_level": 3,
    # 2 = 모든 멤버의 미디어를 검사합니다. 역할 유무로 봐주지 않습니다.
    "explicit_content_filter": 2,
    # 1 = 멘션만 알림. 기본값(모든 메시지)이면 사람들이 알림 때문에 나갑니다.
    "default_message_notifications": 1,
}

LEVEL_NAME = {0: "없음", 1: "낮음", 2: "보통", 3: "높음", 4: "매우 높음"}

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
· **날짜가 박힌 로드맵** — 지키지 못한 계획은 나중에 불리한 기록이 됩니다
· **정해지지 않은 것을 정해진 것처럼 말하는 것** — 무엇에 대해서든

**다만 확정된 사실은 알립니다.** 정해지지 않은 것을 정해진 것처럼 말하지 않겠다는 뜻이지,
이미 일어난 일을 숨기겠다는 뜻이 아닙니다. 홀더가 알아야 할 일이 확정되면 그대로 알립니다.
숨기는 것도 정직하지 않습니다.

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

# 영문 병기.
# 번역이 아니라 **같은 내용을 영어로 다시 쓴 것**입니다 — 한글본이 원본이고,
# 둘이 어긋나면 그것도 「공지와 코드가 다른」 상태입니다.
#
# 영어가 봇을 막지는 않습니다. 막는 것은 자동조정과 인증 수준입니다.
# 다만 영어권 방문자가 규칙을 못 읽어서 어기는 경우를 없애고,
# 사기 경고를 못 읽는 사람이 없게 합니다. 크립토 서버 방문자의 상당수가 영어권입니다.

MSG_START_EN = [
    f"""# What this is  ·  English

One person building a token in public, with a **verifiable record every week.**
The record is the point; the token comes second. **The record is free** — you can
read all of it without holding anything, and that will not change.

**There is one promise, and only one: I will not stop.**

If eight consecutive weeks pass with no verifiable record, the project ends.
No exceptions, and I don't get to be the judge — each week the record's SHA-256
hash goes on-chain. If the last one is over eight weeks old, it is over.

**The 7-day timelock is not a lock. It is an alarm.** It does not stop things
from moving; it makes sure a noise happens first.

## Not discussed here

· **Price** — how high, when to buy. Not here.
· **Returns** — no yield, no principal, no "N×".
· **Roadmaps with dates** — a missed plan becomes evidence against you later.
· **Anything undecided, stated as if it were decided.**

**Settled facts are still announced.** The rule is that I won't state undecided
things as if they were decided — not that I'll hide what already happened.
Hiding it would be its own kind of dishonesty.

You are not stopped from talking about price. **I just won't answer.**
Posts promising returns get removed — including mine.

## Discussed here instead

· What I did this week, and **what failed**
· Wrong math, bad docs, decisions I reversed
· Numbers and addresses — **things you can check yourself**

**Failure records are the most valuable thing here.** Success stories can be
invented; specific failures have to be lived.

## Links

· The promise, and what is not promised → {GH}/blob/main/PROMISE.md
· Allocation and reasoning → {GH}/blob/main/docs/TOKENOMICS.md
· Decision log → {GH}/blob/main/docs/DECISIONS.md
· Every address → {GH}/blob/main/docs/WALLETS.md
· Weekly records → {GH}/tree/main/log""",
    f"""## ⚠️ Read this before anything else

**1) There is no mainnet token yet.**
What exists today is a **testnet (Base Sepolia) contract** with no value at all.
Every address is public → {GH}/blob/main/docs/WALLETS.md

If anyone hands you an address for "Yumi", **it is a scam.** When a mainnet token
exists, it goes here and in the repository at the same time. Until then, no
address is official.

**2) A ticker is not an identity. The contract address is.**
`YUMI` already exists on other chains. Anyone can deploy a token with any symbol,
and no registry exists to prevent it.
**The official address lives in exactly one place — the repository.**
Never trust an address from a DM, a search result, or any other site.

**3) There is no presale, and no private sale. No exceptions.**
If you want to buy and don't know how, **I am glad to explain how.**
I will not take your money and send you tokens.

**4) I will never need access to your wallet.**
Anyone asking for your seed phrase, private key, or password is **a scammer —
including if they are pretending to be me.** I will never ask, and neither will
any bot in this server.""",
]

MSG_LOG_EN = [
    f"""*(English)* No record has been published yet. When the first one goes up,
the link and its anchoring transaction appear here together.

Anchor list → {GH}/blob/main/log/ANCHORS.md"""
]

MSG_LOG = [
    f"""아직 발행된 기록이 없습니다.
첫 기록이 올라가면 여기에 링크와 앵커 트랜잭션이 함께 올라옵니다.

앵커 목록 → {GH}/blob/main/log/ANCHORS.md"""
]

# ─── 커뮤니티 활성화 ─────────────────────────────────────
# 켜면 「멤버십 심사」(규칙에 동의해야 참여) 와 습격 보호를 쓸 수 있습니다.
# 사기 봇 상당수가 규칙 동의 화면에서 걸립니다.
#
# 디스코드가 채널 두 개를 요구합니다 — 규칙 채널과 운영 알림 채널.
# 규칙 채널은 #시작하기 를 그대로 씁니다.
# 운영 알림 채널은 디스코드가 공지를 보내는 곳이라 새로 만들어야 하지만,
# @everyone 에게서 숨겨두므로 방문자에게 보이는 채널은 여전히 셋뿐입니다.

VIEW_CHANNEL = 1 << 10

MOD_CHANNEL = {
    "name": "운영-알림",
    "topic": "디스코드가 서버 운영자에게 보내는 공지. 멤버에게는 보이지 않습니다.",
}

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


MAX_LEN = 2000  # 디스코드 메시지 길이 제한


def check_lengths():
    """문안이 길이 제한을 넘으면 서버에 손대기 전에 멈춥니다.

    영문본을 붙이다가 실제로 넘겨서 PATCH 가 HTTP 400 으로 죽었습니다.
    적용 도중에 죽으면 일부만 반영된 상태로 남습니다.
    """
    bad = [
        (m.splitlines()[0][:40], len(m))
        for group in (MSG_START, MSG_START_EN, MSG_LOG, MSG_LOG_EN)
        for m in group
        if len(m) > MAX_LEN
    ]
    if bad:
        lines = [f"  {h} — {n}자 ({n - MAX_LEN}자 초과)" for h, n in bad]
        nl = chr(10)
        raise SystemExit(nl + f"문안이 {MAX_LEN}자 제한을 넘습니다:" + nl + nl.join(lines) + nl)


def main():
    check_lengths()
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

    # ─ 서버 보안 설정 ─
    diff = {k: v for k, v in GUILD_SETTINGS.items() if g.get(k) != v}
    for k, v in GUILD_SETTINGS.items():
        now = g.get(k)
        if now == v:
            print(f"  = {k} 이미 {v}")
        else:
            print(f"  {'+' if apply else '+'} {k}  {now} → {v}")
    if diff and apply:
        api("PATCH", f"/guilds/{guild}", token, diff)
        print("  + 서버 설정 적용됨")
    print()

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
            cur = existing[name]
            made[name] = cur
            if cur.get("topic") != spec["topic"]:
                # 문안을 고쳤는데 서버가 그대로면 그것도 어긋난 상태입니다
                if apply:
                    api("PATCH", f"/channels/{cur['id']}", token, {"topic": spec["topic"]})
                    print(f"  ~ #{name} 설명 갱신됨")
                else:
                    print(f"  ~ #{name} 설명 갱신 예정")
            else:
                print(f"  = #{name} 이미 있음")
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
        """메시지 단위로 판단합니다.

        예전에는 「고정이 하나라도 있으면 전부 건너뜀」이었는데,
        그러면 문안을 하나 추가했을 때 영영 올라가지 않습니다.
        실제로 영문본을 추가하면서 그 문제가 드러났습니다.
        """
        ch = made.get(chan_name)
        if not ch:
            print(f"  + #{chan_name} 생성 후 메시지 {len(messages)}개 게시·고정 예정")
            return

        # 미리보기에서도 실제 상태를 조회합니다.
        # 안 그러면 이미 게시됐는데 「예정」이라고 찍혀 잘못 읽게 됩니다.
        pinned = api("GET", f"/channels/{ch['id']}/pins", token)
        if isinstance(pinned, dict):  # API 버전에 따라 리스트 또는 {"items": [...]}
            pinned = pinned.get("items", [])
        # 고정 목록의 항목은 메시지이거나 {"message": {...}} 입니다
        have = [(x.get("message") or x) for x in (pinned or [])]

        for body in messages:
            head = body.splitlines()[0].strip()  # 첫 줄로 같은 글인지 판별
            old = next(
                (m for m in have if m.get("content", "").lstrip().startswith(head)), None
            )
            if old is None:
                if not apply:
                    print(f"  + #{chan_name} 「{head[:28]}」 게시·고정 예정 ({len(body)}자)")
                    continue
                m = api("POST", f"/channels/{ch['id']}/messages", token, {"content": body})
                api("PUT", f"/channels/{ch['id']}/pins/{m['id']}", token)
                print(f"  + #{chan_name} 「{head[:28]}」 게시·고정 ({len(body)}자)")
                time.sleep(0.6)
            elif old.get("content", "").strip() != body.strip():
                # 문안을 고쳤는데 올라간 글이 그대로면 그것도 어긋난 상태입니다.
                # 다시 올리면 고정이 둘로 늘고 순서가 뒤집히므로 원래 글을 고칩니다.
                if not apply:
                    print(f"  ~ #{chan_name} 「{head[:28]}」 본문 갱신 예정")
                    continue
                api(
                    "PATCH",
                    f"/channels/{ch['id']}/messages/{old['id']}",
                    token,
                    {"content": body},
                )
                print(f"  ~ #{chan_name} 「{head[:28]}」 본문 갱신됨 ({len(body)}자)")
                time.sleep(0.6)
            else:
                print(f"  = #{chan_name} 「{head[:28]}」 이미 있음")

    post_and_pin("시작하기", MSG_START)
    post_and_pin("시작하기", MSG_START_EN)
    post_and_pin("기록", MSG_LOG)
    post_and_pin("기록", MSG_LOG_EN)

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

    # ─ 커뮤니티 활성화 ─
    print()
    feats = list(g.get("features", []))
    if "COMMUNITY" in feats:
        print("  = 커뮤니티 이미 켜짐")
    elif not apply:
        print(f"  + #{MOD_CHANNEL['name']} 생성 예정 (멤버에게 숨김)")
        print("  + 커뮤니티 활성화 예정 — 규칙 채널 #시작하기")
    else:
        chans = api("GET", f"/guilds/{guild}/channels", token)
        mod = next((c for c in chans if c["name"] == MOD_CHANNEL["name"]), None)
        if not mod:
            mod = api(
                "POST",
                f"/guilds/{guild}/channels",
                token,
                {
                    "name": MOD_CHANNEL["name"],
                    "type": 0,
                    "topic": MOD_CHANNEL["topic"],
                    "permission_overwrites": [
                        {"id": everyone, "type": 0, "deny": str(VIEW_CHANNEL)}
                    ],
                },
            )
            print(f"  + #{MOD_CHANNEL['name']} 생성됨 (멤버에게 숨김)")
        api(
            "PATCH",
            f"/guilds/{guild}",
            token,
            {
                "features": feats + ["COMMUNITY"],
                "rules_channel_id": made["시작하기"]["id"],
                "public_updates_channel_id": mod["id"],
            },
        )
        print("  + 커뮤니티 활성화됨 — 규칙 채널 #시작하기")

    print(
        "\n완료.\n"
        if apply
        else "\n미리보기였습니다. 실제로 적용하려면 --apply 를 붙이세요.\n"
    )
    print("손으로 해야 하는 것 (API 로 안 되거나 권한이 필요합니다):")
    print("  - 서버 아이콘 : assets/yumi-logo-256.png")
    print("  - 규칙 동의 화면 : 서버 설정 → 「멤버십 심사」. 문안은 docs/CHANNELS.md 2-0-5")
    print("  - DM 스팸 필터 : 서버 설정 → 안전 설정 → 최고")
    print("  - 초대 링크 : 저장소를 Public 으로 바꾼 뒤에 만드세요\n")


if __name__ == "__main__":
    main()
