import {DocumentData, FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {TRUSTED_CALLABLE_OPTIONS, businessPath, optionalString, record, requireCallableUid,
  requireTrustedUser, requiredIdempotencyKey, requiredString} from "./common";

// Only versioned assignment is authoritative. Older unused assignment-like
// fields must never silently change the creator-based legacy access policy.
export function customerAssigneeUid(customer: DocumentData): string {
  return customer.assignmentVersion === 1 ?
    optionalString(customer.assignedToUid) : optionalString(customer.createdByUid);
}
export function customerAssignedTo(customer: DocumentData, uid: string): boolean {
  return customerAssigneeUid(customer) === uid;
}
export function initialCustomerAssignment(uid: string, name: string, role: string): DocumentData {
  return {assignedToUid: uid, assignedToName: name, assignedToRole: role,
    assignmentVersion: 1, assignmentRevision: 0};
}

export const reassignCustomer = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "reassignCustomer");
  return reassignCustomerTransaction(getFirestore(), uid, record(request.data));
});

export async function reassignCustomerTransaction(firestore: Firestore, uid: string | undefined, input: DocumentData) {
  const companyId = requiredString(input.companyId, "companyId");
  const customerId = requiredString(input.customerId, "customerId");
  const targetUid = requiredString(input.assignedToUid, "assignedToUid");
  const key = requiredIdempotencyKey(input.idempotencyKey);
  const reason = requiredString(input.reason, "reason");
  const expectedUid = requiredString(input.expectedAssignedToUid, "expectedAssignedToUid");
  const expectedRevision = input.expectedAssignmentRevision;
  if ([companyId, customerId, targetUid, expectedUid].some((id) => id.includes("/")) ||
      reason.length > 500 || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new HttpsError("invalid-argument", "Assignment request is invalid.");
  }
  return firestore.runTransaction(async (transaction) => {
    const actor = await requireTrustedUser(transaction, firestore, uid, companyId);
    if (actor.role !== "admin") throw new HttpsError("permission-denied", "Only administrators can reassign customers.");
    const eventRef = firestore.doc(businessPath(companyId, "customer_assignment_events", key));
    const priorEvent = await transaction.get(eventRef);
    if (priorEvent.exists) {
      const prior = priorEvent.data() ?? {};
      if (prior.customerId !== customerId || prior.assignedToUid !== targetUid || prior.actorUid !== actor.uid ||
          prior.expectedAssignmentRevision !== expectedRevision || prior.previousAssignedToUid !== expectedUid || prior.reason !== reason) {
        throw new HttpsError("already-exists", "Assignment operation key is already in use.");
      }
      return {customerId, alreadyReassigned: true};
    }
    const ref = firestore.doc(businessPath(companyId, "customers", customerId));
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError("not-found", "Customer was not found.");
    const customer = snapshot.data() ?? {};
    if (customer.assignmentVersion !== 1 && Object.prototype.hasOwnProperty.call(customer, "assignedToUid")) {
      throw new HttpsError("failed-precondition", "Unversioned legacy assignment metadata requires review.", {reason: "customer-assignment-review"});
    }
    if (customer.companyId !== companyId || customer.id !== customerId || !customerAssigneeUid(customer)) {
      throw new HttpsError("failed-precondition", "Customer identity or legacy ownership requires review.");
    }
    const currentRevision = customer.assignmentRevision ?? 0;
    if (!Number.isSafeInteger(currentRevision) || currentRevision < 0) {
      throw new HttpsError("failed-precondition", "Assignment revision requires review.");
    }
    if (customerAssigneeUid(customer) !== expectedUid || currentRevision !== expectedRevision) {
      throw new HttpsError("failed-precondition", "Customer assignment changed. Refresh before transferring.", {reason: "customer-assignment-stale"});
    }
    const target = await requireTrustedUser(transaction, firestore, targetUid, companyId);
    if (target.uid === expectedUid) throw new HttpsError("invalid-argument", "Choose a different assignee.");
    const next = {assignedToUid: target.uid, assignedToName: target.name, assignedToRole: target.role,
      assignmentVersion: 1, assignmentRevision: currentRevision + 1,
      assignedAt: FieldValue.serverTimestamp(), assignedByUid: actor.uid, assignedByName: actor.name,
      assignmentReason: reason, lastAssignmentEventId: key, updatedAt: FieldValue.serverTimestamp()};
    transaction.update(ref, next);
    transaction.create(eventRef, {id: key, companyId, customerId, customerName: customer.name ?? "",
      previousAssignedToUid: expectedUid,
      previousAssignedToName: customer.assignedToName ?? customer.createdByName ?? "",
      previousAssignedToRole: customer.assignedToRole ?? customer.createdByRole ?? "",
      assignedToUid: target.uid, assignedToName: target.name, assignedToRole: target.role,
      expectedAssignmentRevision: expectedRevision, assignmentRevision: currentRevision + 1,
      legacyAssignment: customer.assignmentVersion !== 1,
      actorUid: actor.uid, actorName: actor.name, actorRole: actor.role, reason, createdAt: FieldValue.serverTimestamp()});
    return {customerId, alreadyReassigned: false};
  });
}
