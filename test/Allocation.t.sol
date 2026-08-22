// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Token} from "../src/Token.sol";
import {FounderVesting} from "../src/FounderVesting.sol";
import {Deploy} from "../script/Deploy.s.sol";

/**
 * @notice 이 프로젝트가 공개적으로 주장하는 두 문장을 코드로 고정합니다.
 *
 *   1. 배분의 합이 정확히 총 발행량이다 — 남는 물량도 모자란 물량도 없다.
 *   2. 예고 없이 움직일 수 있는 양은 총량의 3%다.
 *
 * 두 번째가 사려는 사람이 실제로 확인하는 숫자입니다. 최대 보유자 비중은
 * 모든 스캐너가 첫 줄에 표시하고, 20% 락업은 그 옆에서 무의미해집니다. (D-007)
 *
 * 주의 — 숫자를 script/Deploy.s.sol 에서 직접 읽어옵니다.
 * 배포 스크립트의 상수를 바꾸면 이 테스트가 깨지고,
 * 그때 docs/TOKENOMICS.md 도 같이 고쳐야 한다는 뜻입니다.
 */
contract AllocationTest is Test {
    Deploy internal script;

    Token internal token;
    FounderVesting internal founderVesting;
    VestingWallet internal inventory;
    TimelockController internal timelock;

    address internal treasury = makeAddr("treasury");
    address internal founder = makeAddr("founder");
    address internal operations = makeAddr("operations");
    address internal pool = makeAddr("pool");

    uint256 internal constant SUPPLY = 100_000_000 ether;

    /// @dev 초기 유동성 구간에 투입할 양 — docs/TOKENOMICS.md 「초기 구간」
    uint256 internal constant INITIAL_LIQUIDITY = 2_000_000 ether;

    function setUp() public {
        vm.warp(1_800_000_000); // 결정적 테스트를 위한 고정 시각
        script = new Deploy();

        address[] memory proposers = new address[](1);
        proposers[0] = operations;
        address[] memory executors = new address[](1);
        executors[0] = operations;

        // script/Deploy.s.sol 의 run() 과 같은 순서, 같은 상수로 재현합니다.
        token = new Token("Test Token", "TEST", treasury);

        founderVesting = new FounderVesting(
            founder, uint64(block.timestamp), script.VESTING_DURATION(), script.CLIFF_SECONDS()
        );
        inventory = new VestingWallet(
            operations, uint64(block.timestamp) + script.INVENTORY_START_DELAY(), script.INVENTORY_DURATION()
        );
        timelock = new TimelockController(script.TIMELOCK_MIN_DELAY(), proposers, executors, address(0));

        vm.startPrank(treasury);
        token.transfer(address(founderVesting), script.FOUNDER_ALLOCATION());
        token.transfer(address(inventory), script.INVENTORY_ALLOCATION());
        token.transfer(address(timelock), script.OPERATIONS_ALLOCATION());
        vm.stopPrank();
    }

    // ─── 불변식 1 — 배분의 합 ────────────────────────────────

    /// @notice 네 버킷의 합이 정확히 총 발행량이어야 합니다. 1 wei도 어긋나면 실패입니다.
    function test_AllocationsSumToInitialSupply() public view {
        uint256 sum = script.FOUNDER_ALLOCATION() + script.INVENTORY_ALLOCATION()
            + script.OPERATIONS_ALLOCATION() + script.NEAR_TERM_INVENTORY();

        assertEq(
            sum, token.INITIAL_SUPPLY(), unicode"배분의 합이 총 발행량과 달라서는 안 됩니다"
        );
        assertEq(sum, SUPPLY);
    }

    /**
     * @notice 배포 스크립트의 상수가 docs/TOKENOMICS.md 의 표와 같은지 확인합니다.
     *
     * 이 테스트가 실패하면 둘 중 하나가 거짓말이 된 것입니다.
     * 「공지와 코드가 다르면 안 됩니다」 — 작업을 멈추고 양쪽을 맞추세요.
     */
    function test_ScriptConstantsMatchTokenomicsDocument() public view {
        assertEq(script.FOUNDER_ALLOCATION(), 20_000_000 ether, unicode"창업자 20%");
        assertEq(script.INVENTORY_ALLOCATION(), 65_000_000 ether, unicode"장기 재고 65%");
        assertEq(script.NEAR_TERM_INVENTORY(), 5_000_000 ether, unicode"근거리 재고 5%");
        assertEq(script.OPERATIONS_ALLOCATION(), 10_000_000 ether, unicode"운영 예비 10%");

        assertEq(script.CLIFF_SECONDS(), 180 days, unicode"창업자 클리프 6개월");
        assertEq(script.VESTING_DURATION(), 730 days, unicode"창업자 베스팅 24개월");
        assertEq(script.INVENTORY_START_DELAY(), 730 days, unicode"장기 재고 시작 +2년");
        assertEq(script.INVENTORY_DURATION(), 2920 days, unicode"장기 재고 8년 선형");
        assertEq(script.TIMELOCK_MIN_DELAY(), 7 days, unicode"운영 타임락 7일");
    }

    /// @notice 각 버킷이 배정된 양을 실제로 들고 있는지 확인합니다.
    function test_EachBucketHoldsItsAllocation() public view {
        assertEq(token.balanceOf(address(founderVesting)), script.FOUNDER_ALLOCATION());
        assertEq(token.balanceOf(address(inventory)), script.INVENTORY_ALLOCATION());
        assertEq(token.balanceOf(address(timelock)), script.OPERATIONS_ALLOCATION());
        assertEq(token.balanceOf(treasury), script.NEAR_TERM_INVENTORY());
    }

    /// @notice 네 주소의 잔고 합이 총 발행량입니다 — 어디에도 빠진 물량이 없습니다.
    function test_NoTokensAreUnaccountedFor() public view {
        uint256 held = token.balanceOf(address(founderVesting)) + token.balanceOf(address(inventory))
            + token.balanceOf(address(timelock)) + token.balanceOf(treasury);

        assertEq(
            held, token.totalSupply(), unicode"어느 주소에도 없는 물량이 있으면 안 됩니다"
        );
    }

    // ─── 불변식 2 — 예고 없이 움직일 수 있는 양 ────────────────

    /**
     * @notice 초기 LP 투입 전 기준 — 근거리 재고 5,000,000 뿐입니다.
     *
     * 나머지 셋은 각각 클리프, 미래 시작, 7일 예약으로 막혀 있습니다.
     */
    function test_UnannouncedMovableIsFiveMillionAtDeploy() public view {
        assertEq(unannouncedMovable(), 5_000_000 ether, unicode"배포 직후 5,000,000");
        assertEq(unannouncedMovable(), script.NEAR_TERM_INVENTORY());
    }

    /// @notice 초기 유동성 2,000,000 을 넣고 나면 3,000,000 — 총량의 3%입니다.
    function test_UnannouncedMovableIsThreeMillionAfterInitialLiquidity() public {
        vm.prank(treasury);
        token.transfer(pool, INITIAL_LIQUIDITY);

        assertEq(unannouncedMovable(), 3_000_000 ether, unicode"LP 투입 후 3,000,000");
        assertEq(unannouncedMovable() * 100 / SUPPLY, 3, unicode"총량의 3%");
    }

    /// @notice 잠긴 세 버킷은 배포 직후 각각 0을 기여합니다.
    function test_LockedBucketsContributeNothingAtDeploy() public view {
        assertEq(founderVesting.releasable(address(token)), 0, unicode"창업자 - 클리프");
        assertEq(inventory.releasable(address(token)), 0, unicode"장기 재고 - 2년 뒤 시작");
        assertEq(timelock.getMinDelay(), 7 days, unicode"운영 - 7일 예약 필요");
    }

    /**
     * @notice 첫 6개월 내내 예고 없이 움직일 수 있는 양이 늘어나지 않습니다.
     *
     * 첫 해제 지점은 창업자 클리프(180일)이고, 그 전까지는 어떤 시점을 찍어도
     * 근거리 재고 그대로여야 합니다.
     */
    function testFuzz_UnannouncedMovableDoesNotGrowBeforeFirstCliff(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, script.CLIFF_SECONDS() - 1));
        vm.warp(block.timestamp + elapsed);

        assertEq(
            unannouncedMovable(),
            script.NEAR_TERM_INVENTORY(),
            unicode"클리프 전에는 늘어나지 않습니다"
        );
    }

    // ─── 비율 ────────────────────────────────────────────────

    function test_BucketPercentages() public view {
        assertEq(script.FOUNDER_ALLOCATION() * 100 / SUPPLY, 20);
        assertEq(script.INVENTORY_ALLOCATION() * 100 / SUPPLY, 65);
        assertEq(script.NEAR_TERM_INVENTORY() * 100 / SUPPLY, 5);
        assertEq(script.OPERATIONS_ALLOCATION() * 100 / SUPPLY, 10);
    }

    /// @notice 최대 보유자가 2년간 잠긴 장기 재고임을 확인합니다.
    function test_LargestHolderIsTheLockedInventory() public view {
        uint256 largest = token.balanceOf(address(inventory));

        assertGt(largest, token.balanceOf(address(founderVesting)));
        assertGt(largest, token.balanceOf(address(timelock)));
        assertGt(largest, token.balanceOf(treasury));
        assertEq(largest, script.INVENTORY_ALLOCATION());
    }

    // ─── 헬퍼 ────────────────────────────────────────────────

    /**
     * @dev 「예고 없이 움직일 수 있는 양」의 정의.
     *
     *  - 트레저리 잔량은 즉시 움직입니다.
     *  - 베스팅 두 곳은 지금 해제 가능한 양만큼 움직입니다.
     *  - 타임락 물량은 7일 예약이 필요하므로 예고 없이는 0입니다.
     *    (그 사실 자체는 test/Timelock.t.sol 에서 증명합니다)
     */
    function unannouncedMovable() internal view returns (uint256) {
        return token.balanceOf(treasury) + founderVesting.releasable(address(token))
            + inventory.releasable(address(token));
    }
}
