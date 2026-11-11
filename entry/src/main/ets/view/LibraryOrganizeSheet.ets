import { TransparentGlass } from '../theme/TransparentGlass';
import { DownloadItem } from '../model/Models';
import { DuplicateGroup } from '../service/DuplicateFinder';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { Font, formatBytes, Palette, Space } from '../theme/Tokens';
import { LibraryFindPanel } from './LibraryFindPanel';
import { LibrarySimilarPanel } from './LibrarySimilarPanel';
import { PillButton } from './Widgets';
import { AppSegmentButton, segmentCapsuleWidth } from './AppSegmentButton';

const SECTION_IDS: string[] = ['text', 'duplicates', 'similar'];
const SECTION_LABELS: string[] = ['文字索引', '重复图片', '相似图片'];

@ComponentV2
export struct LibraryOrganizeSheet {
  @Require @Param library: LibraryViewModel;
  @Event onOpenGroup: () => void = (): void => {};
  @Local private section: string = 'text';

  @Builder
  private duplicateSection(title: string, groups: DuplicateGroup[], showKey: boolean) {
    Text(title + ' · ' + groups.length.toString() + ' 组')
      .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
    if (groups.length === 0) {
      Text('未发现').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
    } else {
      ForEach(groups, (group: DuplicateGroup) => {
        Column({ space: Space.s4 }) {
          Text((showKey ? group.key : 'SHA-256 一致') + ' · ' + group.items.length.toString() + ' 张')
            .fontSize(Font.aux).fontColor(TransparentGlass.foreground())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(group.items.map((item: DownloadItem): string => item.name).join('、'))
            .fontSize(Font.caption).fontColor(TransparentGlass.secondary())
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          PillButton({ label: '查看本组', small: true, variant: 'tonal',
            onAction: (): void => { this.library.openDuplicateGroup(group); this.onOpenGroup(); } })
        }.alignItems(HorizontalAlign.Start).width('100%')
          .padding({ top: Space.s6, bottom: Space.s6 })
      }, (group: DuplicateGroup) => group.key)
    }
  }

  @Builder
  private duplicates() {
    Column({ space: Space.s8 }) {
      Text('同来源地址、同来源文件名不代表文件内容相同。检查结果不会自动删除文件。')
        .fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      this.duplicateSection('同来源 URL', this.library.sameUrlGroups, true)
      this.duplicateSection('同来源文件名', this.library.sameSourceNameGroups, true)
      PillButton({ label: this.library.contentAnalyzing ? '正在检查…' : '检查文件内容',
        variant: 'tonal', small: true, active: !this.library.contentAnalyzing,
        onAction: (): void => { this.library.analyzeContent(); } })
      if (this.library.contentAnalyzing) {
        Text(this.library.contentProgress).fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      }
      if (this.library.contentChecked) {
        this.duplicateSection('文件内容一致', this.library.contentReport.groups, false)
        Text('检查 ' + this.library.contentReport.candidates.toString() + ' 个同大小候选，合计 '
          + formatBytes(this.library.contentReport.bytes) + '，耗时 '
          + (this.library.contentReport.elapsedMs / 1000).toFixed(2) + ' 秒；'
          + this.library.contentReport.failures.toString() + ' 个文件无法读取。')
          .fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: Space.s16 }) {
      AppSegmentButton({
        labels: SECTION_LABELS,
        selectedIndex: SECTION_IDS.indexOf(this.section),
        config: { dense: true, width: segmentCapsuleWidth(SECTION_LABELS, Font.caption, Space.s12) },
        onSelectedIndexChange: (index: number): void => {
          this.section = SECTION_IDS[index];
        }
      })
      if (this.section === 'text') {
        LibraryFindPanel({ library: this.library })
      } else if (this.section === 'duplicates') {
        this.duplicates()
      } else {
        LibrarySimilarPanel({ library: this.library, onOpenGroup: this.onOpenGroup })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
