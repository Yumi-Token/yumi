// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Token} from "../src/Token.sol";
import {FounderVesting} from "../src/FounderVesting.sol";

/**
 * @title Deploy
 * @notice 토큰을 배포하고, 트레저리를 네 갈래로 나눠 같은 묶음 안에서 전부 잠급니다.
 *
 * 실행:
 *   테스트넷  forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
 *   메인넷    forge script script/Deploy.s.sol --rpc-url base       --broadcast --verify
 *
 * 이 스크립트가 하는 일:
 *   1. Token 배포 — 전량이 배포자(=treasury) 주소로 발행됩니다
 *   2. FounderVesting 배포 → 20,000,000 이체   (6개월 클리프 + 24개월 선형)
 *   3. VestingWallet 배포  → 65,000,000 이체   (2년 뒤 시작 + 8년 선형)
 *   4. TimelockController 배포 → 10,000,000 이체 (7일 지연)
 *   5. 남은 5,000,000 은 트레저리에 그대로 — 근거리 재고
 *
 * 전부 한 broadcast 안에서 끝납니다. "아직 안 잠긴" 상태가 존재하지 않습니다. (D-004)
 *
 * 새로 짠 컨트랙트는 0줄입니다. 3·4번은 OpenZeppelin 구체 클래스를 그대로 `new` 합니다. (D-001)
 */
