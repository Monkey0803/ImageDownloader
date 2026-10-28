import { fileUri } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';
import { SimilarGroup } from '../model/LibraryAsset';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { PillButton } from './Widgets';
import { Thumb } from './Thumb';

const SCOPES: string[] = ['current', 'selected', 'all'];
const LABELS: string[] = ['当前结果', '已选图片', '全部图片'];

/** Candidate groups are shown for review; opening a group is the only navigation action. */
@ComponentV2
export struct LibrarySimilarPanel {
  @Require @Param library: LibraryViewModel;
  @Event onOpenGroup: () => void = (): void => {};

  private picturePath(item: DownloadItem): string {
    return item.kind === 'livephoto' ? item.stillPath : item.path;
  }

  @Builder
  private groupRow(group: SimilarGroup) {
    Row({ space: Space.s10 }) {
      if (this.library.similarItem(group.representativeId) !== undefined) {
        Thumb({ src: fileUri.getUriFromPath(this.picturePath(
          this.library.similarItem(group.representativeId)!)), fit: ImageFit.Cover,
          firstFramePath: this.library.similarItem(group.representativeId)?.animated ?
            this.picturePath(this.library.similarItem(group.representativeId)!) : '' })
          .width(60).height(60).borderRadius(Radius.r4)
      }
      Column({ space: Space.s4 }) {
        Text(group.ids.length.toString() + ' 张相似图片')
          .fontSize(Font.aux).fontWeight(FontWeight.Medium).fontColor(Palette.fontPrimary)
        Text(group.ids.map((id: string): string => {
          const item: DownloadItem | undefined = this.library.similarItem(id);
          return item === undefined ? '已移除' : item.name + ' · ' + this.library.similarSize(id);
        }).join('、')).fontSize(Font.caption).fontColor(Palette.fontSecondary)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      PillButton({ label: '查看本组', small: true, variant: 'tonal',
        onAction: (): void => {
          this.onOpenGroup();
          this.library.openSimilarGroup(group);
        } })
    }.width('100%').padding({ top: Space.s8, bottom: Space.s8 })
  }

  build() {
    Column({ space: Space.s8 }) {
      Text('相似图片候选').fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.fontPrimary)
      Text('比较画面、颜色与比例；动图取首帧，实况照片取封面。结果仅供查看，不会删除文件。')
        .fontSize(Font.caption).fontColor(Palette.fontSecondary)
      Row({ space: Space.s6 }) {
        ForEach(SCOPES, (scope: string, index: number) => {
          PillButton({ label: LABELS[index], small: true,
            variant: this.library.similarScope === scope ? 'primary' : 'ghost',
            onAction: (): void => { this.library.similarScope = scope; } })
        }, (scope: string) => scope)
      }.width('100%')
      Row({ space: Space.s6 }) {
        PillButton({ label: this.library.similarAnalyzing ? '检查中…' : '开始检查', small: true,
          variant: 'primary', active: !this.library.similarAnalyzing,
          onAction: (): void => { this.library.startSimilar(this.library.similarScope); } })
        if (this.library.similarAnalyzing) {
          PillButton({ label: '取消', small: true, variant: 'ghost',
            onAction: (): void => { this.library.cancelSimilar(); } })
        }
      }.width('100%')
      if (this.library.similarAnalyzing || this.library.similarChecked) {
        Text('已检查 ' + this.library.similarProgress.done.toString() + ' / '
          + this.library.similarProgress.total.toString() + '，失败 '
          + this.library.similarProgress.failed.toString())
          .fontSize(Font.caption).fontColor(Palette.fontSecondary)
      }
      if (this.library.similarNotice.length > 0) {
        Text(this.library.similarNotice).fontSize(Font.caption).fontColor(Palette.fontSecondary)
      }
      if (this.library.similarChecked) {
        ForEach(this.library.similarGroups, (group: SimilarGroup) => {
          this.groupRow(group)
        }, (group: SimilarGroup) => group.representativeId)
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
