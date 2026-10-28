/** Stable image identity survives filtering, deselection and list reordering. */
export class PreviewNavigation {
  static index(ids: string[], current: string, previousIndex: number): number {
    const existing: number = ids.indexOf(current);
    return existing >= 0 ? existing : Math.max(0, Math.min(previousIndex, ids.length - 1));
  }

  static selected(ids: string[], selectedIds: string[]): string[] {
    return ids.filter((id: string): boolean => selectedIds.includes(id));
  }

  static jump(value: string, count: number): number {
    if (!/^[1-9][0-9]*$/.test(value.trim())) { return -1; }
    const page: number = Number(value.trim());
    return Number.isSafeInteger(page) && page <= count ? page - 1 : -1;
  }
}
