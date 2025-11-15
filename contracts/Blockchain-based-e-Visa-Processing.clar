(define-constant contract-owner tx-sender)
(define-constant visa-fee u100000000)
(define-constant renewal-fee u50000000)
(define-constant processing-time u144)
(define-constant renewal-window u1440)
(define-constant extension-fee-emergency u200000000)
(define-constant extension-fee-business u150000000)
(define-constant extension-fee-medical u100000000)
(define-constant max-extension-days u720)
(define-constant refund-rate-early u80)
(define-constant refund-rate-standard u50)
(define-constant refund-rate-late u20)
(define-constant early-rejection-window u72)
(define-constant standard-rejection-window u144)

(define-data-var admin principal tx-sender)
(define-data-var total-refunds-issued uint u0)

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
        renewals: uint,
        extensions-used: uint,
        last-extension-time: (optional uint),
        refund-claimed: bool,
        paid-amount: uint,
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

(define-map TravelHistory
    {
        traveler: principal,
        entry-id: uint,
    }
    {
        destination-country: (string-ascii 2),
        entry-timestamp: uint,
        exit-timestamp: (optional uint),
        entry-point: (string-ascii 50),
        exit-point: (optional (string-ascii 50)),
        compliance-status: (string-ascii 10),
    }
)

(define-data-var next-entry-id uint u1)

(define-read-only (get-visa-status (applicant principal))
    (map-get? VisaApplications applicant)
)

(define-read-only (check-blacklist (user principal))
    (default-to false (map-get? BlacklistedUsers user))
)

(define-read-only (get-country-quota (country-code (string-ascii 2)))
    (map-get? CountryQuotas country-code)
)

(define-read-only (get-country-quota-usage (country-code (string-ascii 2)))
    (match (map-get? CountryQuotas country-code)
        quota-data (let (
                (current-time burn-block-height)
                (daily-limit (get daily-limit quota-data))
                (stored-count (get current-count quota-data))
                (last-reset (get last-reset quota-data))
                (needs-reset (>= (- current-time last-reset) processing-time))
                (effective-count (if needs-reset
                    u0
                    stored-count
                ))
                (remaining (if (>= daily-limit effective-count)
                    (- daily-limit effective-count)
                    u0
                ))
            )
            {
                limit: daily-limit,
                used: effective-count,
                remaining: remaining,
                last-reset: last-reset,
            }
        )
        {
            limit: u0,
            used: u0,
            remaining: u0,
            last-reset: u0,
        }
    )
)

(define-read-only (get-travel-record
        (traveler principal)
        (entry-id uint)
    )
    (map-get? TravelHistory {
        traveler: traveler,
        entry-id: entry-id,
    })
)

