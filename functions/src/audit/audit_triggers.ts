import {getFirestore} from "firebase-admin/firestore";
import {
  FirestoreAuthEvent,
  onDocumentWrittenWithAuthContext,
} from "firebase-functions/v2/firestore";
import {Change} from "firebase-functions/v2";
import {DocumentSnapshot} from "firebase-admin/firestore";
import {buildAuditEvent} from "./audit_event_builder";
import {ENTITY_CONFIGS, EntityAuditConfig} from "./entity_audit_config";
import {writeAuditEvent} from "./audit_writer";

const REGION = "us-central1";

export const auditCompanyDocumentWrite = onDocumentWrittenWithAuthContext({
  document: "companies/{companyId}/{collectionId}/{documentId}",
  region: REGION,
  retry: true,
}, async (event) => {
  const collectionId = event.params.collectionId;
  if (collectionId === "audit_events") return;
  const config = ENTITY_CONFIGS[collectionId];
  if (!config || !event.data) return;
  await handleEvent(event, config, event.params.companyId,
    event.params.documentId);
});

export const auditUserWrite = onDocumentWrittenWithAuthContext({
  document: "users/{documentId}",
  region: REGION,
  retry: true,
}, async (event) => {
  if (!event.data) return;
  const data = event.data.after.exists ? event.data.after.data() :
    event.data.before.data();
  const companyId = string(data?.companyId) || "default_company";
  await handleEvent(event, ENTITY_CONFIGS.users, companyId,
    event.params.documentId);
});

export const auditItemWrite = onDocumentWrittenWithAuthContext({
  document: "items/{documentId}",
  region: REGION,
  retry: true,
}, async (event) => {
  if (!event.data) return;
  const data = event.data.after.exists ? event.data.after.data() :
    event.data.before.data();
  const companyId = string(data?.companyId) || "default_company";
  await handleEvent(event, ENTITY_CONFIGS.items, companyId,
    event.params.documentId);
});

async function handleEvent<P extends Record<string, string>>(
  event: FirestoreAuthEvent<Change<DocumentSnapshot> | undefined, P>,
  config: EntityAuditConfig,
  companyId: string,
  documentId: string,
): Promise<void> {
  const change = event.data;
  if (!change) return;
  const before = change.before.exists ? change.before.data() : undefined;
  const after = change.after.exists ? change.after.data() : undefined;
  const actor = await actorFor(event.authId);
  const auditEvent = buildAuditEvent({
    sourceEventId: event.id,
    eventTime: event.time,
    authType: event.authType,
    authId: event.authId,
    companyId,
    entityId: documentId,
    entityPath: event.document,
    config,
    before,
    after,
    actor,
  });
  if (auditEvent) await writeAuditEvent(auditEvent);
}

async function actorFor(authId?: string): Promise<Record<string, unknown>> {
  if (!authId || authId.includes("@")) return {};
  const snapshot = await getFirestore().collection("users").doc(authId).get();
  return snapshot.data() ?? {};
}

function string(value: unknown): string {
  return typeof value === "string" ? value : "";
}
