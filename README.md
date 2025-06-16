# Blockchain-based e-Visa Processing
A decentralized e-Visa processing system built on Stacks blockchain that enables secure and transparent visa applications.

## 🌟 Features

- Digital visa application submission
- Document verification using hashes
- STX-based fee payment
- Automated quota management
- Blacklist management
- Admin controls

## 💻 Contract Functions

### For Applicants
- `apply-for-visa`: Submit new visa application
- `get-visa-status`: Check application status
- `cancel-application`: Cancel pending application

### For Administrators
- `approve-visa`: Approve visa application
- `reject-visa`: Reject visa application
- `set-country-quota`: Set daily visa quotas
- `blacklist-user`: Add user to blacklist
- `remove-from-blacklist`: Remove user from blacklist
- `transfer-admin`: Transfer admin rights

## 🚀 Usage

1. Deploy contract using Clarinet
2. Submit application with required documents:
```clarity
(contract-call? .visa-processing apply-for-visa 
    passport-hash photo-hash "US" "TOURISM")
```

3. Pay visa fee (100 STX)
4. Wait for admin approval

## ⚙️ Requirements

- Clarinet
- Stacks wallet
- Valid documentation

## 🔐 Security

- Document hashes stored on-chain
- Admin-only approval system
- Blacklist protection
```


