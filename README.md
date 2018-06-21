# Gemini dollar

The Gemini dollar is an ERC20 compliant token backed by the U.S. dollar.

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

### CustodianUpgradeable

This contract provides re-usable code for custodianship and provision for passing the custodian role. All of _ERC20Proxy_, _ERC20Impl_, and _ERC20Store_ inherit from this contract. This contract itself inherits from _LockRequestable_, which provides a cooperatively universally unique identifier generation scheme.

### Custodian

This contract provides general-purpose custodianship designed to be backed by an offline keyset. Approval requires dual control; time lock and revocation features are also provided.

## Upgradeability

The logical separation between the exposed ERC20 interface (_ERC20Proxy_), contract state (_ERC20Store_), and token logic (_ERC20Impl_) allows for upgradeability.

### ERC20ImplUpgradeable

This contract provides re-usable code for replacing the active token logic: the active instance of _ERC20Impl_. It itself inherits from _CustodianUpgradeable_ as the upgrade process is controlled by the custodian. Both _ERC20Proxy_ and _ERC20Store_ inherit from this contract.

## Control of the Token Supply

Management of the token supply demands the security of an offline approval mechanism yet the flexibility of an online approval mechanism.

### PrintLimiter

This contract provides custodianship of _ERC20Impl_ to govern increases to supply of Gemini dollar tokens, with an offline approval mechanism granting limited privileges to an online approval mechanism.

## Copyright

Copyright (c) 2018 Gemini Trust Company LLC. All Rights Reserved
