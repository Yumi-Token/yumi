// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

/**
 * @notice 설계 문서의 주장이 실제로 코드에 의해 보증되는지 검증합니다.
 *
 * 이 테스트들은 「기능이 동작하는가」보다 「약속한 제약이 정말 존재하는가」를
 * 확인하기 위한 것입니다. 백서에 쓸 문장 하나하나가 여기서 증명됩니다.
 */
contract TokenTest is Test {
    Token internal token;

    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant SUPPLY = 100_000_000 ether;

    function setUp() public {
        token = new Token("Test Token", "TEST", treasury);
    }

    // ─── 공급량 ───────────────────────────────────────────

    function test_TotalSupplyIsOneHundredMillion() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), 100_000_000 * 10 ** 18);
    }

    function test_EntireSupplyGoesToTreasury() public view {
        assertEq(token.balanceOf(treasury), SUPPLY);
    }

    function test_DecimalsIsEighteen() public view {
        assertEq(token.decimals(), 18);
    }

    function test_DeployRevertsIfTreasuryIsZero() public {
        vm.expectRevert(Token.TreasuryIsZeroAddress.selector);
        new Token("X", "X", address(0));
    }

    // ─── 발행 권한이 존재하지 않는다 ────────────────────────

    /**
     * @notice 이 컨트랙트에 mint 함수가 없다는 것을 증명합니다.
     *
     * 존재하지 않는 함수를 호출하면 fallback이 없으므로 revert합니다.
     * 즉 「추가 발행을 안 하겠다」가 아니라 「할 수 없다」입니다.
     */
    function test_NoMintFunctionExists() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1 ether));
        assertFalse(ok, unicode"mint(address,uint256)가 존재해서는 안 됩니다");

        (bool ok2,) = address(token).call(abi.encodeWithSignature("mint(uint256)", 1 ether));
        assertFalse(ok2, unicode"mint(uint256)가 존재해서는 안 됩니다");
    }

    /// @notice 소유자 권한이라는 개념 자체가 없습니다.
    function test_NoOwnerFunctionExists() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, unicode"owner()가 존재해서는 안 됩니다");

        (bool ok2,) = address(token).call(abi.encodeWithSignature("transferOwnership(address)", alice));
        assertFalse(ok2, unicode"transferOwnership가 존재해서는 안 됩니다");
    }

    /// @notice 일시정지·블랙리스트 같은 통제 장치가 없습니다.
    function test_NoPauseOrBlacklistExists() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("pause()"));
        assertFalse(ok, unicode"pause()가 존재해서는 안 됩니다");

        (bool ok2,) = address(token).call(abi.encodeWithSignature("blacklist(address)", alice));
        assertFalse(ok2, unicode"blacklist가 존재해서는 안 됩니다");
    }

    // ─── 전송이 표준 그대로다 ──────────────────────────────

    /// @notice 전송 수수료가 없어 받은 금액과 보낸 금액이 정확히 같습니다.
    function test_TransferHasNoFee() public {
        vm.prank(treasury);
        token.transfer(alice, 1000 ether);

        assertEq(token.balanceOf(alice), 1000 ether, unicode"수수료가 붙으면 안 됩니다");
        assertEq(token.balanceOf(treasury), SUPPLY - 1000 ether);
    }

    function testFuzz_TransferPreservesTotalSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);

        vm.prank(treasury);
        token.transfer(alice, amount);

        assertEq(token.totalSupply(), SUPPLY, unicode"전송으로 총량이 변하면 안 됩니다");
        assertEq(token.balanceOf(alice) + token.balanceOf(treasury), SUPPLY);
    }

    // ─── 소각 ─────────────────────────────────────────────

    /// @notice 보유자는 자기 토큰을 소각할 수 있고, 총량이 실제로 줄어듭니다.
    function test_HolderCanBurnOwnTokens() public {
        vm.prank(treasury);
        token.transfer(alice, 1000 ether);

        vm.prank(alice);
        token.burn(400 ether);

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.totalSupply(), SUPPLY - 400 ether, unicode"소각 후 총량이 줄어야 합니다");
    }

    /// @notice 승인 없이 남의 토큰을 소각할 수 없습니다. 발행자도 예외가 아닙니다.
    function test_CannotBurnOthersTokensWithoutAllowance() public {
        vm.prank(treasury);
        token.transfer(alice, 1000 ether);

        vm.prank(bob);
        vm.expectRevert();
        token.burnFrom(alice, 100 ether);

        vm.prank(treasury);
        vm.expectRevert();
        token.burnFrom(alice, 100 ether);

        assertEq(token.balanceOf(alice), 1000 ether, unicode"남의 잔고가 변하면 안 됩니다");
    }

    /// @notice 소각은 되돌릴 수 없습니다 — 소각 후 재발행 경로가 없음을 확인합니다.
    function test_BurnIsIrreversible() public {
        vm.prank(treasury);
        token.burn(1_000_000 ether);

        uint256 reduced = SUPPLY - 1_000_000 ether;
        assertEq(token.totalSupply(), reduced);

        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", treasury, 1 ether));
        assertFalse(ok, unicode"소각분을 다시 발행할 방법이 없어야 합니다");
        assertEq(token.totalSupply(), reduced);
    }

    // ─── 이벤트 (DAXA 심사 기준 ③) ──────────────────────────

    /**
     * @notice 전송과 소각이 이벤트를 emit하는지 확인합니다.
     *
     * DAXA 공통 거래지원 심사 기준 ③은 발행·소각·권한변경 등
     * 중요 기능에 이벤트 함수가 구현돼 있을 것을 요구합니다.
     * 거래소 모니터링이 이 이벤트를 읽습니다.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_TransferEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(treasury, alice, 500 ether);

        vm.prank(treasury);
        token.transfer(alice, 500 ether);
    }

    function test_BurnEmitsTransferToZeroAddress() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(treasury, address(0), 500 ether);

        vm.prank(treasury);
        token.burn(500 ether);
    }

    function test_MintEmittedAtDeploy() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), treasury, SUPPLY);

        new Token("Test Token", "TEST", treasury);
    }
}
