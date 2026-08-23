# 프로젝트 이름 미정

> 1인이 AI와 함께 코인을 만들어가는 과정의 공개 기록.
> **약속은 하나뿐입니다 — 멈추지 않는 것.**

---

## 이게 뭔가요

한국 코인은 대부분 멈춰서 죽습니다. 국내 프로젝트 93개를 전수 평가한 결과
우수 등급은 단 2개였고 71개가 C 이하였는데, 지목된 주요 원인이 **개발 활동 중단**이었습니다.

그래서 이 프로젝트는 기술도, 수익도, 상장도 약속하지 않습니다.
**단 하나만 약속하고, 그것이 지켜지는지는 매주 누구나 확인할 수 있습니다.**

- **기록은 무료입니다.** 토큰이 없어도 전부 볼 수 있고, 앞으로도 그렇습니다.
- **토큰은 기록을 사는 것이 아닙니다.** 이 실험에 참여했다는 표식일 뿐이고,
  어떤 수익도 약속하지 않습니다.

---

## 지금 상태

| 항목 | 상태 |
|---|---|
| 컨트랙트 | 작성 완료, 테스트 63개 통과 |
| 테스트넷 배포 | ✅ 2026-08-23 (Base Sepolia) |
| 메인넷 배포 | 아직 |
| 이름·심볼 | **미정** (6주차쯤 확정) |
| 유동성 | 없음 (계획상 한참 뒤) |

---

## 컨트랙트

### `src/Token.sol`

고정 공급 ERC-20. **이 컨트랙트에 없는 것들이 곧 설계입니다.**

| 없는 것 | 의미 |
|---|---|
| `mint` 함수 | 추가 발행을 "안 하는" 게 아니라 **할 수 없습니다** |
| `Ownable` | 소유자 권한이라는 개념 자체가 없습니다 |
| 일시정지·블랙리스트 | 존재하지 않으므로 누구도 전송을 막을 수 없습니다 |
| 전송 수수료 | 표준 그대로. 지갑·DEX 호환성 문제가 없습니다 |
| 커스텀 로직 | 상속한 두 컨트랙트 모두 OpenZeppelin 표준입니다 |

`ERC20Burnable`이 더하는 것은 `burn` / `burnFrom` 두 함수뿐이며,
보유자가 자기 토큰만 소각할 수 있으므로 발행자에게 어떤 권한도 주지 않습니다.

### `src/FounderVesting.sol`

창업자 물량(총량의 20%)을 잠그는 베스팅 지갑. **3개월 클리프 + 12개월 선형**.

OpenZeppelin `VestingWalletCliff` 표준을 그대로 씁니다.
락업을 공지만 하고 코드로 걸지 않는 것은 2026년 5월 국내 밈코인 기소 사유 목록에
"허위 락업 공지로 안전성 가장"으로 명시돼 있습니다.
**이 컨트랙트의 목적은 덤핑 방지이기 이전에 검증 가능성입니다.**

> 참고: 클리프 직후에는 3개월치가 한 번에 열립니다(총량의 약 4.9%).
> 선형 계산의 기준점이 클리프가 아니라 시작 시각이기 때문이며, OpenZeppelin 표준 동작입니다.
> 이 사실은 공개 문서에 반드시 명시해야 합니다.

### 나머지 둘은 새로 짜지 않았습니다

장기 재고와 운영 물량은 **OpenZeppelin 구체 클래스를 배포 스크립트에서 그대로 씁니다.**
래퍼도, 상속도, 커스텀 로직도 없습니다.

| 용도 | 쓰는 것 | 설정 |
|---|---|---|
| 장기 재고 | `VestingWallet` | `start` = 배포 +1년, `duration` = 3년, **클리프 없음** |
| 운영·예비 + LP NFT | `TimelockController` | `minDelay` = 7일, 외부 admin 없음, 실행은 누구나 |

장기 재고에 클리프를 쓰지 않은 이유는 D-008입니다. OpenZeppelin은 선형 계산의
기준점이 클리프가 아니라 `start`라서, 「1년 클리프」로 걸면 1년째에 21,666,666개가
한 번에 열립니다. 그래서 클리프 대신 시작 시각 자체를 1년 뒤로 미뤘습니다.

### 두 베스팅의 수령 주소는 지갑이 아니라 타임락입니다 (D-015)

해제된 물량이 발행자 지갑으로 직행하면 그 순간부터 마찰이 0이고,
「예고 없이 움직일 수 있는 양 1%」는 배포 후 180일짜리 숫자가 됩니다. 10년 뒤에는 86%고요.

수령 주소가 타임락이면 **해제는 잠금을 푸는 것이 아니라 한 칸 앞으로 옮기는 것**이 됩니다.
빼려면 여전히 7일 공개 예약을 거쳐야 합니다.

타임락에 예약을 걸 수 있는 것은 **Safe 2-of-3 멀티시그**입니다. → [`docs/SECURITY.md`](docs/SECURITY.md)

---

## 토크노믹스

총 발행량 **100,000,000** (1억, 18 decimals) 고정. 추가 발행 불가.

**배분과 그 근거는 [`docs/TOKENOMICS.md`](docs/TOKENOMICS.md)가 유일한 출처입니다.**

