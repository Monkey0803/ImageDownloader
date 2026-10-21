const storage = new LocalStorage();

@Entry(storage)
@Component
struct DownloadWidget {
  @LocalStorageProp('count') count: string = '0';
  @LocalStorageProp('status') status: string = '暂无待处理任务';
  @LocalStorageProp('name') name: string = '';
  @LocalStorageProp('progress') progress: string = '';
  @LocalStorageProp('percent') percent: string = '0';
  @LocalStorageProp('layout') layout: string = 'wide';

  private openTasks(): void {
    postCardAction(this, {
      action: 'router',
      bundleName: 'com.example.imagedownloader',
      abilityName: 'EntryAbility',
      params: { 'widgetPage': 'tasks' }
    });
  }

  build() {
    Column({ space: 10 }) {
      Text('下载概览')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.font_primary'))
        .width('100%')

      if (this.layout === 'compact') {
        Text(this.count)
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
          .width('100%')
        Text(this.status)
          .fontSize(13)
          .fontColor($r('app.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else {
        Row({ space: 8 }) {
          Text(this.count + ' 项待处理')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text(this.status)
            .fontSize(13)
            .fontColor($r('app.color.font_secondary'))
        }
        .width('100%')

        if (this.name.length > 0) {
          Text(this.name)
            .fontSize(14)
            .fontColor($r('app.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: 8 }) {
            if (this.progress.endsWith('%')) {
              Progress({ value: Number(this.percent), total: 100, type: ProgressType.Linear })
                .color($r('app.color.brand'))
                .layoutWeight(1)
            }
            Text(this.progress)
              .fontSize(12)
              .fontColor($r('app.color.font_secondary'))
          }
          .width('100%')
        }
      }

      Blank()
      Text('点击查看任务')
        .fontSize(11)
        .fontColor($r('app.color.font_tertiary'))
        .width('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius(18)
    .onClick((): void => this.openTasks())
  }
}
