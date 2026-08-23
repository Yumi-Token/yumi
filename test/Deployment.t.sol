// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Token} from "../src/Token.sol";
import {FounderVesting} from "../src/FounderVesting.sol";
import {Deploy} from "../script/Deploy.s.sol";

/**
 * @notice 배포 전체 구성이 공개 문서와 일치하는지 검증합니다.
 *
 * 여기서 검증하는 것은 컨트랙트 하나가 아니라 **공개한 주장**입니다.
 *   - 배분의 합이 총 발행량과 같은가
 *   - 두 베스팅의 수령 주소가 타임락인가
 *   - 예고 없이 움직일 수 있는 양이 정말 5,000,000인가
 *   - 타임락에 admin이 없고 실행은 열려 있는가
 *
 * docs/TOKENOMICS.md의 숫자와 어긋나면 여기가 먼저 깨져야 합니다.
 */
contract DeploymentTest is Test {
    Token internal token;
    FounderVesting internal founderVesting;
    VestingWallet internal inventoryVesting;
    TimelockController internal timelock;

    address internal deployer = makeAddr("deployer");
    address internal safe = makeAddr("safe");

    uint64 internal deployedAt;

    uint256 internal constant FOUNDER = 20_000_000 ether;
    uint256 internal constant INVENTORY = 65_000_000 ether;
    uint256 internal constant OPERATIONS = 10_000_000 ether;
    uint256 internal constant NEAR_TERM = 5_000_000 ether;

    uint64 internal constant CLIFF = 90 days;
    uint64 internal constant FOUNDER_DURATION = 365 days;
    uint64 internal constant INVENTORY_START_DELAY = 365 days;
    uint64 internal constant INVENTORY_DURATION = 1095 days;
    uint256 internal constant MIN_DELAY = 7 days;

    /// @dev 초기 LP 투입량 — docs/TOKENOMICS.md 「초기 구간」, D-016
    uint256 internal constant INITIAL_LIQUIDITY = 4_000_000 ether;

    /// @dev script/Deploy.s.sol 과 같은 순서로 배포합니다.
    function setUp() public {
        vm.warp(1_800_000_000);
        deployedAt = uint64(block.timestamp);

        vm.startPrank(deployer);

        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new TimelockController(MIN_DELAY, proposers, executors, address(0));
        token = new Token(unicode"Yumi", unicode"YUMI", deployer);
        founderVesting = new FounderVesting(address(timelock), deployedAt, FOUNDER_DURATION, CLIFF);
        inventoryVesting =
            new VestingWallet(address(timelock), deployedAt + INVENTORY_START_DELAY, INVENTORY_DURATION);

        token.transfer(address(founderVesting), FOUNDER);
        token.transfer(address(inventoryVesting), INVENTORY);
        token.transfer(address(timelock), OPERATIONS);

        vm.stopPrank();
    }

    // ─── 배포 스크립트가 이 파일과 같은 숫자를 쓰는가 ─────────

    /**
     * @notice script/Deploy.s.sol 의 상수를 직접 읽어 대조합니다.
     *
     * 이 테스트가 없으면 배포 스크립트의 숫자만 바꿔도 나머지 테스트가
     * 전부 통과합니다. 이 파일과 Inventory.t.sol 은 값을 각자 하드코딩하고
     * 있어서, 실제로 배포되는 값과 연결되는 지점이 여기 하나뿐입니다.
     *
     * 깨지면 docs/TOKENOMICS.md 까지 세 곳을 같이 맞춰야 한다는 뜻입니다.
     */
    function test_DeployScriptUsesTheSameNumbers() public {
        Deploy script = new Deploy();

        assertEq(script.FOUNDER_ALLOCATION(), FOUNDER, unicode"창업자 20,000,000");
        assertEq(script.INVENTORY_ALLOCATION(), INVENTORY, unicode"장기 재고 65,000,000");
        assertEq(script.OPERATIONS_ALLOCATION(), OPERATIONS, unicode"운영 예비 10,000,000");
        assertEq(script.NEAR_TERM_ALLOCATION(), NEAR_TERM, unicode"근거리 재고 5,000,000");

        assertEq(script.CLIFF_SECONDS(), CLIFF, unicode"창업자 클리프 90일");
        assertEq(script.VESTING_DURATION(), FOUNDER_DURATION, unicode"창업자 베스팅 365일");
        assertEq(script.INVENTORY_START_DELAY(), INVENTORY_START_DELAY, unicode"재고 시작 +365일");
        assertEq(script.INVENTORY_DURATION(), INVENTORY_DURATION, unicode"재고 해제 1095일");
        assertEq(script.TIMELOCK_MIN_DELAY(), MIN_DELAY, unicode"타임락 7일");
    }

    /**
     * @notice 이름과 심볼이 자리표시자가 아닌지 고정합니다.
     *
     * 배포하면 영원히 못 바꾸는 값인데 개발 중에는 "Test Token"으로 두기 쉽습니다.
     * 이 테스트가 실패하면 누군가 되돌린 것입니다. (D-027)
     */
    function test_TokenNameAndSymbolAreFinal() public {
        Deploy script = new Deploy();

        // 배포 스크립트의 값
        assertEq(script.TOKEN_NAME(), unicode"Yumi", unicode"배포 스크립트의 이름");
        assertEq(script.TOKEN_SYMBOL(), unicode"YUMI", unicode"배포 스크립트의 심볼");

        // 이 테스트가 재현한 배포도 같은 값이어야 합니다
        assertEq(token.name(), script.TOKEN_NAME(), unicode"재현 배포와 스크립트가 어긋남");
        assertEq(token.symbol(), script.TOKEN_SYMBOL(), unicode"재현 배포와 스크립트가 어긋남");

        assertTrue(
            keccak256(bytes(script.TOKEN_NAME())) != keccak256(bytes("Test Token")),
            unicode"자리표시자로 되돌아갔습니다"
        );
    }

    // ─── 배분 불변식 ────────────────────────────────────────

    function test_AllocationsSumToTotalSupply() public view {
        assertEq(FOUNDER + INVENTORY + OPERATIONS + NEAR_TERM, token.INITIAL_SUPPLY());
    }

    function test_EveryTokenIsAccountedFor() public view {
        uint256 sum = token.balanceOf(address(founderVesting)) + token.balanceOf(address(inventoryVesting))
            + token.balanceOf(address(timelock)) + token.balanceOf(deployer);

        assertEq(
            sum, token.totalSupply(), unicode"어느 주소에도 없는 물량이 있으면 안 됩니다"
        );
    }

    function test_BucketBalancesMatchDocuments() public view {
        assertEq(token.balanceOf(address(founderVesting)), FOUNDER);
        assertEq(token.balanceOf(address(inventoryVesting)), INVENTORY);
        assertEq(token.balanceOf(address(timelock)), OPERATIONS);
        assertEq(token.balanceOf(deployer), NEAR_TERM);
    }

    // ─── 공개한 헤드라인 숫자 ────────────────────────────────

    /**
     * @notice 「예고 없이 움직일 수 있는 양」의 검증.
     *
     * 배포 직후에는 근거리 재고 5,000,000 뿐이고,
     * 초기 LP에 4,000,000을 넣으면 1,000,000(총량의 1%)이 남습니다. (D-016)
     */
    function test_UnannouncedMovableIsNearTermOnly() public view {
        assertEq(token.balanceOf(deployer), 5_000_000 ether, unicode"배포 직후 근거리 재고");
        assertEq(
            token.balanceOf(deployer) - INITIAL_LIQUIDITY,
            1_000_000 ether,
            unicode"초기 LP 투입 후 남는 양 = 총량의 1%"
        );
    }

    /**
     * @notice 재고 시작 시점이 창업자 베스팅 종료와 맞물려야 합니다.
     *
     * 두 일정을 따로 고치다가 사이에 빈 구간이나 겹침이 생기는 것을 막습니다.
     * 겹치면 그 구간에 해제 속도가 두 배가 됩니다.
     */
    function test_InventoryStartsWhenFounderVestingEnds() public view {
        assertEq(
            inventoryVesting.start(),
            founderVesting.start() + founderVesting.duration(),
            unicode"재고 시작 = 창업자 종료 (D-020)"
        );
    }

    /// @notice 이 둘이 타임락이어야 「1%」가 시간에 대해 참이 됩니다.
    function test_BothVestingBeneficiariesAreTimelock() public view {
        assertEq(founderVesting.owner(), address(timelock), unicode"창업자 베스팅 수령 주소");
        assertEq(inventoryVesting.owner(), address(timelock), unicode"장기 재고 수령 주소");
    }

    /**
     * @notice 10년이 지나 전부 해제돼도 발행자 지갑으로 직행하는 물량이 없습니다.
     *
     * 이 테스트가 깨지면 「10년 뒤 86%」 설계로 되돌아간 것입니다.
     */
    function test_NothingReachesDeployerDirectlyAfterTenYears() public {
        uint256 before = token.balanceOf(deployer);

        vm.warp(deployedAt + 3650 days);
        founderVesting.release(address(token));
        inventoryVesting.release(address(token));

        assertEq(
            token.balanceOf(deployer), before, unicode"해제분은 전부 타임락으로 가야 합니다"
        );
        assertEq(token.balanceOf(address(timelock)), OPERATIONS + FOUNDER + INVENTORY);
    }

    // ─── 타임락 구성 ────────────────────────────────────────

    function test_MinDelayIsSevenDays() public view {
        assertEq(timelock.getMinDelay(), 7 days);
    }

    /// @notice 외부 admin이 없어야 합니다. 배포 후 renounce할 필요도 없습니다.
    function test_NoExternalAdmin() public view {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        assertFalse(timelock.hasRole(adminRole, deployer), unicode"배포자가 admin이면 안 됩니다");
        assertFalse(timelock.hasRole(adminRole, safe), unicode"Safe가 admin이면 안 됩니다");
        assertTrue(
            timelock.hasRole(adminRole, address(timelock)), unicode"자기 자신은 admin입니다 (표준)"
        );
    }

    function test_OnlyOperatorCanPropose() public view {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();

        assertTrue(timelock.hasRole(proposerRole, safe));
        assertFalse(
            timelock.hasRole(proposerRole, address(0)), unicode"예약까지 열려 있으면 안 됩니다"
        );
    }

    /// @notice 실행은 누구나 할 수 있어야 합니다. 키를 잃어도 물량이 브릭되지 않습니다.
    function test_ExecutionIsOpenToAnyone() public view {
        assertTrue(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)),
            unicode"실행은 열려 있어야 합니다"
        );
    }

    /**
     * @notice proposer가 배포 지갑이면 안 됩니다.
     *
     * 이게 깨지면 D-007의 영구 동결 구조입니다 — 키 하나가 예약과 취소를
     * 동시에 쥐면 공격자도 나도 물량을 못 옮깁니다.
     */
    function test_ProposerIsNotTheDeployer() public view {
        assertFalse(
            timelock.hasRole(timelock.PROPOSER_ROLE(), deployer),
            unicode"배포 지갑이 proposer면 안 됩니다 (D-019)"
        );
    }

    /**
     * @notice 배포 지갑은 취소 권한도 없어야 합니다.
     *
     * CANCELLER는 PROPOSER와 함께 부여되므로 위 테스트와 짝입니다.
     */
    function test_DeployerHasNoCancellerRole() public view {
        assertFalse(
            timelock.hasRole(timelock.CANCELLER_ROLE(), deployer),
            unicode"배포 지갑이 취소 권한을 가지면 안 됩니다 (D-007)"
        );
    }

    // ─── 타임락은 실제로 지연을 강제하는가 ───────────────────

    function test_CannotExecuteWithoutScheduling() public {
        bytes memory data = abi.encodeCall(token.transfer, (safe, 1 ether));

        vm.expectRevert();
        timelock.execute(address(token), 0, data, bytes32(0), bytes32("s1"));
    }

    function test_CannotExecuteBeforeDelayPasses() public {
        bytes memory data = abi.encodeCall(token.transfer, (safe, 1 ether));

        vm.prank(safe);
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("s1"), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY - 1);
        vm.expectRevert();
        timelock.execute(address(token), 0, data, bytes32(0), bytes32("s1"));
    }

    function test_ExecutesAfterDelay() public {
        bytes memory data = abi.encodeCall(token.transfer, (safe, 1 ether));

        vm.prank(safe);
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("s1"), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        timelock.execute(address(token), 0, data, bytes32(0), bytes32("s1"));

        assertEq(token.balanceOf(safe), 1 ether);
    }

    /**
     * @notice 같은 작업을 두 번 예약하려면 salt를 바꿔야 합니다.
     *
     * collect()처럼 calldata가 매번 같은 호출을 반복할 때 반드시 걸리는 함정이라
     * 문서(TOKENOMICS.md)에 적어두고 여기서 고정합니다.
     */
    function test_SameOperationCannotBeScheduledTwice() public {
        bytes memory data = abi.encodeCall(token.transfer, (safe, 1 ether));

        vm.startPrank(safe);
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("same"), MIN_DELAY);

        vm.expectRevert();
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("same"), MIN_DELAY);

        // salt를 바꾸면 통과합니다
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("different"), MIN_DELAY);
        vm.stopPrank();
    }

    /// @notice 타임락이 ERC-721(LP 포지션 NFT)을 받을 수 있어야 합니다.
    function test_TimelockCanReceiveERC721() public {
        bytes4 selector = timelock.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, bytes4(0x150b7a02), unicode"LP 포지션 NFT를 보관할 수 있어야 합니다");
    }

    /// @notice 7일보다 짧은 지연으로는 예약 자체가 되지 않습니다.
    function test_CannotScheduleWithShorterDelay() public {
        bytes memory data = abi.encodeCall(token.transfer, (safe, 1 ether));

        vm.prank(safe);
        vm.expectRevert();
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("s1"), MIN_DELAY - 1);
    }

    /**
     * @notice 예약은 공개된 사실입니다 — 「예약이 곧 사전 공지」의 실체.
     *
     * 예약하는 순간 CallScheduled 이벤트가 남고, 실행 예정 시각을
     * 누구나 getTimestamp로 조회할 수 있습니다. 이것이 없으면
     * D-007의 「7일은 주간 기록 주기와 맞다」는 근거가 성립하지 않습니다.
     */
    function test_ScheduledOperationIsPubliclyVisible() public {
        bytes memory data = abi.encodeCall(token.transfer, (safe, 1 ether));
        bytes32 id = timelock.hashOperation(address(token), 0, data, bytes32(0), bytes32("s1"));

        assertFalse(timelock.isOperation(id), unicode"예약 전에는 조회되지 않습니다");

        vm.prank(safe);
        timelock.schedule(address(token), 0, data, bytes32(0), bytes32("s1"), MIN_DELAY);

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

    /**
     * @notice 지연 시간 변경조차 타임락을 거쳐야 합니다.
     *
     * Safe가 updateDelay(0)을 직접 부를 수 있다면 7일은 언제든
     * 사라질 수 있는 숫자가 되고, 「예고 없이 움직일 수 있는 양」 주장이 무너집니다.
     */
    function test_MinDelayCannotBeChangedDirectly() public {
        vm.prank(safe);
        vm.expectRevert();
        timelock.updateDelay(0);

        assertEq(timelock.getMinDelay(), MIN_DELAY, unicode"지연이 그대로여야 합니다");
    }
}
