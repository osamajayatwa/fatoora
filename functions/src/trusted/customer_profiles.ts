import {DocumentData, FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  TRUSTED_CALLABLE_OPTIONS,
  businessPath,
  deterministicId,
  optionalString,
  permissionValue,
  record,
  requireCallableUid,
  requireTrustedUser,
  requiredIdempotencyKey,
  requiredString,
} from "./common";

interface CustomerProfileRequest {
  companyId?: unknown;
  customerId?: unknown;
  idempotencyKey?: unknown;
  name?: unknown;
  phone?: unknown;
  addressText?: unknown;
  city?: unknown;
  area?: unknown;
  notes?: unknown;
  active?: unknown;
}

interface ValidatedCustomerProfile {
  name: string;
  phone: string;
  addressText: string;
  city: string;
  area: string;
  notes: string;
  active: boolean;
  phoneNormalized: string;
  nameLower: string;
  cityLower: string;
  areaLower: string;
  searchKeywords: string[];
}

export const createCustomer = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "createCustomer");
  const input = record(request.data) as CustomerProfileRequest;
  const companyId = requiredString(input.companyId, "companyId");
  const key = requiredIdempotencyKey(input.idempotencyKey);
  return createCustomerTransaction(
    getFirestore(),
    uid,
    companyId,
    key,
    input,
  );
});

export const updateCustomer = onCall(TRUSTED_CALLABLE_OPTIONS, async (request) => {
  const uid = requireCallableUid(request, "updateCustomer");
  const input = record(request.data) as CustomerProfileRequest;
  return updateCustomerTransaction(
    getFirestore(),
    uid,
    requiredString(input.companyId, "companyId"),
    requiredString(input.customerId, "customerId"),
    input,
  );
});

export async function createCustomerTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  idempotencyKey: string,
  input: CustomerProfileRequest,
): Promise<{customerId: string; alreadyPosted: boolean}> {
  const profile = validateProfile(input, true);
  if (!profile.active) {
    throw new HttpsError("invalid-argument", "New customers must be active.");
  }
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    let creationAllowed = true;
    if (user.role === "sales_rep") {
      const settings = await transaction.get(firestore.doc(
        businessPath(companyId, "settings", "app"),
      ));
      creationAllowed = permissionValue(
        settings.data(),
        "allowSalesRepCreateCustomers",
      );
    }

    const customerId = deterministicId("customer", idempotencyKey);
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const existing = await transaction.get(customerRef);
    if (existing.exists) {
      if (!sameCreateRequest(
        existing.data() ?? {},
        user.uid,
        companyId,
        idempotencyKey,
        profile,
      )) {
        throw new HttpsError("already-exists", "Idempotency key is already in use.");
      }
      return {customerId, alreadyPosted: true};
    }
    if (!creationAllowed) {
      throw new HttpsError("permission-denied", "Customer creation is disabled.");
    }

    const reservationRef = profile.phoneNormalized ? firestore.doc(businessPath(
      companyId,
      "customer_phone_reservations",
      profile.phoneNormalized,
    )) : null;
    const reservation = reservationRef ? await transaction.get(reservationRef) : null;
    if (reservation?.exists && reservation.data()?.customerId !== customerId) {
      throw new HttpsError("already-exists", "Customer phone is already in use.");
    }

    transaction.set(customerRef, {
      id: customerId,
      companyId,
      idempotencyKey,
      ...profile,
      currentBalance: 0,
      totalSales: 0,
      totalPaid: 0,
      createdByUid: user.uid,
      createdByName: user.name,
      createdByRole: user.role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (reservationRef) {
      transaction.set(reservationRef, reservationData(
        companyId,
        customerId,
        profile.phoneNormalized,
      ));
    }
    return {customerId, alreadyPosted: false};
  });
}

