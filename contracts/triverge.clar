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
(define-constant ERR_INSUFFICIENT_YIELD_RESERVES u112)
(define-constant ERR_WITHDRAWAL_QUEUE_FULL u113)

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
(define-constant MAX_WITHDRAWAL_QUEUE u100) ;; Maximum pending withdrawals

;; Admin (kept for backward compatibility)
(define-data-var admin principal tx-sender)

;; Security state variables
(define-data-var contract-paused bool false)
(define-data-var max-deposit-per-user uint u1000000000) ;; 1000 STX in microSTX
(define-data-var max-vault-capacity uint u10000000000) ;; 10000 STX in microSTX

;; Fund management variables
(define-data-var total-yield-reserves uint u0) ;; Total funds allocated for yield payments
(define-data-var total-pending-yields uint u0) ;; Total yields owed to users
(define-data-var withdrawal-queue-count uint u0) ;; Number of pending withdrawals
(define-data-var emergency-reserve-ratio uint u10) ;; 10% emergency reserve requirement

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

;; Withdrawal queue for fund management
(define-map withdrawal-queue
  { user: principal, vault-id: uint }
  {
    amount: uint,
    yield: uint,
    total: uint,
    queued-block: uint
  }
)

;; Fund management tracking
(define-map vault-reserves
  { vault-id: uint }
  {
    allocated-reserves: uint,
    pending-yields: uint
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

;; === Fund Management Helper Functions ===

(define-private (calculate-required-reserves (vault-id uint))
  (match (map-get? vaults { id: vault-id })
    vault-data
    (let ((total-deposits (get total-deposit vault-data))
          (vault-type (get vault-type vault-data)))
      (let ((yield-rate (if (is-eq vault-type VAULT_LOW)
                           u2
                           (if (is-eq vault-type VAULT_MEDIUM)
                               u5
                               u10))))
        (/ (* total-deposits yield-rate) u100)
      )
    )
    u0
  )
)

(define-private (update-vault-reserves (vault-id uint) (deposit-amount uint))
  (let ((required-yield (calculate-yield vault-id deposit-amount))
        (current-reserves (default-to { allocated-reserves: u0, pending-yields: u0 }
                                     (map-get? vault-reserves { vault-id: vault-id }))))
    (map-set vault-reserves
      { vault-id: vault-id }
      {
        allocated-reserves: (+ (get allocated-reserves current-reserves) required-yield),
        pending-yields: (+ (get pending-yields current-reserves) required-yield)
      }
    )
    (var-set total-pending-yields (+ (var-get total-pending-yields) required-yield))
  )
)

(define-private (check-fund-sufficiency (total-amount uint))
  (let ((contract-balance (stx-get-balance (as-contract tx-sender)))
        (emergency-reserve (/ (* contract-balance (var-get emergency-reserve-ratio)) u100)))
    (>= contract-balance (+ total-amount emergency-reserve))
  )
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

;; Enhanced fund contract for yield payments with reserve tracking
(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-valid-amount amount) (err ERR_INVALID_AMOUNT))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (let ((validated-amount (sanitize-amount amount)))
      (match (stx-transfer? validated-amount tx-sender (as-contract tx-sender))
        success
        (begin
          (var-set total-yield-reserves (+ (var-get total-yield-reserves) validated-amount))
          (ok true)
        )
        error (err ERR_TRANSFER_FAILED)
      )
    )
  )
)

;; Emergency withdrawal for admin - with input validation and reserve protection
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-valid-amount amount) (err ERR_INVALID_AMOUNT))
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (let ((validated-amount (sanitize-amount amount))
          (contract-balance (stx-get-balance (as-contract tx-sender)))
          (required-reserves (var-get total-pending-yields))
          (admin-sender tx-sender))
      ;; Ensure we don't withdraw funds needed for user yields
      (asserts! (>= (- contract-balance validated-amount) required-reserves) (err ERR_INSUFFICIENT_YIELD_RESERVES))
      (as-contract (stx-transfer? validated-amount tx-sender admin-sender))
    )
  )
)

;; Set emergency reserve ratio (admin only)
(define-public (set-emergency-reserve-ratio (ratio uint))
  (begin
    (asserts! (<= ratio u50) (err ERR_INVALID_AMOUNT)) ;; Max 50% reserve
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (var-set emergency-reserve-ratio ratio)
    (ok true)
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
      ;; Initialize vault reserves
      (map-set vault-reserves
        { vault-id: vault-id }
        {
          allocated-reserves: u0,
          pending-yields: u0
        }
      )
      (ok vault-id)
    )
  )
)

;; Enhanced deposit with comprehensive input validation and reserve management
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
              ;; Update reserve tracking
              (update-vault-reserves validated-vault-id validated-amount)
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

