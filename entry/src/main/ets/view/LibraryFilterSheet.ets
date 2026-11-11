import { TransparentGlass } from '../theme/TransparentGlass';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { CollectionSummary } from '../service/CollectionGroups';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { PillButton, SettingSelect } from './Widgets';
import { AppSegmentButton, segmentCapsuleWidth } from './AppSegmentButton';
import { AppSearch } from './AppSearch';
import { Glyph } from './Icons';

const SORT_IDS: string[] = ['newest', 'name', 'size'];
const SORT_LABELS: string[] = ['时间', '名称', '大小'];
const SORT_OPTIONS: SelectOption[] = SORT_LABELS.map((label: string): SelectOption => ({ value: label }));
const FORMAT_IDS: string[] = ['', 'jpg', 'png', 'gif', 'webp', 'heic', 'avif'];
const FORMAT_LABELS: string[] = ['全部格式', 'JPEG', 'PNG', 'GIF', 'WebP', 'HEIC', 'AVIF'];
const FORMAT_OPTIONS: SelectOption[] = FORMAT_LABELS.map((label: string): SelectOption => ({ value: label }));
const SEARCH_SCOPES: string[] = ['all', 'name', 'text', 'tags'];
const SEARCH_LABELS: string[] = ['全部', '文件名', '图片文字', '标签'];
const LAYOUT_LABELS: string[] = ['瀑布流', '三列方形'];

/** 图库的次级筛选项；搜索关键词仍留在首页。 */
@ComponentV2
export struct LibraryFilterSheet {
  @Require @Param library: LibraryViewModel;
  /** 相册 / 最近删除 / 查找与整理：都只是换面板内容，由页面持有 sheet 状态。 */
  @Event onOpenAlbums: () => void = (): void => {};
  @Event onOpenTrash: () => void = (): void => {};
  @Event onOpenOrganize: () => void = (): void => {};

  private collectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部来源' }];
    for (const group of this.library.collections) { options.push({ value: this.library.collectionLabel(group) }); }
    return options;
  }

  private selectedCollectionLabel(): string {
    const current: CollectionSummary | undefined = this.library.collections.find(
      (group: CollectionSummary): boolean => group.id === this.library.collectionFilter);
    return current === undefined ? '全部来源' : this.library.collectionLabel(current);
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

  /** 面板内的跳转行：把原来占首页一整排的入口收进来。 */
  @Builder
  private navRow(glyph: string, label: string, value: string, action: () => void) {
    Row({ space: Space.s10 }) {
      Stack() {
        Glyph({ glyph: glyph, glyphSize: 18, glyphTone: Palette.brand, glyphWeight: 1.7 })
      }
      .width(32).height(32).borderRadius(Radius.r8).backgroundColor(Palette.brandFaint)
      Text(label).fontSize(Font.body).fontColor(TransparentGlass.foreground()).layoutWeight(1)
      Text(value).fontSize(Font.caption).fontColor(Palette.fontTertiary).maxLines(1)
      Glyph({ glyph: 'chevronRight', glyphSize: 16, glyphTone: Palette.fontTertiary })
    }
    .width('100%')
    .height(44)
    .onClick((): void => { action(); })
    .accessibilityText(label + '，' + value)
  }

  build() {
    Column({ space: Space.s16 }) {
      this.navRow('image', '相册', this.library.albums.length.toString() + ' 个',
        (): void => { this.onOpenAlbums(); })
      this.navRow('trash', '最近删除', this.library.trashEntries.length.toString() + ' 项',
        (): void => { this.onOpenTrash(); })
      this.navRow('list', '查找与整理', '文字索引 · 重复 · 相似',
        (): void => { this.onOpenOrganize(); })

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
          label: this.selectedCollectionLabel(),
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
        AppSegmentButton({
          labels: SEARCH_LABELS,
          selectedIndex: Math.max(0, SEARCH_SCOPES.indexOf(this.library.searchScope)),
          config: { dense: true, width: segmentCapsuleWidth(SEARCH_LABELS, Font.caption, Space.s12) },
          onSelectedIndexChange: (index: number): void => {
            this.library.searchScope = SEARCH_SCOPES[index];
          }
        })

        AppSearch({ placeholder: '按来源网页搜索', text: this.library.sourceQuery,
          useImmersiveMaterial: true,
          onChange: (value: string): void => { this.library.sourceQuery = value; } })
        AppSearch({ placeholder: '按标签筛选', text: this.library.tagFilter,
          useImmersiveMaterial: true,
          onChange: (value: string): void => { this.library.tagFilter = value; } })

        Row({ space: Space.s8 }) {
          PillButton({ label: this.library.favoritesOnly ? '仅收藏 ✓' : '仅收藏', small: true,
            variant: this.library.favoritesOnly ? 'primary' : 'ghost',
            onAction: (): void => { this.library.favoritesOnly = !this.library.favoritesOnly; } })
          Blank()
          AppSegmentButton({
            labels: LAYOUT_LABELS,
            selectedIndex: this.library.squareTiles() ? 1 : 0,
            config: { dense: true, width: segmentCapsuleWidth(LAYOUT_LABELS, Font.caption, Space.s12) },
            onSelectedIndexChange: (index: number): void => {
              this.library.setGridStyle(index === 0 ? 'masonry' : 'square');
            }
          })
        }.width('100%')
      }

      PillButton({ label: '重置筛选', small: true, variant: 'ghost',
        onAction: (): void => { this.library.resetOptions(); } })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
