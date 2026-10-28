import { DownloadItem } from '../model/Models';
import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditDocument, EditRect, EditResult, EditStroke, EditTicket, ImageEditorPort, PreviewSize } from '../model/ImageEditDocument';
import { DownloadStore } from '../service/DownloadStore';
import { EditExport } from '../service/EditExport';
import { EditJournal } from '../service/EditJournal';
import { LibraryImageReader } from '../service/LibraryImageReader';
import { Font, Palette, Space } from '../theme/Tokens';
import { SCREEN_INSETS } from '../theme/Metrics';
import { SheetStyle } from '../theme/SheetStyle';
import { TransparentGlass } from '../theme/TransparentGlass';
import { HdsColorPicker } from '@kit.UIDesignKit';
import { ImageEditorViewModel } from '../viewmodel/ImageEditorViewModel';
import { ImageEditorCanvas } from '../view/ImageEditorCanvas';
import { Glyph } from '../view/Icons';
import { PillButton } from '../view/Widgets';

interface ImageEditorParams { id?: string; }

class EditorRuntimePort implements ImageEditorPort {
  source: (id: string) => Promise<AssetStamp> = async (id: string): Promise<AssetStamp> => {
    throw new Error('编辑来源尚未就绪');
  };
  info: (stamp: AssetStamp) => Promise<PreviewSize> = async (stamp: AssetStamp): Promise<PreviewSize> => {
    throw new Error('图片尺寸尚未就绪');
  };
  exportAndRegister: (id: string, doc: EditDocument, token: AnalysisToken) => Promise<DownloadItem> =
    async (id: string, doc: EditDocument, token: AnalysisToken): Promise<DownloadItem> => {
      throw new Error('编辑导出尚未就绪');
    };
  showError: (message: string) => void = (message: string): void => {};
  finish: (newId: string) => void = (newId: string): void => {};
}

@Entry
@ComponentV2
struct ImageEditor {
  @Local private vm: ImageEditorViewModel = new ImageEditorViewModel();
  @Local private tool: string = 'crop';
  @Local private color: string = '#FF0000';
  @Local private customColor: string = '#FF0000';
  @Local private customSelected: boolean = false;
  @Local private colorDraft: string = '#FF0000';
  @Local private colorPickerOpen: boolean = false;
  @Local private penWidth: number = 4;
  @Local private notice: string = '';
  private leaving: boolean = false;
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.material();

  aboutToAppear(): void {
    const port: EditorRuntimePort = new EditorRuntimePort();
    port.source = (id: string): Promise<AssetStamp> => this.source(id);
    port.info = (stamp: AssetStamp): Promise<PreviewSize> => LibraryImageReader.info(stamp);
    port.exportAndRegister = (id: string, doc: EditDocument, token: AnalysisToken): Promise<DownloadItem> =>
      this.exportAndRegister(id, doc, token);
    port.showError = (message: string): void => { this.notice = message; };
    port.finish = (newId: string): void => {
      this.notice = '已保存编辑副本';
      this.leaving = true;
      this.getUIContext().getRouter().back();
    };
    this.vm.attach(port);
    const params: ImageEditorParams = this.getUIContext().getRouter().getParams() as ImageEditorParams;
    const id: string = params?.id ?? '';
    this.vm.load(id).catch((error: Error): void => {
      this.notice = '无法打开图片：' + error.message;
    });
  }

  aboutToDisappear(): void { this.vm.cancel(); }

