import {HttpsError} from "firebase-functions/v2/https";

// Persist the existing numeric schema, computing three-decimal values with
// integer arithmetic. BigInt intermediates never enter Firestore documents.
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
  return Number(units) / 1000;
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
