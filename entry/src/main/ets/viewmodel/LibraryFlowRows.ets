import { DownloadItem, ZipItem } from '../model/Models';

export class LibraryFlowRow {
  key: string = '';
  kind: string = '';
  title: string = '';
  count: number = 0;
  state: string = '';
  image: DownloadItem | undefined = undefined;
  archive: ZipItem | undefined = undefined;
}

/** Stable IDs keep visible thumbnails mounted while filters and selection change. */
export class LibraryFlowRows implements IDataSource {
  private items: LibraryFlowRow[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): LibraryFlowRow { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
  replace(next: LibraryFlowRow[]): void {
    const old: LibraryFlowRow[] = this.items;
    this.items = next;
    if (old.length !== next.length || old.some((row: LibraryFlowRow, index: number): boolean =>
      row.key !== next[index].key)) {
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
      return;
    }
    this.listeners.forEach((listener: DataChangeListener): void => {
      for (let index: number = 0; index < next.length; index++) {
        if (index === 0 || old[index].state !== next[index].state) { listener.onDataChange(index); }
      }
    });
  }
}
