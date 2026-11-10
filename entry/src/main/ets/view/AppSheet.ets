import { SheetStyle } from '../theme/SheetStyle';
import { DownloadStore } from '../service/DownloadStore';

/** 统一的半模态宿主。放在页面 Stack 内，与页面内容同级。 */
@ComponentV2
export struct AppSheet {
  @Param visible: boolean = false;
  @Param initialSize: SheetSize | Length = SheetSize.MEDIUM;
  @Param detents: [SheetSize | Length, SheetSize | Length, SheetSize | Length] | undefined = undefined;
  @Param showClose: boolean = false;
  @Param dragBar: boolean = true;
  @Param useMaterial: boolean = true;
  @Param opaqueBackground: boolean = false;
  @Param scrollSizeMode: ScrollSizeMode | undefined = undefined;
  @Event onDismiss: () => void = (): void => {};
  @Event onShown: () => void = (): void => {};
  @Event onWillDismiss: (action: DismissSheetAction) => void = (action: DismissSheetAction): void => {
    action.dismiss();
  };

  @Builder
  emptyContent() {}

  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  private sheetContent() {
    this.content()
  }

  private sheetDetents(): [SheetSize | Length, SheetSize | Length, SheetSize | Length] {
    if (this.detents !== undefined) { return this.detents; }
    if (this.initialSize === SheetSize.LARGE) { return [SheetSize.LARGE, SheetSize.MEDIUM, 320]; }
    if (this.initialSize === SheetSize.MEDIUM) { return [SheetSize.MEDIUM, SheetSize.LARGE, 320]; }
    return [this.initialSize, SheetSize.MEDIUM, SheetSize.LARGE];
  }

  private options(): SheetOptions {
    const immersiveOn: boolean = this.useMaterial && DownloadStore.lightEffect
      && DownloadStore.materialType !== 'none';
    const material: SystemUiMaterial | undefined = SheetStyle.material(immersiveOn);
    return {
      detents: this.sheetDetents(),
      dragBar: this.dragBar,
      showClose: this.showClose,
      scrollSizeMode: this.scrollSizeMode,
      backgroundColor: SheetStyle.sheetBackground(material, immersiveOn, this.opaqueBackground),
      systemMaterial: material,
      onWillDismiss: (action: DismissSheetAction): void => { this.onWillDismiss(action); },
      onAppear: (): void => { this.onShown(); },
      onDisappear: (): void => { this.onDismiss(); }
    };
  }

  build() {
    Stack()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .bindSheet(this.visible, this.sheetContent(), this.options())
  }
}
