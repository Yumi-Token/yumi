// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Token} from "../src/Token.sol";
import {FounderVesting} from "../src/FounderVesting.sol";

/**
 * @title Deploy
 * @notice 토큰과 세 개의 잠금 장치를 한 묶음으로 배포합니다.
 *
 * 실행:
 *   테스트넷  forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
 *   메인넷    forge script script/Deploy.s.sol --rpc-url base       --broadcast --verify
 *
 * ─── 배포 순서가 중요합니다 (D-015, D-019) ─────────────────────
 *
 *   0. Safe 2-of-3 생성      ← 스크립트 밖. app.safe.global (D-019)
 *   1. TimelockController   ← proposers = [Safe 주소]
 *   2. Token                  전량이 deployer(=treasury)에게 발행
 *   3. FounderVesting         beneficiary = 타임락
 *   4. VestingWallet (재고)   beneficiary = 타임락, 1년 뒤 시작
 *   5. 물량 이체 3건
 *
 * 베스팅의 수령 주소를 발행자 지갑이 아니라 타임락으로 두는 이유:
 *
 *   해제된 물량이 발행자 지갑으로 바로 가면 그 순간부터 마찰이 0입니다.
 *   그러면 "예고 없이 움직일 수 있는 양 1%"는 배포 후 180일짜리 숫자가 되고,
 *   10년 뒤에는 88%가 됩니다.
 *
 *   수령 주소가 타임락이면 해제분이 타임락으로 들어가고, 빼려면 7일 공개 예약을
 *   거칩니다. 해제는 잠금을 푸는 것이 아니라 한 칸 앞으로 옮기는 것이 됩니다.
 *   덤으로 transferOwnership(수령권 매각)도 7일 예약을 거치게 됩니다.
 *
 * ─── 새로 짠 컨트랙트는 없습니다 ──────────────────────────────
 *
 *   VestingWallet, VestingWalletCliff, TimelockController 전부 OpenZeppelin
 *   표준입니다. 감사할 커스텀 코드는 여전히 0줄입니다. (D-001)
 */
