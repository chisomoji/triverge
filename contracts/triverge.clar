;; Triverge Vault Contract - Warning-Free Version

;; Error constants
(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_VAULT_NOT_FOUND u101)
(define-constant ERR_INSUFFICIENT_BALANCE u102)
(define-constant ERR_LOCKED u103)
(define-constant ERR_INVALID_VAULT u104)
(define-constant ERR_INVALID_AMOUNT u105)
(define-constant ERR_TRANSFER_FAILED u106)
(define-constant ERR_ALREADY_DEPOSITED u107)

;; Vault risk types
(define-constant VAULT_LOW u1)
(define-constant VAULT_MEDIUM u2)
(define-constant VAULT_HIGH u3)

;; Admin
(define-data-var admin principal tx-sender)

;; Vault struct
(define-map vaults
  { id: uint }
  {
    total-deposit: uint,
    total-yield: uint,
    lock-period: uint,
    vault-type: uint
  }
)

;; User deposits
(define-map deposits
  { user: principal, vault-id: uint }
  {
    amount: uint,
    deposit-block: uint,
    claimed: bool
  }
)

(define-data-var vault-counter uint u0)

;; === Helper Functions ===

(define-private (is-admin (sender principal))
  (is-eq sender (var-get admin))
)

(define-private (generate-vault-id)
  (let ((id (var-get vault-counter)))
    (begin
      (var-set vault-counter (+ id u1))
      id
    )
  )
)

(define-private (is-valid-vault-type (vault-type uint))
  (or (is-eq vault-type VAULT_LOW)
      (or (is-eq vault-type VAULT_MEDIUM)
          (is-eq vault-type VAULT_HIGH)))
)

;; === Public Functions ===

;; Admin-only: create a new vault
(define-public (create-vault (vault-type uint) (lock-period uint))
  (begin
    (asserts! (is-admin tx-sender) (err ERR_UNAUTHORIZED))
    (asserts! (is-valid-vault-type vault-type) (err ERR_INVALID_VAULT))
    (asserts! (> lock-period u0) (err ERR_INVALID_AMOUNT))
    (let ((vault-id (generate-vault-id)))
      (map-set vaults
        { id: vault-id }
        {
          total-deposit: u0,
          total-yield: u0,
          lock-period: lock-period,
          vault-type: vault-type
        }
      )
      (ok vault-id)
    )
  )
)

;; Deposit into a vault
(define-public (deposit (vault-id uint) (amount uint))
  (begin
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    (let ((vault-opt (map-get? vaults { id: vault-id }))
          (existing-deposit (map-get? deposits { user: tx-sender, vault-id: vault-id })))
      (asserts! (is-some vault-opt) (err ERR_VAULT_NOT_FOUND))
      (asserts! (is-none existing-deposit) (err ERR_ALREADY_DEPOSITED))
      (match vault-opt
        vault-data
        (match (stx-transfer? amount tx-sender (as-contract tx-sender))
          success
          (begin
            (map-set deposits
              { user: tx-sender, vault-id: vault-id }
              {
                amount: amount,
                deposit-block: stacks-block-height,
                claimed: false
              }
            )
            (map-set vaults
              { id: vault-id }
              {
                total-deposit: (+ (get total-deposit vault-data) amount),
                total-yield: (get total-yield vault-data),
                lock-period: (get lock-period vault-data),
                vault-type: (get vault-type vault-data)
              }
            )
            (ok true)
          )
          error (err ERR_TRANSFER_FAILED)
        )
        (err ERR_VAULT_NOT_FOUND)
      )
    )
  )
)

