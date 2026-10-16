// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2020 Gemini Trust Company LLC. All Rights Reserved
pragma solidity ^0.8.0;

import "./CustodianUpgradeableV1dot1.sol";
import "./ERC20Proxy.sol";
import "./ERC20Store.sol";

/** @title  ERC20 compliant token intermediary contract holding core logic.
  *
  * @notice  This contract serves as an intermediary between the exposed ERC20
  * interface in ERC20Proxy and the store of balances in ERC20Store. This
  * contract contains core logic that the proxy can delegate to
  * and that the store is called by.
  *
  * @dev  This contract contains the core logic to implement the
  * ERC20 specification as well as several extensions.
  * 1. Changes to the token supply.
  * 2. Batched transfers.
  * 3. Relative changes to spending approvals.
  * 4. Delegated transfer control ('sweeping').
  *
  * @author  Gemini Trust Company, LLC
  */
contract ERC20Impl is CustodianUpgradeableV1dot1 {

    // TYPES
    /// @dev  The struct type for pending increases to the token supply (print).
    struct PendingPrint {
        address receiver;
        uint256 value;
    }

    // MEMBERS
    /// @dev  The reference to the proxy.
    ERC20Proxy immutable public erc20Proxy;

    /// @dev  The reference to the store.
    ERC20Store immutable public erc20Store;

    /// @dev  The map of lock ids to pending token increases.
    mapping (bytes32 => PendingPrint) public pendingPrintMap;

    // CONSTRUCTOR
    constructor(
          address _erc20Proxy,
          address _erc20Store,
          address _custodian
    )
        CustodianUpgradeableV1dot1(_custodian)
    {
        erc20Proxy = ERC20Proxy(_erc20Proxy);
        erc20Store = ERC20Store(_erc20Store);
    }

    // MODIFIERS
    modifier onlyProxy {
        require(msg.sender == address(erc20Proxy), "unauthorized");
        _;
    }


    /** @notice  Core logic of the ERC20 `approve` function.
      *
      * @dev  This function can only be called by the referenced proxy,
      * which has an `approve` function.
      * Every argument passed to that function as well as the original
      * `msg.sender` gets passed to this function.
      * NOTE: approvals for the zero address (unspendable) are disallowed.
      *
      * @param  _sender  The address initiating the approval in proxy.
      */
    function approveWithSender(
        address _sender,
        address _spender,
        uint256 _value
    )
        external
        onlyProxy
        returns (bool success)
    {
        require(_spender != address(0), "zero address"); // disallow unspendable approvals
        erc20Store.setAllowance(_sender, _spender, _value);
        erc20Proxy.emitApproval(_sender, _spender, _value);
        return true;
    }

    /** @notice  Core logic of the `increaseApproval` function.
      *
      * @dev  This function can only be called by the referenced proxy,
      * which has an `increaseApproval` function.
      * Every argument passed to that function as well as the original
      * `msg.sender` gets passed to this function.
      * NOTE: approvals for the zero address (unspendable) are disallowed.
      *
      * @param  _sender  The address initiating the approval.
      */
    function increaseApprovalWithSender(
        address _sender,
        address _spender,
        uint256 _addedValue
    )
        external
        onlyProxy
        returns (bool success)
    {
        require(_spender != address(0), "zero address"); // disallow unspendable approvals
        uint256 currentAllowance = erc20Store.allowed(_sender, _spender);

        unchecked {
            // unchecked `+` is safe as overflow check follows
            uint256 newAllowance = currentAllowance + _addedValue;
            require(newAllowance >= currentAllowance, "overflow");

            erc20Store.setAllowance(_sender, _spender, newAllowance);
            erc20Proxy.emitApproval(_sender, _spender, newAllowance);
            return true;
        }
    }

    /** @notice  Core logic of the `decreaseApproval` function.
      *
      * @dev  This function can only be called by the referenced proxy,
      * which has a `decreaseApproval` function.
      * Every argument passed to that function as well as the original
      * `msg.sender` gets passed to this function.
      * NOTE: approvals for the zero address (unspendable) are disallowed.
      *
      * @param  _sender  The address initiating the approval.
      */
    function decreaseApprovalWithSender(
        address _sender,
        address _spender,
        uint256 _subtractedValue
    )
        external
        onlyProxy
        returns (bool success)
    {
        require(_spender != address(0), "zero address"); // disallow unspendable approvals
        uint256 currentAllowance = erc20Store.allowed(_sender, _spender);

        unchecked {
            // unchecked `-` is safe as overflow check follows
            uint256 newAllowance = currentAllowance - _subtractedValue;
            require(newAllowance <= currentAllowance, "overflow");

            erc20Store.setAllowance(_sender, _spender, newAllowance);
            erc20Proxy.emitApproval(_sender, _spender, newAllowance);
        }

        return true;
    }

    /** @notice  Requests an increase in the token supply, with the newly created
      * tokens to be added to the balance of the specified account.
      *
      * @dev  Returns a unique lock id associated with the request.
      * Anyone can call this function, but confirming the request is authorized
      * by the custodian.
      * NOTE: printing to the zero address is disallowed.
      *
      * @param  _receiver  The receiving address of the print, if confirmed.
      * @param  _value  The number of tokens to add to the total supply and the
      * balance of the receiving address, if confirmed.
      *
      * @return  lockId  A unique identifier for this request.
      */
    function requestPrint(address _receiver, uint256 _value) external returns (bytes32 lockId) {
        require(_receiver != address(0), "zero address");

        (bytes32 preLockId, uint256 lockRequestIdx) = generatePreLockId();
        lockId = keccak256(
            abi.encodePacked(
                preLockId,
                this.requestPrint.selector,
                _receiver,
                _value
            )
        );

        pendingPrintMap[lockId] = PendingPrint({
            receiver: _receiver,
            value: _value
        });

        emit PrintingLocked(lockId, _receiver, _value, lockRequestIdx);
    }

    function _executePrint(address _receiver, uint256 _value) private returns (bool success) {
        uint256 supply = erc20Store.totalSupply();

        unchecked {
            // unchecked `+` is safe as overflow check follows
            uint256 newSupply = supply + _value;
            if (newSupply >= supply) {
                erc20Store.setTotalSupply(newSupply);
                erc20Store.addBalance(_receiver, _value);

                erc20Proxy.emitTransfer(address(0), _receiver, _value);
                return true;
            }
        }
    }

    function executePrint(address _receiver, uint256 _value) external onlyCustodian {
        require(_receiver != address(0), "zero address");
        _executePrint(_receiver, _value);
    }

    /** @notice  Confirms a pending increase in the token supply.
      *
      * @dev  When called by the custodian with a lock id associated with a
      * pending increase, the amount requested to be printed in the print request
      * is printed to the receiving address specified in that same request.
      * NOTE: this function will not execute any print that would overflow the
      * total supply, but it will not revert either.
      *
      * @param  _lockId  The identifier of a pending print request.
      */
    function confirmPrint(bytes32 _lockId) external onlyCustodian {
        PendingPrint storage print = pendingPrintMap[_lockId];

        // reject ‘null’ results from the map lookup
        // this can only be the case if an unknown `_lockId` is received
        address receiver = print.receiver;
        require (receiver != address(0), "no such lockId");
        uint256 value = print.value;

        delete pendingPrintMap[_lockId];

        if (_executePrint(receiver, value)) {
            emit PrintingConfirmed(_lockId, receiver, value);
        }
    }

    function _executeBurn(address _owner, uint256 _value) private returns (bool success) {
        uint256 balanceOfSender = erc20Store.balances(_owner);
        require(_value <= balanceOfSender, "insufficient balance");

        unchecked {
            // unchecked `-` is safe as `_value <= balanceOfSender`
            erc20Store.setBalance(_owner, balanceOfSender - _value);
            // unchecked `-` is safe as the global invariants is that
            // the sum of all balances equals the total supply, therefore
            // as `_value <= balanceOfSender`, then `_value <= totalSupply`
            erc20Store.setTotalSupply(erc20Store.totalSupply() - _value);
        }

        erc20Proxy.emitTransfer(_owner, address(0), _value);

        return true;
    }

    /** @notice  Burns the specified value from the sender's balance.
      *
      * @dev  Sender's balanced is subtracted by the amount they wish to burn.
      *
      * @param  _value  The amount to burn.
      *
      * @return  success  true if the burn succeeded.
      */
    function burn(uint256 _value) external returns (bool success) {
        return _executeBurn(msg.sender, _value);
    }

    /** @notice  Burns the specified value from the owner's balance.
      *
      * @dev  Owner's balance is subtracted by the amount the custodian wishes to burn.
      *
      * @param  _owner  The owner of the tokens.
      * @param  _value  The amount to burn.
      */
    function burn(address _owner, uint256 _value) external onlyCustodian {
        _executeBurn(_owner, _value);
    }

    /** @notice  A function for a sender to issue multiple transfers to multiple
      * different addresses at once. This function is implemented for gas
      * considerations when someone wishes to transfer, as one transaction is
      * cheaper than issuing several distinct individual `transfer` transactions.
      *
      * @dev  By specifying a set of destination addresses and values, the
      * sender can issue one transaction to transfer multiple amounts to
      * distinct addresses, rather than issuing each as a separate
      * transaction. The `_tos` and `_values` arrays must be equal length, and
      * an index in one array corresponds to the same index in the other array
      * (e.g. `_tos[0]` will receive `_values[0]`, `_tos[1]` will receive
      * `_values[1]`, and so on.)
      * NOTE: transfers to the zero address are disallowed.
      *
      * @param  _tos  The destination addresses to receive the transfers.
      * @param  _values  The values for each destination address.
      * @return  success  If transfers succeeded.
      */
    function batchTransfer(address[] calldata _tos, uint256[] calldata _values) external returns (bool success) {
        require(_tos.length == _values.length, "inconsistent length");

        uint256 numTransfers = _tos.length;
        uint256 senderBalance = erc20Store.balances(msg.sender);

        for (uint256 i = 0; i < numTransfers; i++) {
          address to = _tos[i];
          require(to != address(0), "zero address");
          uint256 v = _values[i];
          require(senderBalance >= v, "insufficient balance");

          if (msg.sender != to) {
            senderBalance -= v;
            erc20Store.addBalance(to, v);
          }
          erc20Proxy.emitTransfer(msg.sender, to, v);
        }

        erc20Store.setBalance(msg.sender, senderBalance);

        return true;
    }

    /** @notice  Core logic of the ERC20 `transferFrom` function.
      *
      * @dev  This function can only be called by the referenced proxy,
      * which has a `transferFrom` function.
      * Every argument passed to that function as well as the original
      * `msg.sender` gets passed to this function.
      * NOTE: transfers to the zero address are disallowed.
      *
      * @param  _sender  The address initiating the transfer in proxy.
      */
    function transferFromWithSender(
        address _sender,
        address _from,
        address _to,
        uint256 _value
    )
        external
        onlyProxy
        returns (bool success)
    {
        require(_to != address(0), "zero address"); // ensure burn is the cannonical transfer to 0x0

        uint256 balanceOfFrom = erc20Store.balances(_from);
        require(_value <= balanceOfFrom, "insufficient balance");

        uint256 senderAllowance = erc20Store.allowed(_from, _sender);
        require(_value <= senderAllowance, "insufficient allowance");

        unchecked {
            // unchecked `-` is safe as `_value <= balanceOfFrom`
            erc20Store.setBalance(_from, balanceOfFrom - _value);
        }
        erc20Store.addBalance(_to, _value);

        unchecked {
            // unchecked `-` is safe as `_value <= senderAllowance`
            erc20Store.setAllowance(_from, _sender, senderAllowance - _value);
        }

        erc20Proxy.emitTransfer(_from, _to, _value);

        return true;
    }

    /** @notice  Core logic of the ERC20 `transfer` function.
      *
      * @dev  This function can only be called by the referenced proxy,
      * which has a `transfer` function.
      * Every argument passed to that function as well as the original
      * `msg.sender` gets passed to this function.
      * NOTE: transfers to the zero address are disallowed.
      *
      * @param  _sender  The address initiating the transfer in proxy.
      */
    function transferWithSender(
        address _sender,
        address _to,
        uint256 _value
    )
        external
        onlyProxy
        returns (bool success)
    {
        require(_to != address(0), "zero address"); // ensure burn is the cannonical transfer to 0x0

        uint256 balanceOfSender = erc20Store.balances(_sender);
        require(_value <= balanceOfSender, "insufficient balance");

        unchecked {
            // unchecked `-` is safe as `_value <= balanceOfSender`
            erc20Store.setBalance(_sender, balanceOfSender - _value);
        }
        erc20Store.addBalance(_to, _value);

        erc20Proxy.emitTransfer(_sender, _to, _value);

        return true;
    }

    // METHODS (ERC20 sub interface impl.)
    /// @notice  Core logic of the ERC20 `totalSupply` function.
    function totalSupply() external view returns (uint256) {
        return erc20Store.totalSupply();
    }

    /// @notice  Core logic of the ERC20 `balanceOf` function.
    function balanceOf(address _owner) external view returns (uint256 balance) {
        return erc20Store.balances(_owner);
    }

    /// @notice  Core logic of the ERC20 `allowance` function.
    function allowance(address _owner, address _spender) external view returns (uint256 remaining) {
        return erc20Store.allowed(_owner, _spender);
    }

    // EVENTS
    /// @dev  Emitted by successful `requestPrint` calls.
    event PrintingLocked(bytes32 _lockId, address _receiver, uint256 _value, uint256 _lockRequestIdx);
    /// @dev Emitted by successful `confirmPrint` calls.
    event PrintingConfirmed(bytes32 _lockId, address _receiver, uint256 _value);
}
