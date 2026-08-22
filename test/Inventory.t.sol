// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Token} from "../src/Token.sol";

/**
 * @notice 장기 재고 65,000,000 이 「한 번에 열리는 지점 없이」 잠기는지 검증합니다.
 *
 * 이 파일의 핵심은 test_NothingUnlocksAtTheStartMoment 하나입니다.
 * 클리프를 썼다면 그 순간 13,000,000개가 열립니다. 즉시 이동 가능량을
 * 3%로 낮춘 설계 전체가 그날 무너집니다. (D-008)
 *
 * 그래서 클리프 대신 start를 2년 뒤로 미뤘고, 그 선택이 실제로
 * 작동하는지를 여기서 증명합니다.
 */
contract InventoryTest is Test {
    Token internal token;
    VestingWallet internal inventory;

    address internal treasury = makeAddr("treasury");
    address internal operations = makeAddr("operations");
    address internal stranger = makeAddr("stranger");

    uint64 internal deployedAt;
    uint64 internal start;

    uint64 internal constant START_DELAY = 730 days; // 배포 +2년
    uint64 internal constant DURATION = 2920 days; // 이후 8년

    uint256 internal constant INVENTORY_ALLOCATION = 65_000_000 ether; // 총량의 65%

    function setUp() public {
        vm.warp(1_800_000_000); // 결정적 테스트를 위한 고정 시각
        deployedAt = uint64(block.timestamp);
        start = deployedAt + START_DELAY;

        token = new Token("Test Token", "TEST", treasury);
        inventory = new VestingWallet(operations, start, DURATION);

        vm.prank(treasury);
        token.transfer(address(inventory), INVENTORY_ALLOCATION);
    }

    // ─── 파라미터가 공지한 대로인가 ─────────────────────────

    function test_ParametersMatchPublishedSchedule() public view {
        assertEq(inventory.owner(), operations, unicode"수령인이 운영 지갑이어야 합니다");
        assertEq(inventory.start(), start, unicode"시작은 배포 +2년이어야 합니다");
        assertEq(inventory.duration(), DURATION, unicode"해제 기간은 8년이어야 합니다");
        assertEq(inventory.start() + inventory.duration(), deployedAt + 3650 days, unicode"총 10년");
    }

    function test_FullAllocationIsLocked() public view {
        assertEq(token.balanceOf(address(inventory)), INVENTORY_ALLOCATION);
        assertEq(token.balanceOf(operations), 0, unicode"시작 시점에 운영 지갑 잔고는 0");
    }

    /// @notice 클리프 함수 자체가 없습니다. VestingWalletCliff가 아님을 확인합니다. (D-008)
    function test_NoCliffFunctionExists() public {
        (bool ok,) = address(inventory).call(abi.encodeWithSignature("cliff()"));
        assertFalse(ok, unicode"장기 재고에 cliff()가 있으면 안 됩니다");
    }

    // ─── 2년 동안 한 개도 나오지 않는다 ──────────────────────

    function test_NothingReleasableAtDeploy() public view {
        assertEq(vestedNow(), 0, unicode"배포 직후 해제량은 0이어야 합니다");
    }

    function test_NothingReleasableOneSecondBeforeStart() public {
        vm.warp(start - 1);
        assertEq(vestedNow(), 0, unicode"2년 -1초 시점에 0이어야 합니다");
    }

    /**
     * @notice 이 테스트가 이 파일에서 가장 중요합니다.
     *
     * 「2년 클리프 + 10년 선형」으로 걸었다면 이 시점에
     * 65,000,000 × 730 / 3650 = 13,000,000개(총량 13%)가 한 번에 열립니다.
     * 0이 나와야만 D-008이 코드로 지켜진 것입니다.
     */
    function test_NothingUnlocksAtTheStartMoment() public {
        vm.warp(start);
        assertEq(vestedNow(), 0, unicode"시작 정각에 열리는 물량이 있으면 안 됩니다");
    }

    /// @notice 시작 직후에도 계단이 아니라 초 단위로 조금씩 늘어납니다.
    function test_UnlockStartsFromZeroAndCrawls() public {
        vm.warp(start + 1);

        uint256 oneSecond = INVENTORY_ALLOCATION / DURATION; // 약 257개
        assertEq(vestedNow(), oneSecond);
        assertLt(vestedNow(), 1000 ether, unicode"시작 1초 뒤 해제량은 미미해야 합니다");
    }

    // ─── 시작 이후 선형 해제 ────────────────────────────────

    /// @notice 시작 +1년 (배포 +3년) 시점에 65,000,000 / 8 = 8,125,000
    function test_OneYearAfterStartReleasesOneEighth() public {
        vm.warp(start + 365 days);

        assertEq(vestedNow(), 8_125_000 ether, unicode"8년 중 1년치");
        assertEq(vestedNow(), INVENTORY_ALLOCATION / 8);
    }

    function test_HalfwayReleasesHalf() public {
        vm.warp(start + DURATION / 2);
        assertEq(vestedNow(), INVENTORY_ALLOCATION / 2);
    }

    /// @notice 배포 +10년 = 시작 +8년 시점에 전량 해제
    function test_FullyVestedAtTenYearsFromDeploy() public {
        vm.warp(deployedAt + 3650 days);
        assertEq(vestedNow(), INVENTORY_ALLOCATION, unicode"10년 시점에 65,000,000 전량");
    }

    function test_NoMoreThanAllocationAfterEnd() public {
        vm.warp(deployedAt + 7300 days); // 20년
        assertEq(
            vestedNow(),
            INVENTORY_ALLOCATION,
            unicode"기간이 지나도 배정량을 넘을 수 없습니다"
        );
    }

    // ─── 자금은 항상 수령인에게만 간다 ───────────────────────

    function test_ReleaseBeforeStartTransfersNothing() public {
        vm.warp(start - 1 days);

        inventory.release(address(token)); // 호출은 성공하되 금액이 0
        assertEq(token.balanceOf(operations), 0, unicode"시작 전에는 한 개도 나가면 안 됩니다");
    }

    function test_AnyoneCanCallReleaseButFundsGoToBeneficiary() public {
        vm.warp(start + 365 days);

        vm.prank(stranger);
        inventory.release(address(token));

        assertEq(token.balanceOf(operations), 8_125_000 ether);
        assertEq(token.balanceOf(stranger), 0, unicode"호출자가 가져갈 수 없습니다");
    }

    /// @notice 조기 인출 경로가 없습니다.
    function test_NoEmergencyWithdrawExists() public {
        (bool ok,) = address(inventory).call(abi.encodeWithSignature("emergencyWithdraw()"));
        assertFalse(ok, unicode"비상 인출 함수가 있으면 안 됩니다");

        (bool ok2,) =
            address(inventory).call(abi.encodeWithSignature("withdraw(address,uint256)", address(token), 1));
        assertFalse(ok2, unicode"임의 인출 함수가 있으면 안 됩니다");
    }

    // ─── 어떤 시점에도 배정량을 넘지 않는다 ───────────────────

    function testFuzz_ReleasableNeverExceedsAllocation(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, 7300 days)); // 배포 후 0 ~ 20년
        vm.warp(deployedAt + elapsed);

        assertLe(vestedNow(), INVENTORY_ALLOCATION, unicode"어떤 시점에도 배정량 초과 불가");
    }

    function testFuzz_NothingReleasableBeforeStart(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, START_DELAY)); // 배포 ~ 시작 정각까지
        vm.warp(deployedAt + elapsed);

        assertEq(vestedNow(), 0, unicode"시작 전 구간은 전부 0이어야 합니다");
    }

    function testFuzz_ReleaseIsMonotonic(uint64 t1, uint64 t2) public {
        t1 = uint64(bound(t1, 0, 3650 days));
        t2 = uint64(bound(t2, t1, 3650 days));

        vm.warp(deployedAt + t1);
        uint256 a = vestedNow();

        vm.warp(deployedAt + t2);
        uint256 b = vestedNow();

        assertGe(b, a, unicode"해제량은 시간에 따라 줄어들 수 없습니다");
    }

    // ─── 헬퍼 ────────────────────────────────────────────────

    /// @dev 아직 한 번도 release하지 않은 상태이므로 releasable == 누적 해제량입니다.
    function vestedNow() internal view returns (uint256) {
        return inventory.releasable(address(token));
    }
}
