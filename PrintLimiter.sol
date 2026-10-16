// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2020 Gemini Trust Company LLC. All Rights Reserved
pragma solidity ^0.8.0;

import "./ERC20Impl.sol";
import "./LockRequestableV1dot1.sol";

/** @title  A contact to govern hybrid control over increases to the token supply.
  *
  * @notice  A contract that acts as a custodian of the active token
  * implementation, and an intermediary between it and the ‘true’ custodian.
  * It preserves the functionality of direct custodianship as well as granting
  * limited control of token supply increases to an additional key.
  *
  * @dev  This contract is a layer of indirection between an instance of
  * ERC20Impl and a custodian. The functionality of the custodianship over
  * the token implementation is preserved (printing and custodian changes),
  * but this contract adds the ability for an additional key
  * (the 'limited printer') to increase the token supply up to a ceiling,
  * and this supply ceiling can only be raised by the custodian.
  *
  * @author  Gemini Trust Company, LLC
  */
contract PrintLimiter is LockRequestableV1dot1 {

    // TYPES
    /// @dev The struct type for ceiling/limit raises.
    struct Raise {
        uint256 raiseBy;
    }

    // MEMBERS
    /// @dev  The reference to the active token implementation.
    ERC20Impl immutable public erc20Impl;

    /// @dev  The address of the account or contract that acts as the custodian.
    address immutable public custodian;

    /** @dev  The sole authorized caller of limited printing.
      * This account is also authorized to lower the supply ceiling.
      */
    address immutable public limitedPrinter;

    /** @dev  The maximum that the token supply can be increased to
      * through use of the limited printing feature.
      * The difference between the current total supply and the supply
      * ceiling is what is available to the 'limited printer' account.
      * The value of the ceiling can only be increased by the custodian.
      */
    uint256 public totalSupplyCeiling;

    /** @dev  The maximum that can be seized (burnt) through use of
      * the limited burn feature.
      * The value of the limit can only be increased by the custodian.
      * The value of the limit can be decreased by the 'limited printer'.
      */
    uint256 public seizureLimit;

    /// @dev  The map of lock ids to pending ceiling raises.
    mapping (bytes32 => Raise) public pendingRaiseMap;

    /// @dev  The map of lock ids to pending seizure limit raises.
    mapping (bytes32 => Raise) public pendingSeizureLimitRaiseMap;

    // CONSTRUCTOR
    constructor(
        address _erc20Impl,
        address _custodian,
        address _limitedPrinter,
        uint256 _initialCeiling,
        uint256 _initialSeizureLimit
    )
    {
        erc20Impl = ERC20Impl(_erc20Impl);
        custodian = _custodian;
        limitedPrinter = _limitedPrinter;
        totalSupplyCeiling = _initialCeiling;
        seizureLimit = _initialSeizureLimit;
    }

    // MODIFIERS
    modifier onlyCustodian {
        require(msg.sender == custodian, "unauthorized");
        _;
    }
    modifier onlyLimitedPrinter {
        require(msg.sender == limitedPrinter, "unauthorized");
        _;
    }

    /** @notice  Increases the token supply, with the newly created tokens
      * being added to the balance of the specified account.
      *
      * @dev  The function checks that the value to print does not
      * exceed the supply ceiling when added to the current total supply.
      * NOTE: printing to the zero address is disallowed.
      *
      * @param  _receiver  The receiving address of the print.
      * @param  _value  The number of tokens to add to the total supply and the
      * balance of the receiving address.
      */
    function limitedPrint(address _receiver, uint256 _value) external onlyLimitedPrinter {
        uint256 totalSupply = erc20Impl.totalSupply();

        unchecked {
            // unchecked `+` is safe as overflow check follow
            uint256 newTotalSupply = totalSupply + _value;
            require(newTotalSupply >= totalSupply, "overflow");

            require(newTotalSupply <= totalSupplyCeiling, "ceiling exceeded");
            erc20Impl.executePrint(_receiver, _value);
        }
    }

    function limitedBurn(address _owner, uint256 _value) external onlyLimitedPrinter {
        require(_value <= seizureLimit, "limit exceeded");

        unchecked {
            // unchecked `-` is safe as `_value <= seizureLimit`
            seizureLimit = seizureLimit - _value;
        }
        erc20Impl.burn(_owner, _value);
    }

    function requestRaise(mapping(bytes32 => Raise) storage _m, bytes4 _selector, uint256 _raiseBy) private returns (bytes32 lockId, uint256 lockRequestIdx) {
        require(_raiseBy != 0, "zero");

        (bytes32 preLockId, uint256 idx) = generatePreLockId();
        lockId = keccak256(
            abi.encodePacked(
                preLockId,
                _selector,
                _raiseBy
            )
        );
        lockRequestIdx = idx;

        _m[lockId] = Raise({
            raiseBy: _raiseBy
        });
    }

    /** @notice  Requests an increase to the supply ceiling.
      *
      * @dev  Returns a unique lock id associated with the request.
      * Anyone can call this function, but confirming the request is authorized
      * by the custodian.
      *
      * @param  _raiseBy  The amount by which to raise the ceiling.
      *
      * @return  lockId  A unique identifier for this request.
      */
    function requestCeilingRaise(uint256 _raiseBy) external returns (bytes32 lockId) {
        (bytes32 id, uint256 idx) = requestRaise(pendingRaiseMap, this.requestCeilingRaise.selector, _raiseBy);

        emit CeilingRaiseLocked(id, _raiseBy, idx);
        return id;
    }

    /** @notice  Requests an increase to the seizure limit.
      *
      * @dev  Returns a unique lock id associated with the request.
      * Anyone can call this function, but confirming the request is authorized
      * by the custodian.
      *
      * @param  _raiseBy  The amount by which to raise the seizure limit.
      *
      * @return  lockId  A unique identifier for this request.
      */
    function requestSeizureLimitRaise(uint256 _raiseBy) external returns (bytes32 lockId) {
        (bytes32 id, uint256 idx) = requestRaise(pendingSeizureLimitRaiseMap, this.requestSeizureLimitRaise.selector, _raiseBy);

        emit SeizureLimitRaiseLocked(id, _raiseBy, idx);
        return id;
    }

    function getRequest(mapping(bytes32 => Raise) storage _m, bytes32 _lockId) private view returns (uint256 raiseBy) {
        Raise storage r = _m[_lockId];

        // reject ‘null’ results from the map lookup
        // this can only be the case if an unknown `_lockId` is received
        raiseBy = r.raiseBy;
        require(raiseBy != 0, "no such lockId");
    }

    /** @notice  Confirms a pending increase in the token supply.
      *
      * @dev  When called by the custodian with a lock id associated with a
      * pending ceiling increase, the amount requested is added to the
      * current supply ceiling.
      * NOTE: this function will not execute any raise that would overflow the
      * supply ceiling, but it will not revert either.
      *
      * @param  _lockId  The identifier of a pending ceiling raise request.
      */
    function confirmCeilingRaise(bytes32 _lockId) external onlyCustodian {
        uint256 raiseBy = getRequest(pendingRaiseMap, _lockId);

        delete pendingRaiseMap[_lockId];

        unchecked {
            // unchecked `+` is safe as overflow check follows
            uint256 newCeiling = totalSupplyCeiling + raiseBy;
            if (newCeiling >= totalSupplyCeiling) {
                totalSupplyCeiling = newCeiling;

                emit CeilingRaiseConfirmed(_lockId, raiseBy, newCeiling);
            }
        }
    }

    /** @notice  Confirms a pending increase in the seizure limit.
      *
      * @dev  When called by the custodian with a lock id associated with a
      * pending seizure limit increase, the amount requested is added to the
      * current limit.
      * NOTE: this function will not execute any raise that would overflow the
      * seizure limit, but it will not revert either.
      *
      * @param  _lockId  The identifier of a pending seizure limit raise request.
      */
    function confirmSeizureLimitRaise(bytes32 _lockId) external onlyCustodian {
        uint256 raiseBy = getRequest(pendingSeizureLimitRaiseMap, _lockId);

        delete pendingSeizureLimitRaiseMap[_lockId];

        unchecked {
            // unchecked `+` is safe as overflow check follows
            uint256 newSeizureLimit = seizureLimit + raiseBy;
            if (newSeizureLimit >= seizureLimit) {
                seizureLimit = newSeizureLimit;

                emit SeizureLimitRaiseConfirmed(_lockId, raiseBy, newSeizureLimit);
            }
        }
    }

    /** @notice  Lowers the supply ceiling, further constraining the bound of
      * what can be printed by the limited printer.
      *
      * @dev  The limited printer is the sole authorized caller of this function,
      * so it is the only account that can elect to lower its limit to increase
      * the token supply.
      *
      * @param  _lowerBy  The amount by which to lower the supply ceiling.
      */
    function lowerCeiling(uint256 _lowerBy) external onlyLimitedPrinter {
        unchecked {
            // unchecked `-` is safe as overflow check follows
            uint256 newCeiling = totalSupplyCeiling - _lowerBy;
            require(newCeiling <= totalSupplyCeiling, "overflow");

            totalSupplyCeiling = newCeiling;

            emit CeilingLowered(_lowerBy, newCeiling);
        }
    }

    /** @notice  Lowers the seizure limit, further constraining the bound of
      * what can be seized (burnt) by the limited printer.
      *
      * @dev  The limited printer is the sole authorized caller of this function,
      * so it is the only account that can elect to lower its limit to seize assets.
      *
      * @param  _lowerBy  The amount by which to lower the seizure limit.
      */
    function lowerSeizureLimit(uint256 _lowerBy) external onlyLimitedPrinter {
        unchecked {
            // unchecked `-` is safe as overflow check follows
            uint256 newSeizureLimit = seizureLimit - _lowerBy;
            require(newSeizureLimit <= seizureLimit, "overflow");

            seizureLimit = newSeizureLimit;

            emit SeizureLimitLowered(_lowerBy, newSeizureLimit);
        }
    }

    /** @notice  Pass-through control of print confirmation, allowing this
      * contract's custodian to act as the custodian of the associated
      * active token implementation.
      *
      * @dev  This contract is the direct custodian of the active token
      * implementation, but this function allows this contract's custodian
      * to act as though it were the direct custodian of the active
      * token implementation. Therefore the custodian retains control of
      * unlimited printing.
      *
      * @param  _lockId  The identifier of a pending print request in
      * the associated active token implementation.
      */
    function confirmPrintProxy(bytes32 _lockId) external onlyCustodian {
        erc20Impl.confirmPrint(_lockId);
    }

    /** @notice  Pass-through control of custodian change confirmation,
      * allowing this contract's custodian to act as the custodian of
      * the associated active token implementation.
      *
      * @dev  This contract is the direct custodian of the active token
      * implementation, but this function allows this contract's custodian
      * to act as though it were the direct custodian of the active
      * token implementation. Therefore the custodian retains control of
      * custodian changes.
      *
      * @param  _lockId  The identifier of a pending custodian change request
      * in the associated active token implementation.
      */
    function confirmCustodianChangeProxy(bytes32 _lockId) external onlyCustodian {
        erc20Impl.confirmCustodianChange(_lockId);
    }

    // EVENTS
    /// @dev  Emitted by successful `requestCeilingRaise` calls.
    event CeilingRaiseLocked(bytes32 _lockId, uint256 _raiseBy, uint256 _lockRequestIdx);
    /// @dev  Emitted by successful `confirmCeilingRaise` calls.
    event CeilingRaiseConfirmed(bytes32 _lockId, uint256 _raiseBy, uint256 _newCeiling);

    /// @dev  Emitted by successful `requestSeizureLimitRaise` calls.
    event SeizureLimitRaiseLocked(bytes32 _lockId, uint256 _raiseBy, uint256 _lockRequestIdx);
    /// @dev  Emitted by successful `confirmSeizureLimitRaise` calls.
    event SeizureLimitRaiseConfirmed(bytes32 _lockId, uint256 _raiseBy, uint256 _newSeizureLimit);

    /// @dev  Emitted by successful `lowerCeiling` calls.
    event CeilingLowered(uint256 _lowerBy, uint256 _newCeiling);

    /// @dev  Emitted by successful `lowerSeizureLimit` calls.
    event SeizureLimitLowered(uint256 _lowerBy, uint256 _newSeizureLimit);
}
