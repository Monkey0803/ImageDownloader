import { DownloadItem } from '../../model/Models';
import { BatchView } from '../../model/BatchView';
import { TaskRow } from '../../viewmodel/TaskRows';
import { CollectionSummary } from '../../service/CollectionGroups';
import { TasksViewModel } from '../../viewmodel/TasksViewModel';
import { Font, Layout, Palette, Space } from '../../theme/Tokens';
import { ScreenMetrics, SCREEN_INSETS } from '../../theme/Metrics';
import { BatchCard, TaskCard } from '../Cards';
import { EmptyState, PillButton, SectionHead, SettingSelect, TitleBar } from '../Widgets';

/** Task filters stay at the top; the cards below are created only when visible. */
@ComponentV2
export struct TasksScreen {
  @Require @Param tasks: TasksViewModel;

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
      Scroll() {
        Row({ space: Space.s6 }) {
          ForEach(['all', 'active', 'completed', 'failed', 'cancelled'],
            (status: string, index: number) => {
              PillButton({ label: ['全部', '进行中', '已完成', '失败', '已取消'][index]
                + ' ' + this.tasks.statusCounts[index].toString(), small: true,
                variant: this.tasks.statusFilter === status ? 'primary' : 'ghost',
                onAction: (): void => { this.tasks.setStatusFilter(status); } })
            }, (status: string) => status)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      Text(this.tasks.queueSummary).fontSize(Font.caption).fontColor(Palette.fontSecondary).width('100%')
      if (this.tasks.failureSummary.length > 0) {
        Text('失败原因：' + this.tasks.failureSummary)
          .fontSize(Font.caption).fontColor(Palette.warning).width('100%')
      }
      Row({ space: Space.s8 }) {
        PillButton({ label: this.tasks.floatActive() ? '关闭闪控窗' : '开启闪控窗', small: true,
          variant: 'ghost', active: !this.tasks.isEmpty() || this.tasks.floatActive(),
          onAction: (): void => { this.tasks.toggleFloat(); } })
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
      .padding({
        left: Layout.pagePad, right: Layout.pagePad,
        top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true),
        bottom: ScreenMetrics.bottomInset(SCREEN_INSETS.safeBottom, 0)
      })
      .onDidScroll((): void => { this.tasks.markScrolled(); })

      TitleBar({
        heading: '任务',
        caption: this.tasks.caption(),
        actionGlyph: this.tasks.isEmpty() ? '' : 'trash',
        actionLabel: '删除全部下载文件和记录',
        layer: Layout.tbLayerSecondary,
        onAction: (): void => { this.tasks.confirmClearAll(); }
      })
    }.width('100%').height('100%')
  }
}
