# Bitcoin Time Capsule NFT

A SIP-009 compliant NFT smart contract for Stacks blockchain, enabling users to mint, reveal, and manage "time capsule" NFTs that unlock at a specified block height. Capsules can be public or private, and only the owner can reveal or transfer them.

---

## Features

- **SIP-009 Compliant NFT**: Implements the standard NFT interface for Stacks.
- **Time-Locked Capsules**: Each NFT has an `unlock-block` height; contents can only be revealed after this block.
- **Owner-Only Reveal**: Only the capsule owner can reveal the contents after unlock.
- **Public/Private Capsules**: Capsules can be marked as public or private.
- **Metadata Storage**: Stores a hash (e.g., IPFS or encrypted) for off-chain data.
- **Transferable**: NFTs can be transferred between principals.
- **Capsule Visibility Management**: Owners can toggle the public/private status.
- **Total Supply Tracking**: Query the total number of minted capsules.
- **Ownership Management**: Contract owner can be changed.

---

## Contract Functions

- `mint-capsule (unlock-block uint) (data-hash (buff 32)) (is-public bool)`: Mint a new time capsule NFT.
- `reveal-capsule (id uint)`: Reveal a capsule after its unlock block (owner only).
- `can-reveal? (id uint)`: Check if a capsule can be revealed.
- `is-revealed? (id uint)`: Check if a capsule has been revealed.
- `get-capsule-info (id uint)`: Get all stored data for a capsule.
- `blocks-until-unlock (id uint)`: Get blocks remaining until unlock.
- `transfer (id uint) (sender principal) (recipient principal)`: Transfer NFT to another principal.
- `get-owner (id uint)`: Get the owner of a capsule.
- `get-token-uri (id uint)`: Get the token URI (static in this contract).
- `get-total-supply`: Get the total number of minted capsules.
- `set-contract-owner (new-owner principal)`: Change contract owner (owner only).
- `get-contract-owner`: Get the current contract owner.
- `is-public? (id uint)`: Check if a capsule is public.
- `set-capsule-visibility (id uint) (is-public bool)`: Change capsule visibility (owner only).
- `get-public-capsule-info (id uint)`: Get info for a public capsule.
- `capsule-exists? (id uint)`: Check if a capsule exists.

---

## Usage

1. **Mint a Capsule**  
   Call `mint-capsule` with the desired unlock block, data hash, and visibility.

2. **Reveal a Capsule**  
   After the unlock block, the owner can call `reveal-capsule`.

3. **Transfer Ownership**  
   Use `transfer` to send the NFT to another principal.

4. **Manage Visibility**  
   Owners can toggle public/private status with `set-capsule-visibility`.

---

## Notes

- The contract does **not** store actual data, only a hash (e.g., IPFS CID or encrypted reference).
- Only the owner can reveal or change visibility of their capsule.
- The token URI is static and should be extended for real metadata endpoints.

---

## License

MIT License. See LICENSE for details.
