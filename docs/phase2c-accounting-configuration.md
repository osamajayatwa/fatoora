# Phase 2C — Book and account configuration

2026-11-10, Asia/Amman. Local implementation of the first accounting-foundation
subphase requested by the owner. No deployment, remote configuration, financial
posting, opening balances, import or active-book switch is part of this change.

## Foundation delivery sequence

| Subphase | Deliverable | State |
|---|---|---|
| 2C | Book/currency/scales, chart, mappings, fiscal periods, tax evidence and opening-boundary draft | Implemented locally; policy confirmation and deployment remain pending |
| 2D | Reusable exact atomic posting engine; settlement as the first integrated example | [Implemented locally](phase2d-atomic-posting-engine.md); synthetic emulator acceptance only |
| 2E | Customer open items/allocations, treasury and quantity-only inventory controls | [Implemented locally](phase2e-subledger-treasury-quantity-controls.md); synthetic emulator acceptance only |
| 2F | Linked corrections/reversals and period close/reopen | Pending |
| 2G | Minimal GL/TB reads, reconciliations and integrated foundation acceptance | Pending |

Phase 3 remains the broader existing-workflow/UI integration; Phase 4 is the
historical importer/reconciler. Phase 2C does not certify either phase.

## Backend contract

`manageAccountingConfiguration` is one trusted callable with `read` and `save`
actions. It is default-off unless the server process explicitly has
`FATOORA_ACCOUNTING_CONFIGURATION_ENABLED=true`. It uses `requireCallableUid`
and the existing `requireTrustedUser` resolver; no additional role resolver or
client financial writer was introduced. Every transaction requires a current,
active, approved company administrator and a correctly scoped active company.
Company/book references are explicit; there is no default-company fallback.

Read accepts `action`, `companyId`, `bookId`. A missing book returns revision 0
with null configuration/readiness and creates nothing. Save also accepts a full
`configuration`, `expectedRevision` and actor-scoped `requestId`. Unknown fields
are rejected, including attempts to supply approval, posting or activation flags.

The save transaction reads authorization, company/book, previous immutable
configuration, request identity, maintenance lock and all affected accounts,
reserved codes and periods before its first write. It writes atomically:

- An inactive configuration-mode book, with all journal/settlement posting gates
  false, and an optimistic configuration revision/digest.
- An immutable `configuration_revisions/revision_N` snapshot, unreviewed
  `policy_revisions/revision_N` and `account_mappings/revision_N`.
- Current `chart_accounts`, permanent `account_codes` reservations and draft
  `periods`, serialized through the same book revision.
- An immutable audit event with previous/new digests and an actor-scoped
  `configuration_requests` receipt containing the original result.

Identical retries return the committed result after current authorization;
conflicting request reuse rejects. Concurrent different saves against one
revision have one winner. Used targets, selected/active books, live/enabled books,
unknown book contracts and maintenance locks block new saves. Existing account
and period IDs must remain in later drafts; accounts can be deactivated.
Reserved account codes are never reassigned to another account.

The draft contract explicitly supplies currency, independent money/quantity/price
scales, a fiscal-year boundary and Asia/Amman dates. No company currency, account
codes or tax rate is preselected. Accounts require unique normalized codes,
valid same-type group parents, acyclic hierarchy and valid control types.
Mappings require active posting accounts of the correct type/control. Company
and representative cash controls are distinct; customers/representatives remain
dimensions of control accounts.

Periods use logical local dates `[startsOn, endsBefore)`, reject invalid dates,
overlap and fiscal-year crossings. Date-to-instant conversion belongs to the
posting adapter in 2D; draft dates are never treated as UTC posting timestamps.
Tax-code revisions use exact decimal percentage strings with at most six decimal
places, evidenced output-tax accounts and nonoverlapping ranges per code.
Documented tax/opening evidence requires references. No referenced evidence is
automatically verified or approved by this command.

Limits: 80 accounts, 36 periods, 80 tax-code revisions, 20 opening references,
192 KiB input configuration. At maximum account/period counts, a new-book save
has 202 writes and 201 document reads including authorization (202 reads when
an existing revision is loaded). The retained
request/configuration payloads and policy evidence have index exemptions in the
local index manifest. These limits bound configuration work; they do not prove
posting throughput or cloud billing behavior.

## Readiness and approval boundary

`configurationComplete` means the required settings/evidence descriptions are
present. Missing account mappings, equity account, periods, tax policy, opening
coverage/cutover and retained-earnings treatment are individually reported.
Incomplete drafts may be saved; inconsistent values are rejected.

Every returned readiness result still has `approvalStatus=unreviewed` and
`postingEnabled=false`. Owner/accountant confirmation, actual opening
reconciliation and posting-engine acceptance remain explicit activation blockers.
There is no approval or activation command in 2C. The company active-book pointer,
legacy currency bindings, cash/stock positions and existing business writers are
untouched. This draft does not satisfy the old settlement preflight's approved
configuration contract or reopen the Phase 2B-15 staging activation gate.

Inventory remains `quantity_only`, with `costCoverage=not_recorded`. No amounts
or quantities are accepted in the opening contract. Unknown financial/quantity
coverage stays unknown; no zero balance, opening-equity plug, inventory valuation
or profit is inferred.

## UI integration

The existing Financial Settings area gains Accounting setup at
`/settings/financial/accounting-configuration`, behind the client build flag
`FATOORA_ACCOUNTING_CONFIGURATION=true` (default false), existing approved-user
and admin middleware, and the settings scaffold's administrator guard.
`SettingsRepository` uses the existing authenticated callable transport and
business-user context; no direct Firestore reads/writes were added. The page's
company is pinned across retries and checked against current authority, so a
changed sign-in cannot redirect an old draft into a different company.

The form opens an explicitly identified draft, edits accounts/group hierarchy,
mappings, periods, dated tax codes, policy evidence and opening references, and
shows the server's saved revision/readiness. English/Arabic labels and RTL/LTR
are included. The DTO rejects cross-scope/enabled/approved/malformed responses
and retains an immutable copy. Saving uses `PendingPostingKeys`, preserving
request identity through unconfirmed responses. Editing is disabled while an
unconfirmed save is retried with the same payload/revision. Conflicts preserve
the draft and require reload; reload asks before discarding unsaved edits.

## Verification

The test fixture is synthetic and is not loaded by application code. Backend
contract and emulator tests cover validation, exact tax strings, account/code
integrity, current authorization, concurrency, retries, interruption/atomicity,
used/active-book guards and default-off callable behavior. Existing Firestore
Rules deny client reads/lists/creates/updates/deletes for all new paths; the
existing denial test now includes these configuration collections. Flutter
tests cover DTO scope/immutability, translations, narrow English/Arabic layouts
at 2x text, revision conflicts, unconfirmed-save retries and account dialogs.

Results: 68 focused backend tests passed; the existing financial-ledger,
settlement persistence and preflight regression suites passed. The extended
Rules denial test passed. The focused Flutter/settings/retry batch passed 27
tests, and full Flutter analysis passed with no issues. These are local results
using synthetic evidence, not live accounting acceptance.

Commands (isolated loopback emulator only for backend transaction/Rules tests):

```text
npm --prefix functions run test:accounting-configuration
flutter test --no-pub test/accounting_configuration_test.dart test/settings_menu_sections_test.dart test/business_settings_defaults_test.dart test/pending_posting_keys_test.dart
flutter analyze --no-pub
```

Live configuration, real policy approval, positive cloud/native acceptance and
production deployment have not been performed. They are separate from local
Phase 2C implementation acceptance.
