// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { VaultOperator } from "./VaultOperator.sol";

/**
 * @title VaultaireAuth
 * @dev Implementation of EIP712 signature-based authorization for operators
 */
abstract contract VaultAuth is VaultOperator, EIP712 {
    /// @dev Mapping to track used authorization nonces for each controller
    mapping(address controller => mapping(bytes32 nonce => bool used)) public authorizations;

    /**
     * @dev Error thrown when an authorization is attempted after the deadline has expired.
     */
    error AuthorizationExpired(uint256 currentTime, uint256 deadline);

    /**
     * @dev Error thrown when attempting to use an authorization nonce that has already been used.
     */
    error AuthorizationNonceUsed(address controller, bytes32 nonce);

    /**
     * @dev Error thrown when signature verification fails during authorization.
     */
    error InvalidSignature(address expectedSigner, address recoveredSigner);

    constructor(string memory name, string memory version) EIP712(name, version) { }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Authorizes an operator based on a signed message from the controller
     */
    function authorizeOperator(
        address controller,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    )
        public
        virtual
        returns (bool success)
    {
        if (msg.sender == operator) revert CannotSetSelfAsOperator(msg.sender);

        if (block.timestamp > deadline) revert AuthorizationExpired(block.timestamp, deadline);
        if (authorizations[controller][nonce]) revert AuthorizationNonceUsed(controller, nonce);

        authorizations[controller][nonce] = true;

        bytes32 r;
        bytes32 s;
        uint8 v;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                // solhint-disable-next-line max-line-length
                                "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                            ),
                            controller,
                            operator,
                            approved,
                            nonce,
                            deadline
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        if (recoveredAddress == address(0) || recoveredAddress != controller) {
            revert InvalidSignature(controller, recoveredAddress);
        }

        isOperator[controller][operator] = approved;

        emit OperatorSet(controller, operator, approved);

        success = true;
    }
}
