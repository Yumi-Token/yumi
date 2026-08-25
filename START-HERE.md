# 여기서부터 시작하세요

이 폴더를 사용자님 컴퓨터에 풀고, **그 폴더에서 Claude Code를 열면** 바로 작업이 이어집니다.
`CLAUDE.md`가 같이 들어 있어서 Claude Code가 이 프로젝트의 규칙을 자동으로 읽습니다.

---

## 0. 지금 이 폴더에 들어 있는 것

컨트랙트 2개, 테스트 **64개**, 배포 스크립트 1개, 문서 7개, 0주차 선언문 초안.
**컴파일과 테스트는 이미 통과한 상태**입니다. 배포 스크립트도 로컬에서 끝까지 돌려봤습니다.

트레저리 4분할(창업자 베스팅 / 장기 재고 / 운영 타임락 / 근거리 재고)이
배포 스크립트에 반영돼 있고, **새로 짠 컨트랙트 코드는 0줄**입니다.
장기 재고와 타임락은 OpenZeppelin 구체 클래스를 그대로 `new` 합니다.

빠져 있는 것은 `lib/`(OpenZeppelin, forge-std) 하나뿐입니다.
용량이 커서 뺐고, 아래 2번에서 받습니다.

> **다음에 할 작업은 `docs/HANDOVER.md`에 있습니다.**
> Claude Code에게 "docs/HANDOVER.md 보고 이어서 해줘"라고 하시면 됩니다.

---

## 1. Foundry 설치 (한 번만) — Windows

사용자님 컴퓨터는 Windows입니다. 두 가지 길이 있고, **첫 번째를 권합니다.**

### 방법 A — WSL (권장)

Foundry가 공식으로 지원하는 환경이고, 이 문서의 명령어가 그대로 돌아갑니다.

PowerShell을 **관리자 권한으로** 열고:

```powershell
wsl --install
```

재부팅 후 Ubuntu 터미널에서:

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
forge --version
```

압축 푼 폴더는 WSL 안에서 `/mnt/c/Users/<사용자명>/...` 로 접근됩니다.
**다만 프로젝트 파일은 WSL 홈(`~/`)에 두는 게 훨씬 빠릅니다.** `/mnt/c`는 파일 I/O가 느립니다.

### 방법 B — 네이티브 Windows 바이너리

WSL을 쓰고 싶지 않다면 GitHub 릴리스에서 직접 받습니다.

```powershell
# 다운로드 & 압축 해제
curl.exe -L -o foundry.zip https://github.com/foundry-rs/foundry/releases/download/stable/foundry_stable_win32_amd64.zip
Expand-Archive foundry.zip -DestinationPath "$env:USERPROFILE\.foundry\bin"

