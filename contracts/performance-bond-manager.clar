;; Performance Bond Manager Smart Contract
;; Issues and manages digital performance bonds for construction projects

;; Constants for contract administration
(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-invalid-date (err u105))
(define-constant err-milestone-limit (err u106))
(define-constant err-already-claimed (err u107))
(define-constant err-bond-expired (err u108))

;; Bond status constants
(define-constant bond-active u1)
(define-constant bond-completed u2)
(define-constant bond-claimed u3)
(define-constant bond-cancelled u4)
(define-constant bond-defaulted u5)

;; Milestone status constants
(define-constant milestone-pending u1)
(define-constant milestone-in-review u2)
(define-constant milestone-completed u3)
(define-constant milestone-rejected u4)

;; Claim status constants
(define-constant claim-filed u1)
(define-constant claim-under-review u2)
(define-constant claim-approved u3)
(define-constant claim-rejected u4)

;; Maximum milestones per bond
(define-constant max-milestones-per-bond u50)

;; Data variables for tracking IDs and statistics
(define-data-var bond-id-nonce uint u0)
(define-data-var milestone-id-nonce uint u0)
(define-data-var claim-id-nonce uint u0)
(define-data-var total-bonds uint u0)
(define-data-var total-bond-value uint u0)
(define-data-var total-completed uint u0)
(define-data-var total-claimed uint u0)
(define-data-var total-milestones uint u0)

;; Performance bonds registry
(define-map bonds
  { bond-id: uint }
  {
    contractor: principal,
    project-owner: principal,
    surety: (optional principal),
    bond-amount: uint,
    project-name: (string-ascii 100),
    project-description: (string-ascii 200),
    status: uint,
    issued-at: uint,
    completion-date: uint,
    milestone-count: uint
  }
)

;; Project milestones
(define-map milestones
  { milestone-id: uint }
  {
    bond-id: uint,
    description: (string-ascii 200),
    payment-amount: uint,
    status: uint,
    target-date: uint,
    completed-at: uint,
    verifier: (optional principal)
  }
)

;; Bond collateral tracking
(define-map bond-collateral
  { bond-id: uint }
  {
    amount: uint,
    deposited: bool,
    released: bool
  }
)

;; Claims registry
(define-map claims
  { claim-id: uint }
  {
    bond-id: uint,
    claimant: principal,
    amount: uint,
    reason: (string-ascii 200),
    status: uint,
    filed-at: uint,
    resolved-at: uint
  }
)

;; Contractor bonds tracking
(define-map contractor-bonds
  { contractor: principal, index: uint }
  { bond-id: uint }
)

(define-map contractor-bond-count
  { contractor: principal }
  { count: uint }
)

;; Owner bonds tracking
(define-map owner-bonds
  { owner: principal, index: uint }
  { bond-id: uint }
)

(define-map owner-bond-count
  { owner: principal }
  { count: uint }
)

;; Bond-specific milestone tracking
(define-map bond-milestones
  { bond-id: uint, milestone-index: uint }
  { milestone-id: uint }
)

;; Bond-specific claim tracking
(define-map bond-claims
  { bond-id: uint, claim-index: uint }
  { claim-id: uint }
)

(define-map bond-claim-count
  { bond-id: uint }
  { count: uint }
)

;; Contractor statistics
(define-map contractor-stats
  { contractor: principal }
  {
    total-bonds: uint,
    completed-bonds: uint,
    defaulted-bonds: uint,
    total-value: uint
  }
)

