# Photoverse Smart Contract

Photoverse is a decentralized NFT marketplace and staking platform built on Stacks. It enables users to mint, list, and trade NFTs while earning rewards through staking. The platform features a unique revenue-sharing model that distributes transaction fees among platform stakeholders.

## Key Features

### NFT Operations
- Mint new NFTs
- List NFTs for sale with custom pricing
- Purchase listed NFTs
- Automated fee distribution on sales

### Staking System
- Stake PHOTO tokens to earn platform rewards
- Dynamic reward distribution based on stake size
- Flexible unstaking mechanism
- Claim accumulated rewards

### Revenue Distribution
- Platform fee: 2.5% of transaction value
- Revenue pool: 1% for platform operations
- Creator royalty: 0.5% to original NFT creator
- Staker rewards: 1% distributed to token stakers

## Contract Structure

### Tokens
- `photo-token`: Platform utility token (SFT)
- `photoverse-nft`: NFT implementation

### Storage
- `nft-listings`: Tracks active NFT sales
- `staking-positions`: Records user staking information
- `revenue-periods`: Manages revenue distribution periods
- `user-balances`: Tracks user reward balances

### Key Functions

#### Public Functions
```clarity
(define-public (mint-nft (nft-id uint)))
(define-public (list-nft (nft-id uint) (price uint)))
(define-public (buy-nft (nft-id uint)))
(define-public (stake-tokens (amount uint)))
(define-public (unstake-tokens))
(define-public (claim-rewards))
```

#### Read-Only Functions
```clarity
(define-read-only (get-listing (nft-id uint)))
(define-read-only (get-staking-position (staker principal)))
(define-read-only (get-user-balance (user principal)))
(define-read-only (get-total-staked))
```

## Error Handling
The contract includes comprehensive error handling for various scenarios:
- `err-not-owner`: Unauthorized operation attempt
- `err-not-found`: Requested item doesn't exist
- `err-already-listed`: NFT already listed
- `err-insufficient-balance`: Insufficient funds
- `err-invalid-price`: Invalid pricing
- `err-too-many-stakers`: Staker limit reached
- `err-revenue-pool-error`: Revenue pool operation failed
- `err-distribution-error`: Reward distribution failed

## Usage Examples

### Minting and Listing an NFT
```clarity
;; Mint a new NFT
(try! (mint-nft u1))

;; List the NFT for sale at 100 STX
(try! (list-nft u1 u100))
```

### Staking Tokens
```clarity
;; Stake 1000 PHOTO tokens
(try! (stake-tokens u1000))

;; Check staking position
(get-staking-position tx-sender)

;; Claim rewards
(try! (claim-rewards))
```

### Buying an NFT
```clarity
;; Purchase NFT with ID 1
(try! (buy-nft u1))
```

## Security Considerations
- Contract owner controls are minimized for decentralization
- Staking positions are protected by principal-based access
- All financial operations include comprehensive error checking
- Revenue distribution uses atomic operations to prevent partial updates

## Technical Requirements
- Clarity language support
- Stacks blockchain
- Support for fungible and non-fungible tokens

## Notes
- Maximum of 200 concurrent stakers supported
- Daily revenue periods (144 blocks)
- All fees are calculated using a denominator of 10000 for precision