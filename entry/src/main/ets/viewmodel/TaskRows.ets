import { DownloadItem } from '../model/Models';
import { BatchView } from '../model/BatchView';

/** A flattened task-list row. Cards stay lazy while section headings scroll with them. */
export class TaskRow {
  key: string = '';
  kind: string = '';
  title: string = '';
  count: number = 0;
  state: string = '';
  task: DownloadItem | undefined = undefined;
  batch: BatchView | undefined = undefined;
}

export class TaskRows implements IDataSource {
  private rows: TaskRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.rows.length; }
  getData(index: number): TaskRow { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }

  replace(next: TaskRow[]): void {
    const previous: TaskRow[] = this.rows;
    this.rows = next;
    if (previous.length !== next.length || previous.some((row: TaskRow, index: number): boolean =>
      row.key !== next[index].key)) {
      this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
      return;
    }
    for (let index: number = 0; index < next.length; index++) {
      const old: TaskRow = previous[index];
      const current: TaskRow = next[index];
      if (old.count !== current.count || old.title !== current.title || old.state !== current.state ||
        old.batch?.status !== current.batch?.status || old.batch?.done !== current.batch?.done ||
        old.batch?.failed !== current.batch?.failed || old.batch?.error !== current.batch?.error ||
        old.batch?.thumbs.join('|') !== current.batch?.thumbs.join('|')) {
        this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataChange(index); });
      }
    }
  }
}
