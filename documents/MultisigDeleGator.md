# MultiSig DeleGator Smart Contract

### Overview

The MultiSigDeleGator is a Solidity smart contract that extends the functionality of the DeleGatorCore contract. It facilitates multi-signature based access control and delegation. Signers can be externally owned accounts (EOAs) or ERC-1271 contracts, including other MultiSigDeleGators.

### Features

Multi-Signature Support: Enables multi-signature transactions with a flexible threshold.

Delegation: Allows for delegation of transaction execution to other accounts.

The minimum threshold of signatures must be obtained to execute a transaction.

Signatures must be sorted in ascending order by the address of the signer.

### Signature Format

The signature is exactly a threshold amount of entries joined together, sorted by signer address (ascending). Each entry is one of:

```
EOA signer (65 bytes):
+----------------+----------------+-------+
|     r (32)     |     s (32)     | v (1) |
+----------------+----------------+-------+

Contract signer, ERC-1271 (22 + N bytes):
+------------------+---------+--------------------+
| signer addr (20) | len (2) |   signature (N)    |
+------------------+---------+--------------------+
```

The length `N` is stored in 2 bytes, so a contract signature is at most 65,535 bytes.

An entry is parsed as a contract signature when its first 20 bytes are the address of a signer that has code at validation time. Otherwise it is parsed as an EOA signature. A contract signer can itself be a MultiSigDeleGator, in which case its signature is that MultiSigDeleGator's own signature.

`isValidSignature` returns the ERC-1271 magic value `0x1626ba7e` for a valid signature and `0xffffffff` for any invalid one. It does not revert for invalid signature bytes, or when a contract signer reverts or returns an unexpected value.

Example:

```
Root (2 of 3)
 |- Alice (EOA)
 |- Dave (EOA)
 |- Sub (2 of 2)
     |- Bob (EOA)
     |- Carol (EOA)
```

To sign a hash for `Root` with Alice and `Sub`:

```
Sub signature  = bobSig | carolSig                  (Bob and Carol sign the hash, sorted by address)
Sub entry      = Sub address | length | Sub signature
Root signature = aliceSig | Sub entry               (Alice signs the hash, sorted by address)
```

### Considerations

- A contract signer is fully trusted. Its `isValidSignature` decides whether it approves, and its answer can change over time (for example, an upgradeable contract or an EIP-7702 re-delegation). A signature that is valid now can become invalid later.
- An EOA signer that has EIP-7702 code can sign in two ways: with a plain ECDSA signature, or with a contract signer entry that its delegated code checks. So its approval is only as strong as its delegated code, as for any contract signer.
- Telling the two entry types apart costs one storage read per EOA entry, also in multisigs that use only EOA signers.
- The gas used by a contract signer's validation counts toward the caller of `isValidSignature`, or the UserOp verification gas.
- Some contract signers read their own storage to validate a signature, for example a nested MultiSigDeleGator (its signers) or a HybridDeleGator (its keys). During UserOp validation, the ERC-4337 bundler rules (ERC-7562) allow this only from EntryPoint v0.8, and only if the account is staked. With EntryPoint v0.7, public mempool bundlers reject such UserOps even for staked accounts. Signers that read no storage, such as EIP7702StatelessDeleGator, are not affected. Neither are signatures checked outside UserOp validation, such as delegation redemption.
- A contract signer that is not deployed yet (no code) cannot sign until it is deployed.
- Two MultiSigDeleGators can be signers of each other. This is harmless: each nested level validates a strictly shorter part of the signature, so validation always ends.

### Signer Management

The contract provides functions to manage signers:

- Replace Signer: Replace an existing signer with a new one.

- Add Signer: Add a new signer to the contract.

- Remove Signer: Remove a signer from the contract.

- Update Threshold: Adjust the threshold for executing transactions.
