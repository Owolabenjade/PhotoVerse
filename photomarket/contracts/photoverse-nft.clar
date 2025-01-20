;; Constants
(define-constant contract-owner tx-sender)
(define-constant collection-name "Photoverse NFTs")
(define-constant collection-uri "https://photoverse.protocol/collection-metadata")

;; Error codes
(define-constant err-owner-only (err u2001))
(define-constant err-not-token-owner (err u2002))
(define-constant err-token-not-found (err u2003))
(define-constant err-already-minted (err u2004))
(define-constant err-not-authorized (err u2005))
(define-constant err-invalid-uri (err u2006))

;; NFT definition
(define-non-fungible-token photoverse-nft uint)

;; Data Maps
(define-map token-metadata
  { token-id: uint }
  {
    creator: principal,
    uri: (string-ascii 256),
    minted-block: uint,
    is-frozen: bool
  }
)

(define-map token-approvals
  { token-id: uint }
  { approved: (optional principal) }
)

(define-map operator-approvals
  { owner: principal, operator: principal }
  { approved: bool }
)

;; Read-only functions

(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
  (match (map-get? token-metadata { token-id: token-id })
    metadata (ok (get uri metadata))
    (err err-token-not-found))
)

(define-read-only (get-token-metadata (token-id uint))
  (ok (map-get? token-metadata { token-id: token-id }))
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? photoverse-nft token-id))
)

(define-read-only (is-approved-for-all (owner principal) (operator principal))
  (match (map-get? operator-approvals { owner: owner, operator: operator })
    approval-data (ok (get approved approval-data))
    (ok false))
)

;; Variables
(define-data-var last-token-id uint u0)

;; Public functions

;; Mint new NFT
(define-public (mint (recipient principal) (uri (string-ascii 256)))
  (let (
    (token-id (+ (var-get last-token-id) u1))
  )
    (asserts! (is-valid-uri uri) err-invalid-uri)
    (try! (nft-mint? photoverse-nft token-id recipient))
    (map-set token-metadata
      { token-id: token-id }
      {
        creator: tx-sender,
        uri: uri,
        minted-block: block-height,
        is-frozen: false
      }
    )
    (var-set last-token-id token-id)
    (ok token-id))
)

;; Transfer NFT
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-owner-or-approved token-id sender) err-not-authorized)
    (try! (nft-transfer? photoverse-nft token-id sender recipient))
    (map-set token-approvals { token-id: token-id } { approved: none })
    (ok true))
)

;; Set approval for a specific token
(define-public (approve (token-id uint) (operator (optional principal)))
  (let ((owner (unwrap! (nft-get-owner? photoverse-nft token-id) err-token-not-found)))
    (asserts! (is-eq tx-sender owner) err-not-authorized)
    (map-set token-approvals { token-id: token-id } { approved: operator })
    (ok true))
)

;; Set approval for all tokens
(define-public (set-approval-for-all (operator principal) (approved bool))
  (begin
    (map-set operator-approvals
      { owner: tx-sender, operator: operator }
      { approved: approved }
    )
    (ok true))
)

;; Update token URI
(define-public (update-token-uri (token-id uint) (new-uri (string-ascii 256)))
  (let ((metadata (unwrap! (map-get? token-metadata { token-id: token-id }) err-token-not-found)))
    (asserts! (is-eq (get creator metadata) tx-sender) err-not-authorized)
    (asserts! (not (get is-frozen metadata)) err-not-authorized)
    (asserts! (is-valid-uri new-uri) err-invalid-uri)
    (map-set token-metadata
      { token-id: token-id }
      (merge metadata { uri: new-uri })
    )
    (ok true))
)

;; Freeze token metadata
(define-public (freeze-metadata (token-id uint))
  (let ((metadata (unwrap! (map-get? token-metadata { token-id: token-id }) err-token-not-found)))
    (asserts! (is-eq (get creator metadata) tx-sender) err-not-authorized)
    (map-set token-metadata
      { token-id: token-id }
      (merge metadata { is-frozen: true })
    )
    (ok true))
)

;; Private functions

;; Check if sender is token owner or approved
(define-private (is-owner-or-approved (token-id uint) (sender principal))
  (let (
    (owner (unwrap! (nft-get-owner? photoverse-nft token-id) false))
    (approval (map-get? token-approvals { token-id: token-id }))
  )
    (or
      (is-eq sender owner)
      (is-eq (some sender) (get approved approval))
      (is-approved-for-all-bool owner sender)))
)

;; Check if operator is approved for all
(define-private (is-approved-for-all-bool (owner principal) (operator principal))
  (match (map-get? operator-approvals { owner: owner, operator: operator })
    approval-data (get approved approval-data)
    false)
)

;; Validate URI format
(define-private (is-valid-uri (uri (string-ascii 256)))
  (not (is-eq uri ""))
)