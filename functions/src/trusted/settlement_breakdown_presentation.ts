import {HttpsError} from "firebase-functions/v2/https";
import {compare, freeze} from "./settlement_preflight_shared";
import {sumUnits} from "./exact_decimal";
import {settlementInventoryEvidenceDigest as digest} from "./settlement_pending_evidence";
import {SettlementCashBreakdown} from "./settlement_breakdown";
import {CashEvidenceRow} from "./settlement_source_evidence";

export const SETTLEMENT_DETAIL_PAGE_SIZE = 64;

/** Pure view of an ALREADY authorized report; never a database/auth endpoint.
 * Both roots are mandatory so unchanged economics cannot mix two snapshots.
 * Observed blocked history may be shown, always with null financial totals. */
export function settlementBreakdownDetailPage(report: SettlementCashBreakdown, request: {
  evidenceDigest: string; snapshotDigest: string; pageIndex: number;
}) {
  if (!("movements" in report)) throw new HttpsError("failed-precondition", "Incomplete inventory cannot produce settlement detail pages.");
  return detailPage(report, request, new Map(report.movements.map(row => [row.id, row])));
}

/** Construct all bounded pages with one index, rather than indexing the entire
 * immutable movement history again for every 64-row page. */
export function settlementBreakdownDetailPages(report: SettlementCashBreakdown) {
  if (!("movements" in report)) throw new HttpsError("failed-precondition", "Incomplete inventory cannot produce settlement detail pages.");
  const byId = new Map(report.movements.map(row => [row.id, row]));
  return Array.from({length: Math.max(1, Math.ceil(report.cutoffMovementIds.length / SETTLEMENT_DETAIL_PAGE_SIZE))}, (_, pageIndex) =>
    detailPage(report, {pageIndex, evidenceDigest: report.evidenceDigest, snapshotDigest: report.snapshotCoverage.digest}, byId));
}

function detailPage(report: SettlementCashBreakdown, request: {evidenceDigest: string; snapshotDigest: string; pageIndex: number},
  byId: ReadonlyMap<string, CashEvidenceRow>) {
  if (!report.snapshotCoverage.complete || !("movements" in report))
    throw new HttpsError("failed-precondition", "Incomplete inventory cannot produce settlement detail pages.");
  if (request.evidenceDigest !== report.evidenceDigest || request.snapshotDigest !== report.snapshotCoverage.digest)
    throw new HttpsError("failed-precondition", "Settlement detail request belongs to another report/snapshot.");
  const ids = report.cutoffMovementIds, pageCount = Math.max(1, Math.ceil(ids.length / SETTLEMENT_DETAIL_PAGE_SIZE));
  if (!Number.isInteger(request.pageIndex) || request.pageIndex < 0 || request.pageIndex >= pageCount)
    throw new HttpsError("invalid-argument", "Valid settlement detail page index required.");
  const offset = request.pageIndex * SETTLEMENT_DETAIL_PAGE_SIZE;
  const rows = ids.slice(offset, offset + SETTLEMENT_DETAIL_PAGE_SIZE).map(id => {
    const row = byId.get(id);if (!row) throw new HttpsError("data-loss", "Verified detail movement is missing.");return row;
  });
  const page = {schemaVersion: 1 as const, companyId: report.companyId, salesRepId: report.salesRepId, settlementId: report.settlementId,
    evidenceDigest: report.evidenceDigest, snapshotDigest: report.snapshotCoverage.digest, cutoff: report.cutoff,
    status: report.status, currency: report.currency, moneyScale: report.moneyScale, opening: report.opening, carry: report.carry, totals: report.totals,
    issues: report.issues, issueCount: report.issueCount, detailScope: "through_cutoff" as const, order: "sdk_commit" as const,
    rowCount: ids.length, pageSize: SETTLEMENT_DETAIL_PAGE_SIZE, pageCount, pageIndex: request.pageIndex, offset,
    nextPageIndex: request.pageIndex + 1 < pageCount ? request.pageIndex + 1 : null, rows};
  return freeze({...page, pageDigest: pageDigest(page)});
}
export type SettlementBreakdownDetailPage = ReturnType<typeof settlementBreakdownDetailPage>;

