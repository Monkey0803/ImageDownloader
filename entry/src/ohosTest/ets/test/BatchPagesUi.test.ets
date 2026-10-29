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
      // 批量链接是发现页工具栏里的图标入口，打开后是一个独立的 HDS 页面。
      await (await driver.waitForComponent(ON.id('batch-link-entry'), 15000)).click();
      const editor: Component = await driver.waitForComponent(ON.type('TextArea'), 10000);
      const zip: boolean = args.parameters['-s batchZip'] === 'true';
      await (await driver.findComponent(ON.text(zip ? 'ZIP' : '单张'))).click();
      const supplied: Object | undefined = args.parameters['-s batchInput'];
      const input: string = typeof supplied === 'string' ? supplied.split('|').join('\n')
        : 'http://127.0.0.1:18767/one.html\nhttp://127.0.0.1:18767/two\n'
          + 'http://127.0.0.1:18767/login.html\nhttp://127.0.0.1:18767/a.png';
      await editor.inputText(input);
      // 编辑态返回会关闭批量页（页面自己消费返回事件）；重新打开验证文本仍在。
      await driver.pressBack();
      await (await driver.waitForComponent(ON.id('batch-link-entry'), 10000)).click();
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
        // 处理页的标题由 HDS 导航栏提供；返回走页面返回语义，回到批量结果。
        await driver.waitForComponent(ON.text('网页处理'), 5000);
        await driver.pressBack();
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
