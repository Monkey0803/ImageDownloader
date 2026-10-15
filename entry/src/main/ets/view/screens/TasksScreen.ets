import { DownloadItem } from '../../model/Models';
import { BatchView } from '../../model/BatchView';
import { TasksViewModel } from '../../viewmodel/TasksViewModel';
import { Layout, Palette, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { BatchCard, TaskCard } from '../Cards';
import { EmptyState, SectionHead, TitleBar } from '../Widgets';

/**
 * 「任务」页：打包任务卡 + 进行中 + 已结束。
 *
 * 从 Index 的 `tasksScreen()` / `taskList()` 搬过来。三个分组原来各自调一次
 * `activeTasks()` / `settledTasks()` / `batchViews()`，一次渲染要扫好几遍 `downloads`；
 * 现在读的是 `TasksViewModel` 在 `sync()` 里算好的派生数组，build 里只有读取。
 */
@Component
export struct TasksScreen {
  @ObjectLink tasks: TasksViewModel;

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  @Builder
  private taskList(items: DownloadItem[]) {
    Column({ space: Space.s12 }) {
      ForEach(items, (task: DownloadItem) => {
        TaskCard({
          task: task,
          onCancel: (item: DownloadItem): void => {
            this.tasks.cancel(item);
          },
          onRetry: (item: DownloadItem): void => {
            this.tasks.retry(item);
          },
          onLocate: (item: DownloadItem): void => {
            this.tasks.locate(item);
          },
          // 点缩略图看大图；任务页不给改名，所以 rename 传 false，也只给这一张（不滑动换图）。
          onOpen: (item: DownloadItem): void => {
            this.tasks.openTask(item);
          }
        })
      }, (task: DownloadItem) => task.id)
    }
    .width('100%')
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
              this.taskList(this.tasks.active)
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
              this.taskList(this.tasks.settled)
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
          top: ScreenMetrics.topInset(this.safeTop, true),
          bottom: ScreenMetrics.bottomInset(this.safeBottom, 0)
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
        layer: Layout.tbLayerSecondary
      })
    }
    .width('100%')
    .height('100%')
  }
}