contract Deploy is Script {
    // ─── 배포 후 변경 불가 ──────────────────────────────────
    // 이름과 심볼은 영원히 바꿀 수 없습니다. 메인넷 전에 확정하세요.

    string internal constant TOKEN_NAME = "Test Token";
    string internal constant TOKEN_SYMBOL = "TEST";

    // ─── 배분 (합이 정확히 INITIAL_SUPPLY여야 합니다) ────────
    //
    // public 인 이유는 test/Deployment.t.sol 이 이 값을 직접 읽어
    // 문서의 숫자와 대조하기 때문입니다. 여기만 고치고 문서를 안 고치면
    // 테스트가 깨집니다 — 그게 목적입니다.

    uint256 public constant FOUNDER_ALLOCATION = 20_000_000 ether; // 20%
    uint256 public constant INVENTORY_ALLOCATION = 65_000_000 ether; // 65%
    uint256 public constant OPERATIONS_ALLOCATION = 10_000_000 ether; // 10%
    uint256 public constant NEAR_TERM_ALLOCATION = 5_000_000 ether; // 5% — treasury에 잔류

    // ─── 창업자 베스팅: 3개월 클리프 + 12개월 선형 (D-020) ───

    uint64 public constant CLIFF_SECONDS = 90 days;
    uint64 public constant VESTING_DURATION = 365 days;

    // ─── 장기 재고: 1년 뒤 시작, 이후 3년 선형 (D-020) ───────
    //
    // 클리프를 쓰지 않는 이유 (D-008):
    //   OpenZeppelin은 선형 계산의 기준점이 클리프가 아니라 start입니다.
    //   "1년 클리프 + 3년 선형"으로 걸면 1년째에 21,666,666개(총량 21.7%)가
    //   한 번에 열립니다. 기간을 줄일수록 이 계단이 커지므로, 단축한 지금
    //   이 결정은 원안 때보다 더 중요해졌습니다.
    //   start를 미래로 미루면 그런 지점이 없습니다.

    uint64 public constant INVENTORY_START_DELAY = 365 days;
    uint64 public constant INVENTORY_DURATION = 1095 days;

    // ─── 타임락 ─────────────────────────────────────────────

    uint256 public constant TIMELOCK_MIN_DELAY = 7 days;

    function run()
        external
        returns (
            Token token,
            FounderVesting founderVesting,
            VestingWallet inventoryVesting,
            TimelockController timelock
        )
    {
        // 개인키는 .env에서만 읽습니다. 절대 코드에 넣지 마세요.
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // 타임락에 예약을 걸 수 있는 주소 = Safe 2-of-3 (D-019)
        // envAddress는 미설정 시 revert합니다. 폴백을 두지 않는 것이 요점입니다 —
        // 배포 지갑이 조용히 proposer가 되면 D-007의 영구 동결 구조가 됩니다.
        address safe = vm.envAddress("SAFE_ADDRESS");

        require(safe != deployer, "SAFE_ADDRESS == deployer");
        require(safe.code.length > 0, "SAFE_ADDRESS is not a contract");

        _assertAllocationsSumToSupply();

        console2.log("=== Deploy ===");
        console2.log("chain id      :", block.chainid);
        console2.log("deployer      :", deployer);
        console2.log("safe (proposer):", safe);

        vm.startBroadcast(deployerKey);

        // ── 1. 타임락 (가장 먼저) ────────────────────────────
        //
        // proposers  : Safe 2-of-3 주소 하나. PROPOSER와 CANCELLER 역할이 함께 부여됩니다
        //              EOA를 넣으면 그 키 하나가 예약과 취소를 독점하고,
        //              유출 시 도난이 아니라 영구 동결이 됩니다 (D-007 / D-019)
        // executors  : address(0) = 누구나 실행 가능
        //              Safe만 넣으면 키 분실 시 물량이 영구히 잠깁니다.
        //              예약은 여전히 proposer만 할 수 있으므로 위험하지 않습니다
        // admin      : address(0) = 외부 admin 없음
        //              나중에 renounce할 필요가 없도록 처음부터 안 만듭니다

        address[] memory proposers = new address[](1);
        proposers[0] = safe;

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new TimelockController(TIMELOCK_MIN_DELAY, proposers, executors, address(0));

        // ── 2. 토큰 — 전량이 deployer에게 발행 ───────────────
        token = new Token(TOKEN_NAME, TOKEN_SYMBOL, deployer);

        // ── 3. 창업자 베스팅 — 수령 주소는 타임락 ────────────
        founderVesting =
            new FounderVesting(address(timelock), uint64(block.timestamp), VESTING_DURATION, CLIFF_SECONDS);

        // ── 4. 장기 재고 베스팅 — 1년 뒤 시작, 수령 주소는 타임락
        inventoryVesting = new VestingWallet(
            address(timelock), uint64(block.timestamp) + INVENTORY_START_DELAY, INVENTORY_DURATION
        );

        // ── 5. 물량 이체 — 같은 묶음에서 끝냅니다 ────────────
        //
        // "아직 안 잠긴" 상태가 존재하면 안 됩니다. (D-004)
        token.transfer(address(founderVesting), FOUNDER_ALLOCATION);
        token.transfer(address(inventoryVesting), INVENTORY_ALLOCATION);
        token.transfer(address(timelock), OPERATIONS_ALLOCATION);
        // 남은 NEAR_TERM_ALLOCATION은 deployer에 잔류합니다

        vm.stopBroadcast();

        _report(token, founderVesting, inventoryVesting, timelock, deployer);
    }

    /// @dev 배분 합계가 총 발행량과 다르면 배포를 중단합니다.
    function _assertAllocationsSumToSupply() internal pure {
        uint256 sum = FOUNDER_ALLOCATION + INVENTORY_ALLOCATION + OPERATIONS_ALLOCATION + NEAR_TERM_ALLOCATION;
        require(sum == 100_000_000 ether, "allocations != INITIAL_SUPPLY");
    }

    function _report(
        Token token,
        FounderVesting founderVesting,
        VestingWallet inventoryVesting,
        TimelockController timelock,
        address deployer
    ) internal view {
        console2.log("");
        console2.log("--- addresses (docs/WALLETS.md) ---");
        console2.log("token             :", address(token));
        console2.log("timelock          :", address(timelock));
        console2.log("founder vesting   :", address(founderVesting));
        console2.log("inventory vesting :", address(inventoryVesting));
        console2.log("treasury          :", deployer);

        console2.log("");
        console2.log("--- balances (whole tokens) ---");
        console2.log("total supply      :", token.totalSupply() / 1e18);
        console2.log("founder locked    :", token.balanceOf(address(founderVesting)) / 1e18);
        console2.log("inventory locked  :", token.balanceOf(address(inventoryVesting)) / 1e18);
        console2.log("operations (lock) :", token.balanceOf(address(timelock)) / 1e18);
        console2.log("near-term (free)  :", token.balanceOf(deployer) / 1e18);

        console2.log("");
        console2.log("--- schedule (unix seconds) ---");
        console2.log("founder cliff ends:", founderVesting.cliff());
        console2.log("founder ends      :", founderVesting.start() + founderVesting.duration());
        console2.log("inventory starts  :", inventoryVesting.start());
        console2.log("inventory ends    :", inventoryVesting.start() + inventoryVesting.duration());
        console2.log("timelock delay    :", timelock.getMinDelay());

        console2.log("");
        console2.log(unicode"-> 위 주소를 docs/WALLETS.md 에 기록하세요.");
        console2.log(unicode"-> 두 베스팅의 owner() 가 timelock 주소와 같은지 확인하세요.");
        console2.log(unicode"-> Basescan 소스 검증이 끝났는지 확인하세요.");
    }
}
