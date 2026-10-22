export interface ReceiptData {
  target: string;
  folderUri: string;
  status: string;
  message: string;
  parts: string[];
}

/** 原件下载与另存结果分开持久化，重启不自动重复弹系统保存框。 */
@ObservedV2
export class SaveReceipt implements ReceiptData {
  @Trace target: string = '';
  @Trace folderUri: string = '';
  @Trace status: string = '';
  @Trace message: string = '';
  /** 实况照片以 still / motion 分别记录，重试只保存未成功的部分。 */
  @Trace parts: string[] = [];
}

export class ReceiptWire implements ReceiptData {
  target: string = '';
  folderUri: string = '';
  status: string = '';
  message: string = '';
  parts: string[] = [];

  static from(receipt: SaveReceipt): ReceiptWire {
    const wire: ReceiptWire = new ReceiptWire();
    wire.target = receipt.target;
    wire.folderUri = receipt.folderUri;
    wire.status = receipt.status;
    wire.message = receipt.message;
    wire.parts = receipt.parts.slice();
    return wire;
  }

  static restore(wire: ReceiptData | undefined): SaveReceipt {
    const receipt: SaveReceipt = new SaveReceipt();
    if (wire === undefined || wire === null) { return receipt; }
    receipt.target = wire.target ?? '';
    receipt.folderUri = wire.folderUri ?? '';
    receipt.status = wire.status ?? '';
    receipt.message = wire.message ?? '';
    receipt.parts = wire.parts ?? [];
    if (receipt.status === 'pending') {
      receipt.status = 'interrupted';
      receipt.message = '上次另存结果未确认，请检查目标位置后再重试';
    }
    return receipt;
  }
}
