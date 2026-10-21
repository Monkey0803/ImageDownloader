import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { WidgetForms } from '../widget/WidgetForms';
import { WidgetSnapshot } from '../widget/WidgetSnapshot';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id: string = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string ?? '';
    const dimension: number = want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number;
    const layout: string = dimension === formInfo.FormDimension.Dimension_2_2 ? 'compact' : 'wide';
    WidgetForms.add(this.context.filesDir, id, layout);
    const snapshot: WidgetSnapshot = WidgetForms.readSnapshot(this.context.filesDir);
    snapshot.layout = layout;
    return formBindingData.createFormBindingData(snapshot);
  }

  onUpdateForm(formId: string): void {
    WidgetForms.updateOne(this.context.filesDir, formId);
  }

  onRemoveForm(formId: string): void {
    WidgetForms.remove(this.context.filesDir, formId);
  }

  onSizeChanged(formId: string, newDimension: formInfo.FormDimension, newRect: formInfo.Rect): void {
    const layout: string = newDimension === formInfo.FormDimension.Dimension_2_2 ? 'compact' : 'wide';
    WidgetForms.add(this.context.filesDir, formId, layout);
    WidgetForms.updateOne(this.context.filesDir, formId);
  }
}
