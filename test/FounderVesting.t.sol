// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {FounderVesting} from "../src/FounderVesting.sol";

/**
 * @notice 락업이 공지가 아니라 코드로 강제되는지 검증합니다.
 *
 * 설계 원칙: 「공지한 것과 코드가 다르지 않게」
 * 여기서 통과하는 항목만 공개 문서에 쓸 수 있습니다.
 */
contract FounderVestingTest is Test {
    Token internal token;
    FounderVesting internal vesting;

    address internal treasury = makeAddr("treasury");
    address internal founder = makeAddr("founder");
    address internal stranger = makeAddr("stranger");

    uint64 internal start;
    uint64 internal constant CLIFF = 90 days; // 3개월
    uint64 internal constant DURATION = 365 days; // 12개월

    uint256 internal constant FOUNDER_ALLOCATION = 20_000_000 ether; // 총량의 20%

    function setUp() public {
        vm.warp(1_800_000_000); // 결정적 테스트를 위한 고정 시각
        start = uint64(block.timestamp);

        token = new Token("Test Token", "TEST", treasury);
        vesting = new FounderVesting(founder, start, DURATION, CLIFF);

        vm.prank(treasury);
        token.transfer(address(vesting), FOUNDER_ALLOCATION);
    }

    // ─── 파라미터가 공지한 대로인가 ─────────────────────────

    function test_ParametersMatchPublishedSchedule() public view {
        assertEq(vesting.owner(), founder, unicode"수령인이 창업자여야 합니다");
        assertEq(vesting.start(), start);
        assertEq(vesting.duration(), DURATION, unicode"베스팅 기간 12개월");
        assertEq(vesting.cliff(), start + CLIFF, unicode"클리프 3개월");
    }

    function test_FullAllocationIsLocked() public view {
        assertEq(token.balanceOf(address(vesting)), FOUNDER_ALLOCATION);
        assertEq(
            token.balanceOf(founder), 0, unicode"시작 시점에 창업자 잔고는 0이어야 합니다"
        );
    }

    // ─── 클리프 전에는 한 개도 나오지 않는다 ─────────────────

    function test_NothingReleasableAtStart() public view {
        assertEq(vesting.releasable(address(token)), 0);
    }

    function test_NothingReleasableJustBeforeCliff() public {
        vm.warp(start + CLIFF - 1);
        assertEq(
            vesting.releasable(address(token)), 0, unicode"클리프 1초 전에는 0이어야 합니다"
        );
    }

    function test_ReleaseBeforeCliffTransfersNothing() public {
        vm.warp(start + CLIFF - 1 days);

        vesting.release(address(token)); // 호출은 성공하되 금액이 0
        assertEq(token.balanceOf(founder), 0, unicode"클리프 전에는 한 개도 나가면 안 됩니다");
    }

    // ─── 클리프 이후 선형 해제 ──────────────────────────────

    /**
     * @notice 클리프 직후에는 6개월치가 한 번에 열립니다.
     *
     * OpenZeppelin 표준 동작이며, 선형 계산의 기준점이 cliff가 아니라
     * start이기 때문입니다. 이 사실을 공개 문서에 명시해야 합니다.
     */
    function test_CliffUnlocksAccruedPortionAtOnce() public {
        vm.warp(start + CLIFF);

        uint256 expected = FOUNDER_ALLOCATION * CLIFF / DURATION;
        assertEq(vesting.releasable(address(token)), expected);

        // 20,000,000 * 180 / 730 ≈ 4,931,506 개 — 총량의 약 4.9%
        assertApproxEqRel(expected, 4_931_506 ether, 0.001e18);
    }

    function test_HalfwayReleasesHalf() public {
        vm.warp(start + DURATION / 2);
        assertApproxEqRel(vesting.releasable(address(token)), FOUNDER_ALLOCATION / 2, 0.001e18);
    }

    function test_FullyVestedAtEnd() public {
        vm.warp(start + DURATION);
        assertEq(vesting.releasable(address(token)), FOUNDER_ALLOCATION);
    }

    function test_NoMoreThanAllocationAfterEnd() public {
        vm.warp(start + DURATION + 3650 days);
        assertEq(
            vesting.releasable(address(token)),
            FOUNDER_ALLOCATION,
            unicode"기간이 지나도 배정량을 넘을 수 없습니다"
        );
    }

    // ─── 자금은 항상 수령인에게만 간다 ───────────────────────

    /// @notice 제3자가 release를 호출해도 토큰은 창업자에게만 갑니다.
    function test_AnyoneCanCallReleaseButFundsGoToBeneficiary() public {
        vm.warp(start + DURATION);

        vm.prank(stranger);
        vesting.release(address(token));

        assertEq(token.balanceOf(founder), FOUNDER_ALLOCATION);
        assertEq(token.balanceOf(stranger), 0, unicode"호출자가 가져갈 수 없습니다");
    }

    /// @notice 조기 인출 경로가 없습니다.
    function test_NoEmergencyWithdrawExists() public {
        (bool ok,) = address(vesting).call(abi.encodeWithSignature("emergencyWithdraw()"));
        assertFalse(ok, unicode"비상 인출 함수가 있으면 안 됩니다");

        (bool ok2,) =
            address(vesting).call(abi.encodeWithSignature("withdraw(address,uint256)", address(token), 1));
        assertFalse(ok2, unicode"임의 인출 함수가 있으면 안 됩니다");
    }

    // ─── 시간이 흘러도 총량은 배정량을 넘지 않는다 ─────────────

    function testFuzz_ReleasableNeverExceedsAllocation(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, 3650 days));
        vm.warp(start + elapsed);

        assertLe(
            vesting.releasable(address(token)),
            FOUNDER_ALLOCATION,
            unicode"어떤 시점에도 배정량을 초과할 수 없습니다"
        );
    }

    function testFuzz_ReleaseIsMonotonic(uint64 t1, uint64 t2) public {
        t1 = uint64(bound(t1, 0, DURATION));
        t2 = uint64(bound(t2, t1, DURATION));

        vm.warp(start + t1);
        uint256 a = vesting.releasable(address(token));

        vm.warp(start + t2);
        uint256 b = vesting.releasable(address(token));

        assertGe(b, a, unicode"해제량은 시간에 따라 줄어들 수 없습니다");
    }
}
