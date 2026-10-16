# Gemini dollar

The Gemini dollar is an ERC20 compliant token backed by the U.S. dollar.

This repository contains the source of the Gemini dollar V1.1 token logic and supply controls, deployed to Ethereum
mainnet in October 2026. The original 2018 sources are in this repository's first commit.

## Deployed contracts (Ethereum mainnet)

| Contract | Address | Source |
| --- | --- | --- |
| ERC20Proxy (the token) | [`0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd`](https://etherscan.io/address/0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd#code) | unchanged since 2018 |
| ERC20Store | [`0xc42B14e49744538e3C239f8ae48A1Eaaf35e68a0`](https://etherscan.io/address/0xc42B14e49744538e3C239f8ae48A1Eaaf35e68a0#code) | unchanged since 2018 |
| ERC20Impl V1.1 | [`0x483A1E7F16F46266400f1bAF7abdF445c8D140A2`](https://etherscan.io/address/0x483A1E7F16F46266400f1bAF7abdF445c8D140A2#code) | `ERC20Impl.sol` |
| PrintLimiter V1.1 | [`0x342c1B88c2108f159a4Ef37e322B4170b18C42f6`](https://etherscan.io/address/0x342c1B88c2108f159a4Ef37e322B4170b18C42f6#code) | `PrintLimiter.sol` |
| InitializerV1dot1 | [`0x9De27967a2aD2D4bF0cD51C7c112a69D79f0b6bF`](https://etherscan.io/address/0x9De27967a2aD2D4bF0cD51C7c112a69D79f0b6bF#code) | `InitializerV1dot1.sol` |

The V1.1 contracts are verified on Etherscan with an exact match. The files here are byte-identical to the verified
sources, compiled with solc `0.8.30+commit.73712a01`, EVM version `shanghai`, optimizer enabled with 100,000 runs.

`ERC20Proxy.sol` and `ERC20Store.sol` here are the source the V1.1 contracts compile against. The Proxy and Store
deployed in 2018 were not redeployed; their deployed source is in the first commit.

## Contract Separation

The Gemini dollar token is not a single smart contract; instead, it is separated into three cooperating contracts.

### ERC20Proxy

This contract exposes the functions required by the ERC20 standard, and is the only contract with which a user will need to interact with. It is the permanent interface to the Gemini dollar.

### ERC20Impl

This contract encapsulates all the logic of the Gemini dollar token. _ERC20Proxy_ delegates all execution of ERC20 functions to its trusted instance _ERC20Impl_.

### ERC20Store

This contract owns the storage of the Gemini dollar ledger. Calls to the update functions on _ERC20Store_ are limited to its trusted instance of _ERC20Impl_.

## Custodianship

Each smart contract in the Gemini dollar system looks to a custodian for approval of important actions. This custodian may be another smart contract or a keyset (online or offline).

### CustodianUpgradeable and CustodianUpgradeableV1dot1

These contracts provide re-usable code for custodianship and provision for passing the custodian role. _ERC20Proxy_ and _ERC20Store_ inherit from _CustodianUpgradeable_, and _ERC20Impl_ inherits from _CustodianUpgradeableV1dot1_. Each inherits from its _LockRequestable_ counterpart, which provides a cooperatively universally unique identifier generation scheme.

## Upgradeability

The logical separation between the exposed ERC20 interface (_ERC20Proxy_), contract state (_ERC20Store_), and token logic (_ERC20Impl_) allows for upgradeability.

### ERC20ImplUpgradeable

This contract provides re-usable code for replacing the active token logic: the active instance of _ERC20Impl_. It itself inherits from _CustodianUpgradeable_ as the upgrade process is controlled by the custodian. Both _ERC20Proxy_ and _ERC20Store_ inherit from this contract.

### InitializerV1dot1

A one-time helper used during the V1.1 deployment to hand custodianship of the new _ERC20Impl_ to the new _PrintLimiter_ in a single transaction.

## Control of the Token Supply

Management of the token supply demands the security of an offline approval mechanism yet the flexibility of an online approval mechanism.

### PrintLimiter

This contract provides custodianship of _ERC20Impl_ to govern changes to the supply of Gemini dollar tokens, with an offline approval mechanism granting limited privileges to an online approval mechanism. The online key may increase the supply up to a ceiling, and may burn tokens from an address up to a seizure limit that each burn reduces. Only the custodian can raise the ceiling or the seizure limit; the online key can lower either. The custodian retains the ability to print directly and to change the custodian of _ERC20Impl_.

## Copyright

Copyright (c) 2018 Gemini Trust Company LLC. All Rights Reserved
