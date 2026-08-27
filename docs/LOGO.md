# 로고를 지갑·거래 화면에 띄우는 방법

> **토큰 컨트랙트에는 이미지 필드가 없습니다.** 로고는 체인에 올라가지 않습니다.
> 각 사이트가 **자기 목록을 따로 들고** 있고, 거기에 등록돼야 보입니다.
> 그래서 경로가 여러 갈래이고 **비용과 조건이 전부 다릅니다.**

원본은 [`assets/`](../assets/) 에 있습니다. tight 크롭이 공식입니다.

| 파일 | 크기 | 용도 |
|---|---|---|
| `yumi-logo-256.png` | 256×256 · 84KB | **등록용 표준** (대부분 256px 이하 + 100KB 미만을 요구합니다) |
| `yumi-logo-512.png` | 512×512 · 276KB | 고해상도 원본 |
| `yumi-logo-64.png` | 64×64 · 8.8KB | 작은 자리 |

---

## ① 토큰 리스트 — 우리가 직접 만드는 것

**심사도 비용도 없습니다.** 이 저장소의 [`tokenlist.json`](../tokenlist.json) 이 그것입니다.
[Uniswap Token List](https://tokenlists.org/) 표준을 따릅니다.

```
https://raw.githubusercontent.com/Yumi-Token/yumi/main/tokenlist.json
```

Uniswap 인터페이스에서 이 주소를 **직접 추가**하면 로고와 이름이 뜹니다.
지갑·집계 사이트 중에도 토큰 리스트를 읽는 곳이 있습니다.

🔴 **다만 이건 「기본으로 보인다」가 아닙니다.** 사용자가 목록을 추가해야 보입니다.
Uniswap 기본 목록에 들어가는 것은 별개이고, 그건 우리가 정하지 못합니다.

**숫자를 바꾸면 이 파일도 바꿔야 합니다.** `decimals`·주소·심볼이 온체인과 어긋나면
잘못된 금액이 표시됩니다. `TOKENOMICS.md` ↔ `tokenlist.json` 도 대조 대상입니다.

---

## ② Basescan — 지금 열려 있는 유일한 심사 경로

컨트랙트 **소스 검증이 2026-08-27 에 넷 다 끝났습니다** (`Exact Match`).
배포 때 `Not all (0 / 4) contracts were verified!` 가 떴지만 **큐가 느렸을 뿐**이었습니다.

| 컨트랙트 | 상태 |
|---|---|
| [Token](https://basescan.org/address/0xbDD3f6586093d5ec287d902A2F01A681c8131189#code) | ✅ Exact Match |
| [Timelock](https://basescan.org/address/0x22FB76084160482488a3C8d752a963e4F36594A9#code) | ✅ Exact Match |
| [창업자 베스팅](https://basescan.org/address/0x2bdC70Acbf26162B2bFd300eB2826542EFf4e0bE#code) | ✅ Exact Match |
| [장기 재고 베스팅](https://basescan.org/address/0xe4981c703bA99fC7f8F2db5C8c3096a877c8E13c#code) | ✅ Exact Match |

토큰 페이지의 로고·설명·링크는 **따로 신청**합니다. 순서는 이렇습니다.

```
① basescan.org 계정 만들기
② 주소 소유권 증명 — 배포 지갑으로 메시지 서명
③ Token Update 폼 제출
```

**②가 배포 지갑 키를 남겨둔 이유입니다.** 서명은 트랜잭션이 아니라 가스도 들지 않습니다.

### 소유권 서명 명령

Basescan 이 주는 문자열을 그대로 넣으시면 됩니다. **가스 0, 트랜잭션 아님.**

```
cast wallet sign --account deploy "<Basescan 이 준 메시지>"
```

🔴 **`--private-key` 를 쓰지 마세요.** 셸 기록에 키가 남습니다. `--account` 만 씁니다.

### 폼에 넣을 내용

**약속으로 읽힐 문장을 넣지 않습니다.** 아래는 그 기준으로 미리 쓴 것입니다.

```
Token Contract    0xbDD3f6586093d5ec287d902A2F01A681c8131189
Project Name      Yumi
Website           https://github.com/Yumi-Token/yumi
Logo              assets/yumi-logo-256.png   (256×256 · 84KB)
Token List        https://raw.githubusercontent.com/Yumi-Token/yumi/main/tokenlist.json
```

Description (영문 — Basescan 은 영어로 받습니다):

```
Yumi is a one-person, AI-assisted project on Base that publishes its
build log in public. Its only stated commitment is to keep publishing
verifiable weekly records; if eight consecutive weeks pass without one,
the project declares itself ended.

The token contract is a standard OpenZeppelin ERC20 with no custom code:
no owner, no mint function, no transfer fee, no blacklist, no pause.
Treasury holdings sit behind a 7-day timelock and vesting contracts.

All records, decisions, addresses, and mistakes are public. Records are
free to read and require no token.
```

🔴 **「곧」·「예정」·수익 관련 문구가 한 줄도 없는지 넣기 전에 다시 읽으세요.**
등록 정보는 **우리 문서보다 넓게 퍼지고, 고치는 데 다시 심사가 걸립니다.**

---

## ③ 아직 못 하는 곳 — 조건을 실측했습니다

**「무료니까 일단 넣어보자」가 안 됩니다.** 조건을 재봤더니 **둘 다 한참 미달**입니다.

| 어디 | 요구 | 2026-08-27 현재 |
|---|---|---|
| **Trust Wallet** | 홀더 10,000명 | **6명** |
| **Trust Wallet** | 트랜잭션 15,000건 | **0건** |
| **Trust Wallet** | 「brand new tokens are not accepted」 | 배포 **1일차** |
| **CoinGecko** | 활발히 거래 중일 것 | **거래 0건** |
| **DEX Screener** | 로고 등록이 **유료 상품** | 풀 색인도 아직 |

**셋 다 같은 곳에서 막힙니다 — 아직 아무도 사지 않았습니다.**
풀은 정상이고 견적도 정상이지만 **체결이 0건**이라 집계 사이트가 가격을 계산하지 못합니다.
GeckoTerminal 이 `YUMI / USDC 1%` 를 잡고도 가격이 비어 있는 이유입니다.

🔴 **그래서 지금 넣지 않았습니다.** 반려될 신청을 넣는 것은 **홍보가 아니라 소음**이고,
「우리가 신청했다」는 말이 「곧 올라간다」로 읽히면 그건 약속이 됩니다. (D-036)

**이 표의 숫자는 직접 확인하실 수 있습니다** — 홀더 수는 토큰 페이지에,
체결 건수는 풀 주소의 `Swap` 이벤트에 있습니다.

### 🔴 배포 지갑 키를 버리지 마세요

등록처 일부가 **컨트랙트 배포자임을 증명**하라고 요구합니다 —
그 주소에서 서명하거나 트랜잭션을 보내는 방식입니다.

배포 지갑 [`0x521ECcA9…14d6`](https://basescan.org/address/0x521ECcA9039c2502C4a5d1572D705F53723614d6) 은
**잔고를 비웠지만 키는 남겨둡니다.** 비운 것과 버린 것은 다릅니다.
이 지갑은 **아무 권한도 없어서** 남겨둬도 위험하지 않습니다 — 예약·취소·관리자 전부 없습니다.

---

## 지갑에 직접 추가하실 때

로고가 아직 안 뜨더라도 **잔고는 정상적으로 보입니다.** 주소만 넣으시면 됩니다.

```
네트워크  Base
주소      0xbDD3f6586093d5ec287d902A2F01A681c8131189
심볼      YUMI      소수점  18
```

🔴 **주소를 직접 붙여넣으세요.** 검색으로 고르면 같은 이름의 다른 토큰이 잡힐 수 있습니다. (D-027)
