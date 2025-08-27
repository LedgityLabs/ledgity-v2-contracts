// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title IGlobalPause
 * @notice Interface for the GlobalPause contract that holds a global pause state 
 * shared by all contracts of the Ledgity Yield codebase.
 */
interface IGlobalPause {
    /**
     * @notice Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @notice Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @notice Returns true if the contract is paused, and false otherwise.
     * @return True if paused, false otherwise.
     */
    function paused() external view returns (bool);

    /**
     * @notice Triggers stopped state.
     */
    function pause() external;

    /**
     * @notice Returns to normal state.
     */
    function unpause() external;

    /**
     * @notice Returns the address of the current owner.
     * @return The address of the current owner.
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the address of the pending owner.
     * @return The address of the pending owner.
     */
    function pendingOwner() external view returns (address);

    /**
     * @notice Starts the ownership transfer of the contract to a new account.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) external;

    /**
     * @notice The new owner accepts the ownership transfer.
     */
    function acceptOwnership() external;

    /**
     * @notice Leaves the contract without owner. Can only be called by the current owner.
     */
    function renounceOwnership() external;
}
