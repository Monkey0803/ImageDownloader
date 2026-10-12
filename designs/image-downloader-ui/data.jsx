/* ============================================================
   data.jsx — mock content mirroring the app's real data models
   Models.ets: PictureItem / DownloadItem / ZipItem / BatchItem
   ============================================================ */

const photo = (seed, w, h) => 'https://picsum.photos/seed/' + seed + '/' + w + '/' + h;

/* ---- the page sitting in the built-in browser ---- */
const PAGE = {
  title: '青空写真馆 · 京都の秋',
  url: 'aozora.example.com/kyoto-autumn',
  host: 'aozora.example.com',
  scannedAt: '14:32',
};

const PAGE_IMAGES = [
  { id: 'i1',  seed: 'kyoto1',  alt: '东福寺通天桥的红叶',      size: 1_842_000, kind: 'jpg' },
  { id: 'i2',  seed: 'kyoto2',  alt: '清水寺本堂与舞台',        size: 2_104_000, kind: 'jpg' },
  { id: 'i3',  seed: 'kyoto3',  alt: '岚山竹林小径',            size: 1_536_000, kind: 'webp' },
  { id: 'i4',  seed: 'kyoto4',  alt: '鸭川河畔的傍晚',          size: 1_265_000, kind: 'jpg' },
  { id: 'i5',  seed: 'kyoto5',  alt: '伏见稻荷千本鸟居',        size: 2_489_000, kind: 'jpg' },
  { id: 'i6',  seed: 'kyoto6',  alt: '金阁寺雪后',              size: 987_000,   kind: 'png' },
  { id: 'i7',  seed: 'kyoto7',  alt: '哲学之道沿河樱花',        size: 1_701_000, kind: 'jpg' },
  { id: 'i8',  seed: 'kyoto8',  alt: '二年坂石阶',              size: 1_318_000, kind: 'jpg' },
  { id: 'i9',  seed: 'kyoto9',  alt: '贵船神社的灯笼路',        size: 1_092_000, kind: 'webp' },
  { id: 'i10', seed: 'kyoto10', alt: '平安神宫朱红鸟居',        size: 1_640_000, kind: 'jpg' },
  { id: 'i11', seed: 'kyoto11', alt: '建仁寺双龙图',            size: 2_230_000, kind: 'jpg' },
  { id: 'i12', seed: 'kyoto12', alt: '南禅寺水路阁',            size: 1_450_000, kind: 'jpg' },
].map((item, index) => ({
  id: item.id,
  url: photo(item.seed, 900, 900),
  thumb: photo(item.seed, 320, 320),
  preview: photo(item.seed, 900, 900),
  name: 'kyoto-' + String(index + 1).padStart(2, '0') + '.' + item.kind,
  description: item.alt,
  size: item.size,
  kind: item.kind,
  page: index,
  selected: index < 3,
}));

/* ---- download queue (DownloadItem) ---- */
const TASKS = [
  {
    id: 'd1', name: 'kyoto-07.jpg', status: 'running', processed: 1_240_000, total: 1_701_000,
    error: '', batchId: '', sourcePage: PAGE.url, thumb: PAGE_IMAGES[6].thumb, kind: 'jpg',
  },
  {
    id: 'd2', name: 'kyoto-05.jpg', status: 'running', processed: 402_000, total: 2_489_000,
    error: '', batchId: '', sourcePage: PAGE.url, thumb: PAGE_IMAGES[4].thumb, kind: 'jpg',
  },
  {
    id: 'd3', name: 'kyoto-garden-04.webp', status: 'queued', processed: 0, total: 1_092_000,
    error: '', batchId: '', sourcePage: PAGE.url, thumb: PAGE_IMAGES[8].thumb, kind: 'webp',
  },
  {
    id: 'd4', name: 'poster-raw.tiff', status: 'failed', processed: 0, total: 0,
    error: '服务器返回的不是图片', batchId: '', sourcePage: PAGE.url, thumb: PAGE_IMAGES[5].thumb, kind: 'tiff',
  },
  {
    id: 'd5', name: 'kyoto-02.jpg', status: 'completed', processed: 2_104_000, total: 2_104_000,
    error: '', batchId: '', sourcePage: PAGE.url, thumb: PAGE_IMAGES[1].thumb, kind: 'jpg',
  },
];

/* ---- ZIP batch in flight (BatchItem) — its members are real tasks ---- */
const BATCH_ID = 'b1';

const BATCH_TASKS = PAGE_IMAGES.map((image, index) => {
  const state = index < 8 ? 'completed' : index === 8 ? 'failed' : 'running';
  const progress = [0.22, 0.34, 0.46][index - 9] || 0;
  return {
    id: 'bt' + (index + 1),
    name: image.name,
    status: state,
    processed: state === 'completed' ? image.size : Math.round(image.size * progress),
    total: image.size,
    error: state === 'failed' ? 'HTTP 403 Forbidden' : '',
    batchId: BATCH_ID,
    sourcePage: PAGE.url,
    thumb: image.thumb,
    kind: image.kind,
  };
});