/** Screen/PDF consumers must assemble a complete sequence, not label the first
 * rendered page a complete settlement. This checks DTO integrity, not authority
 * or a cryptographic signature; only the original adapter authorizes access. */
export function verifySettlementBreakdownDetailPages(pages: readonly SettlementBreakdownDetailPage[]) {
  const first = pages[0];
  const need = (ok: boolean, message: string) => {if (!ok) throw new HttpsError("data-loss", message);};
  need(Boolean(first) && pages.length <= 256, "Bounded complete settlement detail sequence required.");
  need(first.rowCount >= 0 && first.rowCount <= 16000 && first.pageSize === SETTLEMENT_DETAIL_PAGE_SIZE &&
    first.pageCount === Math.max(1, Math.ceil(first.rowCount / SETTLEMENT_DETAIL_PAGE_SIZE)) && pages.length === first.pageCount,
  "Settlement detail pages are incomplete.");
  const rootHeader = (p: SettlementBreakdownDetailPage) => {
    const {pageIndex, offset, nextPageIndex, rows, pageDigest: checksum, ...header} = p;return digest(header);
  };
  const headerDigest = rootHeader(first), seen = new Set<string>(), rows: SettlementBreakdownDetailPage["rows"] = [];
  for (const [index, page] of pages.entries()) {
    need(rootHeader(page) === headerDigest && page.pageIndex === index && page.offset === index * SETTLEMENT_DETAIL_PAGE_SIZE,
      "Settlement detail pages mix reports, snapshots or ordering.");
    need(page.nextPageIndex === (index + 1 < pages.length ? index + 1 : null) && page.pageDigest === pageDigest(page), "Settlement detail page digest/continuation differs.");
    need(page.rows.length === Math.min(SETTLEMENT_DETAIL_PAGE_SIZE, first.rowCount - page.offset), "Settlement detail rows are missing.");
    for (const row of page.rows) {
      need(!seen.has(row.id) && row.holderUid === first.salesRepId && row.cashAccount === "rep_cash" && row.path.startsWith(`companies/${first.companyId}/cash_movements/`), "Duplicate or wrong-holder settlement detail row.");
      need(compare(row.committedAt, first.cutoff.inclusiveThrough) <= 0, "Settlement detail row exceeds cutoff.");
      const previous = rows.at(-1);
      if (previous) need(compare(previous.committedAt, row.committedAt) <= (first.status === "blocked" ? 0 : -1), "Settlement detail commit ordering differs.");
      seen.add(row.id);rows.push(row);
    }
  }
  need(rows.length === first.rowCount && (first.status === "blocked" ? first.totals === null : first.totals !== null), "Settlement detail coverage/status differs.");
  if (first.totals) need(sumUnits(rows.map(r => BigInt(r.signedUnits))).toString() === first.totals.remainingUnits, "Settlement detail cash does not reconcile with verified remaining balance.");
  return freeze({companyId: first.companyId, salesRepId: first.salesRepId, settlementId: first.settlementId,
    evidenceDigest: first.evidenceDigest, snapshotDigest: first.snapshotDigest, status: first.status, totals: first.totals,
    currency: first.currency, moneyScale: first.moneyScale, cutoff: first.cutoff, order: first.order, completeDetailSequence: true as const,
    opening: first.opening, carry: first.carry, issues: first.issues, issueCount: first.issueCount, detailScope: first.detailScope, rows});
}
function pageDigest(page: {rows: readonly unknown[]} & Record<string, unknown>): string {
  const {rows, ...header} = page, normalized = {...header} as Record<string, unknown>;delete normalized.pageDigest;
  return digest({...normalized, rowDigests: rows.map(digest)});
}
