export function normalizeSearchText(value: unknown): string;
export function buildSearchKeywords(values: Iterable<unknown>): string[];
export function documentSearchFields(collection: string, data: Record<string, unknown>): {
  searchKeywords: string[]; hasStock?: boolean;
};
export const searchKeywordLimit: number;
export const searchPrefixLength: number;
export const searchExactLength: number;