const BATCH = {
  id: BATCH_ID,
  name: '青空写真馆 · 京都の秋.zip',
  status: 'downloading',
  error: '',
  sourcePage: PAGE.url,
  done: 8,
  total: 12,
  failed: 1,
  members: [0, 3, 6].map((i) => PAGE_IMAGES[i].thumb),
};

/* ---- gallery (completed downloads, no batch) ---- */
const GALLERY = [
  { id: 'g1', name: 'kyoto-02.jpg',        size: 2_104_000, at: '今天 14:28', thumb: PAGE_IMAGES[1].thumb, preview: PAGE_IMAGES[1].preview, kind: 'jpg' },
  { id: 'g2', name: 'kyoto-01.jpg',        size: 1_842_000, at: '今天 14:26', thumb: PAGE_IMAGES[0].thumb, preview: PAGE_IMAGES[0].preview, kind: 'jpg' },
  { id: 'g3', name: 'Fushimi-Torii.jpg',   size: 2_489_000, at: '今天 11:02', thumb: PAGE_IMAGES[4].thumb, preview: PAGE_IMAGES[4].preview, kind: 'jpg' },
  { id: 'g4', name: 'kinkakuji-snow.png',  size: 987_000,   at: '昨天 20:41', thumb: PAGE_IMAGES[5].thumb, preview: PAGE_IMAGES[5].preview, kind: 'png' },
  { id: 'g5', name: 'arashiyama.webp',     size: 1_536_000, at: '昨天 20:38', thumb: PAGE_IMAGES[2].thumb, preview: PAGE_IMAGES[2].preview, kind: 'webp' },
  { id: 'g6', name: 'kamogawa-dusk.jpg',   size: 1_265_000, at: '昨天 18:15', thumb: PAGE_IMAGES[3].thumb, preview: PAGE_IMAGES[3].preview, kind: 'jpg' },
  { id: 'g7', name: 'heian-jingu.jpg',     size: 1_640_000, at: '10-09 09:24', thumb: PAGE_IMAGES[9].thumb, preview: PAGE_IMAGES[9].preview, kind: 'jpg' },
  { id: 'g8', name: 'kibune-lantern.webp', size: 1_092_000, at: '10-09 09:20', thumb: PAGE_IMAGES[8].thumb, preview: PAGE_IMAGES[8].preview, kind: 'webp' },
  { id: 'g9', name: 'kenninji-dragon.jpg', size: 2_230_000, at: '10-08 22:07', thumb: PAGE_IMAGES[10].thumb, preview: PAGE_IMAGES[10].preview, kind: 'jpg' },
];

/* ---- archives (ZipItem) ---- */
const ZIPS = [
  { id: 'z1', name: '清水寺素材包.zip',      imageCount: 24, failedCount: 0, size: 38_420_000, at: '今天 13:05', members: [1, 0, 4] },
  { id: 'z2', name: '京都-红叶-2024.zip',   imageCount: 12, failedCount: 1, size: 21_760_000, at: '昨天 21:12', members: [2, 3, 5] },
  { id: 'z3', name: '壁纸-竖版.zip',        imageCount: 36, failedCount: 0, size: 62_150_000, at: '10-07 16:48', members: [6, 7, 8] },
].map((z) => ({ ...z, thumbs: z.members.map((i) => PAGE_IMAGES[i].thumb) }));

/* ---- helpers ---- */
function formatBytes(bytes) {
  if (!bytes) { return '—'; }
  if (bytes < 1024) { return bytes + ' B'; }
  if (bytes < 1024 * 1024) { return (bytes / 1024).toFixed(0) + ' KB'; }
  if (bytes < 1024 * 1024 * 1024) { return (bytes / 1024 / 1024).toFixed(1) + ' MB'; }
  return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

function percent(processed, total) {
  if (!total || total <= 0) { return 0; }
  return Math.max(0, Math.min(100, Math.round((processed / total) * 100)));
}

const STATUS = {
  queued:      { label: '排队中',   chip: '',             icon: 'clock' },
  starting:    { label: '正在启动', chip: '',             icon: 'clock' },
  downloading: { label: '下载中',   chip: 'chip--brand',  icon: 'download' },
  running:     { label: '下载中',   chip: 'chip--brand',  icon: 'download' },
  packing:     { label: '打包中',   chip: 'chip--brand',  icon: 'layers' },
  completed:   { label: '已完成',   chip: 'chip--ok',     icon: 'checkCircle' },
  failed:      { label: '失败',     chip: 'chip--warn',   icon: 'alert' },
  cancelled:   { label: '已取消',   chip: '',             icon: 'xCircle' },
};

const PULSING_STATUS = ['downloading', 'running', 'packing'];

const ACTIVE_STATUS = ['queued', 'starting', 'running', 'packing'];

Object.assign(window, {
  KD: {
    PAGE, PAGE_IMAGES, TASKS, BATCH, BATCH_TASKS, GALLERY, ZIPS,
    formatBytes, percent, STATUS, ACTIVE_STATUS, PULSING_STATUS,
  },
});