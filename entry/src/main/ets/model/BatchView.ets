import { BatchItem, DownloadItem } from './Models';

/**
 * 打包任务卡要显示的全部信息。
 *
 * 它是从「批次记录 + 它的成员下载」派生出来的**只读投影**：卡片只认这个形状，不自己去翻
 * `DownloadStore` 的两张表。原先这个类和它的构造函数长在 view/Cards.ets 里，
 * 于是「任务页要算什么」这件事落在展示层；现在搬进 model，ViewModel 依赖它就不再依赖视图。
 */
export class BatchView {
  id: string = '';
  name: string = '';
  /** 'downloading' | 'packing' | 'failed' | 'completed' */
  status: string = 'downloading';
  total: number = 0;
  done: number = 0;
  failed: number = 0;
  error: string = '';
  thumbs: string[] = [];
}

/** 把一个批次和它的成员下载压成一张卡的视图模型。 */
export function batchViewOf(batch: BatchItem, members: DownloadItem[],
  done: number, failed: number): BatchView {
  const view: BatchView = new BatchView();
  view.id = batch.id;
  view.name = batch.name;
  view.total = members.length;
  view.done = done;
  view.failed = failed;
  view.error = batch.error;
  // Terminal states belong to the batch record: once it has packed, its
  // members are gone, so member counts alone would read as "0/0 下载中".
  if (batch.status === 'failed' || batch.status === 'completed') {
    view.status = batch.status;
  } else {
    view.status = members.length > 0 && (done + failed) >= members.length ? 'packing' : 'downloading';
  }
  view.thumbs = members.slice(0, 3).map((item: DownloadItem): string => item.url);
  return view;
}
