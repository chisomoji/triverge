# Triverge Vault Contract

A secure, role-based vault system for the Stacks blockchain with enhanced security features and analytics.

## New Security Features

- **Role-Based Access Control (RBAC)**
- **Contract Pause Mechanism**
- **Deposit Limits**
- **Input Validation**
- **Emergency Controls**

## Core Features

- **Vault Creation:** Admin/operators can create vaults with risk types and lock periods
- **Deposits:** Users can deposit STX (with deposit caps)
- **Withdrawals:** Time-locked withdrawals with yield
- **Yield Calculation:** Risk-based yields (2%, 5%, 10%)
- **Analytics:** Comprehensive vault and contract statistics

## Roles & Permissions

| Role      | Access Level | Capabilities |
|-----------|--------------|--------------|
| ADMIN     | Full        | All functions + emergency controls |
| OPERATOR  | Limited     | Vault creation + yield management |
| USER      | Basic       | Deposits + withdrawals |

## Security Controls

```clarity
max-deposit-per-user: u1000000000  // 1000 STX
max-vault-capacity:   u10000000000  // 10000 STX
contract-paused:      bool          // Emergency pause
```

## New Functions

### Administrative
```clarity
(grant-role user role)
(revoke-role user)
(set-contract-paused paused)
(set-deposit-limits max-per-user max-vault)
(fund-contract amount)
(emergency-withdraw amount)
```

### Analytics
```clarity
(get-user-role user)
(is-contract-paused)
(get-deposit-limits)
(get-contract-balance)
(get-vault-analytics vault-id)
(get-contract-stats)
```

## Error Codes

| Code | Meaning                   |
|------|---------------------------|
| 100  | Unauthorized              |
| 101  | Vault not found           |
| 102  | Insufficient balance      |
| 103  | Locked (cannot withdraw)  |
| 104  | Invalid vault             |
| 105  | Invalid amount            |
| 106  | Transfer failed           |
| 107  | Already deposited         |
| 108  | Contract paused           |
| 109  | Deposit cap exceeded      |
| 110  | Invalid role             |
| 111  | Invalid principal        |

## Validation Constants

```clarity
MAX_VAULT_ID:     u1000000
MAX_AMOUNT:       u1000000000000  // 1M STX
MIN_LOCK_PERIOD:  u1
MAX_LOCK_PERIOD:  u52560          // ~1 year
```

## Security Notes

- Input validation on all functions
- Role-based access control
- Deposit caps per user and vault
- Emergency pause mechanism
- Protected admin functions
- Safe transfer patterns
- Principal validation

## Contract Analytics

- Vault utilization rates
- Total deposits and yields
- Contract balance monitoring
- Vault performance metrics
- User activity tracking

## License

MIT License

---

For detailed implementation and usage examples, see the contract documentation.
