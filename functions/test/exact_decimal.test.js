"use strict";
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {createHash} = require("node:crypto");
const decimal = require("../lib/trusted/exact_decimal");
const fixture = JSON.parse(readFileSync(
  join(__dirname, "../../test/fixtures/exact_decimal_cases.json"), "utf8",
));

function evaluate(vector) {
  const a = vector.args;
  const units = (index) => BigInt(a[index]);
  switch (vector.op) {
    case "parse": return decimal.parseUnits(a[0], a[1]).toString();
    case "format": return decimal.formatUnits(units(0), a[1]);
    case "rescale": return decimal.rescaleUnits(units(0), a[1], a[2]).toString();
    case "multiply": return decimal.multiplyUnits(units(0), a[1], units(2), a[3], a[4]).toString();
    case "divide": return decimal.divideUnits(units(0), a[1], units(2), a[3], a[4]).toString();
    case "percentage": return decimal.percentageUnits(units(0), units(1), a[2]).toString();
    case "sum": return decimal.sumUnits(a.map(BigInt)).toString();
    case "allocate": return decimal.allocateCumulativeUnits(...a.map(BigInt)).toString();
    case "legacyRound": return decimal.roundDecimal(Number(a[0]));
    case "legacyNumber": return decimal.decimalNumber(units(0));
    default: throw new Error(`Unknown vector operation ${vector.op}`);
  }
}

for (const vector of fixture.cases) {
  test(`shared vector: ${vector.id}`, () => {
    if (vector.error) {
      assert.throws(() => evaluate(vector), (error) => error.code === "invalid-argument");
    } else {
      const actual = evaluate(vector);
      assert.equal(actual, typeof actual === "number" ? Number(vector.expected) : vector.expected);
    }
  });
}

test("the shared contract pins scales, bounds and rounding", () => {
  assert.equal(fixture.schemaVersion, 1);
  assert.equal(fixture.rounding, "half_away_from_zero");
  assert.equal(fixture.maxScale, decimal.MAX_DECIMAL_SCALE);
  assert.equal(fixture.maxUnitDigits, decimal.MAX_DECIMAL_UNIT_DIGITS);
  assert.equal(fixture.legacyScale, 3);
});

// Independent oracle uses quotient/remainder, not the helper's midpoint formula.
function rationalRound(numerator, denominator) {
  const quotient = numerator / denominator;
  const remainder = numerator % denominator;
  return (remainder < 0n ? -remainder : remainder) * 2n >= denominator
    ? quotient + (numerator < 0n ? -1n : 1n) : quotient;
}

function generator() {
  let state = fixture.propertySeed;
  return () => (state = state * 48271 % 2147483647);
}

function expectBounded(calculate, expected) {
  if (expected < -decimal.MAX_DECIMAL_UNITS || expected > decimal.MAX_DECIMAL_UNITS) {
    assert.throws(calculate, (error) => error.code === "invalid-argument");
  } else {
    assert.equal(calculate(), expected);
  }
}

test("seeded exact round trips, products, ratios, percentages and signed sums", () => {
  const next = generator();
  for (let i = 0; i < 2000; i++) {
    const sign = next() % 2 ? 1n : -1n;
    const value = sign * (BigInt(next()) * 10n ** BigInt(next() % 20) + BigInt(next()));
    const scale = next() % 7;
    const right = BigInt(next() % 1000000 + 1);
    const rightScale = next() % 7;
    const outputScale = next() % 7;
    assert.equal(decimal.parseUnits(decimal.formatUnits(value, scale), scale), value);
    assert.equal(decimal.sumUnits([value, right, -value]), right);

    const exponent = outputScale - scale - rightScale;
    const product = exponent >= 0 ? value * right * 10n ** BigInt(exponent)
      : rationalRound(value * right, 10n ** BigInt(-exponent));
    expectBounded(() => decimal.multiplyUnits(value, scale, right, rightScale, outputScale), product);

    const shift = rightScale + outputScale - scale;
    const ratio = rationalRound(value * (shift >= 0 ? 10n ** BigInt(shift) : 1n),
      right * (shift < 0 ? 10n ** BigInt(-shift) : 1n));
    expectBounded(() => decimal.divideUnits(value, scale, right, rightScale, outputScale), ratio);
    const percentage = rationalRound(value * right, 100n * 10n ** BigInt(rightScale));
    expectBounded(() => decimal.percentageUnits(value, right, rightScale), percentage);
  }
});

