/**
 * 图库网格的日期分组文案（纯函数、零 IO）。
 *
 * 分组身份和显示文案必须分开：`keyOf` 给出稳定的 `YYYY-MM-DD` 供 `ForEach` 做 key，
 * `labelOf` 才把键翻成「今天 / 昨天 / 11月10日 / 2024年11月10日」。
 * 两者混在一起会让「今天」在跨零点、跨年后变成两个不同分组。
 */
export class LibraryDates {
  /** 分组键；时间戳无效时返回固定串，保证这类记录仍在同一组。 */
  static keyOf(at: number): string {
    if (!Number.isFinite(at) || at <= 0) {
      return 'unknown';
    }
    const moment: Date = new Date(at);
    return moment.getFullYear().toString() + '-'
      + (moment.getMonth() + 1).toString().padStart(2, '0') + '-'
      + moment.getDate().toString().padStart(2, '0');
  }

  /** 显示标题；`now` 由调用方传入，便于测试固定时间。 */
  static labelOf(key: string, now: number): string {
    if (key === 'unknown') {
      return '日期未知';
    }
    const todayKey: string = LibraryDates.keyOf(now);
    if (key === todayKey) {
      return '今天';
    }
    if (key === LibraryDates.keyOf(now - 24 * 60 * 60 * 1000)) {
      return '昨天';
    }
    const parts: string[] = key.split('-');
    if (parts.length !== 3) {
      return key;
    }
    const year: string = parts[0];
    const month: number = Number(parts[1]);
    const day: number = Number(parts[2]);
    if (!Number.isFinite(month) || !Number.isFinite(day)) {
      return key;
    }
    const thisYear: string = new Date(now).getFullYear().toString();
    return year === thisYear ? month.toString() + '月' + day.toString() + '日'
      : year + '年' + month.toString() + '月' + day.toString() + '日';
  }
}
