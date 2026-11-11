import { DownloadItem } from '../../model/Models';
import { BatchView } from '../../model/BatchView';
import { TaskRow } from '../../viewmodel/TaskRows';
import { TASK_STATUS_IDS, TasksViewModel } from '../../viewmodel/TasksViewModel';
import { Font, Palette, Radius, Space } from '../../theme/Tokens';
import { ScreenMetrics, SCREEN_INSETS } from '../../theme/Metrics';
import { BatchCard, TaskCard } from '../Cards';
import { EmptyState, PillButton, SectionHead, SettingSelect } from '../Widgets';
import { AppSegmentButton } from '../AppSegmentButton';

/** Task filters stay at the top; the cards below are created only when visible. */
@ComponentV2
export struct TasksScreen {
  @Require @Param tasks: TasksViewModel;

  /** 已结束任务只在状态混合时显示胶囊；筛选到单一状态时整列同质，胶囊是重复信息。 */
  private showStatus(task: DownloadItem): boolean {
    if (this.tasks.isActiveStatus(task.status)) { return true; }
    return this.tasks.settledMixed;
  }  @Builder
  private taskCard(task: DownloadItem) {
    TaskCard({
      task: task,
      showStatus: this.showStatus(task),
      thumbnailSource: this.tasks.thumbnailSource(task),
      firstFramePath: this.tasks.firstFramePath(task),
      onCancel: (item: DownloadItem): void => { this.tasks.cancel(item); },
      onPause: (item: DownloadItem): void => { this.tasks.pause(item); },
      onResume: (item: DownloadItem): void => { this.tasks.resume(item); },
      onRetry: (item: DownloadItem): void => { this.tasks.retry(item); },
      onRetryDelivery: (item: DownloadItem): void => { this.tasks.retryDelivery(item); },
      onLocate: (item: DownloadItem): void => { this.tasks.locate(item); },
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

  /** 只有一个来源时下拉没有选择意义，省掉一行高度。 */
  private showCollections(): boolean {
    return this.tasks.collections.length > 1 || this.tasks.collectionFilter !== '*';
  }

  @Builder
  private searchField() {
    Search({ value: this.tasks.query, placeholder: '搜索文件名' })
      .height(36)
      .fontColor(Palette.fontPrimary)
      .placeholderColor(Palette.fontTertiary)
      .backgroundColor(Palette.cardSunken)
      .borderRadius(Radius.full)
      .onChange((value: string): void => { this.tasks.setQuery(value); })
  }

  @Builder
  private filters() {
    Column({ space: Space.s12 }) {
      if (this.tasks.searching) {
        this.searchField()
      }
      // 5 项状态 + 计数：compact 档全宽等分（11fp / 每项内边距 4），窄屏也不截字。
      AppSegmentButton({
        labels: this.tasks.statusLabels,
        selectedIndex: Math.max(0, TASK_STATUS_IDS.indexOf(this.tasks.statusFilter)),
        config: { compact: true },
        onSelectedIndexChange: (index: number): void => {
          this.tasks.setStatusFilter(TASK_STATUS_IDS[index]);
        }
      })
      // 空闲时「等待 0 · 完成 50 · 失败 0」与页签计数重复，只在确有活动/失败时显示。
      if (this.tasks.summaryVisible) {
        Text(this.tasks.queueSummary).fontSize(Font.caption).fontColor(Palette.fontSecondary).width('100%')
      }
      if (this.tasks.statusCounts[3] > 0) {
        Row({ space: Space.s8 }) {
          if (this.tasks.failureSummary.length > 0) {
            Text('失败原因：' + this.tasks.failureSummary)
              .fontSize(Font.caption).fontColor(Palette.warning).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Blank()
          }
          PillButton({ label: '重试全部失败', small: true, variant: 'tonal',
            onAction: (): void => { this.tasks.retryAllFailed(); } })
        }.width('100%').alignItems(VerticalAlign.Center)
      }
      if (this.showCollections()) {
        Column({ space: Space.s6 }) {
          SettingSelect({
            options: this.tasks.collectionOptions,
            selectedIndex: this.tasks.selectedCollectionIndex,
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

  private hideRow(row: TaskRow): void {
    if (row.task !== undefined) { this.tasks.hideTask(row.task); }
  }

  /** 左滑移出：素材仍留在图库，只从任务页拿掉这条记录。 */
  @Builder
  private swipeEnd(row: TaskRow) {
    Row() {
      Text('移出')
        .fontSize(Font.aux)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.white)
    }
    .width(76)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Palette.warning)
    .borderRadius(Radius.r8)
    .accessibilityText('移出任务页，保留素材')
    .onClick((): void => { this.hideRow(row); })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ scroller: this.tasks.scrollController(), space: Space.s12 }) {
        ListItem() {
          this.filters()
        }
        LazyForEach(this.tasks.rows, (row: TaskRow) => {
          if (row.kind === 'heading') {
            ListItem() {
              SectionHead({ heading: row.title, meta: row.count.toString(), actionLabel: row.actionLabel,
                onAction: (): void => { this.tasks.clearFinished(); } })
            }
          } else if (row.kind === 'batch' && row.batch !== undefined) {
            ListItem() {
              this.batchCard(row.batch)
            }
          } else if (row.kind === 'task' && row.task !== undefined) {
            if (this.tasks.isSettledStatus(row.task.status)) {
              ListItem() {
                this.taskCard(row.task)
              }
              .swipeAction({ end: (): void => { this.swipeEnd(row); } })
            } else {
              ListItem() {
                this.taskCard(row.task)
              }
            }
          }
        }, (row: TaskRow) => row.key)
        if (this.tasks.isEmpty()) {
          ListItem() {
            EmptyState({
              glyph: 'inbox',
              heading: this.tasks.searching && this.tasks.query.length > 0 ? '没有匹配的任务' :
                this.tasks.statusFilter !== 'all' ? '此状态下没有任务' :
                this.tasks.collectionFilter === '*' ? '还没有下载任务' : '此来源没有待处理任务',
              body: this.tasks.searching && this.tasks.query.length > 0 ? '换个文件名关键词再试。' :
                this.tasks.statusFilter !== 'all' ? '可切换上方状态查看其他任务。' :
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
