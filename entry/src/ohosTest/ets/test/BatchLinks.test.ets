import { describe, it, expect } from '@ohos/hypium';
import {
  BatchCheckKind, BatchLinkCheck, BatchLinks, BatchLinkReport, BatchLinkRow, BatchLinkStatus
} from '../../../main/ets/service/BatchLinks';

function rowOf(report: BatchLinkReport, line: number): BatchLinkRow {
  const found: BatchLinkRow | undefined = report.rows.find((row: BatchLinkRow): boolean => row.line === line);
  if (found === undefined) {
    throw new Error('missing row ' + line.toString());
  }
  return found;
}

function checkOf(url: string, kind: string): BatchLinkCheck {
  const check: BatchLinkCheck = new BatchLinkCheck();
  check.url = url;
  check.kind = kind;
  if (kind === BatchCheckKind.IMAGE) {
    check.mime = 'image/png';
    check.detail = '已确认图片 · image/png';
  } else if (kind === BatchCheckKind.PAGE) {
    check.mime = 'text/html';
    check.detail = '网页，将解析其中的图片';
  } else {
    check.detail = '类型未确认，仍可导入';
  }
  return check;
}

export default function batchLinksTest() {
  describe('BatchLinks', () => {
    it('reports_each_row_status_reason_and_importable_order', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('https://a.example/a.jpg\n'
        + 'https://a.example/b.webp?token=1\nhttps://a.example/a.jpg\n'
        + 'ftp://a.example/c.png\nhttps://a.example/page.html\n'
        + 'https://a.example/noext\nhttps://a.example/pic.php?sign=1\n'
        + 'https://a.example/photo.png\n');
      expect(report.rows.length).assertEqual(8);
      expect(rowOf(report, 1).status).assertEqual(BatchLinkStatus.VALID);
      expect(rowOf(report, 1).reason).assertEqual('图片直链');
      expect(rowOf(report, 2).status).assertEqual(BatchLinkStatus.VALID);
      expect(rowOf(report, 3).status).assertEqual(BatchLinkStatus.DUPLICATE);
      expect(rowOf(report, 3).duplicateOf).assertEqual(1);
      expect(rowOf(report, 3).reason).assertEqual('与第 1 行重复');
      expect(rowOf(report, 4).status).assertEqual(BatchLinkStatus.INVALID);
      expect(rowOf(report, 4).reason).assertEqual('不是 HTTP(S) 链接');
      expect(rowOf(report, 5).status).assertEqual(BatchLinkStatus.PAGE);
      expect(rowOf(report, 5).reason).assertEqual('网页，将解析其中的图片');
      expect(rowOf(report, 6).status).assertEqual(BatchLinkStatus.PENDING);
      expect(rowOf(report, 6).reason).assertEqual('无扩展名，确认时检测类型');
      expect(rowOf(report, 7).status).assertEqual(BatchLinkStatus.PENDING);
      expect(rowOf(report, 7).reason).assertEqual('扩展名未识别，确认时检测类型');
      expect(rowOf(report, 8).status).assertEqual(BatchLinkStatus.VALID);
      expect(report.valid).assertEqual(3);
      expect(report.pending).assertEqual(2);
      expect(report.invalid).assertEqual(1);
      expect(report.pages).assertEqual(1);
      expect(report.duplicates).assertEqual(1);
      expect(report.urls.join(',')).assertEqual('https://a.example/a.jpg,'
        + 'https://a.example/b.webp?token=1,https://a.example/page.html,https://a.example/noext,'
        + 'https://a.example/pic.php?sign=1,https://a.example/photo.png');
    });

    it('keeps_live_photo_and_rejects_whitespace_inside_urls', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('  https://a.example/live.livp  \r\n'
        + 'https://a.example/bad name.png\n');
      expect(report.urls.length).assertEqual(1);
      expect(rowOf(report, 1).status).assertEqual(BatchLinkStatus.VALID);
      expect(rowOf(report, 1).reason).assertEqual('实况照片包');
      expect(report.invalid).assertEqual(1);
      expect(rowOf(report, 2).reason).assertEqual('链接中不能有空格');
    });

    it('treats_signed_unknown_and_extensionless_links_as_pending', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('https://cdn.example/image?id=42&sign=a\n'
        + 'https://cdn.example/image?id=42&sign=b\nhttps://cdn.example/dl.ashx\n'
        + 'https://cdn.example/archive.zip\n');
      expect(rowOf(report, 1).status).assertEqual(BatchLinkStatus.PENDING);
      expect(rowOf(report, 2).status).assertEqual(BatchLinkStatus.PENDING);
      expect(rowOf(report, 3).status).assertEqual(BatchLinkStatus.PENDING);
      expect(rowOf(report, 4).status).assertEqual(BatchLinkStatus.INVALID);
      expect(report.urls.length).assertEqual(3);
      expect(report.duplicates).assertEqual(0);
    });

    it('merges_head_checks_and_routes_confirmed_pages', 0, () => {
      const parsed: BatchLinkReport = BatchLinks.parse('https://a.example/noext\n'
        + 'https://a.example/page\nhttps://a.example/unknown\nhttps://a.example/a.jpg\n');
      const merged: BatchLinkReport = BatchLinks.merge(parsed, [
        checkOf('https://a.example/noext', BatchCheckKind.IMAGE),
        checkOf('https://a.example/page', BatchCheckKind.PAGE),
        checkOf('https://a.example/unknown', BatchCheckKind.UNKNOWN),
        checkOf('https://a.example/a.jpg', BatchCheckKind.PAGE)
      ]);
      expect(rowOf(merged, 1).status).assertEqual(BatchLinkStatus.VALID);
      expect(rowOf(merged, 1).probed).assertEqual(true);
      expect(rowOf(merged, 1).reason).assertEqual('已确认图片 · image/png');
      expect(rowOf(merged, 2).status).assertEqual(BatchLinkStatus.PAGE);
      expect(rowOf(merged, 2).reason).assertEqual('网页，将解析其中的图片');
      expect(rowOf(merged, 3).status).assertEqual(BatchLinkStatus.PENDING);
      expect(rowOf(merged, 3).reason).assertEqual('类型未确认，仍可导入');
      // 扩展名已经确定的 valid 行不因一条误发的 PAGE check 被排除。
      expect(rowOf(merged, 4).status).assertEqual(BatchLinkStatus.VALID);
      expect(merged.urls.join(',')).assertEqual('https://a.example/noext,'
        + 'https://a.example/page,https://a.example/unknown,https://a.example/a.jpg');
      expect(merged.valid).assertEqual(2);
      expect(merged.pending).assertEqual(1);
      expect(merged.invalid).assertEqual(0);
      expect(merged.pages).assertEqual(1);
    });

    it('ignores_stale_checks_and_keeps_input_unchanged', 0, () => {
      const parsed: BatchLinkReport = BatchLinks.parse('https://a.example/noext\n');
      const before: string = parsed.rows[0].status;
      const merged: BatchLinkReport = BatchLinks.merge(parsed, [
        checkOf('https://a.example/gone', BatchCheckKind.PAGE)
      ]);
      expect(parsed.rows[0].status).assertEqual(before);
      expect(merged.rows[0].status).assertEqual(BatchLinkStatus.PENDING);
      expect(merged.urls.length).assertEqual(1);
    });

    it('classifies_head_results_without_excluding_unknown_failures', 0, () => {
      const image: BatchLinkCheck = BatchLinks.checkOf('https://a.example/a', 200, 'image/png; charset=utf-8', false);
      expect(image.kind).assertEqual(BatchCheckKind.IMAGE);
      expect(image.mime).assertEqual('image/png');
      const page: BatchLinkCheck = BatchLinks.checkOf('https://a.example/p', 200, 'text/html', false);
      expect(page.kind).assertEqual(BatchCheckKind.PAGE);
      const binary: BatchLinkCheck = BatchLinks.checkOf('https://a.example/b', 200, 'application/octet-stream', false);
      expect(binary.kind).assertEqual(BatchCheckKind.UNKNOWN);
      const missing: BatchLinkCheck = BatchLinks.checkOf('https://a.example/m', 200, '', false);
      expect(missing.kind).assertEqual(BatchCheckKind.UNKNOWN);
      const headUnsupported: BatchLinkCheck = BatchLinks.checkOf('https://a.example/h', 405, '', false);
      expect(headUnsupported.kind).assertEqual(BatchCheckKind.UNKNOWN);
      expect(headUnsupported.detail).assertEqual('服务器不支持预检，仍可导入');
      const forbidden: BatchLinkCheck = BatchLinks.checkOf('https://a.example/f', 403, '', false);
      expect(forbidden.kind).assertEqual(BatchCheckKind.UNKNOWN);
      const redirect: BatchLinkCheck = BatchLinks.checkOf('https://a.example/r', 302, '', false);
      expect(redirect.kind).assertEqual(BatchCheckKind.UNKNOWN);
      const serverError: BatchLinkCheck = BatchLinks.checkOf('https://a.example/s', 500, '', false);
      expect(serverError.kind).assertEqual(BatchCheckKind.UNKNOWN);
      const failed: BatchLinkCheck = BatchLinks.checkOf('https://a.example/x', 0, '', true);
      expect(failed.kind).assertEqual(BatchCheckKind.UNKNOWN);
      expect(failed.detail).assertEqual('连接失败，仍可导入');
    });

    it('strips_encoded_line_breaks_copied_with_the_link', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('https://weibo.com/5571216925/RoKcM1STr%0A\n'
        + 'https://weibo.com/2453184077/RoKvs3RRL%0D%0A\n');
      expect(rowOf(report, 1).url).assertEqual('https://weibo.com/5571216925/RoKcM1STr');
      expect(rowOf(report, 2).url).assertEqual('https://weibo.com/2453184077/RoKvs3RRL');
      expect(report.rows.length).assertEqual(2);
      expect(report.pages).assertEqual(2);
      expect(report.urls.join(',')).assertEqual('https://weibo.com/5571216925/RoKcM1STr,'
        + 'https://weibo.com/2453184077/RoKvs3RRL');
    });

    it('keeps_duplicate_and_invalid_rows_out_of_the_import_list', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('https://a.example/noext\n'
        + 'https://a.example/noext\nhttps://a.example/noext?sign=1\n'
        + 'https://a.example/video.mp4\nhttps://a.example/doc.pdf\n');
      expect(report.rows.length).assertEqual(5);
      expect(report.urls.join(',')).assertEqual('https://a.example/noext,https://a.example/noext?sign=1');
      expect(report.pending).assertEqual(2);
      expect(report.duplicates).assertEqual(1);
      expect(report.invalid).assertEqual(2);
      expect(rowOf(report, 2).duplicateOf).assertEqual(1);
    });
  });
}
