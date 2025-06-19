// SPDX-License-Identifier: GNU AFFERO GENERAL PUBLIC LICENSE
pragma solidity ^0.8.4;

/// @title Multisig Wallet
/// @notice Wallet contract requiring majority approval from signers for transactions and signer management without abi.encode
contract Multisig {
    /* ========== ERRORS ========== */
    error NotAuthorised();
    error TxDoesNotExist();
    error AlreadyExecuted();
    error AlreadyConfirmed();
    error NotConfirmed();
    error SignerExists();
    error SignerDoesNotExist();
    error NeedsMinSigners();
    error InvalidRequired();
    error ExecFailed();

    /* ========== EVENTS ========== */
    event SubmitTransaction(uint indexed txId, address indexed proposer, address indexed to, uint value);
    event ConfirmTransaction(uint indexed txId, address indexed signer);
    event RevokeConfirmation(uint indexed txId, address indexed signer);
    event ExecuteTransaction(uint indexed txId, address indexed executor);
    event SignerAdded(address indexed newSigner);
    event SignerRemoved(address indexed oldSigner);

    /* ========== ROLE & SIGNERS ========== */
    bytes32 constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    mapping(address => bytes32) private roles;
    uint256 public totalSigner;
    uint256 public required; // majority threshold

    /* ========== TRANSACTION STRUCT ========== */
    struct Transaction {
        address to;
        uint value;
        bool executed;
        uint confirmations;
        // signer management fields
        bool isSignerMgmt;
        bool addSigner;
        address target;
    }

    mapping(uint => Transaction) public transactions;
    mapping(uint => mapping(address => bool)) public confirmed;
    uint public txCount;

    /* ========== MODIFIERS ========== */
    modifier onlySigner() {
        if (roles[msg.sender] != SIGNER_ROLE) revert NotAuthorised();
        _;
    }

    modifier txExists(uint _txId) {
        if (_txId >= txCount) revert TxDoesNotExist();
        _;
    }

    modifier notExecuted(uint _txId) {
        if (transactions[_txId].executed) revert AlreadyExecuted();
        _;
    }

    modifier notConfirmed(uint _txId) {
        if (confirmed[_txId][msg.sender]) revert AlreadyConfirmed();
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    /// @notice Initialize contract with three initial signers
    /// @param signer1 First initial signer address
    /// @param signer2 Second initial signer address
    /// @param signer3 Third initial signer address
    constructor(address signer1, address signer2, address signer3) {
        roles[signer1] = SIGNER_ROLE;
        roles[signer2] = SIGNER_ROLE;
        roles[signer3] = SIGNER_ROLE;
        totalSigner = 3;
        required = (totalSigner / 2) + 1;
    }

    /* ========== CORE TX METHODS ========== */
    /// @notice Submit a normal transaction
    /// @param _to Destination address
    /// @param _value Wei amount
    function submitTransaction(address _to, uint _value)
        public
        onlySigner
    {
        _newTransaction(_to, _value, false, false, address(0));
    }

    /// @notice Internal helper to create any transaction
    function _newTransaction(
        address _to,
        uint _value,
        bool _isSignerMgmt,
        bool _addSigner,
        address _target
    ) internal {
        uint txId = txCount;
        transactions[txId] = Transaction({
            to: _to,
            value: _value,
            executed: false,
            confirmations: 0,
            isSignerMgmt: _isSignerMgmt,
            addSigner: _addSigner,
            target: _target
        });
        txCount++;
        emit SubmitTransaction(txId, msg.sender, _to, _value);
        _confirmTransaction(txId);
    }

    /// @notice Confirm a transaction
    /// @param _txId Transaction ID
    function confirmTransaction(uint _txId)
        external
        onlySigner
        txExists(_txId)
        notExecuted(_txId)
        notConfirmed(_txId)
    {
        _confirmTransaction(_txId);
    }

    /// @notice Revoke your confirmation
    /// @param _txId Transaction ID
    function revokeConfirmation(uint _txId)
        external
        onlySigner
        txExists(_txId)
        notExecuted(_txId)
    {
        if (!confirmed[_txId][msg.sender]) revert NotConfirmed();
        confirmed[_txId][msg.sender] = false;
        transactions[_txId].confirmations--;
        emit RevokeConfirmation(_txId, msg.sender);
    }

    function _confirmTransaction(uint _txId) internal {
        confirmed[_txId][msg.sender] = true;
        transactions[_txId].confirmations++;
        emit ConfirmTransaction(_txId, msg.sender);
        if (transactions[_txId].confirmations >= required) {
            _executeTransaction(_txId);
        }
    }

    function _executeTransaction(uint _txId) internal notExecuted(_txId) {
        Transaction storage txn = transactions[_txId];
        if (txn.confirmations < required) revert InvalidRequired();
        txn.executed = true;
        (bool success, ) = txn.to.call{value: txn.value}("");
        if (!success) revert ExecFailed();
        // if signer management, apply change
        if (txn.isSignerMgmt) {
            if (txn.addSigner) {
                if (roles[txn.target] == SIGNER_ROLE) revert SignerExists();
                roles[txn.target] = SIGNER_ROLE;
                totalSigner++;
                emit SignerAdded(txn.target);
            } else {
                if (roles[txn.target] != SIGNER_ROLE) revert SignerDoesNotExist();
                if (totalSigner - 1 < 3) revert NeedsMinSigners();
                roles[txn.target] = bytes32(0);
                totalSigner--;
                emit SignerRemoved(txn.target);
            }
            required = (totalSigner / 2) + 1;
        }
        emit ExecuteTransaction(_txId, msg.sender);
    }

    /* ========== PROPOSALS FOR SIGNER MANAGEMENT ========== */
    /// @notice Propose to add a new signer
    /// @param newSigner New signer address
    function proposeAddSigner(address newSigner) external onlySigner {
        if (newSigner == address(0) || roles[newSigner] == SIGNER_ROLE) revert SignerExists();
        _newTransaction(address(this), 0, true, true, newSigner);
    }

    /// @notice Propose to remove an existing signer
    /// @param oldSigner Signer address to remove
    function proposeRemoveSigner(address oldSigner) external onlySigner {
        if (roles[oldSigner] != SIGNER_ROLE) revert SignerDoesNotExist();
        _newTransaction(address(this), 0, true, false, oldSigner);
    }

    /* ========== FALLBACK & RECEIVE ========== */
    fallback() external payable {}
    receive() external payable {}

    /* ========== VIEWERS ========== */
    /// @notice Check signer
    function isSigner(address account) external view returns (bool) {
        return roles[account] == SIGNER_ROLE;
    }

    /// @notice Get transaction details
    function getTransaction(uint _txId) external view returns (
        address to,
        uint value,
        bool executed,
        uint confirmations,
        bool isSignerMgmt,
        bool addSigner,
        address target
    ) {
        Transaction storage txn = transactions[_txId];
        return (
            txn.to,
            txn.value,
            txn.executed,
            txn.confirmations,
            txn.isSignerMgmt,
            txn.addSigner,
            txn.target
        );
    }
}