contract Deploy is Script {
    // ─── 배포 전에 반드시 확인할 값들 ────────────────────────
    // 이름과 심볼은 배포 후 변경이 불가능합니다.
    // 테스트넷에서는 아무 값이나 써도 되지만, 메인넷 전에 확정하세요.

    string internal constant TOKEN_NAME = "Test Token";
    string internal constant TOKEN_SYMBOL = "TEST";

    // ─── 배분 (docs/TOKENOMICS.md 와 반드시 일치) ─────────────
    // public 인 이유: test/Allocation.t.sol 이 이 값을 직접 읽어서
    // 문서와 코드가 어긋나는 순간 테스트가 깨지도록 하기 위해서입니다.

    /// @dev 창업자 배정 — 총량의 20%
    uint256 public constant FOUNDER_ALLOCATION = 20_000_000 ether;

    /// @dev 장기 유동성 공급 재고 — 총량의 65%. 「커뮤니티 배정」이 아닙니다 (D-005)
    uint256 public constant INVENTORY_ALLOCATION = 65_000_000 ether;

    /// @dev 운영·예비 — 총량의 10%. 7일 타임락에 보관
    uint256 public constant OPERATIONS_ALLOCATION = 10_000_000 ether;

    /// @dev 근거리 재고 — 총량의 5%. 별도 이체 없이 트레저리에 남습니다
    uint256 public constant NEAR_TERM_INVENTORY = 5_000_000 ether;

    // ─── 창업자 베스팅 (D-003) ───────────────────────────────

    /// @dev 6개월 클리프
    uint64 public constant CLIFF_SECONDS = 180 days;

    /// @dev 24개월 선형 베스팅
    uint64 public constant VESTING_DURATION = 730 days;

    // ─── 장기 재고 (D-008) ───────────────────────────────────
    //
    // 클리프를 쓰지 않습니다. OpenZeppelin은 선형 계산의 기준점이
    // 클리프가 아니라 start라서, 「2년 클리프」로 걸면 2년째에
    // 13,000,000개가 한 번에 열립니다. 그래서 start 자체를 2년 뒤로 미룹니다.

    /// @dev 배포 +2년부터 해제가 시작됩니다
    uint64 public constant INVENTORY_START_DELAY = 730 days;

    /// @dev 시작 이후 8년에 걸쳐 선형 해제
    uint64 public constant INVENTORY_DURATION = 2920 days;

    // ─── 운영 타임락 (D-007) ─────────────────────────────────

    /// @dev 7일. 주간 기록 주기와 맞춰 예약이 곧 사전 공지가 됩니다
    uint256 public constant TIMELOCK_MIN_DELAY = 7 days;

    function run()
        external
        returns (
            Token token,
            FounderVesting founderVesting,
            VestingWallet inventory,
            TimelockController timelock
        )
    {
        // 개인키는 .env에서만 읽습니다. 절대 코드에 넣지 마세요.
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // 창업자 물량 수령 주소. 배포 지갑과 다른 주소를 권장합니다.
        address founder = vm.envOr("FOUNDER_ADDRESS", deployer);

        // 운영 지갑 — 장기 재고의 수령인이자 타임락의 제안·실행자입니다.
        address operations = vm.envOr("OPERATIONS_ADDRESS", deployer);

        console2.log("=== Deploy ===");
        console2.log("chain id      :", block.chainid);
        console2.log("deployer      :", deployer);
        console2.log("founder       :", founder);
        console2.log("operations    :", operations);

        // 타임락 권한 구성 — 제안자와 실행자 모두 운영 지갑입니다.
        address[] memory proposers = new address[](1);
        proposers[0] = operations;
        address[] memory executors = new address[](1);
        executors[0] = operations;

        vm.startBroadcast(deployerKey);

        // 1. 토큰 — 전량이 deployer에게 발행됩니다
        token = new Token(TOKEN_NAME, TOKEN_SYMBOL, deployer);

        // 2. 창업자 베스팅 — 지금 이 순간부터 시계가 돕니다
        founderVesting = new FounderVesting(founder, uint64(block.timestamp), VESTING_DURATION, CLIFF_SECONDS);
        token.transfer(address(founderVesting), FOUNDER_ALLOCATION);

        // 3. 장기 재고 — 클리프가 아니라 시작 시각을 2년 뒤로 미룹니다 (D-008)
        inventory = new VestingWallet(
            operations, uint64(block.timestamp) + INVENTORY_START_DELAY, INVENTORY_DURATION
        );
        token.transfer(address(inventory), INVENTORY_ALLOCATION);

        // 4. 운영·예비 — 7일 타임락
        //
        //    마지막 인자(admin)를 address(0)으로 둡니다. 관리자 권한을 나중에
        //    포기하는 대신 처음부터 만들지 않습니다 — "나중에 잠그겠다"는
        //    상태가 존재하지 않도록 (D-004, D-013의 구조 예외).
        //
        //    권한이 사라지는 것은 아닙니다. 타임락 자신이 관리자이므로
        //    역할 변경이나 지연 시간 변경도 7일 예약을 거쳐 할 수 있습니다.
        timelock = new TimelockController(TIMELOCK_MIN_DELAY, proposers, executors, address(0));
        token.transfer(address(timelock), OPERATIONS_ALLOCATION);

        // 5. 남은 5,000,000 (근거리 재고)은 트레저리에 그대로 둡니다. 이체 없음.

        vm.stopBroadcast();

        // ─── 자기 점검 — 배분이 어긋난 채로 끝나지 않도록 ──────
        require(
            FOUNDER_ALLOCATION + INVENTORY_ALLOCATION + OPERATIONS_ALLOCATION + NEAR_TERM_INVENTORY
                == token.INITIAL_SUPPLY(),
            "allocation sum != INITIAL_SUPPLY"
        );
        require(token.balanceOf(deployer) == NEAR_TERM_INVENTORY, "treasury remainder != 5,000,000");

        console2.log("");
        console2.log("token           :", address(token));
        console2.log("founderVesting  :", address(founderVesting));
        console2.log("inventory       :", address(inventory));
        console2.log("timelock        :", address(timelock));

        console2.log("");
        console2.log("total supply    :", token.totalSupply() / 1e18);
        console2.log("founder locked  :", token.balanceOf(address(founderVesting)) / 1e18);
        console2.log("inventory locked:", token.balanceOf(address(inventory)) / 1e18);
        console2.log("timelock held   :", token.balanceOf(address(timelock)) / 1e18);
        console2.log("treasury left   :", token.balanceOf(deployer) / 1e18);

        console2.log("");
        console2.log("founder cliff ends  :", founderVesting.cliff());
        console2.log("founder vest ends   :", founderVesting.start() + founderVesting.duration());
        console2.log("inventory starts    :", inventory.start());
        console2.log("inventory ends      :", inventory.start() + inventory.duration());
        console2.log("timelock min delay  :", timelock.getMinDelay());

        console2.log("");
        console2.log(unicode"-> docs/WALLETS.md 에 위 네 주소를 전부 기록하세요.");
        console2.log(unicode"-> Basescan 소스 검증이 끝났는지 반드시 확인하세요.");
        console2.log(
            unicode"-> 예고 없이 움직일 수 있는 양은 트레저리 잔량 5,000,000 뿐입니다."
        );
    }
}
