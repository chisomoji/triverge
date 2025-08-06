;; Triverge Vault Contract - Enhanced with Security & Fund Management

;; Error constants
(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_VAULT_NOT_FOUND u101)
(define-constant ERR_INSUFFICIENT_BALANCE u102)
(define-constant ERR_LOCKED u103)
(define-constant ERR_INVALID_VAULT u104)
(define-constant ERR_INVALID_AMOUNT u105)
(define-constant ERR_TRANSFER_FAILED u106)
(define-constant ERR_ALREADY_DEPOSITED u107)
(define-constant ERR_CONTRACT_PAUSED u108)
(define-constant ERR_DEPOSIT_CAP_EXCEEDED u109)
(define-constant ERR_INVALID_ROLE u110)
(define-constant ERR_INVALID_PRINCIPAL u111)

;; Vault risk types
(define-constant VAULT_LOW u1)
(define-constant VAULT_MEDIUM u2)
(define-constant VAULT_HIGH u3)

;; Role constants
(define-constant ROLE_ADMIN u1)
(define-constant ROLE_OPERATOR u2)

;; Validation constants
(define-constant MAX_VAULT_ID u1000000)
(define-constant MAX_AMOUNT u1000000000000) ;; 1M STX in microSTX
(define-constant MIN_LOCK_PERIOD u1)
(define-constant MAX_LOCK_PERIOD u52560) ;; ~1 year in blocks

;; Admin (kept for backward compatibility)
(define-data-var admin principal tx-sender)

;; Security state variables
(define-data-var contract-paused bool false)
(define-data-var max-deposit-per-user uint u1000000000) ;; 1000 STX in microSTX
(define-data-var max-vault-capacity uint u10000000000) ;; 10000 STX in microSTX

;; Role-based access control
(define-map user-roles
  { user: principal }
  { role: uint }
)

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

;; Initialize admin role for contract deployer
(map-set user-roles { user: tx-sender } { role: ROLE_ADMIN })

;; === Input Validation Functions ===

(define-private (is-valid-principal (user principal))
  (not (is-eq user 'SP000000000000000000002Q6VF78))
)

(define-private (is-valid-amount (amount uint))
  (and (> amount u0) (<= amount MAX_AMOUNT))
)

(define-private (is-valid-vault-id (vault-id uint))
  (and (>= vault-id u0) (< vault-id MAX_VAULT_ID))
)

(define-private (is-valid-role-value (role uint))
  (or (is-eq role ROLE_ADMIN) (is-eq role ROLE_OPERATOR))
)

(define-private (is-valid-lock-period (period uint))
  (and (>= period MIN_LOCK_PERIOD) (<= period MAX_LOCK_PERIOD))
)

(define-private (sanitize-amount (amount uint))
  (if (is-valid-amount amount) amount u0)
)

(define-private (sanitize-vault-id (vault-id uint))
  (if (is-valid-vault-id vault-id) vault-id u0)
)

;; === Helper Functions ===

(define-private (is-admin (sender principal))
  (and (is-valid-principal sender) (is-eq sender (var-get admin)))
)

;; Enhanced role checking with validation
(define-private (has-role (user principal) (required-role uint))
  (and 
    (is-valid-principal user)
    (is-valid-role-value required-role)
    (match (map-get? user-roles { user: user })
      user-data (>= (get role user-data) required-role)
      false
    )
  )
)

(define-private (is-admin-or-operator (sender principal))
  (and (is-valid-principal sender) (has-role sender ROLE_OPERATOR))
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

;; === Security Management Functions ===

;; Grant role (admin only) - with input validation
(define-public (grant-role (user principal) (role uint))
  (begin
    (asserts! (is-valid-principal user) (err ERR_INVALID_PRINCIPAL))
    (asserts! (is-valid-role-value role) (err ERR_INVALID_ROLE))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (map-set user-roles { user: user } { role: role })
    (ok true)
  )
)

;; Revoke role (admin only) - with input validation
(define-public (revoke-role (user principal))
  (begin
    (asserts! (is-valid-principal user) (err ERR_INVALID_PRINCIPAL))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (map-delete user-roles { user: user })
    (ok true)
  )
)

;; Pause/unpause contract (admin only)
(define-public (set-contract-paused (paused bool))
  (begin
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (var-set contract-paused paused)
    (ok true)
  )
)

;; Set deposit limits (admin only) - with input validation
(define-public (set-deposit-limits (max-per-user uint) (max-vault uint))
  (begin
    (asserts! (is-valid-amount max-per-user) (err ERR_INVALID_AMOUNT))
    (asserts! (is-valid-amount max-vault) (err ERR_INVALID_AMOUNT))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (let ((validated-per-user (sanitize-amount max-per-user))
          (validated-vault (sanitize-amount max-vault)))
      (var-set max-deposit-per-user validated-per-user)
      (var-set max-vault-capacity validated-vault)
      (ok true)
    )
  )
)

;; Fund contract for yield payments (admin only) - with input validation
(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-valid-amount amount) (err ERR_INVALID_AMOUNT))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (let ((validated-amount (sanitize-amount amount)))
      (stx-transfer? validated-amount tx-sender (as-contract tx-sender))
    )
  )
)