# PATH에 추가 (영구)
$p = [Environment]::GetEnvironmentVariable("Path", "User")
if ($p -notlike "*\.foundry\bin*") { [Environment]::SetEnvironmentVariable("Path", "$p;$env:USERPROFILE\.foundry\bin", "User") }
```

> ⚠️ 흔한 실수 두 개를 피하려고 이렇게 씁니다.
>
> `$env:Path`는 **시스템 PATH와 사용자 PATH를 합친 값**입니다.
> 그걸 그대로 사용자 PATH에 쓰면 시스템 항목 전체가 사용자 쪽에 복사됩니다.
> 그래서 `GetEnvironmentVariable(..., "User")`로 **사용자 쪽만** 읽습니다.
>
> 그리고 `-notlike` 검사가 있어서 **두 번 실행해도 중복으로 안 붙습니다.**

새 PowerShell 창을 열고:

```powershell
forge --version
```

이 경우 아래의 `source .env` 같은 bash 문법은 PowerShell 문법으로 바꿔야 합니다.
5번 항목에 따로 적어뒀습니다.

> 참고: 제가 작업한 샌드박스에서는 `foundry.paradigm.xyz`가 막혀 있어서
> 컴파일할 때 `--offline` 플래그를 붙여야 했습니다.
> **사용자님 컴퓨터에서는 필요 없습니다.** 그냥 `forge test`로 쓰세요.

---

## 2. 라이브러리 설치

이 폴더는 이미 git 저장소이고 `lib/`가 서브모듈로 잡혀 있습니다.
그러니 대개는 이 한 줄이면 됩니다:

```bash
git submodule update --init --recursive
```

`.git` 폴더가 없는 압축본을 받으셨다면 서브모듈 정보도 없으므로 직접 받으세요:

```bash
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0
```

> ⚠️ `forge install`은 git 서브모듈을 쓰기 때문에 **git 저장소 안에서만 동작합니다.**
> `fatal: not a git repository` 가 나면 먼저 `git init`을 하세요.

`remappings.txt`가 이미 들어 있으므로 추가 설정은 없습니다.
버전은 `forge-std` v1.16.2, `openzeppelin-contracts` **v5.4.0**으로 고정돼 있습니다.

---

## 3. 여기까지 맞는지 확인

```bash
forge build
forge test
```

기대 결과:

```
Suite result: ok. 15 passed; 0 failed  (Token)
Suite result: ok. 13 passed; 0 failed  (FounderVesting)
Suite result: ok. 13 passed; 0 failed  (Inventory)
Suite result: ok. 23 passed; 0 failed  (Deployment)
```

**64개가 전부 통과해야 정상입니다.** 하나라도 실패하면 그 상태로 멈추고 알려주세요.

---

## 4. 테스트넷에 올리기 전에 준비할 것

이 세 가지는 **사용자님만 할 수 있습니다.** 제가 대신 못 합니다.

### (1) 배포 전용 지갑 새로 만들기

메타마스크에서 **새 계정**을 하나 만드세요.
평소 쓰는 지갑을 쓰지 마세요. 이 키는 파일에 저장될 것이기 때문입니다.

이번 배포에 필요한 주소는 **둘**입니다. 같아도 동작하지만 나누는 편이 좋습니다.

| `.env` 항목 | 역할 | 비우면 |
|---|---|---|
| `PRIVATE_KEY` | 배포 지갑 = 트레저리. 근거리 재고 5,000,000을 들고 있게 됩니다 | 필수 |
| `SAFE_ADDRESS` | 타임락에 **예약을 걸 수 있는** Safe 2-of-3 주소 | **필수 — 비우면 배포 실패** |

창업자 물량을 받을 주소는 따로 넣지 않습니다. **두 베스팅의 수령 주소가 타임락**이라
해제분도 타임락으로 들어가고, 빼려면 7일 예약을 거치기 때문입니다. (D-015)

### (2) Base Sepolia 테스트 ETH 받기

- https://www.alchemy.com/faucets/base-sepolia
- 또는 https://docs.base.org/chain/network-faucets 에 있는 목록

배포에 필요한 양은 **0.01 ETH도 안 됩니다.** (로컬 실측 가스 3,182,788 — 컨트랙트가
2개에서 4개로 늘면서 이전 1,256,692에서 증가했습니다)

### (3) Basescan API 키

**https://etherscan.io** 가입 → API Keys → Add → 무료 키 발급.

Etherscan 통합 API(V2)라 **키 하나가 Base 와 Base Sepolia 를 모두 커버합니다.**
basescan.org 에서 따로 받지 않아도 됩니다. `foundry.toml` 이 chain id
(테스트넷 84532 / 메인넷 8453)를 붙여 보냅니다.
컨트랙트 소스 검증(verify)에 씁니다. 검증을 해야 사람들이 코드를 직접 읽을 수 있습니다.

---

## 5. `.env` 만들기

```bash
cp .env.example .env
```

`.env`를 열어서 값을 채우세요.

> ⚠️ **`.env`에 넣은 개인키는 저(AI)에게 보여주지 마세요.**
> 제가 물어봐도 주지 마세요. `.gitignore`에 이미 막혀 있고,
> `CLAUDE.md`에도 "읽지 말 것"으로 적어뒀습니다.
> 한 번 노출된 키는 회수가 불가능합니다.

---

## 6. 테스트넷 배포 — 사용자님이 직접

**WSL / Git Bash:**

```bash
source .env
forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

