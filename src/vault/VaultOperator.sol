// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { IERC7540Operator } from "../interfaces/IERC7540.sol";

/**
 * @title VaultaireOperator
 * @dev Implementation of operator functionality for ERC7540
 */
abstract contract VaultOperator is IERC7540Operator {
    /// @dev Mapping of controllers to their approved operators
    mapping(address controller => mapping(address operator => bool)) public isOperator;

    /**
     * @dev Error thrown when an address attempts to set itself as its own operator.
     * @param sender The address attempting the invalid operation
     */
    error CannotSetSelfAsOperator(address sender);

    /**
     * @dev Error thrown when a caller is neither the controller nor an authorized operator.
     * @param caller The address attempting the operation
     * @param controller The controller address that would be needed for authorization
     */
    error InvalidCaller(address caller, address controller);

    /**
     * @dev Sets or removes an operator for the caller.
     *
     * @param operator The address of the operator.
     * @param approved The approval status.
     * @return success Whether the call was executed successfully or not
     */
    function setOperator(address operator, bool approved) public virtual returns (bool success) {
        if (msg.sender == operator) {
            revert CannotSetSelfAsOperator(msg.sender);
        }

        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        success = true;
    }
}
