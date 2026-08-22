// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Token} from "../src/Token.sol";

/**
 * @notice 운영·예비 10,000,000 이 7일 예약 없이는 움직이지 않는지 검증합니다.
 *
 * 7일인 이유는 주간 기록 주기와 맞기 때문입니다. 운영 물량이 움직이면
 * 그 주 로그에 먼저 나오고 다음 주에 실행됩니다 — 예약이 곧 사전 공지입니다. (D-007)
 *
 * 여기서 통과하는 항목만 「예고 없이 움직일 수 있는 양은 3%」라는 문장의 근거가 됩니다.
 */
contract TimelockTest is Test {
    Token internal token;
    TimelockController internal timelock;

    address internal treasury = makeAddr("treasury");
    address internal operations = makeAddr("operations");
    address internal stranger = makeAddr("stranger");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant MIN_DELAY = 7 days;
    uint256 internal constant OPERATIONS_ALLOCATION = 10_000_000 ether; // 총량의 10%

    bytes32 internal constant NO_PREDECESSOR = bytes32(0);
    bytes32 internal constant SALT = bytes32(uint256(1));

    function setUp() public {
        vm.warp(1_800_000_000); // 결정적 테스트를 위한 고정 시각

        address[] memory proposers = new address[](1);
        proposers[0] = operations;
        address[] memory executors = new address[](1);
        executors[0] = operations;

        token = new Token("Test Token", "TEST", treasury);
        // 마지막 인자 admin = address(0) — 관리자 권한을 처음부터 만들지 않습니다.
        timelock = new TimelockController(MIN_DELAY, proposers, executors, address(0));

        vm.prank(treasury);
        token.transfer(address(timelock), OPERATIONS_ALLOCATION);
    }

    // ─── 파라미터가 공지한 대로인가 ─────────────────────────

    function test_MinDelayIsSevenDays() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY, unicode"지연은 7일이어야 합니다");
        assertEq(timelock.getMinDelay(), 7 days);
    }

    function test_OperationsHoldsProposerAndExecutorRoles() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), operations));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), operations));
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), stranger));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), stranger));
    }

    /**
     * @notice 배포자에게 관리자 권한이 남아 있지 않은지 확인합니다.
     *
     * 관리자가 있으면 역할을 바꿔 7일을 우회할 수 있습니다.
     * admin = address(0)으로 배포했으므로 관리자는 타임락 자신뿐이고,
     * 역할 변경조차 7일 예약을 거쳐야 합니다.
     */
    function test_NoExternalAdminExists() public view {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        assertFalse(
            timelock.hasRole(adminRole, address(this)),
            unicode"배포자에게 관리자 권한이 없어야 합니다"
        );
        assertFalse(
            timelock.hasRole(adminRole, operations), unicode"운영 지갑도 관리자가 아닙니다"
        );
        assertTrue(
            timelock.hasRole(adminRole, address(timelock)), unicode"관리자는 타임락 자신뿐입니다"
        );
    }

    function test_FullAllocationIsHeld() public view {
        assertEq(token.balanceOf(address(timelock)), OPERATIONS_ALLOCATION);
    }

    // ─── 예약 없이는 움직이지 않는다 ─────────────────────────

    /// @notice 예약하지 않은 작업은 실행되지 않습니다.
    function test_ExecuteWithoutScheduleReverts() public {
        vm.prank(operations);
        vm.expectRevert();
        timelock.execute(address(token), 0, transferPayload(1_000_000 ether), NO_PREDECESSOR, SALT);

        assertEq(token.balanceOf(recipient), 0, unicode"한 개도 나가면 안 됩니다");
    }

    /// @notice 7일이 지나기 1초 전까지는 실행되지 않습니다.
    function test_ExecuteBeforeDelayReverts() public {
        bytes memory payload = transferPayload(1_000_000 ether);

        vm.prank(operations);
        timelock.schedule(address(token), 0, payload, NO_PREDECESSOR, SALT, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY - 1);

        vm.prank(operations);
        vm.expectRevert();
        timelock.execute(address(token), 0, payload, NO_PREDECESSOR, SALT);

        assertEq(token.balanceOf(recipient), 0, unicode"7일 전에는 한 개도 나가면 안 됩니다");
    }

    /// @notice 7일보다 짧은 지연으로는 예약 자체가 되지 않습니다.
    function test_ScheduleWithShorterDelayReverts() public {
        vm.prank(operations);
        vm.expectRevert();
        timelock.schedule(
            address(token), 0, transferPayload(1_000_000 ether), NO_PREDECESSOR, SALT, MIN_DELAY - 1
        );
    }

    /// @notice 제안자 권한이 없으면 예약할 수 없습니다.
    function test_StrangerCannotSchedule() public {
        vm.prank(stranger);
        vm.expectRevert();
        timelock.schedule(
            address(token), 0, transferPayload(1_000_000 ether), NO_PREDECESSOR, SALT, MIN_DELAY
        );
    }

    /// @notice 실행자 권한이 없으면 7일이 지나도 실행할 수 없습니다.
    function test_StrangerCannotExecuteAfterDelay() public {
        bytes memory payload = transferPayload(1_000_000 ether);

        vm.prank(operations);
        timelock.schedule(address(token), 0, payload, NO_PREDECESSOR, SALT, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        vm.prank(stranger);
        vm.expectRevert();
        timelock.execute(address(token), 0, payload, NO_PREDECESSOR, SALT);
    }

    // ─── 7일이 지나면 움직인다 ───────────────────────────────

    /// @notice 정상 경로 — 예약하고 7일 기다리면 실행됩니다.
    function test_ExecuteAfterDelaySucceeds() public {
        bytes memory payload = transferPayload(1_000_000 ether);

        vm.prank(operations);
        timelock.schedule(address(token), 0, payload, NO_PREDECESSOR, SALT, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        vm.prank(operations);
        timelock.execute(address(token), 0, payload, NO_PREDECESSOR, SALT);

        assertEq(token.balanceOf(recipient), 1_000_000 ether);
        assertEq(token.balanceOf(address(timelock)), OPERATIONS_ALLOCATION - 1_000_000 ether);
    }

    /**
     * @notice 예약은 공개된 사실입니다.
     *
     * 예약하는 순간 CallScheduled 이벤트가 남고 getTimestamp로 실행 예정
     * 시각을 누구나 조회할 수 있습니다. 이것이 「사전 공지」의 실체입니다.
     */
    function test_ScheduledOperationIsPubliclyVisible() public {
        bytes memory payload = transferPayload(1_000_000 ether);
        bytes32 id = timelock.hashOperation(address(token), 0, payload, NO_PREDECESSOR, SALT);

        assertFalse(timelock.isOperation(id), unicode"예약 전에는 조회되지 않습니다");

        vm.prank(operations);
        timelock.schedule(address(token), 0, payload, NO_PREDECESSOR, SALT, MIN_DELAY);

        assertTrue(
            timelock.isOperation(id), unicode"예약되면 누구나 조회할 수 있어야 합니다"
        );
        assertTrue(timelock.isOperationPending(id));
        assertEq(
            timelock.getTimestamp(id),
            block.timestamp + MIN_DELAY,
            unicode"실행 예정 시각이 공개됩니다"
        );
    }

    /// @notice 지연 시간 변경조차 타임락을 거쳐야 합니다 — 즉시 0으로 낮출 수 없습니다.
    function test_MinDelayCannotBeChangedDirectly() public {
        vm.prank(operations);
        vm.expectRevert();
        timelock.updateDelay(0);

        assertEq(timelock.getMinDelay(), MIN_DELAY, unicode"지연이 그대로여야 합니다");
    }

    // ─── 헬퍼 ────────────────────────────────────────────────

    function transferPayload(uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(token.transfer.selector, recipient, amount);
    }
}
