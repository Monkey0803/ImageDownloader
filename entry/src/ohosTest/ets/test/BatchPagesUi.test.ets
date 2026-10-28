import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';

/** Opt-in only. Default reviews without enqueue; batchCommit explicitly enables fixture downloads. */
export default function batchPagesUiTest() {
  describe('BatchPagesUi', (): void => {
    it('pastes_multiple_sources_and_reviews_selected_images', 0, async (): Promise<void> => {
      const args = abilityDelegatorRegistry.getArguments();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const driver: Driver = Driver.create();
      await delegator.startAbility({ bundleName: args.bundleName, abilityName: 'EntryAbility', moduleName: 'entry' });
      await driver.delayMs(1000);
      const back: Component | undefined = await driver.findComponent(ON.text('返回修改'));
      if (back !== undefined && back !== null) { await back.click(); }
      const expanded: Component | undefined = await driver.findComponent(ON.text('收起批量链接'));
      if (expanded === undefined || expanded === null) {
        await (await driver.waitForComponent(ON.text('批量链接'), 15000)).click();
      }
      const editor: Component = await driver.waitForComponent(ON.type('TextArea'), 10000);
      const zip: boolean = args.parameters['-s batchZip'] === 'true';
      await (await driver.findComponent(ON.text(zip ? 'ZIP' : '单张'))).click();
      const supplied: Object | undefined = args.parameters['-s batchInput'];
      const input: string = typeof supplied === 'string' ? supplied.split('|').join('\n')
        : 'http://127.0.0.1:18767/one.html\nhttp://127.0.0.1:18767/two\n'
          + 'http://127.0.0.1:18767/login.html\nhttp://127.0.0.1:18767/a.png';
      await editor.inputText(input);
      // Component.inputText may set text without showing an IME. A hardware Back could exit
      // the app; collapse/reopen instead, which also verifies the text survives that action.
      await (await driver.findComponent(ON.text('收起批量链接'))).click();
      await (await driver.waitForComponent(ON.text('批量链接'), 10000)).click();
      await (await driver.waitForComponent(ON.text('解析并预览'), 10000)).click();
      const expected: Object | undefined = args.parameters['-s batchExpected'];
      const count: string = typeof expected === 'string' ? expected : '6';
      const suffix: string = zip ? ' · 每个网页一个 ZIP' : ' · 单图下载';
      const summary: Component = await driver.waitForComponent(ON.text('已选 ' + count + ' 张' + suffix), 60000);
      expect(await summary.getText()).assertEqual('已选 ' + count + ' 张' + suffix);
      let selected: number = Number(count);
      if (args.parameters['-s batchDeselect'] === 'true') {
        await (await driver.findComponent(ON.id('batch-select-line-1-0'))).click();
        selected--;
        await driver.waitForComponent(ON.text('已选 ' + selected.toString() + ' 张' + suffix), 5000);
      }
      if (args.parameters['-s batchHandleFixture'] === 'true') {
        const sources: Component = await driver.findComponent(ON.id('batch-source-groups'));
        await (await sources.scrollSearch(ON.text('打开网页处理'))).click();
        await driver.waitForComponent(ON.text('在网页中完成登录或验证，返回后重试对应链接'), 5000);
        await (await driver.findComponent(ON.text('返回批量结果'))).click();
        await driver.waitForComponent(ON.text('已选 ' + selected.toString() + ' 张' + suffix), 5000);
        await (await sources.scrollSearch(ON.text('重试此页'))).click();
        await driver.delayMs(500);
        await driver.waitForComponent(ON.text('已选 ' + selected.toString() + ' 张' + suffix), 10000);
      }
      const confirm: Component = await driver.findComponent(ON.text('加入任务 · ' + selected.toString() + ' 张'));
      expect(await confirm.getText()).assertEqual('加入任务 · ' + selected.toString() + ' 张');
      if (args.parameters['-s batchCommit'] === 'true') { await confirm.click(); await driver.delayMs(3000); }
    });
  });
}