  private async source(id: string): Promise<AssetStamp> {
    const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === id && entry.status === 'completed');
    if (item === undefined) { throw new Error('图片尚未下载或已删除'); }
    return LibraryImageReader.stamp(item);
  }

  private async exportAndRegister(id: string, doc: EditDocument,
    token: AnalysisToken): Promise<DownloadItem> {
    const stamp: AssetStamp = await this.source(id);
    const loaded: AssetStamp | undefined = this.vm.stamp;
    if (loaded === undefined || stamp.path !== loaded.path || stamp.bytes !== loaded.bytes ||
      stamp.modified !== loaded.modified || stamp.changed !== loaded.changed || token.cancelled) {
      throw new Error('原图已变化，请重新打开编辑');
    }
    const setting: string = DownloadStore.editQuality;
    const extension: string = await EditExport.extensionFor(stamp, setting);
    const ticket: EditTicket = await EditJournal.prepare(DownloadStore.context.filesDir,
      DownloadStore.nextId(), id, extension);
    try {
      const result: EditResult = await EditExport.render(stamp, doc, ticket.pendingPath, token, setting);
      if (token.cancelled) { throw new Error('编辑已取消'); }
      await EditJournal.finalize(ticket, result);
      if (token.cancelled) { throw new Error('编辑已取消'); }
      return await DownloadStore.registerEdited(id, ticket, result);
    } catch (error) {
      await EditJournal.rollback(ticket);
      throw new Error(String(error));
    }
  }

  private exit(): void {
    if (this.leaving) { return; }
    if (this.vm.saving) { this.notice = '正在保存编辑副本，请稍候'; return; }
    if (!this.vm.hasChanges) {
      this.leaving = true; this.vm.cancel(); this.getUIContext().getRouter().back(); return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃编辑？', message: '当前修改尚未保存。',
      backgroundColor: SheetStyle.background(),
      systemMaterial: SheetStyle.dialogMaterial(),
      primaryButton: { value: '继续编辑', action: (): void => {} },
      secondaryButton: { value: '放弃修改', action: (): void => {
        this.leaving = true; this.vm.cancel(); this.getUIContext().getRouter().back();
      } }
    });
  }

  onBackPress(): boolean {
    if (this.colorPickerOpen) { this.colorPickerOpen = false; return true; }
    this.exit();
    return true;
  }

  @Builder
  private iconAction(glyph: string, label: string, toolKey: string, action: () => void,
    destructive: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      Glyph({ glyph: glyph, glyphSize: 21,
        glyphTone: toolKey.length > 0 && this.tool === toolKey ? Palette.fontOnPrimary :
          (destructive ? Palette.warning : Palette.brand) })
    }
    .layoutWeight(1).height(44).borderRadius(22)
    .backgroundColor(toolKey.length > 0 && this.tool === toolKey ? Palette.brand :
      (destructive ? Palette.dangerBg : Palette.brandFaint))
    .accessibilityText(label).accessibilitySelected(toolKey.length > 0 && this.tool === toolKey)
    .onClick(action)
  }

  @Builder
  private colorButton(value: string, label: string) {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(28).height(28).fill(value)
        if (!this.customSelected && this.color === value) {
          Glyph({ glyph: 'check', glyphSize: 16, glyphTone: Color.White, glyphWeight: 2.2 })
        }
      }.width(36).height(36).borderRadius(18)
        .border({ width: !this.customSelected && this.color === value ? 2 : 0, color: Palette.brand })
    }
    .layoutWeight(1).height(44).backgroundColor(Color.Transparent)
    .accessibilityText(label).accessibilitySelected(!this.customSelected && this.color === value)
    .onClick((): void => { this.color = value; this.customSelected = false; })
  }

  private openColorPicker(): void {
    this.colorDraft = this.color;
    this.colorPickerOpen = true;
  }

  private openStrokeWidthPicker(): void {
    const widths: string[] = [];
    for (let value: number = 1; value <= 32; value++) { widths.push(value.toString() + ' px'); }
    this.getUIContext().showTextPickerDialog({
      range: widths,
      selected: this.penWidth - 1,
      canLoop: false,
      backgroundColor: SheetStyle.background(),
      systemMaterial: SheetStyle.dialogMaterial(),
      onAccept: (result: TextPickerResult): void => {
        const index: number = Array.isArray(result.index) ? result.index[0] : result.index;
        if (index >= 0 && index < widths.length) { this.penWidth = index + 1; }
      }
    });
  }

  @Builder
  private colorPickerContent() {
    Column({ space: Space.s12 }) {
      Text('自定义颜色').fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
        .width('100%')
      Row({ space: Space.s12 }) {
        HdsColorPicker({ initialColor: this.color,
          onColorSelected: (value: string): void => { this.colorDraft = value; } })
          .width(44).height(44)
        Text('点按色环选择颜色').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
          .layoutWeight(1)
        Circle().width(28).height(28).fill(this.colorDraft)
          .accessibilityText('待应用颜色')
      }.width('100%').height(48)
      Row({ space: Space.s8 }) {
        Column() {
          PillButton({ label: '取消', small: true, variant: 'tonal', block: true,
            onAction: (): void => { this.colorPickerOpen = false; } })
        }.layoutWeight(1)
        Column() {
          PillButton({ label: '确定', small: true, variant: 'primary', block: true,
            onAction: (): void => {
              this.customColor = this.colorDraft;
              this.color = this.colorDraft;
              this.customSelected = true;
              this.colorPickerOpen = false;
            } })
        }.layoutWeight(1)
      }.width('100%').justifyContent(FlexAlign.SpaceBetween)
    }.width('100%').padding({ left: Space.s16, right: Space.s16, top: Space.s20,
      bottom: SCREEN_INSETS.safeBottom + Space.s16 })
  }

  build() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        PillButton({ label: '返回', small: true, variant: 'tonal', onAction: (): void => { this.exit(); } })
        Text('编辑图片副本').fontSize(Font.body).fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary).layoutWeight(1)
        PillButton({ label: this.vm.saving ? '保存中…' : '保存副本', small: true, variant: 'primary',
          active: this.vm.ready && this.vm.hasChanges && !this.vm.saving,
          onAction: (): void => { this.vm.save(); } })
      }.width('100%').padding({ left: Space.s12, right: Space.s12,
        top: SCREEN_INSETS.safeTop + Space.s12 })

      if (this.vm.ready && this.vm.stamp !== undefined) {
        Row() {
          ImageEditorCanvas({ stamp: this.vm.stamp, document: this.vm.document,
            tool: this.tool, color: this.color, strokeWidth: this.penWidth,
            onCrop: (rect: EditRect): void => { this.vm.setCrop(rect); },
            onStroke: (stroke: EditStroke): void => { this.vm.addStroke(stroke); } })
            .width('100%').height('100%')
        }.layoutWeight(1).width('100%').padding({ left: 40, right: 40 })
      } else {
        Stack() {
          if (this.vm.loading) { LoadingProgress().width(28).height(28).color(Palette.brand) }
          else { Text(this.notice.length > 0 ? this.notice : '图片不可编辑').fontColor(Palette.fontSecondary) }
        }.layoutWeight(1).width('100%')
      }

      Scroll() {
        Column({ space: Space.s8 }) {
          Row({ space: Space.s4 }) {
            this.iconAction('crop', '裁剪', 'crop', (): void => { this.tool = 'crop'; })
            this.iconAction('brush', '画笔', 'pen', (): void => { this.tool = 'pen'; })
            this.iconAction('rectangle', '矩形', 'rectangle',
              (): void => { this.tool = 'rectangle'; })
            this.iconAction('rotateLeft', '旋转 90 度', '', (): void => { this.vm.rotate(); })
            this.iconAction('undo', '撤销', '', (): void => { this.vm.undo(); })
            if (this.tool === 'crop') {
              this.iconAction('retry', '重置裁剪', '', (): void => { this.vm.restoreCrop(); })
            } else {
              this.iconAction('trash', '清空标注', '', (): void => { this.vm.clearStrokes(); }, true)
            }
          }.width('100%')
          if (this.tool === 'crop') {
            Row({ space: Space.s8 }) {
              Column() {
                PillButton({ label: '原比例', small: true, variant: 'tonal', block: true,
                  onAction: (): void => { this.vm.setAspect(0); } })
              }.layoutWeight(1)
              Column() {
                PillButton({ label: '1:1', small: true, variant: 'tonal', block: true,
                  onAction: (): void => { this.vm.setAspect(1); } })
              }.layoutWeight(1)
              Column() {
                PillButton({ label: '4:3', small: true, variant: 'tonal', block: true,
                  onAction: (): void => { this.vm.setAspect(4 / 3); } })
              }.layoutWeight(1)
            }.width('100%')
          } else {
            Row({ space: Space.s4 }) {
              this.colorButton('#FF0000', '红色')
              this.colorButton('#0066FF', '蓝色')
              this.colorButton('#000000', '黑色')
              Button({ type: ButtonType.Circle }) {
                Stack({ alignContent: Alignment.Center }) {
                  Glyph({ glyph: 'palette', glyphSize: 22, glyphTone: Palette.brand })
                  Circle().width(9).height(9).fill(this.customColor)
                    .position({ x: 24, y: 24 })
                }.width(36).height(36).borderRadius(18)
                  .border({ width: this.customSelected ? 2 : 0, color: Palette.brand })
              }
              .layoutWeight(1).height(44).backgroundColor(Color.Transparent)
              .accessibilityText('自定义颜色').accessibilitySelected(this.customSelected)
              .onClick((): void => { this.openColorPicker(); })
              Button({ type: ButtonType.Normal }) {
                Text(this.penWidth.toString() + ' px').fontSize(Font.aux).fontWeight(FontWeight.Bold)
                  .fontColor(Palette.brand)
              }
              .width(72).height(44).borderRadius(22).backgroundColor(Palette.brandFaint)
              .accessibilityText('线宽 ' + this.penWidth.toString() + ' 像素，打开滚轮选择')
              .onClick((): void => { this.openStrokeWidthPicker(); })
            }.width('100%')
          }
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(Font.caption).fontColor(Palette.fontSecondary)
          }
        }.width('100%').padding({ left: Space.s12, right: Space.s12,
          bottom: SCREEN_INSETS.safeBottom + Space.s8 })
      }.width('100%').constraintSize({ maxHeight: 180 })
    }
    .width('100%').height('100%').backgroundColor(Palette.bg)
    .bindSheet(this.colorPickerOpen, this.colorPickerContent(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: SheetStyle.background(),
      systemMaterial: this.sheetMaterial,
      onDisappear: (): void => { this.colorPickerOpen = false; }
    })
  }
}