export async function updateCustomerTransaction(
  firestore: Firestore,
  uid: string | undefined,
  companyId: string,
  customerId: string,
  input: CustomerProfileRequest,
): Promise<{customerId: string; alreadyUpdated: boolean}> {
  const profile = validateProfile(input, input.active !== undefined);
  return firestore.runTransaction(async (transaction) => {
    const user = await requireTrustedUser(transaction, firestore, uid, companyId);
    const customerRef = firestore.doc(businessPath(companyId, "customers", customerId));
    const customer = await transaction.get(customerRef);
    if (!customer.exists) {
      throw new HttpsError("not-found", "Customer was not found.");
    }
    const existing = customer.data() ?? {};
    if (
      existing.companyId !== companyId ||
      existing.id !== customerId ||
      (user.role === "sales_rep" && existing.createdByUid !== user.uid)
    ) {
      throw new HttpsError("permission-denied", "Customer is not accessible.");
    }

    const effectiveProfile = {
      ...profile,
      active: input.active === undefined ? existing.active === true : profile.active,
    };
    const oldNormalized = optionalString(existing.phoneNormalized) ||
      normalizePhone(optionalString(existing.phone));
    const phoneChanged = oldNormalized !== effectiveProfile.phoneNormalized;
    const newReservationRef = effectiveProfile.phoneNormalized ?
      firestore.doc(businessPath(
        companyId,
        "customer_phone_reservations",
        effectiveProfile.phoneNormalized,
      )) : null;
    const oldReservationRef = phoneChanged && oldNormalized ? firestore.doc(businessPath(
      companyId,
      "customer_phone_reservations",
      oldNormalized,
    )) : null;
    const newReservation = newReservationRef ? await transaction.get(newReservationRef) : null;
    const oldReservation = oldReservationRef ? await transaction.get(oldReservationRef) : null;

    if (newReservation?.exists && newReservation.data()?.customerId !== customerId) {
      throw new HttpsError("already-exists", "Customer phone is already in use.");
    }
    if (oldReservation?.exists && oldReservation.data()?.customerId !== customerId) {
      throw new HttpsError("data-loss", "Existing phone reservation is inconsistent.");
    }

    const alreadyUpdated = sameProfile(existing, effectiveProfile);
    if (!alreadyUpdated) {
      transaction.update(customerRef, {
        ...effectiveProfile,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (newReservationRef && !newReservation?.exists) {
      transaction.set(newReservationRef, reservationData(
        companyId,
        customerId,
        effectiveProfile.phoneNormalized,
      ));
    }
    if (oldReservationRef && oldReservation?.exists) {
      transaction.delete(oldReservationRef);
    }
    return {customerId, alreadyUpdated};
  });
}

function validateProfile(
  input: CustomerProfileRequest,
  validateActive: boolean,
): ValidatedCustomerProfile {
  const name = boundedRequiredText(input.name, "name", 200);
  if (name.toLowerCase() === "undefined") {
    throw new HttpsError("invalid-argument", "name is invalid.");
  }
  const phone = boundedOptionalText(input.phone, "phone", 40);
  const addressText = boundedOptionalText(input.addressText, "addressText", 500);
  const city = boundedOptionalText(input.city, "city", 100);
  const area = boundedOptionalText(input.area, "area", 100);
  const notes = boundedOptionalText(input.notes, "notes", 1000);
  if (validateActive && typeof input.active !== "boolean") {
    throw new HttpsError("invalid-argument", "active must be a boolean.");
  }
  const phoneNormalized = normalizePhone(phone);
  if (phone && !phoneNormalized) {
    throw new HttpsError("invalid-argument", "phone must contain digits.");
  }
  const nameLower = normalizeText(name);
  const cityLower = normalizeText(city);
  const areaLower = normalizeText(area);
  return {
    name,
    phone,
    addressText,
    city,
    area,
    notes,
    active: input.active !== false,
    phoneNormalized,
    nameLower,
    cityLower,
    areaLower,
    searchKeywords: buildSearchKeywords([
      nameLower,
      phoneNormalized,
      cityLower,
      areaLower,
      normalizeText(addressText),
    ]),
  };
}

function boundedRequiredText(value: unknown, field: string, max: number): string {
  const text = requiredString(value, field);
  if (text.length > max) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return text;
}

function boundedOptionalText(value: unknown, field: string, max: number): string {
  const text = optionalString(value);
  if (text.length > max) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return text;
}

export function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("00962")) return `0${digits.slice(5)}`;
  if (digits.startsWith("962")) return `0${digits.slice(3)}`;
  return digits;
}

function normalizeText(value: string): string {
  return value.trim().toLowerCase();
}

function buildSearchKeywords(values: string[]): string[] {
  const keywords = new Set<string>();
  for (const value of values) {
    const normalized = normalizeText(value);
    if (!normalized) continue;
    keywords.add(normalized);
    for (const token of normalized.split(/[\s\-_/]+/u)) {
      if (!token) continue;
      keywords.add(token);
      for (let index = 1; index <= token.length && index <= 20; index += 1) {
        keywords.add(token.slice(0, index));
      }
    }
  }
  return [...keywords].sort();
}

function reservationData(
  companyId: string,
  customerId: string,
  phoneNormalized: string,
): DocumentData {
  return {
    companyId,
    customerId,
    phoneNormalized,
    createdAt: FieldValue.serverTimestamp(),
  };
}

function sameCreateRequest(
  data: DocumentData,
  uid: string,
  companyId: string,
  idempotencyKey: string,
  profile: ValidatedCustomerProfile,
): boolean {
  return data.companyId === companyId &&
    data.idempotencyKey === idempotencyKey &&
    data.createdByUid === uid &&
    sameProfile(data, profile);
}

function sameProfile(
  data: DocumentData,
  profile: ValidatedCustomerProfile,
): boolean {
  return data.name === profile.name &&
    data.phone === profile.phone &&
    data.addressText === profile.addressText &&
    data.city === profile.city &&
    data.area === profile.area &&
    data.notes === profile.notes &&
    data.active === profile.active &&
    data.phoneNormalized === profile.phoneNormalized &&
    data.nameLower === profile.nameLower &&
    data.cityLower === profile.cityLower &&
    data.areaLower === profile.areaLower &&
    arraysEqual(data.searchKeywords, profile.searchKeywords);
}

function arraysEqual(value: unknown, expected: string[]): boolean {
  return Array.isArray(value) &&
    value.length === expected.length &&
    value.every((entry, index) => entry === expected[index]);
}
