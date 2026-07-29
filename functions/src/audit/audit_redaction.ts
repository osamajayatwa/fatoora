const SENSITIVE = /(password|token|secret|api.?key|private.?key|connection.?string|fcm|qr.?payload|pdf.?data|stack|authorization)/i;
const MAX_STRING = 500;
const MAX_ARRAY = 50;
const MAX_KEYS = 50;
const MAX_DEPTH = 4;

export function sanitizeString(value: unknown, max = MAX_STRING): string {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001F\u007F]/g, " ").replace(/\s+/g, " ")
    .trim().slice(0, max);
}

export function safeValue(value: unknown, depth = 0): unknown {
  if (value == null || typeof value === "boolean" || typeof value === "number") {
    return value;
  }
  if (typeof value === "string") return sanitizeString(value);
  if (value instanceof Date) return value.toISOString();
  if (typeof (value as {toDate?: unknown}).toDate === "function") return value;
  if (depth >= MAX_DEPTH) return "[truncated]";
  if (Array.isArray(value)) {
    return value.slice(0, MAX_ARRAY).map((entry) => safeValue(entry, depth + 1));
  }
  if (typeof value === "object") {
    return Object.entries(value as Record<string, unknown>)
      .filter(([key]) => !SENSITIVE.test(key))
      .slice(0, MAX_KEYS)
      .reduce<Record<string, unknown>>((result, [key, entry]) => {
        result[sanitizeString(key, 80)] = safeValue(entry, depth + 1);
        return result;
      }, {});
  }
  return sanitizeString(String(value));
}

export function isSensitiveField(field: string): boolean {
  return SENSITIVE.test(field);
}
