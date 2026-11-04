import {HttpsError} from "firebase-functions/v2/https";

export const MAX_DECIMAL_SCALE = 6;
export const MAX_DECIMAL_UNIT_DIGITS = 30;
export const MAX_DECIMAL_UNITS = 10n ** BigInt(MAX_DECIMAL_UNIT_DIGITS) - 1n;

function validateScale(scale: number): void {
  if (!Number.isInteger(scale) || scale < 0 || scale > MAX_DECIMAL_SCALE) {
    throw new HttpsError("invalid-argument", "Unsupported decimal scale.");
  }
}

function checkedUnits(value: bigint): bigint {
  if (typeof value !== "bigint" || value < -MAX_DECIMAL_UNITS || value > MAX_DECIMAL_UNITS) {
    throw new HttpsError("invalid-argument", "Decimal units exceed the supported exact range.");
  }
  return value;
}

// Only called after validating scales/operands; intermediate powers are <= 12.
function shiftUnits(value: bigint, exponent: number): bigint {
  const factor = 10n ** BigInt(Math.abs(exponent));
  return checkedUnits(exponent >= 0 ? value * factor : divideRounded(value, factor));
}

/** Strict ASCII decimal input, explicit scale, no rounding or floating point.
 * Excess fractional digits (including zeros), exponent notation and whitespace
 * reject. Leading zeros normalize. Persist returned units with .toString().
 */
export function parseUnits(value: string, scale: number): bigint {
  validateScale(scale);
  if (typeof value !== "string" || value.length > 64) {
    throw new HttpsError("invalid-argument", "Invalid exact decimal string.");
  }
  const match = /^-?[0-9]+(?:\.[0-9]+)?$/.exec(value);
  if (match === null || match[0] !== value) {
    throw new HttpsError("invalid-argument", "Invalid exact decimal string.");
  }
  const negative = value.startsWith("-");
  const [whole, fractional = ""] = (negative ? value.slice(1) : value).split(".");
  if (fractional.length > scale) {
    throw new HttpsError("invalid-argument", "Decimal input exceeds the declared scale.");
  }
  const units = BigInt(whole + fractional.padEnd(scale, "0"));
  return checkedUnits(negative ? -units : units);
}

/** Fixed-scale output; units are bounded independently of the display scale. */
export function formatUnits(value: bigint, scale: number): string {
  validateScale(scale);
  checkedUnits(value);
  const digits = (value < 0n ? -value : value).toString().padStart(scale + 1, "0");
  const magnitude = scale === 0 ? digits : `${digits.slice(0, -scale)}.${digits.slice(-scale)}`;
  return value < 0n ? `-${magnitude}` : magnitude;
}

/** Explicit scale conversion, rounding half away from zero when reducing scale. */
export function rescaleUnits(value: bigint, fromScale: number, toScale: number): bigint {
  validateScale(fromScale);
  validateScale(toScale);
  return shiftUnits(checkedUnits(value), toScale - fromScale);
}

/** Quantity/price/input scales are independent; round only the final product. */
export function multiplyUnits(
  left: bigint, leftScale: number, right: bigint, rightScale: number, resultScale: number,
): bigint {
  validateScale(leftScale);
  validateScale(rightScale);
  validateScale(resultScale);
  return shiftUnits(checkedUnits(left) * checkedUnits(right), resultScale - leftScale - rightScale);
}

/** Exact ratio at an explicit output scale; denominator must be positive. */
export function divideUnits(
  numerator: bigint, numeratorScale: number, denominator: bigint, denominatorScale: number,
  resultScale: number,
): bigint {
  validateScale(numeratorScale);
  validateScale(denominatorScale);
  validateScale(resultScale);
  checkedUnits(numerator);
  checkedUnits(denominator);
  if (denominator <= 0n) {
    throw new HttpsError("invalid-argument", "Decimal denominator must be positive.");
  }
  const exponent = denominatorScale + resultScale - numeratorScale;
  const factor = 10n ** BigInt(Math.abs(exponent));
  return checkedUnits(divideRounded(
    exponent >= 0 ? numerator * factor : numerator,
    exponent >= 0 ? denominator : denominator * factor,
  ));
}

