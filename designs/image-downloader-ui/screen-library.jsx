/* ============================================================
   screen-library.jsx — 图库 / 打包
   ============================================================ */

function ArchiveStack(props) {
  const { thumbs, size = 56 } = props;
  const layers = (thumbs || []).slice(0, 3);
  return (
    <span className="arcstack" style={{ width: size + 'px', height: size + 'px' }}>
      {layers.map((thumb, index) =>
        <span
          key={index}
          className="arcstack__layer"
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
    </span>
  );
}

function GalleryScreen(props) {
  const {
    images, query, onQuery, density, onDensity, onOpen, onRename, onDelete,
    viewer, onCloseViewer, onSaveToGallery, onShare, onExport, notice,
  } = props;

  const filtered = images.filter((image) =>
    image.name.toLowerCase().indexOf(query.trim().toLowerCase()) >= 0);

  return (
    <div className="screen fade-swap" data-screen-label="图库" data-titlebar="secondary">
      <Titlebar
        title="图库"
        subtitle={images.length + ' 张图片 · ' + KD.formatBytes(images.reduce((sum, image) => sum + image.size, 0))}
        actions={[{
          icon: 'grid',
          label: density === 2 ? '切换为三列' : '切换为两列',
          onClick: onDensity,
        }]}
      />

      <div className="scroll">
        <SearchPill
          value={query}
          placeholder="搜索文件名"
          onChange={onQuery}
        />

        {filtered.length > 0 ?
          <div className={'grid-two' + (density === 3 ? ' grid-two--three' : '')}>
            {filtered.map((image) =>
              <div key={image.id} className="shot">
                <button
                  type="button"
                  className="shot__frame"
                  aria-label={image.name}
                  onClick={() => onOpen(image)}
                >
                  <Img src={image.thumb} alt={image.name} fallback={image.kind.toUpperCase()} />
                  <span className="shot__veil" />
                </button>
                <span className="shot__caption">
                  <span className="shot__name" lang="en">{image.name}</span>
                  <span className="shot__sub tnum">{KD.formatBytes(image.size)} · {image.at}</span>
                </span>
              </div>
            )}
          </div>
          :
          <Empty
            icon="image"
            title={query ? '没有匹配的图片' : '图库还是空的'}
            body={query ? '换一个关键词试试。' : '下载完成的图片会出现在这里。'}
          />
        }
      </div>

      {viewer ?
        <ImageViewer
          image={viewer}
          onClose={onCloseViewer}
          onRename={() => onRename(viewer)}
          onDelete={() => onDelete(viewer)}
          onSaveToGallery={() => onSaveToGallery(viewer)}
          onShare={() => onShare(viewer)}
          onExport={() => onExport(viewer)}
        /> : null}

      <Toast text={notice} />
    </div>
  );
}

function ImageViewer(props) {
  const { image, onClose, onRename, onDelete, onSaveToGallery, onShare, onExport } = props;
  return (
    <div className="viewer" data-screen-label="图片预览">
      <div className="viewer__top">
        <span className="viewer__name" lang="en">{image.name}</span>
        <button type="button" className="iconbtn iconbtn--sm iconbtn--plain" aria-label="关闭预览"
          style={{ color: '#fff' }} onClick={onClose}>
          <Icon name="close" size={20} />
        </button>
      </div>

      <div className="viewer__stage">
        <Img src={image.preview} alt={image.name} fallback={image.kind.toUpperCase()} />
      </div>

      <div className="viewer__bar">
        <button className="viewer__act" type="button" onClick={onRename}>
          <Icon name="pencil" size={21} /><span lang="zh">重命名</span>
        </button>
        <button className="viewer__act" type="button" onClick={onSaveToGallery}>
          <Icon name="download" size={21} /><span lang="zh">存相册</span>
        </button>
        <button className="viewer__act" type="button" onClick={onShare}>
          <Icon name="share" size={21} /><span lang="zh">分享</span>
        </button>
        <button className="viewer__act" type="button" onClick={onExport}>
          <Icon name="export" size={21} /><span lang="zh">导出</span>
        </button>
        <button className="viewer__act viewer__act--danger" type="button" onClick={onDelete}>
          <Icon name="trash" size={21} /><span lang="zh">删除</span>
        </button>
      </div>
    </div>
  );
}

function ArchivesScreen(props) {
  const { zips, onRename, onDelete, onExport, onShare, notice } = props;
  const totalBytes = zips.reduce((sum, zip) => sum + zip.size, 0);
  const totalImages = zips.reduce((sum, zip) => sum + zip.imageCount, 0);

  return (
    <div className="screen fade-swap" data-screen-label="打包" data-titlebar="secondary">
      <Titlebar
        title="打包"
        subtitle={zips.length + ' 个压缩包 · ' + totalImages + ' 张 · ' + KD.formatBytes(totalBytes)}
      />

      <div className="scroll">
        {zips.length === 0 ?
          <Empty icon="archive" title="还没有压缩包"
            body="在「发现」里打开 ZIP 模式，把选中的图片打包成一个压缩包。" /> : null}

        {zips.map((zip) =>
          <Card key={zip.id} className="card--pad">
            <div className="row" style={{ gap: 'var(--sp-6)', alignItems: 'flex-start' }}>
              <ArchiveStack thumbs={zip.thumbs} />
              <span className="list__text">
                <span className="zip__name" lang="zh">{zip.name}</span>
                <span className="list__aux tnum">
                  {zip.imageCount} 张图片 · {KD.formatBytes(zip.size)}
                </span>
                <span className="list__aux" lang="zh">
                  {zip.at}
                  {zip.failedCount > 0 ?
                    <span className="zip__warn"> · {zip.failedCount} 张下载失败未打包</span> : null}
                </span>
              </span>
            </div>
            <div className="zip__actions">
              <Btn size="sm" variant="ghost" icon="pencil" onClick={() => onRename(zip)}>重命名</Btn>
              <Btn size="sm" variant="ghost" icon="export" onClick={() => onExport(zip)}>导出</Btn>
              <Btn size="sm" variant="ghost" icon="share" onClick={() => onShare(zip)}>分享</Btn>
              <span className="spacer" />
              <button
                type="button"
                className="iconbtn iconbtn--sm iconbtn--plain zip__del"
                aria-label={'删除 ' + zip.name}
                title="删除"
                onClick={() => onDelete(zip)}
              >
                <Icon name="trash" size={18} />
              </button>
            </div>
          </Card>
        )}
      </div>

      <Toast text={notice} />
    </div>
  );
}

Object.assign(window, { GalleryScreen, ArchivesScreen, ImageViewer, ArchiveStack });