import {AuditChange} from "./audit_types";
import {isSensitiveField, safeValue} from "./audit_redaction";

export function safeDiff(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
  allowedFields: string[],
): AuditChange[] {
  const left = before ?? {};
  const right = after ?? {};
  return allowedFields.filter((field) => !isSensitiveField(field))
    .filter((field) => !equivalent(left[field], right[field]))
    .slice(0, 50)
    .map((field) => ({
      field,
      before: safeValue(left[field]),
      after: safeValue(right[field]),
    }));
}

function equivalent(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (left && right &&
      typeof (left as {isEqual?: unknown}).isEqual === "function") {
    return (left as {isEqual: (other: unknown) => boolean}).isEqual(right);
  }
  try {
    return JSON.stringify(left) === JSON.stringify(right);
  } catch {
    return false;
  }
}
