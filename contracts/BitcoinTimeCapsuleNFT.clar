;; ----------------------------
;; Bitcoin Time Capsule NFT - Enhanced
;; ----------------------------
;; SIP-009 compliant NFT implementation with multi-stage unlocking and economic incentives

(define-non-fungible-token time-capsule uint)
(define-fungible-token capsule-token)

;; Contract state variables
(define-data-var next-id uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var total-rewards-pool uint u0)
(define-data-var min-stake-amount uint u1000000) ;; 1 STX in microSTX

;; Enhanced data structure with multi-stage and economic features
(define-map time-capsule-data
  uint
  {
    owner: principal,
    unlock-block: uint,
    data-hash: (buff 32),
    created-at: uint,
    revealed: bool,
    public: bool,
    reveal-fee: uint,
    early-unlock-penalty: uint,
    stage-count: uint,
    current-stage: uint,
    staked-amount: uint,
    total-views: uint,
    category: (string-ascii 32),
  }
)

;; Multi-stage unlock data
(define-map capsule-stages
  {
    capsule-id: uint,
    stage: uint,
  }
  {
    unlock-block: uint,
    data-hash: (buff 32),
    stage-fee: uint,
    revealed: bool,
  }
)

;; Economic tracking
(define-map user-stakes
  principal
  {
    total-staked: uint,
    reward-debt: uint,
    last-claim-block: uint,
  }
)

(define-map capsule-earnings
  uint
  {
    total-earned: uint,
    total-views: uint,
    last-earning-block: uint,
  }
)