;; Private helper functions
(define-private (get-next-bond-id)
  (let ((current-id (var-get bond-id-nonce)))
    (var-set bond-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (get-next-milestone-id)
  (let ((current-id (var-get milestone-id-nonce)))
    (var-set milestone-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (get-next-claim-id)
  (let ((current-id (var-get claim-id-nonce)))
    (var-set claim-id-nonce (+ current-id u1))
    current-id
  )
)

(define-private (is-bond-expired (completion-date uint))
  (> stacks-block-height completion-date)
)

;; Public functions

;; Issue a performance bond
(define-public (issue-bond
  (project-owner principal)
  (bond-amount uint)
  (project-name (string-ascii 100))
  (project-description (string-ascii 200))
  (completion-date uint)
  (surety (optional principal)))
  (let
    (
      (bond-id (get-next-bond-id))
      (contractor-count (default-to { count: u0 } (map-get? contractor-bond-count { contractor: tx-sender })))
      (owner-count (default-to { count: u0 } (map-get? owner-bond-count { owner: project-owner })))
      (contractor-data (default-to
        { total-bonds: u0, completed-bonds: u0, defaulted-bonds: u0, total-value: u0 }
        (map-get? contractor-stats { contractor: tx-sender })
      ))
    )
    (asserts! (> bond-amount u0) err-invalid-status)
    (asserts! (> completion-date stacks-block-height) err-invalid-date)
    (try! (stx-transfer? bond-amount tx-sender (as-contract tx-sender)))
    (map-set bonds
      { bond-id: bond-id }
      {
        contractor: tx-sender,
        project-owner: project-owner,
        surety: surety,
        bond-amount: bond-amount,
        project-name: project-name,
        project-description: project-description,
        status: bond-active,
        issued-at: stacks-block-height,
        completion-date: completion-date,
        milestone-count: u0
      }
    )
    (map-set bond-collateral
      { bond-id: bond-id }
      { amount: bond-amount, deposited: true, released: false }
    )
    (map-set contractor-bonds
      { contractor: tx-sender, index: (get count contractor-count) }
      { bond-id: bond-id }
    )
    (map-set contractor-bond-count
      { contractor: tx-sender }
      { count: (+ (get count contractor-count) u1) }
    )
    (map-set owner-bonds
      { owner: project-owner, index: (get count owner-count) }
      { bond-id: bond-id }
    )
    (map-set owner-bond-count
      { owner: project-owner }
      { count: (+ (get count owner-count) u1) }
    )
    (map-set contractor-stats
      { contractor: tx-sender }
      {
        total-bonds: (+ (get total-bonds contractor-data) u1),
        completed-bonds: (get completed-bonds contractor-data),
        defaulted-bonds: (get defaulted-bonds contractor-data),
        total-value: (+ (get total-value contractor-data) bond-amount)
      }
    )
    (var-set total-bonds (+ (var-get total-bonds) u1))
    (var-set total-bond-value (+ (var-get total-bond-value) bond-amount))
    (ok bond-id)
  )
)

;; Create a project milestone
(define-public (create-milestone
  (bond-id uint)
  (description (string-ascii 200))
  (payment-amount uint)
  (target-date uint))
  (let
    (
      (bond (unwrap! (map-get? bonds { bond-id: bond-id }) err-not-found))
      (milestone-id (get-next-milestone-id))
      (current-milestone-count (get milestone-count bond))
    )
    (asserts! (is-eq tx-sender (get project-owner bond)) err-unauthorized)
    (asserts! (< current-milestone-count max-milestones-per-bond) err-milestone-limit)
    (map-set milestones
      { milestone-id: milestone-id }
      {
        bond-id: bond-id,
        description: description,
        payment-amount: payment-amount,
        status: milestone-pending,
        target-date: target-date,
        completed-at: u0,
        verifier: none
      }
    )
    (map-set bond-milestones
      { bond-id: bond-id, milestone-index: current-milestone-count }
      { milestone-id: milestone-id }
    )
    (map-set bonds
      { bond-id: bond-id }
      (merge bond { milestone-count: (+ current-milestone-count u1) })
    )
    (var-set total-milestones (+ (var-get total-milestones) u1))
    (ok milestone-id)
  )
)

;; Complete a milestone
(define-public (complete-milestone (milestone-id uint))
  (let
    (
      (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) err-not-found))
      (bond (unwrap! (map-get? bonds { bond-id: (get bond-id milestone) }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get project-owner bond)) err-unauthorized)
    (asserts! (is-eq (get status milestone) milestone-pending) err-invalid-status)
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone
        {
          status: milestone-completed,
          completed-at: stacks-block-height,
          verifier: (some tx-sender)
        }
      )
    )
    (try! (as-contract (stx-transfer? (get payment-amount milestone) tx-sender (get contractor bond))))
    (ok true)
  )
)

;; Complete bond and release collateral
(define-public (complete-bond (bond-id uint))
  (let
    (
      (bond (unwrap! (map-get? bonds { bond-id: bond-id }) err-not-found))
      (collateral (unwrap! (map-get? bond-collateral { bond-id: bond-id }) err-not-found))
      (contractor-data (default-to
        { total-bonds: u0, completed-bonds: u0, defaulted-bonds: u0, total-value: u0 }
        (map-get? contractor-stats { contractor: (get contractor bond) })
      ))
    )
    (asserts! (is-eq tx-sender (get project-owner bond)) err-unauthorized)
    (asserts! (is-eq (get status bond) bond-active) err-invalid-status)
    (asserts! (not (get released collateral)) err-invalid-status)
    (try! (as-contract (stx-transfer? (get amount collateral) tx-sender (get contractor bond))))
    (map-set bonds
      { bond-id: bond-id }
      (merge bond { status: bond-completed })
    )
    (map-set bond-collateral
      { bond-id: bond-id }
      (merge collateral { released: true })
    )
    (map-set contractor-stats
      { contractor: (get contractor bond) }
      (merge contractor-data
        { completed-bonds: (+ (get completed-bonds contractor-data) u1) }
      )
    )
    (var-set total-completed (+ (var-get total-completed) u1))
    (ok true)
  )
)

;; File a claim against a bond
(define-public (file-claim
  (bond-id uint)
  (amount uint)
  (reason (string-ascii 200)))
  (let
    (
      (bond (unwrap! (map-get? bonds { bond-id: bond-id }) err-not-found))
      (claim-id (get-next-claim-id))
      (bond-claim-data (default-to { count: u0 } (map-get? bond-claim-count { bond-id: bond-id })))
    )
    (asserts! (is-eq tx-sender (get project-owner bond)) err-unauthorized)
    (asserts! (<= amount (get bond-amount bond)) err-insufficient-funds)
    (map-set claims
      { claim-id: claim-id }
      {
        bond-id: bond-id,
        claimant: tx-sender,
        amount: amount,
        reason: reason,
        status: claim-filed,
        filed-at: stacks-block-height,
        resolved-at: u0
      }
    )
    (map-set bond-claims
      { bond-id: bond-id, claim-index: (get count bond-claim-data) }
      { claim-id: claim-id }
    )
    (map-set bond-claim-count
      { bond-id: bond-id }
      { count: (+ (get count bond-claim-data) u1) }
    )
    (ok claim-id)
  )
)

;; Approve a claim
(define-public (approve-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-not-found))
      (bond (unwrap! (map-get? bonds { bond-id: (get bond-id claim) }) err-not-found))
      (collateral (unwrap! (map-get? bond-collateral { bond-id: (get bond-id claim) }) err-not-found))
      (contractor-data (default-to
        { total-bonds: u0, completed-bonds: u0, defaulted-bonds: u0, total-value: u0 }
        (map-get? contractor-stats { contractor: (get contractor bond) })
      ))
    )
    (asserts! (is-eq (get status claim) claim-filed) err-already-claimed)
    (asserts! (not (get released collateral)) err-invalid-status)
    (try! (as-contract (stx-transfer? (get amount claim) tx-sender (get claimant claim))))
    (map-set claims
      { claim-id: claim-id }
      (merge claim
        {
          status: claim-approved,
          resolved-at: stacks-block-height
        }
      )
    )
    (map-set bonds
      { bond-id: (get bond-id claim) }
      (merge bond { status: bond-claimed })
    )
    (map-set bond-collateral
      { bond-id: (get bond-id claim) }
      (merge collateral { released: true })
    )
    (map-set contractor-stats
      { contractor: (get contractor bond) }
      (merge contractor-data
        { defaulted-bonds: (+ (get defaulted-bonds contractor-data) u1) }
      )
    )
    (var-set total-claimed (+ (var-get total-claimed) u1))
    (ok true)
  )
)

