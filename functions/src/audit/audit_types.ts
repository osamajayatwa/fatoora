import {Timestamp} from "firebase-admin/firestore";

export const AUDIT_SCHEMA_VERSION = 1 as const;

export const AuditEventLevels = {
  business: "business",
  dataChange: "data_change",
  security: "security",
  system: "system",
} as const;

export const AuditSeverities = {
  info: "info",
  warning: "warning",
  critical: "critical",
} as const;

export const AuditResults = {
  success: "success",
  failure: "failure",
  denied: "denied",
} as const;

export const AuditSources = {
  web: "web",
  android: "android",
  cloudFunction: "cloud_function",
  adminScript: "admin_script",
  migration: "migration",
  system: "system",
} as const;

export interface AuditChange {
  field: string;
  before: unknown;
  after: unknown;
}

export interface AuditEvent {
  schemaVersion: typeof AUDIT_SCHEMA_VERSION;
  eventId: string;
  sourceEventId: string;
  companyId: string;
  occurredAt: Timestamp;
  recordedAt: FirebaseFirestore.FieldValue;
  eventLevel: string;
  category: string;
  action: string;
  severity: string;
  result: string;
  displayInTimeline: boolean;
  operationId: string;
  requestId: string;
  correlationId: string;
  actorType: string;
  actorUid: string;
  actorName: string;
  actorRole: string;
  authType: string;
  authId: string;
  source: string;
  platform: string;
  appVersion: string;
  entityType: string;
  entityId: string;
  entityNumber: string;
  entityLabel: string;
  entityPath: string;
  customerId: string;
  customerNameSnapshot: string;
  salesRepId: string;
  salesRepNameSnapshot: string;
  summaryKey: string;
  summaryArgs: Record<string, unknown>;
  changedFields: string[];
  changes: AuditChange[];
  financialImpact: Record<string, unknown>;
  inventoryImpact: Record<string, unknown>[];
  relatedEntities: Record<string, unknown>[];
  reason: string;
  notes: string;
  metadata: Record<string, unknown>;
}