;; Marketplace for unrevealed capsules
(define-map capsule-listings
  uint
  {
    seller: principal,
    price: uint,
    listed-at: uint,
    active: bool,
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
(define-constant ERR-INSUFFICIENT-PAYMENT (err u406))
(define-constant ERR-INVALID-STAGE (err u407))
(define-constant ERR-INSUFFICIENT-STAKE (err u408))
(define-constant ERR-LISTING-NOT-ACTIVE (err u409))
(define-constant ERR-CANNOT-BUY-OWN (err u410))
(define-constant ERR-INVALID-FEE (err u411))
(define-constant ERR-TRANSFER-FAILED (err u500))
(define-constant ERR-INVALID-DATA (err u402))
(define-constant ERR-INVALID-STAGE-COUNT (err u412))
(define-constant ERR-STAGE-ORDER (err u413))
(define-constant ERR-EARLY-UNLOCK-NOT-ALLOWED (err u414))
(define-constant ERR-EXTEND-NOT-ALLOWED (err u415))
(define-constant ERR-EXTENSION-TOO-LONG (err u416))
(define-constant ERR-CANNOT-LIST-REVEALED (err u417))
(define-constant ERR-FEE-TOO-HIGH (err u418))

;; Helper functions
(define-private (update-user-stake
    (user principal)
    (amount uint)
  )
  (let ((current-stake (default-to {
      total-staked: u0,
      reward-debt: u0,
      last-claim-block: stacks-block-height,
    }
      (map-get? user-stakes user)
    )))
    (map-set user-stakes user {
      total-staked: (+ (get total-staked current-stake) amount),
      reward-debt: (get reward-debt current-stake),
      last-claim-block: (get last-claim-block current-stake),
    })
    (ok true)
  )
)

(define-private (distribute-reveal-rewards (id uint))
  (match (map-get? time-capsule-data id)
    capsule (let ((reward-amount (/ (get staked-amount capsule) u10)))
      (var-set total-rewards-pool (+ (var-get total-rewards-pool) reward-amount))
      (ok reward-amount)
    )
    ERR-NOT-FOUND
  )
)

(define-private (distribute-stage-rewards
    (id uint)
    (stage uint)
  )
  (match (map-get? time-capsule-data id)
    capsule (let ((reward-amount (/ (get staked-amount capsule) (* (get stage-count capsule) u20))))
      (var-set total-rewards-pool (+ (var-get total-rewards-pool) reward-amount))
      (ok reward-amount)
    )
    ERR-NOT-FOUND
  )
)

;; Read-only helper functions
(define-read-only (is-stage-revealed?
    (id uint)
    (stage uint)
  )
  (match (map-get? capsule-stages {
    capsule-id: id,
    stage: stage,
  })
    stage-info (get revealed stage-info)
    false
  )
)

(define-read-only (can-reveal? (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (>= stacks-block-height (get unlock-block capsule-data))
    false
  )
)

(define-read-only (can-reveal-stage?
    (id uint)
    (stage uint)
  )
  (match (map-get? capsule-stages {
    capsule-id: id,
    stage: stage,
  })
    stage-info (>= stacks-block-height (get unlock-block stage-info))
    false
  )
)

;; Enhanced mint function with validation
(define-public (mint-capsule
    (unlock-block uint)
    (data-hash (buff 32))
    (is-public bool)
    (reveal-fee uint)
    (category (string-ascii 32))
    (stake-amount uint)
  )
  (let ((id (var-get next-id)))
    (begin
      ;; Validations
      (asserts! (> unlock-block stacks-block-height) ERR-INVALID-UNLOCK-BLOCK)
      (asserts! (> (len data-hash) u0) ERR-INVALID-DATA)
      (asserts! (>= stake-amount (var-get min-stake-amount))
        ERR-INSUFFICIENT-STAKE
      )
      (asserts! (<= reveal-fee u10000000) ERR-INVALID-FEE) ;; Max 10 STX fee

      ;; Transfer stake amount from user
      (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))

      ;; Update next ID
      (var-set next-id (+ id u1))

      ;; Create capsule data
      (map-set time-capsule-data id {
        owner: tx-sender,
        unlock-block: unlock-block,
        data-hash: data-hash,
        created-at: stacks-block-height,
        revealed: false,
        public: is-public,
        reveal-fee: reveal-fee,
        early-unlock-penalty: u1000, ;; 10% default penalty
        stage-count: u1,
        current-stage: u0,
        staked-amount: stake-amount,
        total-views: u0,
        category: category,
      })

      ;; Initialize earnings tracking
      (map-set capsule-earnings id {
        total-earned: u0,
        total-views: u0,
        last-earning-block: stacks-block-height,
      })

      ;; Update user stakes
      ;; Update user stake and mint NFT
      (unwrap-panic (update-user-stake tx-sender stake-amount))
      (nft-mint? time-capsule id tx-sender)
    )
  )
)

;; Helper function to create stages without recursion
(define-private (create-stages
    (id uint)
    (unlock-blocks (list 10 uint))
    (data-hashes (list 10 (buff 32)))
    (stage-fees (list 10 uint))
  )
  (begin
    (map-set capsule-stages {
      capsule-id: id,
      stage: u0,
    } {
      unlock-block: (unwrap-panic (element-at unlock-blocks u0)),
      data-hash: (unwrap-panic (element-at data-hashes u0)),
      stage-fee: (unwrap-panic (element-at stage-fees u0)),
      revealed: false,
    })
    (and
      (> (len unlock-blocks) u1)
      (map-set capsule-stages {
        capsule-id: id,
        stage: u1,
      } {
        unlock-block: (unwrap-panic (element-at unlock-blocks u1)),
        data-hash: (unwrap-panic (element-at data-hashes u1)),
        stage-fee: (unwrap-panic (element-at stage-fees u1)),
        revealed: false,
      })
    )
    (ok true)
  )
)

;; Create multi-stage capsule with proper validation
(define-public (mint-multi-stage-capsule
    (unlock-blocks (list 10 uint))
    (data-hashes (list 10 (buff 32)))
    (stage-fees (list 10 uint))
    (is-public bool)
    (category (string-ascii 32))
    (stake-amount uint)
  )
  (let (
      (id (var-get next-id))
      (stage-count (len unlock-blocks))
    )
    (begin
      ;; Validations
      (asserts! (> stage-count u0) ERR-INVALID-STAGE-COUNT)
      (asserts! (<= stage-count u10) ERR-INVALID-STAGE-COUNT)
      (asserts! (is-eq stage-count (len data-hashes)) ERR-INVALID-STAGE-COUNT)
      (asserts! (is-eq stage-count (len stage-fees)) ERR-INVALID-STAGE-COUNT)
      (asserts! (>= stake-amount (var-get min-stake-amount))
        ERR-INSUFFICIENT-STAKE
      )

      ;; Transfer stake
      (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))

      ;; Update next ID
      (var-set next-id (+ id u1))

      ;; Create main capsule record
      (map-set time-capsule-data id {
        owner: tx-sender,
        unlock-block: (unwrap-panic (element-at unlock-blocks u0)),
        data-hash: (unwrap-panic (element-at data-hashes u0)),
        created-at: stacks-block-height,
        revealed: false,
        public: is-public,
        reveal-fee: u0,
        early-unlock-penalty: u1000,
        staked-amount: stake-amount,
        total-views: u0,
        category: category,
        stage-count: stage-count,
        current-stage: u0,
      })

      ;; Create stage records
      (unwrap-panic (create-stages id unlock-blocks data-hashes stage-fees))

      ;; Initialize earnings
      (map-set capsule-earnings id {
        total-earned: u0,
        total-views: u0,
        last-earning-block: stacks-block-height,
      })

      ;; Update user stakes
      (unwrap-panic (update-user-stake tx-sender stake-amount))

      ;; Mint NFT
      (nft-mint? time-capsule id tx-sender)
    )
  )
)

;; Enhanced reveal with proper error handling
(define-public (reveal-capsule (id uint))
  (let ((capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND)))
    (begin
      ;; Validations
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      (asserts! (not (get revealed capsule)) ERR-ALREADY-REVEALED)
      (asserts! (can-reveal? id) ERR-CANNOT-REVEAL)

      ;; Mark as revealed
      (map-set time-capsule-data id (merge capsule { revealed: true }))
      (map-set revealed-capsules id true)

      ;; Distribute staking rewards
      (try! (distribute-reveal-rewards id))

      (ok true)
    )
  )
)