test("seeded split payments/returns conserve signed original totals and replay ranges", () => {
  const next = generator();
  for (let i = 0; i < 1000; i++) {
    const total = BigInt(next()) * (next() % 2 ? 1n : -1n);
    const quantity = BigInt(next() % 1000000 + 1);
    const cuts = [0n, quantity];
    for (let j = 0; j < 16; j++) cuts.push(BigInt(next()) % quantity);
    cuts.sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
    let sum = 0n;
    for (let j = 1; j < cuts.length; j++) {
      const a = cuts[j - 1], b = cuts[j];
      const amount = decimal.allocateCumulativeUnits(total, a, b, quantity);
      assert.equal(amount, rationalRound(total * b, quantity) - rationalRound(total * a, quantity));
      assert.equal(decimal.allocateCumulativeUnits(total, a, b, quantity), amount);
      assert.ok(total >= 0n ? amount >= 0n : amount <= 0n);
      sum += amount;
    }
    assert.equal(sum, total);
    assert.equal(decimal.allocateCumulativeUnits(total, cuts[2], cuts[6], quantity) +
      decimal.allocateCumulativeUnits(total, cuts[6], cuts[12], quantity),
    decimal.allocateCumulativeUnits(total, cuts[2], cuts[12], quantity));
  }
});

test("10000 legacy operations retain the pre-change baseline fingerprint", () => {
  const next = generator();
  const results = [];
  for (let i = 0; i < 2000; i++) {
    const x = (next() % 20000001 - 10000000) / 1000;
    const y = (next() % 100001) / 1000;
    results.push([
      decimal.roundDecimal(x), decimal.multiplyDecimal(x, y), decimal.percentageDecimal(x, y),
      decimal.prorateDecimal(x, y, 101), decimal.sumDecimals([x, y, -x]),
    ].map((value) => decimal.decimalUnits(value).toString()));
  }
  assert.equal(createHash("sha256").update(JSON.stringify(results)).digest("hex"),
    "6cd9ef81e9d6c0d018e99c4630b170a8b8725029fe9ab4f40261bcc8c503280b");
});

test("independent legacy prorating stays compatible; cumulative API carries residual", () => {
  assert.equal(decimal.sumDecimals(Array(3).fill(decimal.prorateDecimal(0.998, 1, 3))), 0.999);
  assert.equal(decimal.sumUnits([0n, 1n, 2n].map((q) =>
    decimal.allocateCumulativeUnits(998n, q, q + 1n, 3n))), 998n);
});

test("runtime input errors fail closed without mutating arguments", () => {
  assert.throws(() => decimal.parseUnits(1, 3), (e) => e.code === "invalid-argument");
  assert.throws(() => decimal.parseUnits("1", 0.5), (e) => e.code === "invalid-argument");
  assert.throws(() => decimal.sumUnits([1]), (e) => e.code === "invalid-argument");
  const values = Object.freeze([1n, -1n, 5n]);
  assert.equal(decimal.sumUnits(values), 5n);
  assert.deepEqual(values, [1n, -1n, 5n]);
  assert.throws(() => decimal.roundDecimal(NaN), (e) => e.code === "invalid-argument");
  assert.throws(() => decimal.roundDecimal(Infinity), (e) => e.code === "invalid-argument");
});

test("legacy numeric output rejects a lost thousandth inside the safe-integer bound", () => {
  assert.throws(() => decimal.decimalNumber(9007199254740991n),
    (error) => error.code === "invalid-argument");
  assert.throws(() => decimal.decimalNumber(-9007199254740991n),
    (error) => error.code === "invalid-argument");
});