**네이티브 PowerShell:** `source`가 없으므로 `.env`를 직접 읽어 넣습니다.

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
  }
}

forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
```

끝나면 출력에 주소 **네 개**가 찍힙니다 — 타임락, 토큰, 창업자 베스팅, 장기 재고.
그 네 주소를 전부 `docs/WALLETS.md`에 적어두세요. **발행 주체가 누구이고 어떤 지갑이 무엇을 쥐고 있는지를 처음부터 공개하는 것**이 이 프로젝트의 출발점입니다.

Basescan에서 확인:

```
https://sepolia.basescan.org/token/<토큰주소>
```

---

## 7. 배포 직후에 확인할 것

```bash
# 총 발행량이 1억인가
cast call <토큰주소> "totalSupply()(uint256)" --rpc-url base_sepolia

# mint가 정말 없는가 (revert 나야 정상)
cast call <토큰주소> "mint(address,uint256)" <내주소> 1 --rpc-url base_sepolia

# 잔고가 20M / 65M / 10M / 5M 인가
cast call <토큰주소> "balanceOf(address)(uint256)" <창업자베스팅> --rpc-url base_sepolia
cast call <토큰주소> "balanceOf(address)(uint256)" <장기재고>     --rpc-url base_sepolia
cast call <토큰주소> "balanceOf(address)(uint256)" <타임락>       --rpc-url base_sepolia
cast call <토큰주소> "balanceOf(address)(uint256)" <배포지갑>     --rpc-url base_sepolia

# ★ 두 베스팅의 수령 주소가 타임락인가 (D-015 — 여기가 틀리면 10년 뒤 86%입니다)
cast call <창업자베스팅> "owner()(address)" --rpc-url base_sepolia
cast call <장기재고>     "owner()(address)" --rpc-url base_sepolia

# 지금 꺼낼 수 있는 양 (창업자는 클리프 전이라 0, 재고는 1년 전이라 0)
cast call <창업자베스팅> "releasable(address)(uint256)" <토큰주소> --rpc-url base_sepolia
cast call <장기재고>     "releasable(address)(uint256)" <토큰주소> --rpc-url base_sepolia

# 장기 재고 시작 시각 = 배포 시각 + 365일 이어야 합니다
cast call <장기재고> "start()(uint256)" --rpc-url base_sepolia

# 타임락 지연이 7일(604800초)인가
cast call <타임락> "getMinDelay()(uint256)" --rpc-url base_sepolia

# 외부 admin이 없는가 (false 나야 정상)
cast call <타임락> "hasRole(bytes32,address)(bool)"   0x0000000000000000000000000000000000000000000000000000000000000000   <배포지갑> --rpc-url base_sepolia

# 실행이 열려 있는가 (true 나야 정상 — 키를 잃어도 물량이 브릭되지 않습니다)
cast call <타임락> "hasRole(bytes32,address)(bool)"   $(cast keccak "EXECUTOR_ROLE")   0x0000000000000000000000000000000000000000 --rpc-url base_sepolia
```

---

## 8. 그 다음 — 첫 기록

배포가 끝나면 `log/` 폴더에 첫 주차 기록을 쓰세요.
`log/_TEMPLATE.md`를 복사하고, **"안 된 것"부터** 씁니다.

이 프로젝트의 유일한 약속은 "멈추지 않는 것"이고,
그 약속이 지켜졌다는 증거는 코드가 아니라 이 기록입니다.

---

## 메인넷은 아직입니다

`foundry.toml`에 메인넷 설정이 들어 있지만, 지금 쓰지 마세요.
메인넷에 올리면 **이름, 심볼, 총량, 베스팅 일정을 영원히 바꿀 수 없습니다.**
장기 재고의 `start`(배포 +1년)와 타임락의 7일도 마찬가지로 앞당길 수 없습니다.

메인넷 전 체크리스트는 `README.md` 하단에 있습니다.
그 항목을 전부 통과하기 전에는 테스트넷에서만 움직이는 게 맞습니다.