;; Reveal specific stage with validation
(define-public (reveal-stage
    (id uint)
    (stage uint)
  )
  (let (
      (capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND))
      (stage-info (unwrap!
        (map-get? capsule-stages {
          capsule-id: id,
          stage: stage,
        })
        ERR-NOT-FOUND
      ))
    )
    (begin
      ;; Validations
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      (asserts! (< stage (get stage-count capsule)) ERR-INVALID-STAGE)
      (asserts! (not (get revealed stage-info)) ERR-ALREADY-REVEALED)
      (asserts! (can-reveal-stage? id stage) ERR-CANNOT-REVEAL)

      ;; Check sequential unlock (must reveal previous stages first)
      (asserts! (or (is-eq stage u0) (is-stage-revealed? id (- stage u1)))
        ERR-STAGE-ORDER
      )

      ;; Mark stage as revealed
      (map-set capsule-stages {
        capsule-id: id,
        stage: stage,
      }
        (merge stage-info { revealed: true })
      )

      ;; Update current stage
      (map-set time-capsule-data id
        (merge capsule { current-stage: (+ (get current-stage capsule) u1) })
      )

      ;; Distribute rewards
      (try! (distribute-stage-rewards id stage))

      (ok true)
    )
  )
)

;; Pay to view revealed content
(define-public (view-revealed-content (id uint))
  (let (
      (capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND))
      (earnings (unwrap! (map-get? capsule-earnings id) ERR-NOT-FOUND))
    )
    (begin
      ;; Check if revealed
      (asserts! (get revealed capsule) ERR-CANNOT-REVEAL)

      ;; Handle fee payment
      (if (> (get reveal-fee capsule) u0)
        (begin
          ;; Transfer fee to owner
          (try! (stx-transfer? (get reveal-fee capsule) tx-sender (get owner capsule)))
          ;; Update earnings
          (map-set capsule-earnings id {
            total-earned: (+ (get total-earned earnings) (get reveal-fee capsule)),
            total-views: (+ (get total-views earnings) u1),
            last-earning-block: stacks-block-height,
          })
        )
        ;; Free content, just update view count
        (map-set capsule-earnings id
          (merge earnings { total-views: (+ (get total-views earnings) u1) })
        )
      )

      ;; Update capsule view count
      (map-set time-capsule-data id
        (merge capsule { total-views: (+ (get total-views capsule) u1) })
      )

      (ok true)
    )
  )
)

