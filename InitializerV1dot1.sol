// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2020 Gemini Trust Company LLC. All Rights Reserved
pragma solidity ^0.8.0;

import "./ERC20Impl.sol";

contract InitializerV1dot1 {
    ERC20Impl public immutable impl;
    address public immutable printCustodian;
    bool public initialized;

    constructor(address _impl, address _printCustodian) {
        require(_impl != address(0), "zero impl");
        require(_printCustodian != address(0), "zero custodian");

        impl = ERC20Impl(_impl);
        printCustodian = _printCustodian;
    }

    function initialize() external {
        require(!initialized, "already initialized");
        initialized = true;

        // Pass custodianship of the pinned impl to the pinned print custodian.
        impl.confirmCustodianChange(impl.requestCustodianChange(printCustodian));
    }
}