;; Cancel a bond (only if no milestones completed)
(define-public (cancel-bond (bond-id uint))
  (let
    (
      (bond (unwrap! (map-get? bonds { bond-id: bond-id }) err-not-found))
      (collateral (unwrap! (map-get? bond-collateral { bond-id: bond-id }) err-not-found))
    )
    (asserts!
      (or
        (is-eq tx-sender (get contractor bond))
        (is-eq tx-sender (get project-owner bond))
      )
      err-unauthorized
    )
    (asserts! (is-eq (get status bond) bond-active) err-invalid-status)
    (asserts! (is-eq (get milestone-count bond) u0) err-invalid-status)
    (try! (as-contract (stx-transfer? (get amount collateral) tx-sender (get contractor bond))))
    (map-set bonds
      { bond-id: bond-id }
      (merge bond { status: bond-cancelled })
    )
    (map-set bond-collateral
      { bond-id: bond-id }
      (merge collateral { released: true })
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-bond (bond-id uint))
  (map-get? bonds { bond-id: bond-id })
)

(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-bond-collateral (bond-id uint))
  (map-get? bond-collateral { bond-id: bond-id })
)

(define-read-only (get-contractor-bond (contractor principal) (index uint))
  (map-get? contractor-bonds { contractor: contractor, index: index })
)

(define-read-only (get-owner-bond (owner principal) (index uint))
  (map-get? owner-bonds { owner: owner, index: index })
)

(define-read-only (get-bond-milestone (bond-id uint) (milestone-index uint))
  (map-get? bond-milestones { bond-id: bond-id, milestone-index: milestone-index })
)

(define-read-only (get-bond-claim (bond-id uint) (claim-index uint))
  (map-get? bond-claims { bond-id: bond-id, claim-index: claim-index })
)

(define-read-only (get-contractor-stats (contractor principal))
  (map-get? contractor-stats { contractor: contractor })
)

(define-read-only (get-contractor-bond-count (contractor principal))
  (default-to { count: u0 } (map-get? contractor-bond-count { contractor: contractor }))
)

(define-read-only (get-platform-stats)
  {
    total-bonds: (var-get total-bonds),
    total-value: (var-get total-bond-value),
    total-completed: (var-get total-completed),
    total-claimed: (var-get total-claimed),
    total-milestones: (var-get total-milestones)
  }
)
