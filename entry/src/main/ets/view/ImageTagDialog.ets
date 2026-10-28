import { TransparentGlass } from '../theme/TransparentGlass';
import { LibraryText } from '../util/LibraryText';
import { Font, Palette, Space } from '../theme/Tokens';
import { SCREEN_INSETS } from '../theme/Metrics';
import { PillButton } from './Widgets';

@ComponentV2
export struct ImageTagDialog {
  @Param current: string[] = [];
  @Param single: boolean = true;
  @Event onSave: (add: string[], remove: string[]) => void =
    (add: string[], remove: string[]): void => {};
  @Event onClose: () => void = (): void => {};
  @Local private addDraft: string = '';
  @Local private removeDraft: string = '';

  aboutToAppear(): void {
    this.addDraft = this.single ? this.current.join('，') : '';
    this.removeDraft = '';
  }

  private words(value: string): string[] {
    return LibraryText.tags(value.split(/[，,\n]+/));
  }

  private apply(): void {
    const add: string[] = this.words(this.addDraft);
    if (!this.single) {
      this.onSave(add, this.words(this.removeDraft));
      return;
    }
    const removed: string[] = this.current.filter((tag: string): boolean =>
      !add.some((value: string): boolean => LibraryText.normalize(value) === LibraryText.normalize(tag)));
    this.onSave(add, removed);
  }

  build() {
    Column({ space: Space.s12 }) {
      Text(this.single ? '编辑图片标签' : '批量编辑标签')
        .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
      Text(this.single ? '用逗号分隔标签，删除输入中的标签即移除。'
        : '可同时添加和移除标签，不会删除图片。')
        .fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      TextInput({ placeholder: this.single ? '输入标签' : '添加标签', text: this.addDraft })
        .fontSize(Font.body).fontColor(TransparentGlass.foreground())
        .onChange((value: string): void => { this.addDraft = value; })
      if (!this.single) {
        TextInput({ placeholder: '移除标签（可留空）', text: this.removeDraft })
          .fontSize(Font.body).fontColor(TransparentGlass.foreground())
          .onChange((value: string): void => { this.removeDraft = value; })
      }
      Row({ space: Space.s8 }) {
        PillButton({ label: '取消', variant: 'ghost', onAction: this.onClose })
        PillButton({ label: '保存', variant: 'primary', onAction: (): void => { this.apply(); } })
      }.justifyContent(FlexAlign.End).width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.s16, right: Space.s16, top: Space.s16,
      bottom: SCREEN_INSETS.safeBottom + Space.s16 })
    .width('100%')
  }
}
