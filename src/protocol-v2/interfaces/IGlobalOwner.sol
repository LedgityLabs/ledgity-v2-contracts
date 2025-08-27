// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title IGlobalOwner
 * @notice Interface for the GlobalOwner contract that holds the address of a global 
 * owner account shared by all contracts of the Ledgity Yield's codebase.
 */
interface IGlobalOwner {
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