(define-read-only (get-travel-compliance-score (traveler principal))
    (let ((total-entries u10))
        (if (> total-entries u0)
            u85
            u0
        )
    )
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
        (match (map-get? CountryQuotas destination)
            quota-data (let (
                    (daily-limit (get daily-limit quota-data))
                    (stored-count (get current-count quota-data))
                    (last-reset (get last-reset quota-data))
                    (needs-reset (>= (- current-time last-reset) processing-time))
                    (new-count (if needs-reset
                        u1
                        (+ stored-count u1)
                    ))
                    (new-last-reset (if needs-reset
                        current-time
                        last-reset
                    ))
                )
                (asserts! (<= new-count daily-limit) (err u33))
                (map-set CountryQuotas destination {
                    daily-limit: daily-limit,
                    current-count: new-count,
                    last-reset: new-last-reset,
                })
            )
            true
        )
        (try! (stx-transfer? visa-fee tx-sender contract-owner))
        (map-set VisaApplications tx-sender {
            status: "PENDING",
            application-time: current-time,
            expiry: (+ current-time u5200),
            passport-hash: passport-hash,
            photo-hash: photo-hash,
            destination: destination,
            purpose: purpose,
            renewals: u0,
            extensions-used: u0,
            last-extension-time: none,
            refund-claimed: false,
            paid-amount: visa-fee,
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

(define-read-only (check-renewal-eligibility (applicant principal))
    (match (map-get? VisaApplications applicant)
        visa-data (let (
                (current-time burn-block-height)
                (visa-expiry (get expiry visa-data))
                (visa-status (get status visa-data))
            )
            (and
                (is-eq visa-status "APPROVED")
                (>= (- visa-expiry current-time) renewal-window)
                (<= (get renewals visa-data) u2)
            )
        )
        false
    )
)

(define-public (renew-visa)
    (let ((current-time burn-block-height))
        (asserts! (not (check-blacklist tx-sender)) (err u12))
        (asserts! (check-renewal-eligibility tx-sender) (err u13))
        (try! (stx-transfer? renewal-fee tx-sender contract-owner))
        (match (map-get? VisaApplications tx-sender)
            visa-data (begin
                (map-set VisaApplications tx-sender
                    (merge visa-data {
                        expiry: (+ (get expiry visa-data) u5200),
                        renewals: (+ (get renewals visa-data) u1),
                    })
                )
                (ok true)
            )
            (err u14)
        )
    )
)

(define-public (record-entry
        (traveler principal)
        (destination-country (string-ascii 2))
        (entry-point (string-ascii 50))
    )
    (let (
            (current-time burn-block-height)
            (entry-id (var-get next-entry-id))
        )
        (asserts! (is-eq tx-sender (var-get admin)) (err u15))
        (match (get-visa-status traveler)
            visa-data (begin
                (asserts! (is-eq (get status visa-data) "APPROVED") (err u16))
                (asserts! (>= (get expiry visa-data) current-time) (err u17))
                (map-set TravelHistory {
                    traveler: traveler,
                    entry-id: entry-id,
                } {
                    destination-country: destination-country,
                    entry-timestamp: current-time,
                    exit-timestamp: none,
                    entry-point: entry-point,
                    exit-point: none,
                    compliance-status: "ACTIVE",
                })
                (var-set next-entry-id (+ entry-id u1))
                (ok entry-id)
            )
            (err u18)
        )
    )
)

(define-public (record-exit
        (traveler principal)
        (entry-id uint)
        (exit-point (string-ascii 50))
        (compliance-status (string-ascii 10))
    )
    (let ((current-time burn-block-height))
        (asserts! (is-eq tx-sender (var-get admin)) (err u19))
        (match (get-travel-record traveler entry-id)
            travel-data (begin
                (asserts! (is-none (get exit-timestamp travel-data)) (err u20))
                (map-set TravelHistory {
                    traveler: traveler,
                    entry-id: entry-id,
                }
                    (merge travel-data {
                        exit-timestamp: (some current-time),
                        exit-point: (some exit-point),
                        compliance-status: compliance-status,
                    })
                )
                (ok true)
            )
            (err u21)
        )
    )
)

(define-read-only (check-extension-eligibility
        (applicant principal)
        (extension-type (string-ascii 10))
    )
    (match (map-get? VisaApplications applicant)
        visa-data (let (
                (current-time burn-block-height)
                (visa-expiry (get expiry visa-data))
                (visa-status (get status visa-data))
                (extensions-count (get extensions-used visa-data))
                (last-extension (get last-extension-time visa-data))
            )
            (and
                (is-eq visa-status "APPROVED")
                (>= visa-expiry current-time)
                (< extensions-count u3)
                (match last-extension
                    some-time (>= (- current-time some-time) u1440)
                    true
                )
                (or
                    (is-eq extension-type "emergency")
                    (is-eq extension-type "medical")
                    (is-eq extension-type "business")
                )
            )
        )
        false
    )
)

(define-public (request-visa-extension
        (extension-type (string-ascii 10))
        (justification (string-ascii 200))
        (extension-days uint)
    )
    (let (
            (current-time burn-block-height)
            (extension-fee (if (is-eq extension-type "emergency")
                extension-fee-emergency
                (if (is-eq extension-type "medical")
                    extension-fee-medical
                    (if (is-eq extension-type "business")
                        extension-fee-business
                        u0
                    )
                )
            ))
        )
        (asserts! (not (check-blacklist tx-sender)) (err u22))
        (asserts! (check-extension-eligibility tx-sender extension-type)
            (err u23)
        )
        (asserts! (<= extension-days max-extension-days) (err u24))
        (asserts! (> extension-days u0) (err u25))
        (asserts! (> extension-fee u0) (err u26))
        (try! (stx-transfer? extension-fee tx-sender contract-owner))
        (match (map-get? VisaApplications tx-sender)
            visa-data (begin
                (map-set VisaApplications tx-sender
                    (merge visa-data {
                        expiry: (+ (get expiry visa-data) extension-days),
                        extensions-used: (+ (get extensions-used visa-data) u1),
                        last-extension-time: (some current-time),
                    })
                )
                (ok true)
            )
            (err u27)
        )
    )
)

(define-read-only (get-extension-fee (extension-type (string-ascii 10)))
    (if (is-eq extension-type "emergency")
        extension-fee-emergency
        (if (is-eq extension-type "medical")
            extension-fee-medical
            (if (is-eq extension-type "business")
                extension-fee-business
                u0
            )
        )
    )
)

(define-read-only (get-remaining-extension-count (applicant principal))
    (match (map-get? VisaApplications applicant)
        visa-data (- u3 (get extensions-used visa-data))
        u0
    )
)

(define-read-only (calculate-refund-amount (applicant principal))
    (match (map-get? VisaApplications applicant)
        visa-data (let (
                (current-time burn-block-height)
                (app-time (get application-time visa-data))
                (time-elapsed (- current-time app-time))
                (paid (get paid-amount visa-data))
                (status (get status visa-data))
                (refund-rate (if (<= time-elapsed early-rejection-window)
                    refund-rate-early
                    (if (<= time-elapsed standard-rejection-window)
                        refund-rate-standard
                        refund-rate-late
                    )
                ))
            )
            (if (is-eq status "REJECTED")
                (/ (* paid refund-rate) u100)
                u0
            )
        )
        u0
    )
)

(define-read-only (is-refund-eligible (applicant principal))
    (match (map-get? VisaApplications applicant)
        visa-data (let (
                (status (get status visa-data))
                (already-claimed (get refund-claimed visa-data))
            )
            (and
                (is-eq status "REJECTED")
                (not already-claimed)
            )
        )
        false
    )
)

(define-public (claim-refund)
    (let ((refund-amount (calculate-refund-amount tx-sender)))
        (asserts! (is-refund-eligible tx-sender) (err u28))
        (asserts! (> refund-amount u0) (err u29))
        (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
        (match (map-get? VisaApplications tx-sender)
            visa-data (begin
                (map-set VisaApplications tx-sender
                    (merge visa-data { refund-claimed: true })
                )
                (var-set total-refunds-issued
                    (+ (var-get total-refunds-issued) refund-amount)
                )
                (ok refund-amount)
            )
            (err u30)
        )
    )
)

(define-public (reject-visa-with-reason
        (applicant principal)
        (reason (string-ascii 100))
    )
    (let ((current-time burn-block-height))
        (asserts! (is-eq tx-sender (var-get admin)) (err u31))
        (match (map-get? VisaApplications applicant)
            visa-data (begin
                (map-set VisaApplications applicant
                    (merge visa-data { status: "REJECTED" })
                )
                (ok true)
            )
            (err u32)
        )
    )
)

(define-read-only (get-total-refunds-issued)
    (var-get total-refunds-issued)
)

(define-read-only (get-refund-status (applicant principal))
    (match (map-get? VisaApplications applicant)
        visa-data
        {
            eligible: (is-refund-eligible applicant),
            amount: (calculate-refund-amount applicant),
            claimed: (get refund-claimed visa-data),
        }
        {
            eligible: false,
            amount: u0,
            claimed: false,
        }
    )
)
