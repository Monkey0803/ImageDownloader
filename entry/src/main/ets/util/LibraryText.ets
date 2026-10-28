import { EditRect } from '../model/ImageEditDocument';
import { RecognizedLine } from '../model/LibraryAsset';

class IndexedText {
  key: string = '';
  offsets: number[] = [];
}

/** Plain-text matching for file names, OCR content and user labels. */
export class LibraryText {
  private static starts(length: number): number[] {
    const result: number[] = [];
    for (let start: number = 0; start < length; start += 1920) {
      result.push(start);
      if (start + 2048 >= length) { break; }
    }
    return result;
  }

  /** Tiles overlap so text crossing a decode boundary can be recognized. */
  static tiles(width: number, height: number): EditRect[] {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) { return []; }
    const result: EditRect[] = [];
    for (const y of LibraryText.starts(height)) {
      for (const x of LibraryText.starts(width)) {
        const rect: EditRect = new EditRect();
        rect.x = x; rect.y = y;
        rect.width = Math.min(2048, width - x); rect.height = Math.min(2048, height - y);
        result.push(rect);
      }
    }
    return result;
  }

  private static overlap(a: RecognizedLine, b: RecognizedLine): boolean {
    const width: number = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x));
    const height: number = Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
    const smaller: number = Math.min(a.width * a.height, b.width * b.height);
    return smaller > 0 && width * height >= smaller * 0.5;
  }

  static mergeLines(lines: RecognizedLine[]): string {
    const ordered: RecognizedLine[] = lines.slice().sort((a: RecognizedLine, b: RecognizedLine): number =>
      a.y - b.y || a.x - b.x);
    const accepted: RecognizedLine[] = [];
    for (const line of ordered) {
      if (line.text.trim().length === 0) { continue; }
      const duplicate: boolean = accepted.some((other: RecognizedLine): boolean =>
        LibraryText.textKey(other.text) === LibraryText.textKey(line.text) && LibraryText.overlap(other, line));
      if (!duplicate) { accepted.push(line); }
    }
    let output: string = '';
    let previous: RecognizedLine | undefined = undefined;
    for (const line of accepted) {
      if (previous !== undefined) {
        output += Math.abs(line.y - previous.y) <= Math.min(line.height, previous.height) * 0.5 ? ' ' : '\n';
      }
      output += line.text.trim();
      previous = line;
    }
    return output;
  }

  static normalize(value: string): string {
    return value.trim().toLowerCase().replace(/\s+/g, ' ');
  }

  static textKey(value: string): string {
    return value.toLowerCase().replace(/\s+/g, '');
  }

  static tags(values: string[]): string[] {
    const result: string[] = [];
    const seen: Set<string> = new Set();
    for (const raw of values) {
      const display: string = raw.trim();
      const key: string = LibraryText.normalize(display);
      if (key.length === 0 || seen.has(key)) { continue; }
      seen.add(key);
      result.push(display);
    }
    return result;
  }

  private static indexed(value: string): IndexedText {
    const indexed: IndexedText = new IndexedText();
    for (let offset: number = 0; offset < value.length; offset++) {
      const current: string = value.charAt(offset);
      if (/\s/.test(current)) { continue; }
      const folded: string = current.toLowerCase();
      indexed.key += folded;
      for (let index: number = 0; index < folded.length; index++) {
        indexed.offsets.push(offset);
      }
    }
    return indexed;
  }

  static snippet(value: string, query: string, limit: number = 96): string {
    if (value.length === 0) { return ''; }
    const mapped: IndexedText = LibraryText.indexed(value);
    const needle: string = LibraryText.textKey(query);
    if (needle.length === 0) { return value.slice(0, Math.max(1, limit)); }
    const position: number = mapped.key.indexOf(needle);
    if (position < 0) { return ''; }
    const first: number = mapped.offsets[position];
    const last: number = mapped.offsets[Math.min(mapped.offsets.length - 1,
      position + needle.length - 1)] + 1;
    const width: number = Math.max(1, limit, last - first);
    let start: number = Math.max(0, first - Math.floor((width - (last - first)) / 2));
    let end: number = Math.min(value.length, start + width);
    start = Math.max(0, end - width);
    const prefix: string = start > 0 ? '…' : '';
    const suffix: string = end < value.length ? '…' : '';
    return prefix + value.slice(start, end).replace(/\s+/g, ' ') + suffix;
  }
}
