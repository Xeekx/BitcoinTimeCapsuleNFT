;; ----------------------------
;; Bitcoin Time Capsule NFT
;; ----------------------------
;; SIP-009 compliant NFT implementation

(define-non-fungible-token time-capsule uint)

(define-data-var next-id uint u1)
(define-data-var contract-owner principal tx-sender)

;; Enhanced data structure with additional fields
(define-map time-capsule-data
  uint
  {
    owner: principal,
    unlock-block: uint,
    data-hash: (buff 32), ;; IPFS or encrypted data hash
    created-at: uint,
    revealed: bool,
    public: bool, ;; Whether capsule is publicly discoverable
  }
)

;; Track revealed capsules
(define-map revealed-capsules
  uint
  bool
)

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-UNLOCK-BLOCK (err u400))
(define-constant ERR-CANNOT-REVEAL (err u403))
(define-constant ERR-ALREADY-REVEALED (err u405))

;; Enhanced mint function with validation
(define-public (mint-capsule
    (unlock-block uint)
    (data-hash (buff 32))
    (is-public bool)
  )
  (let ((id (var-get next-id)))
    (begin
      ;; Validate unlock block is in the future (at least 1 block ahead)
      (asserts! (> unlock-block stacks-block-height) ERR-INVALID-UNLOCK-BLOCK)
      ;; Validate data-hash is not empty
      (asserts! (> (len data-hash) u0) (err u402))
      (var-set next-id (+ id u1))
      (map-set time-capsule-data id {
        owner: tx-sender,
        unlock-block: unlock-block,
        data-hash: data-hash,
        created-at: stacks-block-height,
        revealed: false,
        public: is-public,
      })
      (nft-mint? time-capsule id tx-sender)
    )
  )
)

(define-read-only (can-reveal? (id uint))
  (let ((capsule (map-get? time-capsule-data id)))
    (match capsule
      capsule-data (>= stacks-block-height (get unlock-block capsule-data))
      false
    )
  )
)

;; New function to mark capsule as revealed (owner-only)
(define-public (reveal-capsule (id uint))
  (let ((capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND)))
    (begin
      ;; Only owner can reveal their capsule
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      ;; Check if capsule can be revealed (unlock block reached)
      (asserts! (can-reveal? id) ERR-CANNOT-REVEAL)
      ;; Check if already revealed
      (asserts! (not (get revealed capsule)) ERR-ALREADY-REVEALED)
      ;; Mark as revealed
      (map-set time-capsule-data id (merge capsule { revealed: true }))
      (map-set revealed-capsules id true)
      (ok true)
    )
  )
)

;; Check if capsule is revealed
(define-read-only (is-revealed? (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (get revealed capsule-data)
    false
  )
)

;; Get complete capsule information
(define-read-only (get-capsule-info (id uint))
  (map-get? time-capsule-data id)
)

;; Get blocks remaining until unlock
(define-read-only (blocks-until-unlock (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (if (>= stacks-block-height (get unlock-block capsule-data))
      u0
      (- (get unlock-block capsule-data) stacks-block-height)
    )
    u0
  )
)

;; SIP-009 transfer function
(define-public (transfer
    (id uint)
    (sender principal)
    (recipient principal)
  )
  (begin
    ;; Validate sender is the transaction sender
    (asserts! (is-eq tx-sender sender) ERR-UNAUTHORIZED)
    ;; Validate capsule exists
    (asserts! (is-some (map-get? time-capsule-data id)) ERR-NOT-FOUND)
    ;; Validate sender owns the NFT
    (asserts! (is-eq sender (unwrap-panic (get-owner id))) ERR-UNAUTHORIZED)
    ;; Transfer the NFT
    (match (nft-transfer? time-capsule id sender recipient)
      success (begin
        ;; Update the owner in our data map
        (map-set time-capsule-data id
          (merge (unwrap-panic (map-get? time-capsule-data id)) { owner: recipient })
        )
        (ok true)
      )
      error (err error)
    )
  )
)

;; SIP-009 get-owner function
(define-read-only (get-owner (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (ok (get owner capsule-data))
    ERR-NOT-FOUND
  )
)

;; SIP-009 get-token-uri function
(define-read-only (get-token-uri (id uint))
  (if (is-some (map-get? time-capsule-data id))
    (ok (some "https://api.timecapsule.com/metadata/"))
    ERR-NOT-FOUND
  )
)

;; Get total supply
(define-read-only (get-total-supply)
  (- (var-get next-id) u1)
)

;; Enhanced contract owner functions with validation
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Check if capsule is public
(define-read-only (is-public? (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (get public capsule-data)
    false
  )
)

;; Update capsule visibility (owner only)
(define-public (set-capsule-visibility
    (id uint)
    (is-public bool)
  )
  (let ((capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND)))
    (begin
      ;; Only owner can change visibility
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      ;; Update visibility
      (map-set time-capsule-data id (merge capsule { public: is-public }))
      (ok true)
    )
  )
)

;; Get public capsule info (for discovery)
(define-read-only (get-public-capsule-info (id uint))
  (let ((capsule (map-get? time-capsule-data id)))
    (match capsule
      capsule-data (if (get public capsule-data)
        (some capsule-data)
        none
      )
      none
    )
  )
)

;; Emergency function to check if capsule exists
(define-read-only (capsule-exists? (id uint))
  (is-some (map-get? time-capsule-data id))
)
