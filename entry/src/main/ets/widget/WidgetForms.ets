import { formBindingData, formProvider } from '@kit.FormKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { WidgetSnapshot } from './WidgetSnapshot';

class FormRecord {
  id: string = '';
  layout: string = 'wide';
}

/** Shared filesDir is visible to UIAbility and FormExtensionAbility, unlike their process memory. */
export class WidgetForms {
  private static readonly IDS_FILE: string = 'download-widget-ids.json';

  static readSnapshot(filesDir: string): WidgetSnapshot {
    try {
      return WidgetSnapshot.fromSavedText(fs.readTextSync(filesDir + '/download-state.json'));
    } catch (error) {
      return new WidgetSnapshot();
    }
  }

  static add(filesDir: string, id: string, layout: string): void {
    if (id.length === 0) { return; }
    const records: FormRecord[] = WidgetForms.readIds(filesDir).filter((item: FormRecord): boolean => item.id !== id);
    const record: FormRecord = new FormRecord();
    record.id = id;
    record.layout = layout;
    records.push(record);
    WidgetForms.writeIds(filesDir, records);
  }

  static remove(filesDir: string, id: string): void {
    WidgetForms.writeIds(filesDir, WidgetForms.readIds(filesDir).filter((item: FormRecord): boolean => item.id !== id));
  }

  static layout(filesDir: string, id: string): string {
    const record: FormRecord | undefined = WidgetForms.readIds(filesDir).find((item: FormRecord): boolean => item.id === id);
    return record?.layout ?? 'wide';
  }

  static updateOne(filesDir: string, id: string): void {
    const snapshot: WidgetSnapshot = WidgetForms.readSnapshot(filesDir);
    snapshot.layout = WidgetForms.layout(filesDir, id);
    WidgetForms.send(id, snapshot);
  }

  static publish(filesDir: string, snapshot: WidgetSnapshot): void {
    const records: FormRecord[] = WidgetForms.readIds(filesDir);
    for (const record of records) {
      snapshot.layout = record.layout;
      WidgetForms.send(record.id, snapshot);
    }
  }

  private static send(id: string, snapshot: WidgetSnapshot): void {
    formProvider.updateForm(id, formBindingData.createFormBindingData(snapshot)).catch((error: Error): void => {
      console.error('download widget update failed: ' + error.message);
    });
  }

  private static readIds(filesDir: string): FormRecord[] {
    try {
      const parsed: FormRecord[] = JSON.parse(fs.readTextSync(filesDir + '/' + WidgetForms.IDS_FILE)) as FormRecord[];
      if (!Array.isArray(parsed)) { return []; }
      return parsed.filter((item: FormRecord): boolean => item !== null && typeof item.id === 'string'
        && (item.layout === 'compact' || item.layout === 'wide'));
    } catch (error) {
      return [];
    }
  }

  private static writeIds(filesDir: string, records: FormRecord[]): void {
    const path: string = filesDir + '/' + WidgetForms.IDS_FILE;
    const temp: string = path + '.tmp';
    try {
      const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(records));
      fs.closeSync(file);
      fs.renameSync(temp, path);
    } catch (error) {
      console.error('download widget IDs save failed: ' + String(error));
    }
  }
}
