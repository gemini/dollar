// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2020 Gemini Trust Company LLC. All Rights Reserved
pragma solidity ^0.8.0;

/** @title  A contract for generating unique identifiers
  *
  * @notice  A contract that provides a identifier generation scheme,
  * guaranteeing uniqueness across all contracts that inherit from it,
  * as well as unpredictability of future identifiers.
  *
  * @dev  This contract is intended to be inherited by any contract that
  * implements the callback software pattern for cooperative custodianship.
  *
  * @author  Gemini Trust Company, LLC
  */
abstract contract LockRequestableV1dot1 {

    // MEMBERS
    /// @notice  the count of all invocations of `generatePreLockId`.
    uint256 public lockRequestCount;

    // CONSTRUCTOR
    constructor() {
        lockRequestCount = 0;
    }

    // FUNCTIONS
    /** @notice  Returns a fresh unique identifier.
      *
      * @dev the generation scheme uses three components.
      * First, the blockhash of the previous block.
      * Second, the deployed address.
      * Third, the next value of the counter.
      * This ensure that identifiers are unique across all contracts
      * following this scheme, and that future identifiers are
      * unpredictable.
      *
      * @return preLockId a 32-byte unique identifier.
      * @return lockRequestIdx index of lock request

      */
    function generatePreLockId() internal returns (bytes32 preLockId, uint256 lockRequestIdx) {
        unchecked {
            // unchecked `-` is safe as this can never be evaluated in the genesis (0) block
            // unchecked `++` is safe as it is infeasible to exhaust 256-bit integer counter
            lockRequestIdx = ++lockRequestCount;
            preLockId = keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    address(this),
                    lockRequestIdx
                )
            );
        }
    }
}
