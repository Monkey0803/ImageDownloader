import { BusinessError, pasteboard } from '@kit.BasicServicesKit';

export type ClipboardReadProblem = 'permission' | 'non-text' | 'unavailable';

export class ClipboardReadError extends Error {
  readonly problem: ClipboardReadProblem;

  constructor(problem: ClipboardReadProblem) {
    super(problem);
    this.problem = problem;
  }
}

/**
 * 只在系统 PasteButton 成功授予本次临时读取权限后调用。
 * 顺序为 hasData → getData，避免空剪贴板时无意义的读取。
 * 先 `getData` 不查 `hasData` 会被 CodeLinter 的
 * `@correctness/paste-board-for-user-grant-check` 报出来；而且剪贴板里没东西时，
 * 系统读取可能报错。错误只在日志里保留阶段和错误码，不记录剪贴板内容。
 */
export class Clipboard {
  private static failure(stage: string, error: Object): ClipboardReadError {
    const code: number = (error as BusinessError).code;
    console.error('clipboard ' + stage + ' failed, code=' + String(code));
    return new ClipboardReadError(code === 201 ? 'permission' : 'unavailable');
  }

  static readProblemMessage(error: Object): string {
    if (error instanceof ClipboardReadError) {
      if (error.problem === 'permission') { return '剪贴板授权已失效，请再次点击粘贴'; }
      if (error.problem === 'non-text') { return '剪贴板内容不是文字'; }
    }
    return '剪贴板暂时无法读取，请重试';
  }

  static async writeText(value: string): Promise<void> {
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
  }

  static async readText(): Promise<string> {
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    try {
      if (!await board.hasData()) { return ''; }
    } catch (error) { throw Clipboard.failure('hasData', error); }
    let data: pasteboard.PasteData;
    try {
      data = await board.getData();
    } catch (error) { throw Clipboard.failure('getData', error); }
    let value: string;
    let plainText: boolean;
    try {
      value = data.getPrimaryText();
      plainText = data.hasMimeType(pasteboard.MIMETYPE_TEXT_PLAIN);
    } catch (error) { throw Clipboard.failure('inspectData', error); }
    if (value.length === 0 && !plainText) {
      throw new ClipboardReadError('non-text');
    }
    return value;
  }
}
