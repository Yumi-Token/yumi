// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VestingWalletCliff} from "@openzeppelin/contracts/finance/VestingWalletCliff.sol";

/**
 * @title FounderVesting
 * @notice 창업자 물량을 잠그는 베스팅 지갑. 6개월 클리프 + 24개월 선형 해제.
 *
 * 왜 이게 필요한가:
 *
 *   설계 문서의 원칙은 "공지한 것과 코드가 다르지 않게"입니다.
 *   락업을 공지만 하고 컨트랙트로 걸지 않는 것은 2026년 5월 국내 밈코인
 *   기소 사유 목록에 "허위 락업 공지로 안전성 가장"으로 명시돼 있습니다.
 *
 *   즉 이 컨트랙트의 목적은 덤핑 방지이기 이전에 검증 가능성입니다.
 *   주소를 공개하면 누구나 잠긴 물량과 해제 일정을 직접 확인할 수 있습니다.
 *
 * 동작:
 *   - start 시점부터 cliff 기간 동안은 0이 해제됩니다.
 *   - cliff 이후 duration 전체에 대해 선형 비례로 해제됩니다.
 *     (선형 계산의 기준점은 start이지 cliff가 아닙니다. 즉 클리프 직후
 *      6개월치가 한 번에 열립니다 — OpenZeppelin 표준 동작입니다.)
 *   - release(token)은 누구나 호출할 수 있고, 자금은 항상 beneficiary에게만 갑니다.
 *
 * 상속한 두 컨트랙트 모두 OpenZeppelin 표준이며 커스텀 로직은 없습니다.
 */
contract FounderVesting is VestingWalletCliff {
    /**
     * @param beneficiary     해제된 물량을 받을 주소
     * @param startTimestamp  베스팅 시작 시각 (unix seconds)
     * @param durationSeconds 전체 베스팅 기간 (기본 24개월)
     * @param cliffSeconds    클리프 기간 (기본 6개월). durationSeconds 이하여야 합니다.
     */
    constructor(address beneficiary, uint64 startTimestamp, uint64 durationSeconds, uint64 cliffSeconds)
        VestingWallet(beneficiary, startTimestamp, durationSeconds)
        VestingWalletCliff(cliffSeconds)
    {}
}
