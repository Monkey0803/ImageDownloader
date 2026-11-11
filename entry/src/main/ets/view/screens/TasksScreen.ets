import { DownloadItem } from '../../model/Models';
import { BatchView } from '../../model/BatchView';
import { TaskRow } from '../../viewmodel/TaskRows';
import { CollectionSummary } from '../../service/CollectionGroups';
import { TasksViewModel } from '../../viewmodel/TasksViewModel';
import { Font, Layout, Palette, Space } from '../../theme/Tokens';
import { ScreenMetrics, SCREEN_INSETS } from '../../theme/Metrics';
import { BatchCard, TaskCard } from '../Cards';
import { EmptyState, PillButton, SectionHead, SettingSelect } from '../Widgets';
import { AppSegmentButton } from '../AppSegmentButton';

/** 状态筛选的取值与显示顺序；与 `TasksViewModel.statusFilter` 一一对应。 */
const TASK_STATUS_IDS: string[] = ['all', 'active', 'completed', 'failed', 'cancelled'];
const TASK_STATUS_LABELS: string[] = ['全部', '进行中', '已完成', '失败', '已取消'];

/** Task filters stay at the top; the cards below are created only when visible. */
@ComponentV2
export struct TasksScreen {
  @Require @Param tasks: TasksViewModel;

  /** 标签带实时计数；计数变化时组件按「标签串」重建 items，不用手动刷新。 */
  private statusLabels(): string[] {
    const labels: string[] = [];
    for (let i: number = 0; i < TASK_STATUS_IDS.length; i += 1) {
      labels.push(TASK_STATUS_LABELS[i] + ' ' + this.tasks.statusCounts[i].toString());
    }
    return labels;
  }

  private collectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部来源' }];
    for (const group of this.tasks.collections) { options.push({ value: group.name }); }
    return options;
  }

  @Builder
  private taskCard(task: DownloadItem) {
    TaskCard({
      task: task,
      thumbnailSource: this.tasks.thumbnailSource(task),
      firstFramePath: this.tasks.firstFramePath(task),
      onCancel: (item: DownloadItem): void => { this.tasks.cancel(item); },
      onPause: (item: DownloadItem): void => { this.tasks.pause(item); },
      onResume: (item: DownloadItem): void => { this.tasks.resume(item); },
      onRetry: (item: DownloadItem): void => { this.tasks.retry(item); },
      onRetryDelivery: (item: DownloadItem): void => { this.tasks.retryDelivery(item); },
      onLocate: (item: DownloadItem): void => { this.tasks.locate(item); },
      onHide: (item: DownloadItem): void => { this.tasks.hideTask(item); },
      onOpen: (item: DownloadItem): void => { this.tasks.openTask(item); }
    })
  }

  @Builder
  private batchCard(view: BatchView) {
    BatchCard({
      view: view,
      onRetry: (batch: BatchView): void => { this.tasks.retryBatch(batch); },
      onDismiss: (batch: BatchView): void => { this.tasks.dismissBatch(batch); },
      onOpen: (batch: BatchView): void => { this.tasks.openBatch(batch); }
    })
  }

  @Builder
  private filters() {
    Column({ space: Space.s12 }) {
      // 5 项状态 + 计数：compact 档全宽等分（11fp / 每项内边距 4），窄屏也不截字。
      AppSegmentButton({
        labels: this.statusLabels(),
        selectedIndex: Math.max(0, TASK_STATUS_IDS.indexOf(this.tasks.statusFilter)),
        config: { compact: true },
        onSelectedIndexChange: (index: number): void => {
          this.tasks.setStatusFilter(TASK_STATUS_IDS[index]);
        }
      })
      Text(this.tasks.queueSummary).fontSize(Font.caption).fontColor(Palette.fontSecondary).width('100%')
      if (this.tasks.failureSummary.length > 0) {
        Text('失败原因：' + this.tasks.failureSummary)
          .fontSize(Font.caption).fontColor(Palette.warning).width('100%')
      }
      Row({ space: Space.s8 }) {
        if (this.tasks.statusCounts[3] > 0) {
          PillButton({ label: '重试全部失败', small: true, variant: 'tonal',
            onAction: (): void => { this.tasks.retryAllFailed(); } })
        }
        PillButton({ label: '清理已完成与已取消', small: true, variant: 'ghost',
          active: this.tasks.statusCounts[2] + this.tasks.statusCounts[4] > 0,
          onAction: (): void => { this.tasks.clearFinished(); } })
      }.width('100%')
      if (this.tasks.collections.length > 0) {
        Column({ space: Space.s6 }) {
          SettingSelect({
            options: this.collectionOptions(),
            selectedIndex: this.tasks.collectionFilter === '*' ? 0
              : this.tasks.collections.findIndex((group: CollectionSummary): boolean =>
                group.id === this.tasks.collectionFilter) + 1,
            label: this.tasks.selectedCollection()?.name ?? '全部来源',
            onPick: (index: number): void => {
              this.tasks.setCollectionFilter(index === 0 ? '*' : this.tasks.collections[index - 1].id);
            }
          })
          if (this.tasks.selectedCollection() !== undefined) {
            Text('累计加入 ' + this.tasks.selectedCollection()!.added.toString() + ' · 跳过 '
              + this.tasks.selectedCollection()!.skipped.toString() + ' · 完成 '
              + this.tasks.selectedCollection()!.completed.toString() + ' · 失败 '
              + this.tasks.selectedCollection()!.failed.toString())
              .fontSize(Font.caption).fontColor(Palette.fontSecondary)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private rowContent(row: TaskRow) {
    if (row.kind === 'heading') {
      SectionHead({ heading: row.title, meta: row.count.toString() })
    } else if (row.kind === 'batch' && row.batch !== undefined) {
      this.batchCard(row.batch)
    } else if (row.kind === 'task' && row.task !== undefined) {
      this.taskCard(row.task)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ scroller: this.tasks.scrollController(), space: Space.s12 }) {
        ListItem() {
          this.filters()
        }
        LazyForEach(this.tasks.rows, (row: TaskRow) => {
          ListItem() {
            this.rowContent(row)
          }
        }, (row: TaskRow) => row.key)
        if (this.tasks.isEmpty()) {
          ListItem() {
            EmptyState({
              glyph: 'inbox',
              heading: this.tasks.statusFilter !== 'all' ? '此状态下没有任务' :
                this.tasks.collectionFilter === '*' ? '还没有下载任务' : '此来源没有待处理任务',
              body: this.tasks.statusFilter !== 'all' ? '可切换上方状态查看其他任务。' :
                this.tasks.collectionFilter === '*' ? '回到「发现」，扫描网页并选择要保存的图片。'
                  : '已完成的素材可在「图库」按来源查看。'
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentStartOffset(ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true))
      .contentEndOffset(SCREEN_INSETS.contentBottomInsetVp + Space.s12)
      .padding({
        left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
        right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight),
      })
      .onDidScroll((): void => { this.tasks.markScrolled(); })

    }.width('100%').height('100%')
  }
}
