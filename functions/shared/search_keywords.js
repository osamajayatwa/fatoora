"use strict";

// Keep this protocol in sync with lib/core/search/normalized_search.dart.
const searchKeywordLimit = 1024;
const searchPrefixLength = 80;
const searchExactLength = 240;

function normalizeSearchText(value) {
  let text = String(value ?? "").toLowerCase()
    .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]/gu, "")
    .replace(/[أإآٱ]/gu, "ا").replace(/ى/gu, "ي")
    .replace(/[\u200E\u200F\u202A-\u202E\u2066-\u2069]/gu, "")
    .replace(/\u200B/gu, " ");
  const arabicDigits = "٠١٢٣٤٥٦٧٨٩";
  const persianDigits = "۰۱۲۳۴۵۶۷۸۹";
  for (let index = 0; index < 10; index++) {
    text = text.replaceAll(arabicDigits[index], String(index))
      .replaceAll(persianDigits[index], String(index));
  }
  return text.replace(/[\s\-_/]+/gu, " ").trim();
}

function buildSearchKeywords(values) {
  const keywords = new Set();
  const add = (value) => {
    if (value && Array.from(value).length <= searchExactLength && keywords.size < searchKeywordLimit) {
      keywords.add(value);
    }
  };
  for (const value of values) {
    const legacy = String(value ?? "").trim().toLowerCase();
    const normalized = normalizeSearchText(value);
    const variants = new Set([normalized, legacy,
      normalized.replace(/[\s\-_/]+/gu, " "), legacy.replace(/[\s\-_/]+/gu, " ")]);
    for (const variant of variants) {
      add(variant);
      const words = variant.split(/\s+/u).filter(Boolean);
      for (let start = 0; start < words.length; start++) {
        const suffix = words.slice(start).join(" ");
        add(suffix);
        const runes = Array.from(suffix).slice(0, searchPrefixLength);
        for (let length = 1; length <= runes.length; length++) {
          add(runes.slice(0, length).join("").trimEnd());
        }
        if (keywords.size === searchKeywordLimit) break;
      }
      if (keywords.size === searchKeywordLimit) break;
    }
    if (keywords.size === searchKeywordLimit) break;
  }
  return [...keywords].sort();
}

function documentSearchFields(collection, data) {
  if (collection === "invoices") {
    return {searchKeywords: buildSearchKeywords([
      data.invoiceNumber, data.customerSnapshot?.name, data.customerSnapshot?.phone,
      data.salesRepName, data.dateString,
      ...(Array.isArray(data.items) ? data.items.map((item) => item?.itemName) : []),
    ])};
  }
  if (collection === "items") {
    return {searchKeywords: buildSearchKeywords([
      data.name, data.code, data.description, data.barcode, data.category,
    ])};
  }
  if (collection === "rep_inventory_balances") {
    return {searchKeywords: buildSearchKeywords([data.itemNameSnapshot, data.modelSnapshot]),
      hasStock: typeof data.quantity === "number" && Number.isFinite(data.quantity) && data.quantity > 0};
  }
  throw new Error(`Unsupported search collection: ${collection}`);
}

module.exports = {normalizeSearchText, buildSearchKeywords, documentSearchFields,
  searchKeywordLimit, searchPrefixLength, searchExactLength};