숫자를 두 곳에 두면 언젠가 반드시 어긋나고, 어긋난 순간 이 프로젝트의 신뢰 자산이 사라집니다.
그래서 여기에는 표를 두지 않습니다.

---

## 시작하기

### 필요한 것

- [Foundry](https://getfoundry.sh) — `curl -L https://foundry.paradigm.xyz | bash` 후 `foundryup`
- 이 프로젝트 **전용** 지갑 (평소 쓰는 지갑 금지)
- [Base Sepolia faucet](https://www.alchemy.com/faucets/base-sepolia) 테스트 ETH
- [Etherscan API 키](https://etherscan.io/myapikey) (무료) — 키 하나로 Base·Base Sepolia 둘 다 됩니다

### 설치

`lib/`는 git 서브모듈입니다. **`--recurse-submodules`를 빼먹으면 빌드가 실패합니다.**

```bash
git clone --recurse-submodules <이 저장소>
cd CoinProject
forge build
forge test
```

이미 서브모듈 없이 받았다면 `git submodule update --init --recursive`.

**63개 테스트가 전부 통과해야 합니다.**
(Token 15 / FounderVesting 13 / Inventory 13 / Deployment 22)

라이브러리는 `forge-std` v1.16.2, `openzeppelin-contracts` **v5.4.0**으로 고정돼 있습니다.
OpenZeppelin 버전을 함부로 올리지 마세요 — `VestingWallet`의 해제 계산이나
`TimelockController`의 역할 구조가 바뀌면 공지한 일정이 조용히 달라집니다.

### 배포 (테스트넷)

```bash
cp .env.example .env
# .env 를 열어 PRIVATE_KEY, ETHERSCAN_API_KEY, SAFE_ADDRESS 를 채웁니다

forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

한 번의 broadcast 안에서 타임락 → 토큰 → 두 베스팅 → 물량 이체까지 끝납니다.
「아직 안 잠긴」 상태가 존재하지 않습니다. (D-004)

배포가 끝나면 출력된 **네 주소를 전부** [`docs/WALLETS.md`](docs/WALLETS.md)에 기록하고,
Basescan에서 **소스 검증이 완료됐는지 반드시 확인**하세요.
검증되지 않은 컨트랙트는 아무도 신뢰하지 않습니다.

### 메인넷 배포 전 체크리스트

- [ ] 이름과 심볼을 확정했다 (**배포 후 변경 불가**)
- [ ] 테스트넷에서 전체 흐름을 최소 한 번 완주했다
- [ ] `docs/TOKENOMICS.md` 의 숫자가 `script/Deploy.s.sol` 의 상수와 일치한다
      (`forge test --match-test DeployScriptUsesTheSameNumbers` 가 통과한다)
- [ ] 두 베스팅의 `owner()` 가 타임락 주소다 (D-015)
- [ ] 타임락에 외부 admin이 없다 (`hasRole(DEFAULT_ADMIN_ROLE, 배포지갑) == false`)
- [ ] 타임락 실행이 열려 있다 (`hasRole(EXECUTOR_ROLE, address(0)) == true`) — 키 분실 시 브릭 방지
- [ ] `SAFE_ADDRESS` 가 Safe 2-of-3 컨트랙트 주소다 (EOA 아님)
- [ ] 배포 키가 이 배포 전용으로 새로 만든 키다
- [ ] 배포 직후 `docs/WALLETS.md` 를 갱신할 준비가 됐다
- [ ] 0주차 기록을 쓸 준비가 됐다

---

## ⚠️ 개인키

이 프로젝트에서 가장 위험한 것은 컨트랙트 코드가 아니라 **키 관리**입니다.

- 평소 쓰는 지갑을 쓰지 마세요. 전용 지갑을 새로 만드세요.
- 테스트넷 키와 메인넷 키를 분리하세요.
- **개인키를 AI 도구·채팅·이슈·스크린샷에 절대 붙여넣지 마세요.**
  제가 물어보더라도 주지 마세요. 정상적인 작업에 필요한 적이 없습니다.
- 메인넷에서는 하드웨어 지갑을 쓰세요.

북한 연계 공격자가 한국 크립토 개발자를 표적 사회공학으로 노립니다.
2025년 전체 탈취액 34억 달러 중 20.2억 달러가 이들 소행으로 추정됩니다.
**개발자 노트북이 Solidity 코드보다 큰 리스크 표면입니다.**

---

## 운영 원칙 세 줄

1. **공지한 것과 코드가 다르지 않게.** 베스팅도, 배포 기준도, 지갑도.
2. **전부 기록으로 남기세요.** 백서 버전, 지갑 주소, 배포 내역, 결정의 이유.
3. **물량을 움직일 땐 먼저 알리고 움직이세요.** 사후 설명보다 사전 공지가 언제나 쌉니다.

---

## 문서

- [`docs/TOKENOMICS.md`](docs/TOKENOMICS.md) — 배분과 근거
- [`docs/WALLETS.md`](docs/WALLETS.md) — 공개 지갑 주소
- [`docs/UTILITY.md`](docs/UTILITY.md) — 왜 지금은 아무 기능도 안 붙이는가
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — 결정 기록
- [`log/`](log/) — 주간 기록

---

## 라이선스

MIT
