import { MediaFormat } from './MediaFormat';

/** 批量直链每一行的状态。 */
export class BatchLinkStatus {
  /** 扩展名已经能确定是图片 / 实况照片包，或 HEAD 已确认是图片。 */
  static readonly VALID: string = 'valid';
  /** HTTP(S) 已成立，但类型无法由地址确定，等待按需 HEAD 探测。 */
  static readonly PENDING: string = 'pending';
  /** 不是 HTTP(S)、链接格式错误、明确不是图片，或 HEAD 确认是网页。 */
  static readonly INVALID: string = 'invalid';
  /** 与前面某一行的完整 URL 完全相同。 */
  static readonly DUPLICATE: string = 'duplicate';
}

/** HEAD 探测的结论类型。 */
export class BatchCheckKind {
  static readonly IMAGE: string = 'image';
  static readonly PAGE: string = 'page';
  static readonly UNKNOWN: string = 'unknown';
}

/** 输入区逐行展示的一行；`line` 是原始文本里的物理行号。 */
export class BatchLinkRow {
  line: number = 0;
  url: string = '';
  status: string = BatchLinkStatus.INVALID;
  reason: string = '';
  /** 重复行指向首次出现的行号；其他情况为 0。 */
  duplicateOf: number = 0;
  /** 是否已经做过 HEAD 探测。 */
  probed: boolean = false;
  mime: string = '';
}

/** 一次 HEAD 探测的纯结果，不包含任何网络对象。 */
export class BatchLinkCheck {
  url: string = '';
  kind: string = BatchCheckKind.UNKNOWN;
  detail: string = '';
  mime: string = '';
}

/** 解析与合并的完整结果；`urls` 是实际可导入的链接（valid + pending）。 */
export class BatchLinkReport {
  rows: BatchLinkRow[] = [];
  urls: string[] = [];
  valid: number = 0;
  pending: number = 0;
  invalid: number = 0;
  duplicates: number = 0;
}

/** 探测取消令牌；由 ViewModel 在换文本 / 关闭面板 / 跳转时取消。 */
export class BatchProbeToken {
  cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }
}

/**
 * 批量直链的纯逻辑：逐行解析、HEAD 结果分类、探测结果合并。
 *
 * 这一层不碰网络和文件，所以既能被宿主测试直接加载，也能被 ViewModel 在
 * `@Computed` 里反复调用。真正的 HEAD 请求在 `BatchLinkProbe`。
 */
export class BatchLinks {
  /** 明确不是图片、不应该再花 HEAD 去确认的后缀。 */
  private static readonly NON_IMAGE_EXTENSIONS: string[] = [
    'html', 'htm', 'xhtml', 'pdf', 'txt', 'json', 'xml', 'js', 'css',
    'zip', 'mp4', 'mov', 'm4v', 'webm'
  ];

  /**
   * 逐行解析输入文本，保留物理行号与输入顺序。
   *
   * 重复判定用**完整 URL 精确匹配**：查询参数和签名参与比较，所以同一路径带不同
   * token 的链接不会被误合并。重复行不进入 `urls`，只指向首次出现的行。
   */
  static parse(text: string): BatchLinkReport {
    const report: BatchLinkReport = new BatchLinkReport();
    const firstLine: Map<string, number> = new Map<string, number>();
    const lines: string[] = text.split(/\r?\n/);
    for (let index: number = 0; index < lines.length; index++) {
      const raw: string = lines[index].trim();
      if (raw.length === 0) { continue; }
      const row: BatchLinkRow = new BatchLinkRow();
      row.line = index + 1;
      row.url = raw;
      if (!BatchLinks.isHttpUrl(raw)) {
        row.status = BatchLinkStatus.INVALID;
        row.reason = BatchLinks.invalidUrlReason(raw);
      } else {
        const earlier: number | undefined = firstLine.get(raw);
        if (earlier !== undefined) {
          row.status = BatchLinkStatus.DUPLICATE;
          row.duplicateOf = earlier;
          row.reason = '与第 ' + earlier.toString() + ' 行重复';
        } else {
          firstLine.set(raw, row.line);
          BatchLinks.classifyUrl(row);
        }
      }
      report.rows.push(row);
    }
    return BatchLinks.recount(report);
  }

