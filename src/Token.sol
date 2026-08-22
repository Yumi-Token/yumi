// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title Token
 * @notice 고정 공급 ERC-20. 생성자에서 전량 발행하고 그 뒤로는 발행이 불가능합니다.
 *
 * 설계 원칙 — 이 컨트랙트에 없는 것들이 곧 설계입니다:
 *
 *  - mint 함수가 없습니다.
 *      추가 발행을 "안 하겠다"는 약속이 아니라 "할 수 없는" 구조입니다.
 *      totalSupply()는 소각을 제외하면 영원히 고정입니다.
 *
 *  - Ownable이 없습니다.
 *      소유자 권한이라는 개념 자체가 존재하지 않습니다.
 *      일시정지, 블랙리스트, 강제 회수, 수수료 변경 — 전부 불가능합니다.
 *
 *  - 전송 수수료가 없습니다.
 *      transfer는 표준 그대로입니다. DEX·지갑·거래소 호환성 문제가 생기지 않습니다.
 *
 *  - 커스텀 로직이 없습니다.
 *      감사받지 않은 코드에 남의 돈을 올리지 않기 위한 선택입니다.
 *      상속한 두 컨트랙트는 모두 OpenZeppelin 표준입니다.
 *
 * ERC20Burnable이 더하는 것은 burn / burnFrom 두 함수뿐이며,
 * 보유자가 자기 토큰(또는 승인받은 토큰)만 소각할 수 있으므로
 * 발행자에게 어떤 권한도 주지 않습니다.
 */
contract Token is ERC20, ERC20Burnable {
    /// @notice 총 발행량 1억 개 (18 decimals)
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether;

    /// @dev treasury 주소가 0이면 배포를 중단합니다. 전량이 소각 주소로 가는 사고를 막습니다.
    error TreasuryIsZeroAddress();

    /**
     * @param name_     토큰 이름 (배포 후 변경 불가)
     * @param symbol_   토큰 심볼 (배포 후 변경 불가)
     * @param treasury  전량을 수령할 주소. 이후 배분은 여기서 시작합니다.
     */
    constructor(string memory name_, string memory symbol_, address treasury) ERC20(name_, symbol_) {
        if (treasury == address(0)) revert TreasuryIsZeroAddress();
        _mint(treasury, INITIAL_SUPPLY);
    }
}
