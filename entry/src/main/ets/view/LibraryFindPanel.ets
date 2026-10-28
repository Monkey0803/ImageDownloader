import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { LibrarySearchEntry } from '../model/LibraryAsset';
import { Font, Palette, Space } from '../theme/Tokens';
import { PillButton } from './Widgets';

const OCR_SCOPES: string[] = ['current', 'selected', 'all'];
const OCR_SCOPE_LABELS: string[] = ['当前结果', '已选图片', '全部图片'];

@ComponentV2
export struct LibraryFindPanel {
  @Require @Param library: LibraryViewModel;

  build() {
    Column({ space: Space.s10 }) {
      Text('文字索引').fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.fontPrimary)
      if (!this.library.catalogReady) {
        Text(this.library.catalogError.length > 0 ? this.library.catalogError : '正在读取整理信息…')
          .fontSize(Font.caption).fontColor(Palette.fontSecondary)
        if (this.library.catalogError.length > 0) {
          PillButton({ label: '重新读取', small: true, variant: 'ghost',
            onAction: (): void => { this.library.retryCatalog(); } })
        }
      } else {
        Text('已建立文字索引 ' + this.library.catalogEntries.filter((entry: LibrarySearchEntry): boolean =>
          entry.ocrStatus === 'ready' || entry.ocrStatus === 'empty').length.toString()
          + ' / ' + this.library.imageCount.toString())
          .fontSize(Font.caption).fontColor(Palette.fontSecondary)
        Text('识别范围').fontSize(Font.caption).fontColor(Palette.fontSecondary)
        Row({ space: Space.s6 }) {
          ForEach(OCR_SCOPES, (scope: string, index: number) => {
            PillButton({ label: OCR_SCOPE_LABELS[index], small: true,
              variant: this.library.ocrScope === scope ? 'primary' : 'ghost',
              onAction: (): void => { this.library.ocrScope = scope; } })
          }, (scope: string) => scope)
        }.width('100%')
        Row({ space: Space.s6 }) {
          PillButton({ label: this.library.ocrAnalyzing ? '识别中…' : '建立文字索引', small: true,
            variant: 'primary', active: !this.library.ocrAnalyzing,
            onAction: (): void => { this.library.startOcr(this.library.ocrScope, false); } })
          if (this.library.ocrAnalyzing) {
            PillButton({ label: '取消', small: true, variant: 'ghost',
              onAction: (): void => { this.library.cancelAnalysis(); } })
          }
        }.width('100%')
        Row({ space: Space.s6 }) {
          PillButton({ label: '重试失败', small: true, variant: 'ghost',
            active: !this.library.ocrAnalyzing,
            onAction: (): void => { this.library.retryFailedOcr(); } })
          PillButton({ label: '重建索引', small: true, variant: 'ghost',
            active: !this.library.ocrAnalyzing,
            onAction: (): void => { this.library.startOcr(this.library.ocrScope, true); } })
          PillButton({ label: '清空文字', small: true, variant: 'ghost',
            onAction: (): void => { this.library.clearTextIndex(); } })
        }.width('100%')
        if (this.library.ocrAnalyzing || this.library.ocrProgress.total > 0) {
          Text('进度 ' + this.library.ocrProgress.done.toString() + ' / '
            + this.library.ocrProgress.total.toString() + '，失败 '
            + this.library.ocrProgress.failed.toString())
            .fontSize(Font.caption).fontColor(Palette.fontSecondary)
        }
        if (this.library.ocrNotice.length > 0) {
          Text(this.library.ocrNotice).fontSize(Font.caption).fontColor(Palette.fontSecondary)
        } else if (this.library.ocrFailureReason().length > 0) {
          Text('上次失败原因：' + this.library.ocrFailureReason())
            .fontSize(Font.caption).fontColor(Palette.fontSecondary)
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