;; Early unlock with penalty
(define-public (early-unlock (id uint))
  (let (
      (capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND))
      (penalty-amount (/ (* (get staked-amount capsule) (get early-unlock-penalty capsule))
        u10000
      ))
    )
    (begin
      ;; Validations
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      (asserts! (< stacks-block-height (get unlock-block capsule))
        ERR-EARLY-UNLOCK-NOT-ALLOWED
      )
      (asserts! (not (get revealed capsule)) ERR-ALREADY-REVEALED)

      ;; Apply penalty to rewards pool
      (var-set total-rewards-pool (+ (var-get total-rewards-pool) penalty-amount))

      ;; Mark as revealed
      (map-set time-capsule-data id (merge capsule { revealed: true }))
      (map-set revealed-capsules id true)

      (ok penalty-amount)
    )
  )
)

;; Extend unlock time with limitations
(define-public (extend-unlock-time
    (id uint)
    (additional-blocks uint)
  )
  (let ((capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND)))
    (begin
      ;; Validations
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      (asserts! (not (get revealed capsule)) ERR-ALREADY-REVEALED)
      (asserts! (< stacks-block-height (get unlock-block capsule))
        ERR-EXTEND-NOT-ALLOWED
      )
      (asserts! (<= additional-blocks u52560) ERR-EXTENSION-TOO-LONG) ;; Max 1 year

      ;; Update unlock block
      (map-set time-capsule-data id
        (merge capsule { unlock-block: (+ (get unlock-block capsule) additional-blocks) })
      )

      (ok true)
    )
  )
)

;; Marketplace functions
(define-public (list-capsule-for-sale
    (id uint)
    (price uint)
  )
  (let ((capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND)))
    (begin
      ;; Validations
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      (asserts! (not (get revealed capsule)) ERR-CANNOT-LIST-REVEALED)
      (asserts! (> price u0) ERR-INVALID-FEE)

      (map-set capsule-listings id {
        seller: tx-sender,
        price: price,
        listed-at: stacks-block-height,
        active: true,
      })

      (ok true)
    )
  )
)

(define-public (buy-listed-capsule (id uint))
  (let (
      (listing (unwrap! (map-get? capsule-listings id) ERR-NOT-FOUND))
      (capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND))
    )
    (begin
      ;; Validations
      (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE)
      (asserts! (not (is-eq tx-sender (get seller listing))) ERR-CANNOT-BUY-OWN)

      ;; Calculate fees
      (let (
          (platform-fee (/ (* (get price listing) (var-get platform-fee-rate)) u10000))
          (seller-amount (- (get price listing) platform-fee))
        )
        ;; Transfer payments
        (try! (stx-transfer? seller-amount tx-sender (get seller listing)))
        (try! (stx-transfer? platform-fee tx-sender (var-get contract-owner)))

        ;; Transfer NFT
        (try! (nft-transfer? time-capsule id (get seller listing) tx-sender))

        ;; Update capsule owner
        (map-set time-capsule-data id (merge capsule { owner: tx-sender }))

        ;; Deactivate listing
        (map-set capsule-listings id (merge listing { active: false }))

        (ok true)
      )
    )
  )
)

;; Staking functions
(define-public (stake-for-rewards (amount uint))
  (begin
    (asserts! (>= amount (var-get min-stake-amount)) ERR-INSUFFICIENT-STAKE)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (unwrap-panic (update-user-stake tx-sender amount))
    (ok true)
  )
)