/** Percent is in percent units (16 at scale 0 means 16%); output keeps amount scale.
 * Tax/discount eligibility and rate bounds remain the business caller's rules.
 */
export function percentageUnits(amount: bigint, percent: bigint, percentScale: number): bigint {
  validateScale(percentScale);
  return checkedUnits(divideRounded(
    checkedUnits(amount) * checkedUnits(percent), 100n * 10n ** BigInt(percentScale),
  ));
}

/** Same-scale/currency unit sum; caller validates that shared unit metadata.
 * Allow cancelling intermediates; reject an out-of-range final result.
 */
export function sumUnits(values: readonly bigint[]): bigint {
  return checkedUnits(values.reduce((sum, value) => sum + checkedUnits(value), 0n));
}

/** Allocation for [previousQuantity, nextQuantity] from the ORIGINAL total.
 * All quantities must use the same unit scale. Cumulative rounded endpoints
 * conserve the total including its last residual; identical ranges replay
 * identically. The caller must persist/authorize consumed ranges atomically.
 */
export function allocateCumulativeUnits(
  total: bigint, previousQuantity: bigint, nextQuantity: bigint, totalQuantity: bigint,
): bigint {
  checkedUnits(total);
  checkedUnits(previousQuantity);
  checkedUnits(nextQuantity);
  checkedUnits(totalQuantity);
  if (totalQuantity <= 0n || previousQuantity < 0n || nextQuantity < previousQuantity ||
      nextQuantity > totalQuantity) {
    throw new HttpsError("invalid-argument", "Invalid cumulative allocation range.");
  }
  return checkedUnits(divideRounded(total * nextQuantity, totalQuantity) -
    divideRounded(total * previousQuantity, totalQuantity));
}

// Persist the existing numeric schema, computing three-decimal values with
// integer arithmetic. These legacy adapters retain their input rounding/order;
// new explicit-scale APIs above do not change any posting caller or schema.
export function divideRounded(numerator: bigint, denominator: bigint): bigint {
  if (denominator <= 0n) throw new HttpsError("invalid-argument", "Invalid decimal denominator.");
  const sign = numerator < 0n ? -1n : 1n;
  const absolute = numerator * sign;
  return sign * ((absolute + denominator / 2n) / denominator);
}

export function decimalUnits(value: number): bigint {
  if (!Number.isFinite(value)) throw new HttpsError("invalid-argument", "Invalid decimal value.");
  const [mantissa, exponent = "0"] = Math.abs(value).toString().toLowerCase().split("e");
  const [whole, fractional = ""] = mantissa.split(".");
  const digits = BigInt(whole + fractional);
  const power = Number(exponent) - fractional.length + 3;
  const scaled = power >= 0 ? digits * 10n ** BigInt(power) : divideRounded(digits, 10n ** BigInt(-power));
  return value < 0 ? -scaled : scaled;
}

export function decimalNumber(units: bigint): number {
  if (units > BigInt(Number.MAX_SAFE_INTEGER) || units < -BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new HttpsError("invalid-argument", "Decimal value exceeds the supported exact range.");
  }
  const value = Number(units) / 1000;
  if (decimalUnits(value) !== units) {
    throw new HttpsError("invalid-argument", "Numeric decimal conversion would lose units.");
  }
  return value;
}

export function roundDecimal(value: number): number {
  return decimalNumber(decimalUnits(value));
}

export function multiplyDecimal(left: number, right: number): number {
  return decimalNumber(divideRounded(decimalUnits(left) * decimalUnits(right), 1000n));
}

export function percentageDecimal(amount: number, percent: number): number {
  return decimalNumber(divideRounded(decimalUnits(amount) * decimalUnits(percent), 100000n));
}

export function prorateDecimal(amount: number, quantity: number, totalQuantity: number): number {
  return decimalNumber(divideRounded(decimalUnits(amount) * decimalUnits(quantity), decimalUnits(totalQuantity)));
}

export function sumDecimals(values: number[]): number {
  return decimalNumber(values.reduce((sum, value) => sum + decimalUnits(value), 0n));
}
