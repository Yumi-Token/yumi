// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Token} from "../src/Token.sol";

/**
 * @notice 장기 재고가 1년간 잠기고, 그 뒤 「한 번에 열리는 지점 없이」 풀리는지 검증합니다.
 *
 * 이 파일의 존재 이유는 test_NothingUnlocksAtOnceWhenVestingStarts 하나입니다.
 * 클리프를 썼다면 1년째에 21,666,666개(총량 21.7%)가 한꺼번에 열립니다. (D-008)
 */
contract InventoryTest is Test {
    Token internal token;
    VestingWallet internal vesting;

    address internal treasury = makeAddr("treasury");
    address internal timelock = makeAddr("timelock");

    uint64 internal deployedAt;

    uint64 internal constant START_DELAY = 365 days; // 1년 뒤 시작
    uint64 internal constant DURATION = 1095 days; // 이후 3년 선형

    uint256 internal constant INVENTORY = 65_000_000 ether;

    function setUp() public {
        vm.warp(1_800_000_000); // 결정적 테스트를 위한 고정 시각
        deployedAt = uint64(block.timestamp);

        token = new Token("Test Token", "TEST", treasury);
        vesting = new VestingWallet(timelock, deployedAt + START_DELAY, DURATION);

        vm.prank(treasury);
        token.transfer(address(vesting), INVENTORY);
    }

    // ─── 수령 주소가 타임락인가 ─────────────────────────────

    /// @notice 여기가 깨지면 해제분이 지갑으로 직행하고 10년 뒤 86%가 됩니다.
    function test_BeneficiaryIsTimelock() public view {
        assertEq(vesting.owner(), timelock, unicode"수령 주소는 타임락이어야 합니다");
    }

    function test_FullInventoryIsLocked() public view {
        assertEq(token.balanceOf(address(vesting)), INVENTORY);
    }

    // ─── 1년간 한 개도 나오지 않는다 ────────────────────────

    function test_NothingReleasableAtDeploy() public view {
        assertEq(vesting.releasable(address(token)), 0);
    }

    function test_NothingReleasableJustBeforeStart() public {
        vm.warp(deployedAt + START_DELAY - 1);
        assertEq(vesting.releasable(address(token)), 0, unicode"시작 1초 전에는 0이어야 합니다");
    }

    // ─── 시작 시점에 한 번에 열리는 지점이 없다 ──────────────

    /**
     * @notice 이 프로젝트에서 가장 중요한 테스트입니다.
     *
     * VestingWalletCliff를 썼다면 이 시점에 13,000,000개가 열립니다.
     * (65,000,000 × 730일 / 3650일)
     * start를 미래로 미뤘기 때문에 0이어야 합니다.
     */
    function test_NothingUnlocksAtOnceWhenVestingStarts() public {
        vm.warp(deployedAt + START_DELAY);
        assertEq(vesting.releasable(address(token)), 0, unicode"시작 정각에도 0이어야 합니다");
    }

    function test_ReleaseIsGradualRightAfterStart() public {
        vm.warp(deployedAt + START_DELAY + 1 days);

        uint256 oneDay = INVENTORY * 1 days / DURATION;
        assertApproxEqRel(vesting.releasable(address(token)), oneDay, 0.001e18);

        // 하루치는 65,000,000 / 1095 = 약 59,361개. 총량의 0.06% 미만입니다
        assertLt(vesting.releasable(address(token)), 60_000 ether);
    }

    // ─── 이후 선형 해제 ────────────────────────────────────

    function test_OneYearAfterStart() public {
        vm.warp(deployedAt + START_DELAY + 365 days);

        uint256 expected = INVENTORY * 365 days / DURATION; // 약 21,666,666
        assertApproxEqRel(vesting.releasable(address(token)), expected, 0.001e18);
        assertApproxEqRel(expected, 21_666_666 ether, 0.001e18);
    }

    function test_FullyVestedAtEnd() public {
        vm.warp(deployedAt + START_DELAY + DURATION);
        assertEq(vesting.releasable(address(token)), INVENTORY);
    }

    function test_NoMoreThanAllocationAfterEnd() public {
        vm.warp(deployedAt + START_DELAY + DURATION + 3650 days);
        assertEq(vesting.releasable(address(token)), INVENTORY);
    }

    // ─── 해제분은 타임락으로만 간다 ─────────────────────────

    /// @notice 제3자가 release를 호출해도 토큰은 타임락에게만 갑니다.
    function test_AnyoneCanReleaseButFundsGoToTimelock() public {
        vm.warp(deployedAt + START_DELAY + DURATION);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vesting.release(address(token));

        assertEq(token.balanceOf(timelock), INVENTORY, unicode"해제분은 타임락으로 갑니다");
        assertEq(token.balanceOf(stranger), 0, unicode"호출자가 가져갈 수 없습니다");
    }

    /// @notice 10년이 지나도 발행자 지갑으로 직행하는 물량이 없습니다.
    function test_NothingEverGoesDirectlyToTreasury() public {
        uint256 before = token.balanceOf(treasury);

        vm.warp(deployedAt + START_DELAY + DURATION);
        vesting.release(address(token));

        assertEq(
            token.balanceOf(treasury), before, unicode"트레저리 잔고는 변하지 않아야 합니다"
        );
    }

    // ─── 어떤 시점에도 배정량을 넘지 않는다 ──────────────────

    function testFuzz_ReleasableNeverExceedsAllocation(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, 7300 days));
        vm.warp(deployedAt + elapsed);
        assertLe(vesting.releasable(address(token)), INVENTORY);
    }

    function testFuzz_NothingReleasableBeforeStart(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, START_DELAY));
        vm.warp(deployedAt + elapsed);
        assertEq(vesting.releasable(address(token)), 0, unicode"시작 전에는 항상 0입니다");
    }
}
