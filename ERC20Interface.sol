// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2020 Gemini Trust Company LLC. All Rights Reserved
pragma solidity ^0.8.0;

interface ERC20Interface {
  // METHODS

  // NOTE:
  //   public getter functions are not currently recognised as an
  //   implementation of the matching abstract function by the compiler.

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#name
  // function name() public view returns (string);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#symbol
  // function symbol() public view returns (string);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#totalsupply
  // function decimals() public view returns (uint8);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#totalsupply
  function totalSupply() external view returns (uint256);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#balanceof
  function balanceOf(address _owner) external view returns (uint256 balance);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#transfer
  function transfer(address _to, uint256 _value) external returns (bool success);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#transferfrom
  function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#approve
  function approve(address _spender, uint256 _value) external returns (bool success);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#allowance
  function allowance(address _owner, address _spender) external view returns (uint256 remaining);

  // EVENTS
  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#transfer-1
  event Transfer(address indexed _from, address indexed _to, uint256 _value);

  // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md#approval
  event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}
