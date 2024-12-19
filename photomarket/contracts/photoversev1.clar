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
(define-constant err-too-many-stakers (err u105))
(define-constant err-revenue-pool-error (err u106))
(define-constant err-distribution-error (err u107))

;; Variables
(define-data-var total-staked-tokens uint u0)
(define-data-var active-stakers (list 200 principal) (list))

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
  (ok (var-get total-staked-tokens))
)

;; Helper function to get amount from staking position
(define-private (get-amount (position {staker: principal, amount: uint}))
  (get amount position)
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
    (var-set total-staked-tokens (+ (var-get total-staked-tokens) amount))
    (map-set staking-positions
      { staker: tx-sender }
      {
        amount: amount,
        timestamp: block-height
      }
    )
    (let ((new-stakers (unwrap! (as-max-len? (append (var-get active-stakers) tx-sender) u200) err-too-many-stakers)))
      (var-set active-stakers new-stakers)
      (ok true)))
)

;; Unstake PHOTO tokens
(define-public (unstake-tokens)
  (let (
    (position (unwrap! (get-staking-position tx-sender) err-not-found))
    (amount (get amount position))
  )
    (try! (as-contract (ft-transfer? photo-token amount (as-contract tx-sender) tx-sender)))
    (var-set total-staked-tokens (- (var-get total-staked-tokens) amount))
    (map-delete staking-positions { staker: tx-sender })
    (var-set active-stakers (filter remove-staker (var-get active-stakers)))
    (ok true))
)

;; Helper function to remove staker from list
(define-private (remove-staker (staker principal))
  (not (is-eq staker tx-sender))
)

;; Private functions

;; Distribute fees from sale
(define-private (distribute-fees (revenue-pool-cut uint) (creator-cut uint) (creator principal) (staker-cut uint))
  (begin 
    (unwrap! (add-to-revenue-pool revenue-pool-cut) err-revenue-pool-error)
    (try! (stx-transfer? creator-cut tx-sender creator))
    (unwrap! (distribute-to-stakers staker-cut) err-distribution-error)
    (ok true))
)

;; Add funds to revenue pool
(define-private (add-to-revenue-pool (amount uint))
  (let (
    (current-period (/ block-height u144))
    (period-key { period: current-period })
  )
    (match (map-get? revenue-periods period-key)
      prev-data (begin
        (map-set revenue-periods
          period-key
          {
            total-revenue: (+ amount (get total-revenue prev-data)),
            distributed-amount: (get distributed-amount prev-data),
            remaining-amount: (+ amount (get remaining-amount prev-data))
          }
        )
        (ok true))
      (begin
        (map-set revenue-periods
          period-key
          {
            total-revenue: amount,
            distributed-amount: u0,
            remaining-amount: amount
          }
        )
        (ok true)))
    )
)

;; Distribute rewards to stakers
(define-private (distribute-to-stakers (amount uint))
  (let (
    (total-staked (var-get total-staked-tokens))
    (active-staker-list (var-get active-stakers))
  )
    (if (> total-staked u0)
      (let (
        (share-per-token (/ (* amount fee-denominator) total-staked))
      )
        (match (fold distribute-staker-share-fold 
          active-staker-list
          (ok { share: share-per-token, success: true }))
          success (ok true)
          error (err err-distribution-error)))
      (ok true)))
)

;; Helper for fold operation
(define-private (distribute-staker-share-fold (staker principal) (previous-result (response {share: uint, success: bool} uint)))
  (match previous-result
    success-data 
      (let (
        (share (get share success-data))
      )
        (match (map-get? staking-positions { staker: staker })
          position (let (
            (staker-amount (/ (* (get amount position) share) fee-denominator))
            (current-balance (get balance (get-user-balance staker)))
          )
            (begin
              (map-set user-balances
                { user: staker }
                { balance: (+ staker-amount current-balance) }
              )
              (ok { share: share, success: true })))
          (ok { share: share, success: false })))
    error previous-result)
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