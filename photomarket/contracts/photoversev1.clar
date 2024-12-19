;; Constants
(define-constant contract-owner tx-sender)
(define-constant fee-denominator u10000)
(define-constant platform-fee u250) ;; 2.5% total fee
(define-constant revenue-pool-share u100) ;; 1% to revenue pool
(define-constant creator-royalty u50) ;; 0.5% to creator
(define-constant staker-share u100) ;; 1% to stakers

;; Error codes
(define-constant err-not-owner (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-listed (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-price (err u104))

;; Data Maps
(define-map nft-listings
  { nft-id: uint }
  { 
    seller: principal,
    price: uint,
    creator: principal
  }
)

(define-map staking-positions
  { staker: principal }
  {
    amount: uint,
    timestamp: uint
  }
)

(define-map revenue-periods
  { period: uint }
  {
    total-revenue: uint,
    distributed-amount: uint,
    remaining-amount: uint
  }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

;; SFT for PHOTO token
(define-fungible-token photo-token)

;; NFT definition
(define-non-fungible-token photoverse-nft uint)

;; Read-only functions
(define-read-only (get-listing (nft-id uint))
  (map-get? nft-listings { nft-id: nft-id })
)

(define-read-only (get-staking-position (staker principal))
  (map-get? staking-positions { staker: staker })
)

(define-read-only (get-user-balance (user principal))
  (default-to { balance: u0 }
    (map-get? user-balances { user: user }))
)

(define-read-only (get-total-staked)
  (fold + (map get-stake-amount (map-get? staking-positions)))
)

;; Public functions

;; Mint new NFT
(define-public (mint-nft (nft-id uint))
  (begin
    (try! (nft-mint? photoverse-nft nft-id tx-sender))
    (ok true))
)

;; List NFT for sale
(define-public (list-nft (nft-id uint) (price uint))
  (let ((owner (unwrap! (nft-get-owner? photoverse-nft nft-id) err-not-found)))
    (asserts! (is-eq tx-sender owner) err-not-owner)
    (asserts! (> price u0) err-invalid-price)
    (map-set nft-listings
      { nft-id: nft-id }
      { 
        seller: tx-sender,
        price: price,
        creator: tx-sender
      }
    )
    (ok true))
)

;; Buy listed NFT
(define-public (buy-nft (nft-id uint))
  (let (
    (listing (unwrap! (get-listing nft-id) err-not-found))
    (price (get price listing))
    (seller (get seller listing))
    (creator (get creator listing))
    (platform-cut (/ (* price platform-fee) fee-denominator))
    (revenue-pool-cut (/ (* price revenue-pool-share) fee-denominator))
    (creator-cut (/ (* price creator-royalty) fee-denominator))
    (staker-cut (/ (* price staker-share) fee-denominator))
  )
    (try! (stx-transfer? price tx-sender seller))
    (try! (distribute-fees revenue-pool-cut creator-cut creator staker-cut))
    (try! (nft-transfer? photoverse-nft nft-id seller tx-sender))
    (map-delete nft-listings { nft-id: nft-id })
    (ok true))
)

;; Stake PHOTO tokens
(define-public (stake-tokens (amount uint))
  (let ((current-balance (ft-get-balance photo-token tx-sender)))
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (try! (ft-transfer? photo-token amount tx-sender (as-contract tx-sender)))
    (map-set staking-positions
      { staker: tx-sender }
      {
        amount: amount,
        timestamp: block-height
      }
    )
    (ok true))
)

;; Unstake PHOTO tokens
(define-public (unstake-tokens)
  (let (
    (position (unwrap! (get-staking-position tx-sender) err-not-found))
    (amount (get amount position))
  )
    (try! (as-contract (ft-transfer? photo-token amount (as-contract tx-sender) tx-sender)))
    (map-delete staking-positions { staker: tx-sender })
    (ok true))
)

;; Private functions

;; Distribute fees from sale
(define-private (distribute-fees (revenue-pool-cut uint) (creator-cut uint) (creator principal) (staker-cut uint))
  (begin
    (try! (add-to-revenue-pool revenue-pool-cut))
    (try! (stx-transfer? creator-cut tx-sender creator))
    (try! (distribute-to-stakers staker-cut))
    (ok true))
)

;; Add funds to revenue pool
(define-private (add-to-revenue-pool (amount uint))
  (let ((current-period (/ block-height u144))) ;; ~1 day periods
    (map-set revenue-periods
      { period: current-period }
      {
        total-revenue: (+ amount (default-to u0 (get total-revenue (map-get? revenue-periods { period: current-period })))),
        distributed-amount: u0,
        remaining-amount: amount
      }
    )
    (ok true))
)

;; Distribute rewards to stakers
(define-private (distribute-to-stakers (amount uint))
  (let (
    (total-staked (get-total-staked))
  )
    (map distribute-staker-share 
      (map-get? staking-positions)
      (/ (* amount fee-denominator) total-staked))
    (ok true))
)

;; Helper to distribute share to individual staker
(define-private (distribute-staker-share (position { staker: principal, amount: uint }) (share uint))
  (let ((staker-amount (/ (* (get amount position) share) fee-denominator)))
    (map-set user-balances
      { user: (get staker position) }
      { balance: (+ staker-amount (get balance (get-user-balance (get staker position)))) }
    ))
)

;; Claim accumulated rewards
(define-public (claim-rewards)
  (let (
    (balance (get balance (get-user-balance tx-sender)))
  )
    (asserts! (> balance u0) err-insufficient-balance)
    (try! (stx-transfer? balance (as-contract tx-sender) tx-sender))
    (map-set user-balances { user: tx-sender } { balance: u0 })
    (ok true))
)