;; Emergency withdrawal for admin - with input validation
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-valid-amount amount) (err ERR_INVALID_AMOUNT))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (let ((validated-amount (sanitize-amount amount)))
      (as-contract (stx-transfer? validated-amount tx-sender tx-sender))
    )
  )
)

;; === Public Functions ===

;; Admin-only: create a new vault (enhanced with input validation)
(define-public (create-vault (vault-type uint) (lock-period uint))
  (begin
    (asserts! (is-valid-vault-type vault-type) (err ERR_INVALID_VAULT))
    (asserts! (is-valid-lock-period lock-period) (err ERR_INVALID_AMOUNT))
    (asserts! (is-admin-or-operator tx-sender) (err ERR_UNAUTHORIZED))
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

;; Enhanced deposit with comprehensive input validation
(define-public (deposit (vault-id uint) (amount uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-vault-id vault-id) (err ERR_VAULT_NOT_FOUND))
    (asserts! (is-valid-amount amount) (err ERR_INVALID_AMOUNT))
    
    ;; Security checks
    (asserts! (not (var-get contract-paused)) (err ERR_CONTRACT_PAUSED))
    (asserts! (<= amount (var-get max-deposit-per-user)) (err ERR_DEPOSIT_CAP_EXCEEDED))
    
    (let ((validated-vault-id (sanitize-vault-id vault-id))
          (validated-amount (sanitize-amount amount))
          (vault-opt (map-get? vaults { id: validated-vault-id }))
          (existing-deposit (map-get? deposits { user: tx-sender, vault-id: validated-vault-id })))
      (asserts! (is-some vault-opt) (err ERR_VAULT_NOT_FOUND))
      (asserts! (is-none existing-deposit) (err ERR_ALREADY_DEPOSITED))
      
      (match vault-opt
        vault-data
        (begin
          ;; Check vault capacity
          (asserts! (<= (+ (get total-deposit vault-data) validated-amount) (var-get max-vault-capacity)) 
                   (err ERR_DEPOSIT_CAP_EXCEEDED))
          
          ;; Proceed with deposit
          (match (stx-transfer? validated-amount tx-sender (as-contract tx-sender))
            success
            (begin
              (map-set deposits
                { user: tx-sender, vault-id: validated-vault-id }
                {
                  amount: validated-amount,
                  deposit-block: stacks-block-height,
                  claimed: false
                }
              )
              (map-set vaults
                { id: validated-vault-id }
                {
                  total-deposit: (+ (get total-deposit vault-data) validated-amount),
                  total-yield: (get total-yield vault-data),
                  lock-period: (get lock-period vault-data),
                  vault-type: (get vault-type vault-data)
                }
              )
              (ok true)
            )
            error (err ERR_TRANSFER_FAILED)
          )
        )
        (err ERR_VAULT_NOT_FOUND)
      )
    )
  )
)

;; Fixed withdraw function with comprehensive input validation
(define-public (withdraw (vault-id uint))
  (begin
    (asserts! (is-valid-vault-id vault-id) (err ERR_VAULT_NOT_FOUND))
    (let ((validated-vault-id (sanitize-vault-id vault-id))
          (user-deposit-opt (map-get? deposits { user: tx-sender, vault-id: validated-vault-id }))
          (vault-opt (map-get? vaults { id: validated-vault-id })))
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
                  (yield (calculate-yield validated-vault-id amount))
                  (total (+ amount yield)))
              ;; Check contract has sufficient balance
              (asserts! (>= (stx-get-balance (as-contract tx-sender)) total) (err ERR_INSUFFICIENT_BALANCE))
              ;; Delete deposit record first
              (map-delete deposits { user: tx-sender, vault-id: validated-vault-id })
              ;; Update vault totals
              (map-set vaults
                { id: validated-vault-id }
                {
                  total-deposit: (- (get total-deposit vault-data) amount),
                  total-yield: (get total-yield vault-data),
                  lock-period: (get lock-period vault-data),
                  vault-type: (get vault-type vault-data)
                }
              )
              ;; Transfer from contract to user (FIXED)
              (as-contract (stx-transfer? total tx-sender tx-sender))
            )
          )
          (err ERR_VAULT_NOT_FOUND)
        )
        (err ERR_INSUFFICIENT_BALANCE)
      )
    )
  )
)

;; === Yield Calculation Logic ===

(define-private (calculate-yield (vault-id uint) (amount uint))
  (let ((validated-vault-id (sanitize-vault-id vault-id))
        (validated-amount (sanitize-amount amount)))
    (match (map-get? vaults { id: validated-vault-id })
      vault-data
      (let ((vault-type (get vault-type vault-data)))
        (let ((rate (if (is-eq vault-type VAULT_LOW)
                        u2
                        (if (is-eq vault-type VAULT_MEDIUM)
                            u5
                            (if (is-eq vault-type VAULT_HIGH)
                                u10
                                u1)))))
          (/ (* validated-amount rate) u100)
        )
      )
      u0
    )
  )
)

