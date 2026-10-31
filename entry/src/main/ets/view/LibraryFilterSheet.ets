import { TransparentGlass } from '../theme/TransparentGlass';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { CollectionSummary } from '../service/CollectionGroups';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { PillButton, SettingSelect } from './Widgets';

const SORT_IDS: string[] = ['newest', 'name', 'size'];
const SORT_LABELS: string[] = ['时间', '名称', '大小'];
const SORT_OPTIONS: SelectOption[] = SORT_LABELS.map((label: string): SelectOption => ({ value: label }));
const FORMAT_IDS: string[] = ['', 'jpg', 'png', 'gif', 'webp', 'heic', 'avif'];
const FORMAT_LABELS: string[] = ['全部格式', 'JPEG', 'PNG', 'GIF', 'WebP', 'HEIC', 'AVIF'];
const FORMAT_OPTIONS: SelectOption[] = FORMAT_LABELS.map((label: string): SelectOption => ({ value: label }));
const SEARCH_SCOPES: string[] = ['all', 'name', 'text', 'tags'];
const SEARCH_LABELS: string[] = ['全部', '文件名', '图片文字', '标签'];

/** 图库的次级筛选项；搜索关键词仍留在首页。 */
@ComponentV2
export struct LibraryFilterSheet {
  @Require @Param library: LibraryViewModel;

  private collectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部来源' }];
    for (const group of this.library.collections) { options.push({ value: group.name }); }
    return options;
  }

  private sortFieldIndex(): number {
    if (this.library.sortOrder === 'name' || this.library.sortOrder === 'nameDesc') { return 1; }
    if (this.library.sortOrder === 'size' || this.library.sortOrder === 'sizeAsc') { return 2; }
    return 0;
  }

  private sortDirectionLabel(): string {
    switch (this.library.sortOrder) {
      case 'oldest': return '旧→新';
      case 'name': return '正序';
      case 'nameDesc': return '倒序';
      case 'size': return '大→小';
      case 'sizeAsc': return '小→大';
      default: return '新→旧';
    }
  }

  private toggleSortDirection(): void {
    switch (this.library.sortOrder) {
      case 'newest': this.library.sortOrder = 'oldest'; break;
      case 'oldest': this.library.sortOrder = 'newest'; break;
      case 'name': this.library.sortOrder = 'nameDesc'; break;
      case 'nameDesc': this.library.sortOrder = 'name'; break;
      case 'size': this.library.sortOrder = 'sizeAsc'; break;
      case 'sizeAsc': this.library.sortOrder = 'size'; break;
      default: this.library.sortOrder = 'newest'; break;
    }
  }

  build() {
    Column({ space: Space.s16 }) {
      Row({ space: Space.s8 }) {
        Text('排序').fontSize(Font.body).fontColor(TransparentGlass.foreground()).layoutWeight(1)
        SettingSelect({
          options: SORT_OPTIONS,
          selectedIndex: this.sortFieldIndex(),
          label: SORT_LABELS[this.sortFieldIndex()],
          onPick: (index: number): void => { this.library.sortOrder = SORT_IDS[index]; }
        })
        PillButton({ label: this.sortDirectionLabel(), small: true, variant: 'ghost',
          onAction: (): void => { this.toggleSortDirection(); } })
      }.width('100%')

      Row({ space: Space.s8 }) {
        Text('来源分组').fontSize(Font.body).fontColor(TransparentGlass.foreground()).layoutWeight(1)
        SettingSelect({
          options: this.collectionOptions(),
          selectedIndex: this.library.collectionFilter === '*' ? 0
            : this.library.collections.findIndex((group: CollectionSummary): boolean =>
              group.id === this.library.collectionFilter) + 1,
          label: this.library.collections.find((group: CollectionSummary): boolean =>
            group.id === this.library.collectionFilter)?.name ?? '全部来源',
          onPick: (index: number): void => {
            this.library.collectionFilter = index === 0 ? '*' : this.library.collections[index - 1].id;
          }
        })
      }.width('100%')

      if (!this.library.isZips()) {
        Row({ space: Space.s8 }) {
          Text('格式').fontSize(Font.body).fontColor(TransparentGlass.foreground()).layoutWeight(1)
          SettingSelect({
            options: FORMAT_OPTIONS,
            selectedIndex: FORMAT_IDS.indexOf(this.library.formatFilter),
            label: FORMAT_LABELS[FORMAT_IDS.indexOf(this.library.formatFilter)],
            onPick: (index: number): void => { this.library.formatFilter = FORMAT_IDS[index]; }
          })
        }.width('100%')

        Text('搜索范围').fontSize(Font.body).fontColor(TransparentGlass.foreground())
        Row({ space: Space.s6 }) {
          ForEach(SEARCH_SCOPES, (scope: string, index: number) => {
            PillButton({ label: SEARCH_LABELS[index], small: true,
              variant: this.library.searchScope === scope ? 'primary' : 'ghost',
              onAction: (): void => { this.library.searchScope = scope; } })
          }, (scope: string) => scope)
        }.width('100%')

        TextInput({ placeholder: '按来源网页搜索', text: this.library.sourceQuery })
          .fontSize(Font.aux).fontColor(TransparentGlass.foreground())
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4).width('100%')
          .onChange((value: string): void => { this.library.sourceQuery = value; })
        TextInput({ placeholder: '按标签筛选', text: this.library.tagFilter })
          .fontSize(Font.aux).fontColor(TransparentGlass.foreground())
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4).width('100%')
          .onChange((value: string): void => { this.library.tagFilter = value; })

        Row({ space: Space.s8 }) {
          PillButton({ label: this.library.favoritesOnly ? '仅收藏 ✓' : '仅收藏', small: true,
            variant: this.library.favoritesOnly ? 'primary' : 'ghost',
            onAction: (): void => { this.library.favoritesOnly = !this.library.favoritesOnly; } })
          PillButton({ label: this.library.density === 2 ? '两列' : '三列', small: true,
            variant: 'ghost',
            onAction: (): void => { this.library.setDensity(this.library.density === 2 ? 3 : 2); } })
        }.width('100%')
      }

      PillButton({ label: '重置筛选', small: true, variant: 'ghost',
        onAction: (): void => { this.library.resetOptions(); } })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
