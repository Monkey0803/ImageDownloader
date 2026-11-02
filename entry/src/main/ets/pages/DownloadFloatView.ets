import { FLOAT_DOWNLOAD_STATE } from '../service/FloatDownload';
import { Palette } from '../theme/Tokens';

@Entry
@ComponentV2
struct DownloadFloatView {
  private state = FLOAT_DOWNLOAD_STATE;

  build() {
    Column({ space: 6 }) {
      Text(this.state.status + ' · ' + this.state.count + ' 项待处理')
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(Palette.fontPrimary).width('100%')
      if (this.state.name.length > 0) {
        Text(this.state.name).fontSize(15).fontColor(Palette.fontPrimary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      if (this.state.progress.length > 0) {
        if (this.state.progress.endsWith('%')) {
          Progress({ value: this.state.percent, total: 100, type: ProgressType.Linear })
            .color(Palette.brand).width('100%')
        }
        Text(this.state.progress).fontSize(12).fontColor(Palette.fontSecondary).width('100%')
      }
    }.padding({ top: 40, left: 16, right: 16, bottom: 8 })
      .width('100%').height('100%').backgroundColor(Palette.card)
  }
}