;; FIXED withdraw function with proper fund management and queue system
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
              ;; Check if we can process withdrawal immediately or need to queue
              (if (check-fund-sufficiency total)
                ;; Process withdrawal immediately
                (begin
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
                  ;; Update reserve tracking
                  (let ((current-reserves (default-to { allocated-reserves: u0, pending-yields: u0 }
                                                      (map-get? vault-reserves { vault-id: validated-vault-id }))))
                    (map-set vault-reserves
                      { vault-id: validated-vault-id }
                      {
                        allocated-reserves: (if (>= (get allocated-reserves current-reserves) yield)
                                               (- (get allocated-reserves current-reserves) yield)
                                               u0),
                        pending-yields: (if (>= (get pending-yields current-reserves) yield)
                                          (- (get pending-yields current-reserves) yield)
                                          u0)
                      }
                    )
                    (var-set total-pending-yields (if (>= (var-get total-pending-yields) yield)
                                                     (- (var-get total-pending-yields) yield)
                                                     u0))
                  )
                  ;; Transfer from contract to user
                  (let ((recipient tx-sender))
                    (as-contract (stx-transfer? total tx-sender recipient))
                  )
                )
                ;; Queue withdrawal if insufficient immediate funds
                (begin
                  (asserts! (< (var-get withdrawal-queue-count) MAX_WITHDRAWAL_QUEUE) (err ERR_WITHDRAWAL_QUEUE_FULL))
                  (map-set withdrawal-queue
                    { user: tx-sender, vault-id: validated-vault-id }
                    {
                      amount: amount,
                      yield: yield,
                      total: total,
                      queued-block: current-block
                    }
                  )
                  (var-set withdrawal-queue-count (+ (var-get withdrawal-queue-count) u1))
                  (ok true)
                )
              )
            )
          )
          (err ERR_VAULT_NOT_FOUND)
        )
        (err ERR_INSUFFICIENT_BALANCE)
      )
    )
  )
)

;; Process queued withdrawals (admin function)
(define-public (process-withdrawal-queue (user principal) (vault-id uint))
  (begin
    (asserts! (has-role tx-sender ROLE_ADMIN) (err ERR_UNAUTHORIZED))
    (asserts! (is-valid-principal user) (err ERR_INVALID_PRINCIPAL))
    (asserts! (is-valid-vault-id vault-id) (err ERR_VAULT_NOT_FOUND))
    (let ((validated-vault-id (sanitize-vault-id vault-id))
          (queued-withdrawal (map-get? withdrawal-queue { user: user, vault-id: validated-vault-id })))
      (match queued-withdrawal
        withdrawal-data
        (let ((total (get total withdrawal-data)))
          (asserts! (check-fund-sufficiency total) (err ERR_INSUFFICIENT_BALANCE))
          ;; Remove from queue
          (map-delete withdrawal-queue { user: user, vault-id: validated-vault-id })
          (var-set withdrawal-queue-count (- (var-get withdrawal-queue-count) u1))
          ;; Process the withdrawal
          (as-contract (stx-transfer? total tx-sender user))
        )
        (err ERR_VAULT_NOT_FOUND)
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

;; === New Fund Management Read-Only Functions ===

;; Get fund management status
(define-read-only (get-fund-status)
  (ok {
    total-yield-reserves: (var-get total-yield-reserves),
    total-pending-yields: (var-get total-pending-yields),
    withdrawal-queue-count: (var-get withdrawal-queue-count),
    emergency-reserve-ratio: (var-get emergency-reserve-ratio),
    available-for-withdrawal: (let ((balance (stx-get-balance (as-contract tx-sender)))
                                   (pending (var-get total-pending-yields))
                                   (emergency-reserve (/ (* balance (var-get emergency-reserve-ratio)) u100)))
                                (if (>= balance (+ pending emergency-reserve))
                                    (- balance (+ pending emergency-reserve))
                                    u0))
  })
)

;; Get vault reserves
(define-read-only (get-vault-reserves (vault-id uint))
  (if (is-valid-vault-id vault-id)
    (let ((validated-vault-id (sanitize-vault-id vault-id)))
      (match (map-get? vault-reserves { vault-id: validated-vault-id })
        reserves (ok reserves)
        (ok { allocated-reserves: u0, pending-yields: u0 })
      )
    )
    (err ERR_VAULT_NOT_FOUND)
  )
)

;; Get queued withdrawal
(define-read-only (get-queued-withdrawal (user principal) (vault-id uint))
  (if (and (is-valid-principal user) (is-valid-vault-id vault-id))
    (let ((validated-vault-id (sanitize-vault-id vault-id)))
      (match (map-get? withdrawal-queue { user: user, vault-id: validated-vault-id })
        withdrawal-data (ok withdrawal-data)
        (err ERR_VAULT_NOT_FOUND)
      )
    )
    (err ERR_INVALID_PRINCIPAL)
  )
)

;; Check if withdrawal can be processed immediately
(define-read-only (can-process-withdrawal-immediately (vault-id uint) (amount uint))
  (if (and (is-valid-vault-id vault-id) (is-valid-amount amount))
    (let ((yield (calculate-yield vault-id amount))
          (total (+ amount yield)))
      (ok (check-fund-sufficiency total))
 
