(define-constant contract-owner tx-sender)
(define-constant visa-fee u100000000)
(define-constant processing-time u144)

(define-data-var admin principal tx-sender)

(define-map VisaApplications
    principal
    {
        status: (string-ascii 20),
        application-time: uint,
        expiry: uint,
        passport-hash: (buff 32),
        photo-hash: (buff 32),
        destination: (string-ascii 2),
        purpose: (string-ascii 50),
    }
)

(define-map CountryQuotas
    (string-ascii 2)
    {
        daily-limit: uint,
        current-count: uint,
        last-reset: uint,
    }
)

(define-map BlacklistedUsers
    principal
    bool
)

(define-read-only (get-visa-status (applicant principal))
    (map-get? VisaApplications applicant)
)

(define-read-only (check-blacklist (user principal))
    (default-to false (map-get? BlacklistedUsers user))
)

(define-read-only (get-country-quota (country-code (string-ascii 2)))
    (map-get? CountryQuotas country-code)
)

(define-public (apply-for-visa
        (passport-hash (buff 32))
        (photo-hash (buff 32))
        (destination (string-ascii 2))
        (purpose (string-ascii 50))
    )
    (let ((current-time burn-block-height))
        (asserts! (not (check-blacklist tx-sender)) (err u1))
        (asserts! (is-none (get-visa-status tx-sender)) (err u2))
        (try! (stx-transfer? visa-fee tx-sender contract-owner))
        (map-set VisaApplications tx-sender {
            status: "PENDING",
            application-time: current-time,
            expiry: (+ current-time u5200),
            passport-hash: passport-hash,
            photo-hash: photo-hash,
            destination: destination,
            purpose: purpose,
        })
        (ok true)
    )
)

(define-public (approve-visa (applicant principal))
    (let ((current-time burn-block-height))
        (asserts! (is-eq tx-sender (var-get admin)) (err u3))
        (match (map-get? VisaApplications applicant)
            visa-data (begin
                (map-set VisaApplications applicant
                    (merge visa-data { status: "APPROVED" })
                )
                (ok true)
            )
            (err u4)
        )
    )
)

(define-public (reject-visa (applicant principal))
    (let ((current-time burn-block-height))
        (asserts! (is-eq tx-sender (var-get admin)) (err u5))
        (match (map-get? VisaApplications applicant)
            visa-data (begin
                (map-set VisaApplications applicant
                    (merge visa-data { status: "REJECTED" })
                )
                (ok true)
            )
            (err u6)
        )
    )
)

(define-public (set-country-quota
        (country-code (string-ascii 2))
        (daily-limit uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) (err u7))
        (map-set CountryQuotas country-code {
            daily-limit: daily-limit,
            current-count: u0,
            last-reset: burn-block-height,
        })
        (ok true)
    )
)

(define-public (blacklist-user (user principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) (err u8))
        (map-set BlacklistedUsers user true)
        (ok true)
    )
)

(define-public (remove-from-blacklist (user principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) (err u9))
        (map-delete BlacklistedUsers user)
        (ok true)
    )
)

(define-public (transfer-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) (err u10))
        (var-set admin new-admin)
        (ok true)
    )
)

(define-public (cancel-application)
    (begin
        (asserts! (is-some (get-visa-status tx-sender)) (err u11))
        (map-delete VisaApplications tx-sender)
        (ok true)
    )
)