(define-public (claim-rewards)
  (let ((user-stake (default-to {
      total-staked: u0,
      reward-debt: u0,
      last-claim-block: u0,
    }
      (map-get? user-stakes tx-sender)
    )))
    (if (> (get total-staked user-stake) u0)
      (let (
          (blocks-since-claim (- stacks-block-height (get last-claim-block user-stake)))
          (reward-rate u10) ;; 10 microSTX per block per 1 STX staked
          (rewards (/ (* (get total-staked user-stake) blocks-since-claim reward-rate)
            u1000000
          ))
        )
        (if (> rewards u0)
          (begin
            ;; Transfer rewards
            (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
            ;; Update user stake record
            (map-set user-stakes tx-sender
              (merge user-stake {
                last-claim-block: stacks-block-height,
                reward-debt: (+ (get reward-debt user-stake) rewards),
              })
            )
            (ok rewards)
          )
          (ok u0)
        )
      )
      (ok u0)
    )
  )
)

;; Read-only functions
(define-read-only (get-capsule-info (id uint))
  (map-get? time-capsule-data id)
)

(define-read-only (get-stage-info
    (id uint)
    (stage uint)
  )
  (map-get? capsule-stages {
    capsule-id: id,
    stage: stage,
  })
)

(define-read-only (get-user-stake (user principal))
  (map-get? user-stakes user)
)

(define-read-only (get-capsule-earnings (id uint))
  (map-get? capsule-earnings id)
)

(define-read-only (get-listing-info (id uint))
  (map-get? capsule-listings id)
)

(define-read-only (get-pending-rewards (user principal))
  (match (map-get? user-stakes user)
    stake-data (let (
        (blocks-since-claim (- stacks-block-height (get last-claim-block stake-data)))
        (reward-rate u10)
      )
      (/ (* (get total-staked stake-data) blocks-since-claim reward-rate)
        u1000000
      )
    )
    u0
  )
)

(define-read-only (is-revealed? (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (get revealed capsule-data)
    false
  )
)

(define-read-only (blocks-until-unlock (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (if (>= stacks-block-height (get unlock-block capsule-data))
      u0
      (- (get unlock-block capsule-data) stacks-block-height)
    )
    u0
  )
)

(define-read-only (is-public? (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (get public capsule-data)
    false
  )
)

(define-read-only (capsule-exists? (id uint))
  (is-some (map-get? time-capsule-data id))
)

;; SIP-009 NFT Standard Functions
(define-public (transfer
    (id uint)
    (sender principal)
    (recipient principal)
  )
  (begin
    (asserts! (is-eq tx-sender sender) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? time-capsule-data id)) ERR-NOT-FOUND)
    (asserts! (is-eq sender (unwrap-panic (get-owner id))) ERR-UNAUTHORIZED)

    (match (nft-transfer? time-capsule id sender recipient)
      success (begin
        (map-set time-capsule-data id
          (merge (unwrap-panic (map-get? time-capsule-data id)) { owner: recipient })
        )
        (ok true)
      )
      error
      ERR-TRANSFER-FAILED
    )
  )
)

(define-read-only (get-owner (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (ok (get owner capsule-data))
    ERR-NOT-FOUND
  )
)

(define-read-only (get-token-uri (id uint))
  (if (is-some (map-get? time-capsule-data id))
    (ok (some "https://api.timecapsule.com/metadata/"))
    ERR-NOT-FOUND
  )
)

(define-read-only (get-total-supply)
  (- (var-get next-id) u1)
)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR-FEE-TOO-HIGH) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-public (set-min-stake-amount (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set min-stake-amount new-amount)
    (ok true)
  )
)

(define-public (set-capsule-visibility
    (id uint)
    (is-public bool)
  )
  (let ((capsule (unwrap! (map-get? time-capsule-data id) ERR-NOT-FOUND)))
    (begin
      (asserts! (is-eq tx-sender (get owner capsule)) ERR-UNAUTHORIZED)
      (map-set time-capsule-data id (merge capsule { public: is-public }))
      (ok true)
    )
  )
)

;; Getter functions for contract state
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (get-total-rewards-pool)
  (var-get total-rewards-pool)
)

(define-read-only (get-min-stake-amount)
  (var-get min-stake-amount)
)

(define-read-only (get-public-capsule-info (id uint))
  (match (map-get? time-capsule-data id)
    capsule-data (if (get public capsule-data)
      (some capsule-data)
      none
    )
    none
  )
)