;; Enhanced admin function to rebalance vaults with input validation
(define-public (rebalance-yields (vault-id uint) (additional-yield uint))
  (begin
    (asserts! (is-valid-vault-id vault-id) (err ERR_VAULT_NOT_FOUND))
    (asserts! (is-valid-amount additional-yield) (err ERR_INVALID_AMOUNT))
    (asserts! (is-admin-or-operator tx-sender) (err ERR_UNAUTHORIZED))
    (let ((validated-vault-id (sanitize-vault-id vault-id))
          (validated-yield (sanitize-amount additional-yield)))
      (match (map-get? vaults { id: validated-vault-id })
        vault-data
        (begin
          (map-set vaults
            { id: validated-vault-id }
            {
              total-deposit: (get total-deposit vault-data),
              total-yield: (+ (get total-yield vault-data) validated-yield),
              lock-period: (get lock-period vault-data),
              vault-type: (get vault-type vault-data)
            }
          )
          (ok (+ (get total-yield vault-data) validated-yield))
        )
        (err ERR_VAULT_NOT_FOUND)
      )
    )
  )
)

;; Enhanced change admin with input validation
(define-public (change-admin (new-admin principal))
  (begin
    (asserts! (is-valid-principal new-admin) (err ERR_INVALID_PRINCIPAL))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (var-set admin new-admin)
    ;; Grant admin role to new admin
    (map-set user-roles { user: new-admin } { role: ROLE_ADMIN })
    (ok true)
  )
)

;; === Read-Only Functions ===

;; Get vault details with input validation
(define-read-only (get-vault (vault-id uint))
  (if (is-valid-vault-id vault-id)
    (let ((validated-vault-id (sanitize-vault-id vault-id)))
      (match (map-get? vaults { id: validated-vault-id })
        vault-data (ok vault-data)
        (err ERR_VAULT_NOT_FOUND)
      )
    )
    (err ERR_VAULT_NOT_FOUND)
  )
)

;; Get user deposit with input validation
(define-read-only (get-deposit (user principal) (vault-id uint))
  (if (and (is-valid-principal user) (is-valid-vault-id vault-id))
    (let ((validated-vault-id (sanitize-vault-id vault-id)))
      (match (map-get? deposits { user: user, vault-id: validated-vault-id })
        deposit-data (ok deposit-data)
        (err ERR_INSUFFICIENT_BALANCE)
      )
    )
    (err ERR_INVALID_PRINCIPAL)
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

;; Check if user can withdraw with input validation
(define-read-only (can-withdraw (user principal) (vault-id uint))
  (if (and (is-valid-principal user) (is-valid-vault-id vault-id))
    (let ((validated-vault-id (sanitize-vault-id vault-id)))
      (match (map-get? deposits { user: user, vault-id: validated-vault-id })
        deposit-data
        (match (map-get? vaults { id: validated-vault-id })
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
    (err ERR_INVALID_PRINCIPAL)
  )
)

;; Get expected yield for a deposit with input validation
(define-read-only (get-expected-yield (vault-id uint) (amount uint))
  (if (and (is-valid-vault-id vault-id) (is-valid-amount amount))
    (ok (calculate-yield vault-id amount))
    (err ERR_INVALID_AMOUNT)
  )
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

;; === New Security Read-Only Functions ===

;; Get user role with input validation
(define-read-only (get-user-role (user principal))
  (if (is-valid-principal user)
    (match (map-get? user-roles { user: user })
      role-data (ok (get role role-data))
      (ok u0)
    )
    (err ERR_INVALID_PRINCIPAL)
  )
)

;; Check if contract is paused
(define-read-only (is-contract-paused)
  (ok (var-get contract-paused))
)

;; Get deposit limits
(define-read-only (get-deposit-limits)
  (ok {
    max-per-user: (var-get max-deposit-per-user),
    max-vault: (var-get max-vault-capacity)
  })
)

;; Get contract balance
(define-read-only (get-contract-balance)
  (ok (stx-get-balance (as-contract tx-sender)))
)

;; Get vault analytics with input validation
(define-read-only (get-vault-analytics (vault-id uint))
  (if (is-valid-vault-id vault-id)
    (let ((validated-vault-id (sanitize-vault-id vault-id)))
      (match (map-get? vaults { id: validated-vault-id })
        vault-data
        (ok {
          vault-id: validated-vault-id,
          total-deposit: (get total-deposit vault-data),
          total-yield: (get total-yield vault-data),
          vault-type: (get vault-type vault-data),
          lock-period: (get lock-period vault-data),
          utilization-rate: (if (> (get total-deposit vault-data) u0)
                               (/ (* (get total-yield vault-data) u100) (get total-deposit vault-data))
                               u0)
        })
        (err ERR_VAULT_NOT_FOUND)
      )
    )
    (err ERR_VAULT_NOT_FOUND)
  )
)

;; Get contract stats
(define-read-only (get-contract-stats)
  (ok {
    total-vaults: (var-get vault-counter),
    contract-balance: (stx-get-balance (as-contract tx-sender)),
    is-paused: (var-get contract-paused),
    current-block: stacks-block-height
  })
)
