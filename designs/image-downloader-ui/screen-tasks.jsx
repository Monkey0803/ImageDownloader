/* ============================================================
   screen-tasks.jsx — 任务
   ============================================================ */

function TaskRow(props) {
  const { task, onCancel, onRetry, onLocate, onRename } = props;
  const active = KD.ACTIVE_STATUS.indexOf(task.status) >= 0;
  const pct = KD.percent(task.processed, task.total);

  return (
    <div className="card card--flush">
      <div className="task">
        <span className="task__thumb">
          <Img src={task.thumb} alt={task.name} fallback={task.kind.toUpperCase()} />
          <span className="task__ext">{task.kind.toUpperCase()}</span>
        </span>

        <div className="task__body">
          <div className="task__top">
            <button
              type="button"
              className="task__name"
              title={onRename ? '点击重命名' : task.name}
              onClick={onRename}
            >
              {task.name}
            </button>
            <StatusChip status={task.status} />
          </div>

          {active && task.total > 0 ?
            <Progress value={pct} tone={task.status === 'running' ? undefined : 'warn'} /> : null}

          <span className="task__meta">
            {task.status === 'running' ?
              <React.Fragment>
                <span>{KD.formatBytes(task.processed)} / {KD.formatBytes(task.total)}</span>
                <span>·</span>
                <span>{pct}%</span>
              </React.Fragment> : null}
            {task.status === 'queued' ?
              <span>等待并发空位 · {KD.formatBytes(task.total)}</span> : null}
            {task.status === 'completed' ?
              <span>已保存 · {KD.formatBytes(task.total)}</span> : null}
            {task.error ?
              <span className="task__meta-err" lang="zh">{task.error}</span> : null}
          </span>
        </div>

        <span className="task__actions">
          {active ?
            <IconBtn icon="close" label="取消下载" onClick={onCancel} /> : null}
          {task.status === 'failed' || task.status === 'cancelled' ?
            <IconBtn icon="retry" label="重试" onClick={onRetry} /> : null}
          {task.status === 'completed' ?
            <IconBtn icon="chevronRight" label="在图库中查看" onClick={onLocate} /> : null}
        </span>
      </div>
    </div>
  );
}

function BatchCard(props) {
  const { batch } = props;
  const layers = batch.members.slice(0, 3);
  return (
    <div className="card card--flush">
      <div className="batch">
        <div className="batch__top">
          <span className="batch__stack">
            {layers.map((thumb, index) =>
              <span
                key={index}
                className="batch__stack-layer"
                style={{
                  left: (index * 7) + 'px',
                  top: (index * 7) + 'px',
                  zIndex: index + 1,
                  opacity: index === layers.length - 1 ? 1 : 0.9,
                }}
              >
                <Img src={thumb} alt="" fallback="" />
              </span>
            )}
            <span className="batch__stack-count tnum">{batch.total}</span>
          </span>

          <div className="task__body">
            <div className="task__top">
              <span className="task__name" lang="zh">{batch.name}</span>
              <StatusChip status={batch.status} />
            </div>
            <span className="task__meta">
              <span lang="zh">
                {batch.status === 'packing'
                  ? '正在压缩为 ZIP…'
                  : '正在下载 · ' + batch.done + '/' + batch.total + ' 张'}
              </span>
              {batch.failed > 0 ?
                <React.Fragment>
                  <span>·</span>
                  <span className="task__meta-err" lang="zh">{batch.failed} 张失败</span>
                </React.Fragment> : null}
            </span>
          </div>
        </div>
        <Progress
          value={batch.status === 'packing' ? 96 : Math.round((batch.done / batch.total) * 100)}
          tone={batch.status === 'packing' ? 'stripe' : undefined}
        />
      </div>
    </div>
  );
}

function TasksScreen(props) {
  const { tasks, batches, concurrency, onCancel, onRetry, onLocate, onRename } = props;

  const running = tasks.filter((task) => KD.ACTIVE_STATUS.indexOf(task.status) >= 0 && task.status !== 'queued');
  const queued = tasks.filter((task) => task.status === 'queued');
  const settled = tasks.filter((task) => task.status === 'completed' || task.status === 'failed' || task.status === 'cancelled');
  const activeCount = running.length + queued.length + batches.length;

  return (
    <div className="screen fade-swap" data-screen-label="任务" data-titlebar="secondary">
      <Titlebar
        title="任务"
        subtitle={activeCount > 0 ? activeCount + ' 个任务进行中 · 并发 ' + concurrency : '队列为空'}
      />

      <div className="scroll">
        {batches.length > 0 ?
          <div>
            <SectionHead title="打包任务" meta="ZIP" />
            <div className="col-gap">
              {batches.map((batch) => <BatchCard key={batch.id} batch={batch} />)}
            </div>
          </div> : null}

        {running.length + queued.length > 0 ?
          <div>
            <SectionHead title="进行中" meta={String(running.length + queued.length)} />
            <div className="col-gap">
              {running.concat(queued).map((task) =>
                <TaskRow
                  key={task.id}
                  task={task}
                  onCancel={() => onCancel(task)}
                  onRetry={() => onRetry(task)}
                  onLocate={() => onLocate(task)}
                  onRename={() => onRename(task)}
                />
              )}
            </div>
          </div> : null}

        {settled.length > 0 ?
          <div>
            {/* meta 是 settled 的总数（已完成 + 失败 + 已取消）；标题只能给一个名字，
                写成「已完成 / 失败」会让数字看起来同时属于两个状态。 */}
            <SectionHead title="已结束" meta={String(settled.length)} />
            <div className="col-gap">
              {settled.map((task) =>
                <TaskRow
                  key={task.id}
                  task={task}
                  onCancel={() => onCancel(task)}
                  onRetry={() => onRetry(task)}
                  onLocate={() => onLocate(task)}
                  onRename={() => onRename(task)}
                />
              )}
            </div>
          </div> : null}

        {activeCount === 0 && settled.length === 0 ?
          /* 页面没有其它卡片时，空态直接顶在标题栏下面会显得挤（对应 ArkTS 里那层 32vp 内边距） */
          <div style={{ marginTop: 'var(--sp-16)' }}>
            <Empty
              icon="inbox"
              title="还没有下载任务"
              body="回到「发现」，扫描网页并选择要保存的图片。"
            />
          </div> : null}
      </div>
    </div>
  );
}

Object.assign(window, { TasksScreen });