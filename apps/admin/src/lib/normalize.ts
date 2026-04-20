export function normalizeName(name: string): string {
  return name.replace(/[^\p{L}\p{N}]/gu, "").toLowerCase();
}
