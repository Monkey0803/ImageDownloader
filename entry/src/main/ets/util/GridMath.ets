/**
 * 网格排布的纯计算。
 *
 * 原先「按列切行」和「补齐末行的空格子」在 Index 里各写了两份（图片一份、下载一份），
 * 两份除了元素类型完全一样。这里合成一组泛型函数：**迭代器**式的切分，没有状态，
 * 因此可以放心在 build 里调用（只做算术，不产生副作用）。
 */

/**
 * 把一维列表按 `columns` 切成若干行。
 *
 * 不做防御性拷贝以外的事：`items` 里的元素仍是原对象引用，所以 `@ObjectLink` 绑定不变。
 * `columns <= 0` 时返回空表，避免调用方算错列数时死循环。
 */
export function chunkRows<T>(items: T[], columns: number): T[][] {
  const rows: T[][] = [];
  if (columns <= 0) {
    return rows;
  }
  for (let start: number = 0; start < items.length; start += columns) {
    rows.push(items.slice(start, start + columns));
  }
  return rows;
}

/** 末行还差几个格子才铺满；给占位 `Column` 用，保证最后一行的列宽与上面一致。 */
export function fillerCells(count: number, columns: number): number[] {
  const cells: number[] = [];
  if (columns <= 0) {
    return cells;
  }
  const missing: number = (columns - (count % columns)) % columns;
  for (let i: number = 0; i < missing; i++) {
    cells.push(i);
  }
  return cells;
}
