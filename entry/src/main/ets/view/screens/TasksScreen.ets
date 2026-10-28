import { DownloadItem } from '../../model/Models';
import { BatchView } from '../../model/BatchView';
import { TasksViewModel } from '../../viewmodel/TasksViewModel';
import { Layout, Palette, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { BatchCard, TaskCard } from '../Cards';
import { EmptyState, SectionHead, TitleBar } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

/**
 * 「任务」页：打包任务卡 + 进行中 + 已结束。
 *
 * 从 Index 的 `tasksScreen()` / `taskList()` 搬过来。分组数组由
 * `TasksViewModel.sync()` 更新，ForEach 直接读取响应式字段。
 */
@ComponentV2
export struct TasksScreen {
  @Require @Param tasks: TasksViewModel;

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  @Builder
  private taskCard(task: DownloadItem) {
    TaskCard({
      task: task,
      onCancel: (item: DownloadItem): void => { this.tasks.cancel(item); },
      onPause: (item: DownloadItem): void => { this.tasks.pause(item); },
      onResume: (item: DownloadItem): void => { this.tasks.resume(item); },
      onRetry: (item: DownloadItem): void => { this.tasks.retry(item); },
      onRetryDelivery: (item: DownloadItem): void => { this.tasks.retryDelivery(item); },
      onLocate: (item: DownloadItem): void => { this.tasks.locate(item); },
      onOpen: (item: DownloadItem): void => { this.tasks.openTask(item); }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.tasks.scrollController()) {
        Column({ space: Space.s16 }) {
          if (this.tasks.batchViews.length > 0) {
            Column({ space: Space.s10 }) {
              SectionHead({ heading: '打包任务', meta: 'ZIP' })
              Column({ space: Space.s12 }) {
                ForEach(this.tasks.batchViews, (view: BatchView) => {
                  BatchCard({
                    view: view,
                    onRetry: (batch: BatchView): void => {
                      this.tasks.retryBatch(batch);
                    },
                    onDismiss: (batch: BatchView): void => {
                      this.tasks.dismissBatch(batch);
                    },
                    // 打包卡的缩略图也进大图预览：取这个批次里的一张成员图，
                    // 规则同单任务卡（任务页不给改名）。成员图没了的批次不会出现在这里 ——
                    // 打成功的批次已经变成压缩包、从任务页消失。
                    onOpen: (batch: BatchView): void => {
                      this.tasks.openBatch(batch);
                    }
                  })
                }, (view: BatchView) => view.id + '|' + view.status + '|'
                  + view.done.toString() + '|' + view.failed.toString())
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.tasks.active.length > 0) {
            Column({ space: Space.s10 }) {
              SectionHead({ heading: '进行中', meta: this.tasks.active.length.toString() })
              Column({ space: Space.s12 }) {
                ForEach(this.tasks.active, (task: DownloadItem) => {
                  this.taskCard(task)
                }, (task: DownloadItem) => 'active|' + task.id + '|' + task.status)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.tasks.settled.length > 0) {
            Column({ space: Space.s10 }) {
              // meta 是「已完成 + 失败 + 已取消」的总数，标题只能配一个名字。
              // 写成「已完成 / 失败」会让这个数字看起来同时属于两个状态，也漏掉了已取消。
              // 单张卡片的 chip 仍逐条区分已完成 / 失败 / 已取消。
              SectionHead({ heading: '已结束', meta: this.tasks.settled.length.toString() })
              Column({ space: Space.s12 }) {
                ForEach(this.tasks.settled, (task: DownloadItem) => {
                  this.taskCard(task)
                }, (task: DownloadItem) => 'settled|' + task.id + '|' + task.status)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.tasks.isEmpty()) {
            // 任务页没有其它卡片时，空态直接顶在标题栏下面会显得挤，给它留一段呼吸空间。
            Column() {
              EmptyState({
                glyph: 'inbox',
                heading: '还没有下载任务',
                body: '回到「发现」，扫描网页并选择要保存的图片。'
              })
            }
            .width('100%')
            .padding({ top: Space.s32 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: ScreenMetrics.height() })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true),
          bottom: ScreenMetrics.bottomInset(SCREEN_INSETS.safeBottom, 0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll((): void => {
        this.tasks.markScrolled();
      })

      TitleBar({
        heading: '任务',
        caption: this.tasks.running > 0
          ? this.tasks.running.toString() + ' 个任务进行中 · 并发 ' + this.tasks.concurrency.toString()
          : '队列为空',
        actionGlyph: this.tasks.isEmpty() ? '' : 'trash',
        actionLabel: '清除下载记录',
        layer: Layout.tbLayerSecondary,
        onAction: (): void => { this.tasks.confirmClearAll(); }
      })
    }
    .width('100%')
    .height('100%')
  }
}
