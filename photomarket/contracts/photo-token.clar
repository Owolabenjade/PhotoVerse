;; PHOTO Token - Semi-Fungible Token Implementation
;; This token is used for staking and governance in the Photoverse ecosystem

;; Constants
(define-constant contract-owner tx-sender)
(define-constant token-name "PHOTO Token")
(define-constant token-symbol "PHOTO")
(define-constant token-decimals u6)
(define-constant token-uri "https://photoverse.protocol/token-metadata")

;; Error codes
(define-constant err-owner-only (err u1001))
(define-constant err-insufficient-balance (err u1002))
(define-constant err-invalid-recipient (err u1003))
(define-constant err-not-approved (err u1004))

;; Token definition
(define-fungible-token photo-token)

;; Data Maps
(define-map token-approvals
  { owner: principal, spender: principal }
  { approved: bool }
)

;; Read-only functions

(define-read-only (get-name)
  (ok token-name)
)

(define-read-only (get-symbol)
  (ok token-symbol)
)

(define-read-only (get-decimals)
  (ok token-decimals)
)

(define-read-only (get-token-uri)
  (ok token-uri)
)

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance photo-token account))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply photo-token))
)

(define-read-only (get-allowance (owner principal) (spender principal))
  (match (map-get? token-approvals { owner: owner, spender: spender })
    approval-data (ok (if (get approved approval-data) (ft-get-balance photo-token owner) u0))
    (ok u0)
  )
)

;; Public functions

(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-owner-only)
    (asserts! (> amount u0) err-insufficient-balance)
    (asserts! (not (is-eq recipient sender)) err-invalid-recipient)
    (try! (ft-transfer? photo-token amount sender recipient))
    (ok true))
)

(define-public (transfer-from (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-approved sender tx-sender) err-not-approved)
    (asserts! (> amount u0) err-insufficient-balance)
    (asserts! (not (is-eq recipient sender)) err-invalid-recipient)
    (try! (ft-transfer? photo-token amount sender recipient))
    (ok true))
)

(define-public (approve (spender principal))
  (begin
    (map-set token-approvals
      { owner: tx-sender, spender: spender }
      { approved: true }
    )
    (ok true))
)

(define-public (revoke (spender principal))
  (begin
    (map-set token-approvals
      { owner: tx-sender, spender: spender }
      { approved: false }
    )
    (ok true))
)

;; Private functions

(define-private (is-approved (owner principal) (spender principal))
  (match (map-get? token-approvals { owner: owner, spender: spender })
    approval-data (get approved approval-data)
    false)
)

;; Administrative functions - only callable by contract owner

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (ft-mint? photo-token amount recipient))
    (ok true))
)

(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (ft-burn? photo-token amount owner))
    (ok true))
)