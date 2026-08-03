import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {AuditEvent} from "./audit_types";

export async function writeAuditEvent(event: AuditEvent): Promise<boolean> {
  const reference = getFirestore()
    .collection("companies").doc(event.companyId)
    .collection("audit_events").doc(event.eventId);
  try {
    const created = await getFirestore().runTransaction(async (transaction) => {
      const existing = await transaction.get(reference);
      if (existing.exists) return false;
      transaction.create(reference, event);
      return true;
    });
    logger.info("business_audit_write", {
      sourceEventId: event.sourceEventId,
      auditEventId: event.eventId,
      operationId: event.operationId,
      entityPath: event.entityPath,
      action: event.action,
      result: created ? "success" : "duplicate",
    });
    return created;
  } catch (error) {
    logger.error("business_audit_write_failed", {
      sourceEventId: event.sourceEventId,
      auditEventId: event.eventId,
      operationId: event.operationId,
      entityPath: event.entityPath,
      action: event.action,
      result: "failure",
      errorName: error instanceof Error ? error.name : "unknown",
      errorMessage: error instanceof Error ? error.message.slice(0, 500) : "unknown",
    });
    throw error;
  }
}