;; Withdraw from vault
(define-public (withdraw (vault-id uint))
  (let ((user-deposit-opt (map-get? deposits { user: tx-sender, vault-id: vault-id }))
        (vault-opt (map-get? vaults { id: vault-id })))
    (asserts! (is-some user-deposit-opt) (err ERR_INSUFFICIENT_BALANCE))
    (asserts! (is-some vault-opt) (err ERR_VAULT_NOT_FOUND))
    (match user-deposit-opt
      deposit-data
      (match vault-opt
        vault-data
        (let ((lock-period (get lock-period vault-data))
              (deposit-block (get deposit-block deposit-data))
              (current-block stacks-block-height))
          (asserts! (>= current-block (+ deposit-block lock-period)) (err ERR_LOCKED))
          (let ((amount (get amount deposit-data))
                (yield (calculate-yield vault-id amount))
                (total (+ amount yield)))
            (map-delete deposits { user: tx-sender, vault-id: vault-id })
            (as-contract (stx-transfer? total tx-sender tx-sender))
          )
        )
        (err ERR_VAULT_NOT_FOUND)
      )
      (err ERR_INSUFFICIENT_BALANCE)
    )
  )
)

;; === Yield Calculation Logic ===

(define-private (calculate-yield (vault-id uint) (amount uint))
  (match (map-get? vaults { id: vault-id })
    vault-data
    (let ((vault-type (get vault-type vault-data)))
      (let ((rate (if (is-eq vault-type VAULT_LOW)
                      u2
                      (if (is-eq vault-type VAULT_MEDIUM)
                          u5
                          (if (is-eq vault-type VAULT_HIGH)
                              u10
                              u1)))))
        (/ (* amount rate) u100)
      )
    )
    u0
  )
)

;; Admin function to rebalance vaults
(define-public (rebalance-yields (vault-id uint) (additional-yield uint))
  (begin
    (asserts! (is-admin tx-sender) (err ERR_UNAUTHORIZED))
    (match (map-get? vaults { id: vault-id })
      vault-data
      (begin
        (map-set vaults
          { id: vault-id }
          {
            total-deposit: (get total-deposit vault-data),
            total-yield: (+ (get total-yield vault-data) additional-yield),
            lock-period: (get lock-period vault-data),
            vault-type: (get vault-type vault-data)
          }
        )
        (ok (+ (get total-yield vault-data) additional-yield))
      )
      (err ERR_VAULT_NOT_FOUND)
    )
  )
)

;; Change admin
(define-public (change-admin (new-admin principal))
  (begin
    (asserts! (is-admin tx-sender) (err ERR_UNAUTHORIZED))
    (var-set admin new-admin)
    (ok true)
  )
)

;; === Read-Only Functions ===

;; Get vault details
(define-read-only (get-vault (vault-id uint))
  (match (map-get? vaults { id: vault-id })
    vault-data (ok vault-data)
    (err ERR_VAULT_NOT_FOUND)
  )
)

;; Get user deposit
(define-read-only (get-deposit (user principal) (vault-id uint))
  (match (map-get? deposits { user: user, vault-id: vault-id })
    deposit-data (ok deposit-data)
    (err ERR_INSUFFICIENT_BALANCE)
  )
)

;; Get current admin
(define-read-only (get-admin)
  (ok (var-get admin))
)

;; Get vault counter
(define-read-only (get-vault-counter)
  (ok (var-get vault-counter))
)

;; Check if user can withdraw
(define-read-only (can-withdraw (user principal) (vault-id uint))
  (match (map-get? deposits { user: user, vault-id: vault-id })
    deposit-data
    (match (map-get? vaults { id: vault-id })
      vault-data
      (let ((lock-period (get lock-period vault-data))
            (deposit-block (get deposit-block deposit-data))
            (current-block stacks-block-height))
        (ok (>= current-block (+ deposit-block lock-period)))
      )
      (err ERR_VAULT_NOT_FOUND)
    )
    (err ERR_INSUFFICIENT_BALANCE)
  )
)

;; Get expected yield for a deposit
(define-read-only (get-expected-yield (vault-id uint) (amount uint))
  (ok (calculate-yield vault-id amount))
)

;; Get vault type name
(define-read-only (get-vault-type-name (vault-type uint))
  (ok (if (is-eq vault-type VAULT_LOW)
          "LOW"
          (if (is-eq vault-type VAULT_MEDIUM)
              "MEDIUM"
              (if (is-eq vault-type VAULT_HIGH)
                  "HIGH"
                  "UNKNOWN"))))
)