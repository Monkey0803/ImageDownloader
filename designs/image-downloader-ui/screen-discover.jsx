/* ============================================================
   screen-discover.jsx — 发现
   address pill → in-app browser → scan sweep → image grid → dock
   ============================================================ */

const PINS = [
  { left: '22%', top: '26%' },
  { left: '68%', top: '18%' },
  { left: '46%', top: '62%' },
  { left: '82%', top: '72%' },
];

function MiniBrowser(props) {
  const { page, heroThumb, count, sweeping, onRescan } = props;
  return (
    <div className="browser">
      <div className="browser__chrome">
        <span className="browser__dots">
          <i /><i /><i />
        </span>
        <span className="browser__url" lang="en">
          <Icon name="globe" size={12} stroke={2} />
          <span className="browser__urltext">{page.url}</span>
        </span>
        <button
          type="button"
          className="browser__rescan"
          aria-label="重新扫描"
          onClick={onRescan}
        >
          <Icon name="refresh" size={16} />
        </button>
      </div>

      <div className="browser__viewport">
        <Img src={heroThumb} alt={page.title} fallback="WEB" />
        <span className="browser__tint" />
        {sweeping ? <span className="browser__sweep" /> : null}
        {!sweeping && PINS.map((pin, index) =>
          <span
            key={index}
            className="browser__pin"
            style={{ left: pin.left, top: pin.top, animationDelay: (index * 70) + 'ms' }}
          >
            {index + 1}
          </span>
        )}
      </div>

      <div className="browser__foot">
        <span className="browser__title" lang="zh">{page.title}</span>
        <span className="browser__meta tnum">
          <Icon name="image" size={13} stroke={2} />
          {count} 张
        </span>
      </div>
    </div>
  );
}

function DiscoverScreen(props) {
  const {
    address, onAddressChange, onOpen,
    images, selectedIds, onToggle, onSelectAll, onClearAll,
    mode, onModeChange, onDownload,
    scanning, onRescan, notice,
    grip, hand, onFlipHand,
  } = props;

  const selectedCount = selectedIds.length;
  const selectedBytes = images
    .filter((image) => selectedIds.indexOf(image.id) >= 0)
    .reduce((sum, image) => sum + image.size, 0);

  return (
    <div className="screen fade-swap" data-screen-label="发现" data-titlebar="secondary">
      <Titlebar
        title="发现"
        subtitle={scanning ? '正在扫描当前网页…' : undefined}
      />

      <div className="scroll">
        <SearchPill
          value={address}
          placeholder="输入网页或图片链接"
          onChange={onAddressChange}
          onSubmit={onOpen}
          actionLabel="打开"
          icon="globe"
        />

        <MiniBrowser
          page={KD.PAGE}
          heroThumb={images.length ? images[0].thumb : ''}
          count={images.length}
          sweeping={scanning}
          onRescan={onRescan}
        />

        <div>
          <SectionHead title="选择要下载的图片" meta={selectedCount > 0 ? '已选 ' + selectedCount : images.length + ' 张'}>
            <button className="text-link" type="button" onClick={onSelectAll}>全选</button>
            <button className="text-link" type="button" onClick={onClearAll} disabled={selectedCount === 0}>清空</button>
          </SectionHead>
          <div className="grid-images">
            {images.map((image, index) =>
              <ImageTile
                key={image.id}
                image={image}
                index={index}
                selected={selectedIds.indexOf(image.id) >= 0}
                onToggle={onToggle}
              />
            )}
          </div>
        </div>

        <div className="hintrow" lang="zh">
          <Icon name="sparkle" size={14} stroke={1.8} />
          <span>扫描只读取当前页面的图片地址；滚动页面后重新扫描可以发现更多。</span>
        </div>
      </div>

      {grip ?
        <button
          type="button"
          className="grip-chip"
          data-light
          aria-label="切换握持手"
          title="智感握姿：点按切换握持手（原型模拟）"
          onClick={onFlipHand}
        >
          <Icon name="grip" size={14} />
          <span lang="zh">握姿 · <strong>{hand === 'left' ? '左手' : '右手'}</strong></span>
        </button> : null}

      {selectedCount > 0 ?
        <div className={'dock' + (grip && hand === 'left' ? ' dock--hand-left' : '')} data-component="selection-dock">
          <span className="dock__count">
            <span className="dock__num tnum" lang="zh">已选 {selectedCount} 张</span>
            <span className="dock__hint tnum" lang="zh">
              {mode === 'zip' ? '打包为 ZIP · ' : ''}{KD.formatBytes(selectedBytes)}
            </span>
          </span>
          <Segmented
            value={mode}
            onChange={onModeChange}
            options={[
              { value: 'single', label: '单张' },
              { value: 'zip', label: 'ZIP' },
            ]}
          />
          <Btn
            variant="primary"
            icon={mode === 'zip' ? 'layers' : 'download'}
            onClick={onDownload}
          >
            下载
          </Btn>
        </div> : null}
    </div>
  );
}

Object.assign(window, { DiscoverScreen });