  /**
   * 把一个 HEAD 响应分类成图片 / 网页 / 未知。
   *
   * 只有 `text/html` 这种明确的网页类型才排除；403、405、3xx、5xx、超时、
   * 缺失或非图片的 Content-Type 一律保留为“未知，仍可导入”。
   */
  static checkOf(url: string, code: number, contentType: string, failed: boolean): BatchLinkCheck {
    const check: BatchLinkCheck = new BatchLinkCheck();
    check.url = url;
    const mime: string = contentType.toLowerCase().split(';')[0].trim();
    check.mime = mime;
    if (failed || code <= 0) {
      check.kind = BatchCheckKind.UNKNOWN;
      check.detail = '连接失败，仍可导入';
      return check;
    }
    if (code === 405 || code === 501) {
      check.kind = BatchCheckKind.UNKNOWN;
      check.detail = '服务器不支持预检，仍可导入';
      return check;
    }
    if (code >= 300 && code < 400) {
      check.kind = BatchCheckKind.UNKNOWN;
      check.detail = '服务器返回重定向，无法确认';
      return check;
    }
    if (code === 401 || code === 403) {
      check.kind = BatchCheckKind.UNKNOWN;
      check.detail = '需要登录或权限，仍可尝试';
      return check;
    }
    if (code === 404) {
      check.kind = BatchCheckKind.UNKNOWN;
      check.detail = '服务器返回 HTTP 404，仍可尝试';
      return check;
    }
    if (code < 200 || code >= 300) {
      check.kind = BatchCheckKind.UNKNOWN;
      check.detail = '服务器返回 HTTP ' + code.toString() + '，仍可尝试';
      return check;
    }
    if (mime.startsWith('image/')) {
      check.kind = BatchCheckKind.IMAGE;
      check.detail = '已确认图片 · ' + mime;
      return check;
    }
    if (mime === 'text/html' || mime === 'application/xhtml+xml') {
      check.kind = BatchCheckKind.PAGE;
      check.detail = '已确认网页，不导入';
      return check;
    }
    check.kind = BatchCheckKind.UNKNOWN;
    check.detail = mime.length > 0 ? '类型未确认（' + mime + '），仍可导入' : '类型未确认，仍可导入';
    return check;
  }

  /**
   * 把探测结果合并回解析结果。
   *
   * 只作用于当前 `pending` 行：图片 → valid，网页 → invalid，未知 → 保持 pending。
   * 输入对象不会被修改；已不在当前文本里的 URL 的旧 check 会被自然忽略。
   */
  static merge(report: BatchLinkReport, checks: BatchLinkCheck[]): BatchLinkReport {
    const byUrl: Map<string, BatchLinkCheck> = new Map<string, BatchLinkCheck>();
    for (const check of checks) {
      byUrl.set(check.url, check);
    }
    const merged: BatchLinkReport = new BatchLinkReport();
    for (const source of report.rows) {
      const row: BatchLinkRow = BatchLinks.copyRow(source);
      if (row.status === BatchLinkStatus.PENDING) {
        const check: BatchLinkCheck | undefined = byUrl.get(row.url);
        if (check !== undefined) {
          row.probed = true;
          row.mime = check.mime;
          row.reason = check.detail;
          if (check.kind === BatchCheckKind.IMAGE) {
            row.status = BatchLinkStatus.VALID;
          } else if (check.kind === BatchCheckKind.PAGE) {
            row.status = BatchLinkStatus.INVALID;
          } else {
            row.status = BatchLinkStatus.PENDING;
          }
        }
      }
      merged.rows.push(row);
    }
    return BatchLinks.recount(merged);
  }

  private static classifyUrl(row: BatchLinkRow): void {
    const kind: string = MediaFormat.mediaKindOf(row.url);
    if (kind === 'image') {
      row.status = BatchLinkStatus.VALID;
      row.reason = '图片直链';
      return;
    }
    if (kind === 'livephoto') {
      row.status = BatchLinkStatus.VALID;
      row.reason = '实况照片包';
      return;
    }
    const extension: string = MediaFormat.extensionOf(row.url);
    if (BatchLinks.NON_IMAGE_EXTENSIONS.includes(extension)) {
      row.status = BatchLinkStatus.INVALID;
      row.reason = '不支持 .' + extension + ' 类型';
      return;
    }
    row.status = BatchLinkStatus.PENDING;
    row.reason = extension.length === 0
      ? '无扩展名，确认时检测类型'
      : '扩展名未识别，确认时检测类型';
  }

  private static isHttpUrl(value: string): boolean {
    return /^https?:\/\/[^/?#\s]+(?:[/?#][^\s]*)?$/i.test(value);
  }

  private static invalidUrlReason(value: string): string {
    if (new RegExp('\\s').test(value)) {
      return '链接中不能有空格';
    }
    if (!/^https?:\/\//i.test(value)) {
      return '不是 HTTP(S) 链接';
    }
    return '链接格式不正确';
  }

  private static copyRow(row: BatchLinkRow): BatchLinkRow {
    const copy: BatchLinkRow = new BatchLinkRow();
    copy.line = row.line;
    copy.url = row.url;
    copy.status = row.status;
    copy.reason = row.reason;
    copy.duplicateOf = row.duplicateOf;
    copy.probed = row.probed;
    copy.mime = row.mime;
    return copy;
  }

  /** 重新计算计数与可导入列表；所有入口都走这里，避免计数和行状态漂移。 */
  private static recount(report: BatchLinkReport): BatchLinkReport {
    report.valid = 0;
    report.pending = 0;
    report.invalid = 0;
    report.duplicates = 0;
    report.urls = [];
    for (const row of report.rows) {
      if (row.status === BatchLinkStatus.VALID) {
        report.valid++;
        report.urls.push(row.url);
      } else if (row.status === BatchLinkStatus.PENDING) {
        report.pending++;
        report.urls.push(row.url);
      } else if (row.status === BatchLinkStatus.DUPLICATE) {
        report.duplicates++;
      } else {
        report.invalid++;
      }
    }
    return report;
  }
}
