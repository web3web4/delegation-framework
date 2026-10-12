// NOTE: Temporary file, do not commit!

// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";

import { MultiSigDeleGator } from "../../src/MultiSigDeleGator.sol";
import { IDelegationManager } from "../../src/interfaces/IDelegationManager.sol";

/**
 * @title NestedMultiSigSignature
 * @notice Usage example: how to build a signature for a MultiSigDeleGator that has another MultiSigDeleGator as a signer.
 * @dev Everything runs in memory. Nothing is deployed to a network and nothing is broadcast.
 * @dev Run with: forge script script/examples/NestedMultiSigSignature.s.sol -vv
 *
 * Accounts used:
 *
 *   Root (2 of 3)
 *    - Alice (EOA)
 *    - Dave (EOA)
 *    - Sub (2 of 2)
 *       - Bob (EOA)
 *       - Carol (EOA)
 *
 * Signature rules:
 *   - Provide exactly `threshold` signatures, sorted by signer address (ascending).
 *   - EOA signer: r (32 bytes) | s (32 bytes) | v (1 byte)
 *   - Contract signer: signer address (20 bytes) | signature length (2 bytes) | signature (length bytes)
 */
contract NestedMultiSigSignature is Script {
    Vm.Wallet internal alice;
    Vm.Wallet internal bob;
    Vm.Wallet internal carol;
    Vm.Wallet internal dave;
    MultiSigDeleGator internal sub;
    MultiSigDeleGator internal root;

    function setUp() public {
        alice = vm.createWallet("alice");
        bob = vm.createWallet("bob");
        carol = vm.createWallet("carol");
        dave = vm.createWallet("dave");

        // The constructor only stores these two addresses, so placeholders are enough for this example
        MultiSigDeleGator implementation_ = new MultiSigDeleGator(IDelegationManager(address(0x1234)), IEntryPoint(address(0x5678)));

        address[] memory subSigners_ = new address[](2);
        subSigners_[0] = bob.addr;
        subSigners_[1] = carol.addr;
        sub = _deployMultiSig(implementation_, subSigners_, 2);

        address[] memory rootSigners_ = new address[](3);
        rootSigners_[0] = alice.addr;
        rootSigners_[1] = address(sub);
        rootSigners_[2] = dave.addr;
        root = _deployMultiSig(implementation_, rootSigners_, 2);
    }

    function run() external view {
        // The hash that Root verifies. In a real flow this is the typed data hash of a delegation or a UserOp.
        bytes32 hash_ = keccak256("hash to sign");

        // Step 1: Bob and Carol sign the hash for Sub. Their signatures are joined in address order.
        bytes memory subSignature_ = _join(bob.addr, _sign(bob.privateKey, hash_), carol.addr, _sign(carol.privateKey, hash_));

        // Step 2: Wrap Sub's signature as a contract signer entry: Sub address | length | signature.
        bytes memory subEntry_ = _encodeContractSignature(address(sub), subSignature_);

        // Step 3: Alice signs the same hash for Root.
        bytes memory aliceSignature_ = _sign(alice.privateKey, hash_);

        // Step 4: Join Alice's signature and Sub's entry in address order. This is Root's signature.
        bytes memory rootSignature_ = _join(alice.addr, aliceSignature_, address(sub), subEntry_);

        // Root accepts it: 2 signers (Alice and Sub) meet the threshold of 2
        require(root.isValidSignature(hash_, rootSignature_) == IERC1271.isValidSignature.selector, "Invalid signature");

        console2.log("Root signature (%s bytes):", rootSignature_.length);
        console2.logBytes(rootSignature_);
    }

    ////////////////////////////// Internal Methods //////////////////////////////

    function _deployMultiSig(
        MultiSigDeleGator _implementation,
        address[] memory _signers,
        uint256 _threshold
    )
        internal
        returns (MultiSigDeleGator)
    {
        bytes memory initData_ = abi.encodeWithSignature("initialize(address[],uint256)", _signers, _threshold);
        return MultiSigDeleGator(payable(address(new ERC1967Proxy(address(_implementation), initData_))));
    }

    function _sign(uint256 _privateKey, bytes32 _hash) internal pure returns (bytes memory) {
        (uint8 v_, bytes32 r_, bytes32 s_) = vm.sign(_privateKey, _hash);
        return abi.encodePacked(r_, s_, v_);
    }

    function _encodeContractSignature(address _signer, bytes memory _signature) internal pure returns (bytes memory) {
        // The length is stored in 2 bytes, and uint16() would silently wrap a longer length
        require(_signature.length <= type(uint16).max, "Signature too long");
        return abi.encodePacked(_signer, uint16(_signature.length), _signature);
    }

    // MultiSigDeleGator requires the signatures to be sorted by ascending signer address
    function _join(
        address _signerA,
        bytes memory _signatureA,
        address _signerB,
        bytes memory _signatureB
    )
        internal
        pure
        returns (bytes memory)
    {
        return _signerA < _signerB ? abi.encodePacked(_signatureA, _signatureB) : abi.encodePacked(_signatureB, _signatureA);
    }
}
