/* ============================================================
   app.jsx — state owner + shell
   ============================================================ */

const TAB_ITEMS = [
  { key: 'discover', label: '发现', icon: 'scan' },
  { key: 'tasks',    label: '任务', icon: 'download' },
  { key: 'gallery',  label: '图库', icon: 'image' },
  { key: 'zip',      label: '打包', icon: 'archive' },
  { key: 'settings', label: '设置', icon: 'sliders' },
];

/* HarmonyOS ships one brand emphasis colour; the theme is the only
   appearance choice the user gets. */
const THEME_OPTIONS = [
  { value: 'system', label: '跟随系统' },
  { value: 'light',  label: '浅色' },
  { value: 'dark',   label: '深色' },
];

function useSystemDark() {
  const [dark, setDark] = useState(() =>
    !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches));
  useEffect(() => {
    if (!window.matchMedia) { return; }
    const query = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (event) => setDark(event.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);
  return dark;
}

/* The real API is uiMaterial.getGlobalMaterialLevel(): the device's compute
   tier decides the material level. A prototype has no such API, so we read the
   core count as a stand-in — the same three tiers, honestly derived. */
function useDeviceLevel() {
  const [level] = useState(() => {
    const cores = navigator.hardwareConcurrency || 4;
    if (cores >= 8) { return 'exquisite'; }
    if (cores >= 4) { return 'gentle'; }
    return 'smooth';
  });
  return level;
}

/* 沉浸光感: the touched focal component is "lit" from the touch point, and the
   glow bleeds outward — HarmonyOS's signature interaction feedback. */
function useLightEffect(enabled) {
  useEffect(() => {
    if (!enabled) { return; }
    const onDown = (event) => {
      const target = event.target;
      const el = target && target.closest ? target.closest('[data-light]') : null;
      if (!el) { return; }
      const rect = el.getBoundingClientRect();
      el.style.setProperty('--lx', (((event.clientX - rect.left) / rect.width) * 100) + '%');
      el.style.setProperty('--ly', ((event.clientY - rect.top) / rect.height * 100) + '%');
      el.classList.add('is-lit');
      window.setTimeout(() => el.classList.remove('is-lit'), 240);
    };
    document.addEventListener('pointerdown', onDown, true);
    return () => document.removeEventListener('pointerdown', onDown, true);
  }, [enabled]);
}

function App() {
  /* ---------- chrome ---------- */
  const [tab, setTab] = useState('discover');
  const [themeMode, setThemeMode] = useState('system');
  const systemDark = useSystemDark();
  const theme = themeMode === 'system' ? (systemDark ? 'dark' : 'light') : themeMode;

  /* ---------- HarmonyOS system capabilities ---------- */
  const [lightEffect, setLightEffect] = useState(true);
  const [matType, setMatType] = useState('adaptive');
  const [matLevelMode, setMatLevelMode] = useState('auto');
  const [grip, setGrip] = useState(false);
  const [hand, setHand] = useState('right');
  const [antiPeek, setAntiPeek] = useState(false);
  const [peeking, setPeeking] = useState(false);
  const deviceLevel = useDeviceLevel();
  const resolvedLevel = matLevelMode === 'auto' ? deviceLevel : matLevelMode;

  useLightEffect(lightEffect);

  /* 防窥保护 is a system capability: the app never enables it, it only reacts
     to a detection — content is covered and the system live view explains why. */
  useEffect(() => {
    if (!peeking) { return; }
    const timer = window.setTimeout(() => setPeeking(false), 5200);
    return () => window.clearTimeout(timer);
  }, [peeking]);

  /* while protected, opening 图库 simulates a detection shortly after */
  useEffect(() => {
    if (!antiPeek || tab !== 'gallery') { return; }
    const timer = window.setTimeout(() => setPeeking(true), 2800);
    return () => window.clearTimeout(timer);
  }, [antiPeek, tab]);

  /* ---------- discover ---------- */
  const [address, setAddress] = useState('aozora.example.com/kyoto-autumn');
  const [images, setImages] = useState(KD.PAGE_IMAGES);
  const [selectedIds, setSelectedIds] = useState(
    KD.PAGE_IMAGES.filter((image) => image.selected).map((image) => image.id));
  const [mode, setMode] = useState('single');
  const [scanning, setScanning] = useState(false);

  /* ---------- library ---------- */
  const [downloads, setDownloads] = useState(KD.BATCH_TASKS.concat(KD.TASKS));
  const [batches, setBatches] = useState([KD.BATCH]);
  const [gallery, setGallery] = useState(KD.GALLERY);
  const [zips, setZips] = useState(KD.ZIPS);
  const [concurrency, setConcurrency] = useState(3);
  const [query, setQuery] = useState('');
  const [density, setDensity] = useState(2);

  /* ---------- overlays ---------- */
  const [viewer, setViewer] = useState(null);
  const [dialog, setDialog] = useState(null);
  const [toast, setToast] = useState('');

  const tasks = downloads.filter((item) => !item.batchId);

  /* a batch is a view over its member tasks — never duplicated state */
  const batchViews = batches.map((batch) => {
    const members = downloads.filter((item) => item.batchId === batch.id);
    const done = members.filter((item) => item.status === 'completed').length;
    const failed = members.filter((item) => item.status === 'failed' || item.status === 'cancelled').length;
    const settled = members.length > 0 && done + failed >= members.length;
    return {
      ...batch,
      total: members.length,
      done,
      failed,
      settled,
      status: settled ? 'packing' : 'downloading',
      members: members.slice(0, 3).map((item) => item.thumb),
    };
  });
  const batchKey = batchViews.map((batch) => batch.id + ':' + batch.settled).join(',');

  /* the packing effect needs the current archive list synchronously */
  const zipsRef = React.useRef(zips);
  useEffect(() => { zipsRef.current = zips; }, [zips]);

  useEffect(() => { document.documentElement.setAttribute('data-theme', theme); }, [theme]);

  const showNotice = useCallback((text) => {
    setToast(text);
    window.clearTimeout(showNotice.timer);
    showNotice.timer = window.setTimeout(() => setToast(''), 2600);
  }, []);

  /* ---------- live download simulation (mirrors DownloadStore.pump) ----------
     One shared queue: `concurrency` slots total across single downloads and
     batch members, exactly like the real DownloadStore. */
  useEffect(() => {
    const timer = window.setInterval(() => {
      setDownloads((prev) => {
        const advanced = prev.map((task) => {
          if (task.status !== 'running' || !task.total) { return task; }
          const processed = Math.min(task.total, task.processed + task.total * 0.04);
          return { ...task, processed, status: processed >= task.total ? 'completed' : 'running' };
        });
        let slots = concurrency - advanced.filter((task) => task.status === 'running').length;
        if (slots <= 0) { return advanced; }
        return advanced.map((task) => {
          if (slots > 0 && task.status === 'queued') { slots -= 1; return { ...task, status: 'running' }; }
          return task;
        });
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [concurrency]);

  /* ---------- every settled batch packs, then lands in 打包 ---------- */
  useEffect(() => {
    const packing = batchViews.filter((batch) => batch.settled);
    if (packing.length === 0) { return; }
    const timer = window.setTimeout(() => {
      const taken = zipsRef.current.slice();
      const archives = packing.map((batch) => {
        const name = uniqueZipName(batch.name, taken);
        const archive = {
          id: 'z' + batch.id,
          name,
          imageCount: batch.done,
          failedCount: batch.failed,
          size: batch.done * 1_640_000,
          at: '刚刚',
          thumbs: batch.members.slice(0, 3),
        };
        taken.push(archive);
        return archive;
      });
      setZips((prev) => archives.concat(prev));
      setBatches((prev) => prev.filter((batch) => !packing.some((item) => item.id === batch.id)));
      showNotice('打包完成 · ' + archives[0].name);
    }, 2600);
    return () => window.clearTimeout(timer);
  }, [batchKey, showNotice]);

  /* ---------- actions ---------- */
  const scan = useCallback(() => {
    setScanning(true);
    window.setTimeout(() => {
      setScanning(false);
      showNotice('找到 ' + images.length + ' 张图片');
    }, 1400);
  }, [images.length, showNotice]);

  const openAddress = () => {
    let input = address.trim();
    if (!input) { return; }
    if (!/^https?:\/\//.test(input)) { input = 'https://' + input; }
    setAddress(input.replace(/^https?:\/\//, ''));
    scan();
  };

  const toggleImage = (image) => {
    setSelectedIds((prev) =>
      prev.indexOf(image.id) >= 0 ? prev.filter((id) => id !== image.id) : prev.concat([image.id]));
  };

  const download = () => {
    const picked = images.filter((image) => selectedIds.indexOf(image.id) >= 0);
    if (picked.length === 0) { showNotice('请先选择图片'); return; }
    const stamp = Date.now();
    if (mode === 'zip') {
      const batchId = 'b' + stamp;
      const name = KD.PAGE.title + '.zip';
      const created = picked.map((image, index) => ({
        id: 'd' + stamp + '_' + index,
        name: image.name,
        status: 'queued',
        processed: 0,
        total: image.size,
        error: '',
        batchId,
        sourcePage: KD.PAGE.url,
        thumb: image.thumb,
        kind: image.kind,
      }));
      setBatches((prev) => [{
        id: batchId, name, error: '',
        sourcePage: KD.PAGE.url,
      }].concat(prev));
      setDownloads((prev) => created.concat(prev));
      showNotice('已把 ' + created.length + ' 张图片加入打包队列');
    } else {
      const created = picked.map((image, index) => ({
        id: 'd' + stamp + '_' + index,
        name: image.name,
        status: 'queued',
        processed: 0,
        total: image.size,
        error: '',
        batchId: '',
        sourcePage: KD.PAGE.url,
        thumb: image.thumb,
        kind: image.kind,
      }));
      setTasks((prev) => created.concat(prev));
      showNotice('已加入 ' + created.length + ' 个下载任务');
    }
    setSelectedIds([]);
    setTab('tasks');
  };

  const patchTask = (task, patch) => {
    setDownloads((prev) => prev.map((item) =>
      item.id === task.id ? { ...item, ...patch } : item));
  };

  const cancelTask = (task) => {
    patchTask(task, { status: 'cancelled', error: '已取消' });
    showNotice('已取消 ' + task.name);
  };

  const retryTask = (task) => {
    patchTask(task, { status: 'queued', error: '', processed: 0 });
    showNotice('重新加入队列');
  };

  /* ---------- dialogs ---------- */
  const renameTarget = dialog && dialog.type === 'rename' ? dialog.payload : null;

  const applyRename = (name) => {
    const target = renameTarget;
    if (!target) { return; }
    if (target.kind === 'zip') {
      const next = name.toLowerCase().endsWith('.zip') ? name : name + '.zip';
      setZips((prev) => prev.map((zip) => zip.id === target.item.id ? { ...zip, name: next } : zip));
    } else {
      setGallery((prev) => prev.map((image) => image.id === target.item.id ? { ...image, name } : image));
      if (viewer && viewer.id === target.item.id) { setViewer({ ...viewer, name }); }
    }
    setDialog(null);
    showNotice('重命名完成');
  };

  const confirmDialog = dialog && dialog.type === 'confirm' ? dialog : null;

  const runConfirm = () => {
    const conf = confirmDialog;
    if (!conf) { return; }
    if (conf.payload.action === 'delete-image') {
      setGallery((prev) => prev.filter((image) => image.id !== conf.payload.item.id));
      setViewer(null);
      showNotice('已删除图片');
    } else if (conf.payload.action === 'delete-zip') {
      setZips((prev) => prev.filter((zip) => zip.id !== conf.payload.item.id));
      showNotice('已删除压缩包');
    } else if (conf.payload.action === 'clear-all') {
      setGallery([]); setZips([]); setDownloads([]); setBatches([]); setViewer(null);
      showNotice('已清空全部记录');
    } else if (conf.payload.action === 'clean-temp') {
      showNotice('暂存目录已清理 · 释放 0 B');
    }
    setDialog(null);
  };

  const screenProps = { notice: toast };

  return (
    <div
      className="device"
      data-mat-type={matType}
      data-mat-level={resolvedLevel}
      data-light-effect={lightEffect ? 'on' : 'off'}
      data-peeking={peeking ? 'on' : 'off'}
    >
      {tab === 'discover' ?
        <DiscoverScreen
          {...screenProps}
          address={address}
          onAddressChange={setAddress}
          onOpen={openAddress}
          images={images}
          selectedIds={selectedIds}
          onToggle={toggleImage}
          onSelectAll={() => setSelectedIds(images.map((image) => image.id))}
          onClearAll={() => setSelectedIds([])}
          mode={mode}
          onModeChange={setMode}
          onDownload={download}
          scanning={scanning}
          onRescan={scan}
          grip={grip}
          hand={hand}
          onFlipHand={() => setHand(hand === 'left' ? 'right' : 'left')}
        /> : null}

      {tab === 'tasks' ?
        <TasksScreen
          {...screenProps}
          tasks={tasks}
          batches={batchViews}
          concurrency={concurrency}
          onConcurrency={setConcurrency}
          onCancel={cancelTask}
          onRetry={retryTask}
          onLocate={(task) => { setTab('gallery'); setQuery(task.name.replace(/\.[^.]+$/, '')); showNotice('已在图库中定位'); }}
          onRename={(task) => setDialog({ type: 'rename', payload: { kind: 'task', item: task } })}
        /> : null}

      {tab === 'gallery' ?
        <GalleryScreen
          {...screenProps}
          images={gallery}
          query={query}
          onQuery={setQuery}
          density={density}
          onDensity={() => setDensity(density === 2 ? 3 : 2)}
          onOpen={setViewer}
          viewer={viewer}
          onCloseViewer={() => setViewer(null)}
          onRename={(image) => setDialog({ type: 'rename', payload: { kind: 'image', item: image } })}
          onDelete={(image) => setDialog({ type: 'confirm', payload: { action: 'delete-image', item: image } })}
          onSaveToGallery={() => showNotice('已保存到系统相册')}
          onShare={() => showNotice('已调起系统分享')}
          onExport={() => showNotice('已导出到所选位置')}
        /> : null}

      {tab === 'zip' ?
        <ArchivesScreen
          {...screenProps}
          zips={zips}
          onRename={(zip) => setDialog({ type: 'rename', payload: { kind: 'zip', item: zip } })}
          onDelete={(zip) => setDialog({ type: 'confirm', payload: { action: 'delete-zip', item: zip } })}
          onExport={() => showNotice('已导出到所选位置')}
          onShare={() => showNotice('已调起系统分享')}
        /> : null}

      {tab === 'settings' ?
        <SettingsScreen
          {...screenProps}
          concurrency={concurrency}
          onConcurrency={setConcurrency}
          theme={theme}
          themeMode={themeMode}
          onThemeMode={setThemeMode}
          themeOptions={THEME_OPTIONS}
          lightEffect={lightEffect}
          onLightEffect={setLightEffect}
          matType={matType}
          onMatType={setMatType}
          matLevelMode={matLevelMode}
          onMatLevelMode={setMatLevelMode}
          deviceLevel={deviceLevel}
          resolvedLevel={resolvedLevel}
          grip={grip}
          onGrip={setGrip}
          hand={hand}
          antiPeek={antiPeek}
          onAntiPeek={(next) => { setAntiPeek(next); if (next) { setPeeking(true); } }}
          onCleanTemp={() => setDialog({ type: 'confirm', payload: { action: 'clean-temp' } })}
          onClearAll={() => setDialog({ type: 'confirm', payload: { action: 'clear-all' } })}
        /> : null}

      <TabBar
        items={TAB_ITEMS.map((item) => ({
          ...item,
          badge: item.key === 'tasks' ? activeCount(downloads, batchViews) : 0,
        }))}
        active={tab}
        onSelect={setTab}
      />

      {/* ---------- 防窥保护: content veil + system live view ---------- */}
      {peeking ?
        <React.Fragment>
          <div className="privacy-veil" role="alert" onClick={() => setPeeking(false)}>
            <span className="privacy-veil__mark"><Icon name="shield" size={28} /></span>
            <span className="privacy-veil__title" lang="zh">内容已隐藏</span>
            <span className="privacy-veil__body" lang="zh">
              防窥保护检测到他人可能正在注视屏幕，图片与压缩包已暂时遮罩。
            </span>
            <span className="privacy-veil__hint" lang="zh">轻点任意位置继续</span>
          </div>
          <div className="liveview" role="status">
            <span className="liveview__mark"><Icon name="eye" size={16} /></span>
            <span className="liveview__text">
              <span className="liveview__title" lang="zh">防窥保护</span>
              <span className="liveview__body" lang="zh">检测到他人注视屏幕，已隐藏内容</span>
            </span>
            <button
              type="button"
              className="liveview__close"
              data-light
              aria-label="关闭提醒"
              onClick={() => setPeeking(false)}
            >
              <Icon name="close" size={15} />
            </button>
          </div>
        </React.Fragment> : null}

      {/* ---------- overlays ---------- */}
      {renameTarget ?
        <RenameDialog
          title={renameTarget.kind === 'zip' ? '重命名压缩包' : '重命名图片'}
          initial={renameTarget.item.name}
          onSave={applyRename}
          onClose={() => setDialog(null)}
        /> : null}

      {confirmDialog ?
        <ConfirmDialog
          title={confirmDialog.payload.action === 'clear-all' ? '清空全部记录'
            : confirmDialog.payload.action === 'clean-temp' ? '清理临时文件'
            : confirmDialog.payload.action === 'delete-zip' ? '删除压缩包' : '删除图片'}
          body={confirmDialog.payload.action === 'clear-all'
            ? '将删除应用内的全部图片、压缩包与下载记录。已导出的副本不受影响。'
            : confirmDialog.payload.action === 'clean-temp'
            ? '删除暂存目录中残留的图片文件。正在进行的打包任务不受影响。'
            : confirmDialog.payload.action === 'delete-zip'
            ? '将同时删除压缩包文件和记录，已导出的副本不受影响。'
            : '将同时删除应用内文件和下载记录，已导出的副本不受影响。'}
          confirmLabel={confirmDialog.payload.action === 'clean-temp' ? '清理' : '删除'}
          tone={confirmDialog.payload.action === 'clean-temp' ? 'primary' : 'danger'}
          onConfirm={runConfirm}
          onClose={() => setDialog(null)}
        /> : null}
    </div>
  );
}

/* mirrors DownloadStore.uniqueName: never overwrite an existing archive */
function uniqueZipName(name, existing) {
  const dot = name.lastIndexOf('.');
  const base = dot > 0 ? name.slice(0, dot) : name;
  const ext = dot > 0 ? name.slice(dot) : '';
  let candidate = name;
  let count = 2;
  while (existing.some((zip) => zip.name === candidate)) {
    candidate = base + ' (' + count + ')' + ext;
    count += 1;
  }
  return candidate;
}

function activeCount(allTasks, batches) {
  const running = allTasks.filter((task) =>
    task.status === 'running' || task.status === 'starting' || task.status === 'queued').length;
  return running + batches.length;
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);