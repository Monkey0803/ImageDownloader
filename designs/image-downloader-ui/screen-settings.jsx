/* ============================================================
   screen-settings.jsx — 设置
   ============================================================ */

function SettingsScreen(props) {
  const {
    concurrency, onConcurrency, notice,
    theme, themeMode, onThemeMode, themeOptions,
    lightEffect, onLightEffect,
    matType, onMatType, matLevelMode, onMatLevelMode, deviceLevel, resolvedLevel,
    grip, onGrip, hand,
    antiPeek, onAntiPeek,
    onCleanTemp, onClearAll,
  } = props;

  const themeName = theme === 'dark' ? '深色' : '浅色';
  const LEVEL_NAME = { exquisite: '精致', gentle: '均衡', smooth: '轻盈' };
  const TIER_NAME = { exquisite: '高算力', gentle: '中算力', smooth: '低算力' };
  const immersiveDegraded = matType === 'immersive' && resolvedLevel === 'smooth';

  return (
    <div className="screen fade-swap" data-screen-label="设置" data-titlebar="normal">
      <Titlebar title="设置" />

      <div className="scroll scroll--plain">
        <div>
          <SectionHead title="外观" />
          <Card className="card--flush">
            <div className="list__row list__row--icon" style={{ alignItems: 'flex-start' }}>
              <span className="list__icon"><Icon name={theme === 'dark' ? 'moon' : 'sun'} size={20} /></span>
              <div className="list__text">
                <span className="list__title" lang="zh">主题</span>
                <span className="list__aux" lang="zh">
                  {themeMode === 'system' ? '跟随系统 · 当前为' + themeName : '固定为' + themeName}
                </span>
                <div style={{ marginTop: 'var(--sp-5)' }}>
                  <Segmented value={themeMode} onChange={onThemeMode} options={themeOptions} />
                </div>
              </div>
            </div>
          </Card>
        </div>

        <div>
          <SectionHead title="系统特性" meta="HarmonyOS" />

          <Card className="card--flush">
            <ListRow
              icon="sparkle"
              iconTone="brand"
              title="沉浸光感"
              aux="触摸时材质表面被点亮，并带交互形变"
              right={<Switch on={lightEffect} onToggle={() => onLightEffect(!lightEffect)} label="沉浸光感" />}
            />

            <div className="list__row list__row--icon" style={{ alignItems: 'flex-start' }}>
              <span className="list__icon"><Icon name="layers" size={20} /></span>
              <div className="list__text">
                <span className="list__title" lang="zh">材质类型</span>
                <span className="list__aux" lang="zh">
                  {matType === 'immersive'
                    ? immersiveDegraded
                      ? '设备不支持时降级为静态模糊（当前已降级）'
                      : '沉浸式材质 · 含边缘流光'
                    : '由系统按场景自动选择材质风格'}
                </span>
                <div style={{ marginTop: 'var(--sp-5)' }}>
                  <Segmented
                    value={matType}
                    onChange={onMatType}
                    options={[
                      { value: 'adaptive', label: '自适应' },
                      { value: 'immersive', label: '沉浸式' },
                    ]}
                  />
                </div>
              </div>
            </div>

            <div className="list__row list__row--icon" style={{ alignItems: 'flex-start' }}>
              <span className="list__icon"><Icon name="sliders" size={20} /></span>
              <div className="list__text">
                <span className="list__title" lang="zh">材质等级</span>
                <span className="list__aux" lang="zh">
                  {matLevelMode === 'auto'
                    ? '跟随设备 · 本机为' + LEVEL_NAME[deviceLevel] + '（' + TIER_NAME[deviceLevel] + '）'
                    : '已手动设为' + LEVEL_NAME[resolvedLevel] + '，模糊与透明度随之变化'}
                </span>
                <div style={{ marginTop: 'var(--sp-5)' }}>
                  <Segmented
                    value={matLevelMode}
                    onChange={onMatLevelMode}
                    options={[
                      { value: 'auto', label: '跟随设备' },
                      { value: 'exquisite', label: '精致' },
                      { value: 'gentle', label: '均衡' },
                      { value: 'smooth', label: '轻盈' },
                    ]}
                  />
                </div>
              </div>
            </div>
          </Card>

          <Card className="card--flush" style={{ marginTop: 'var(--sp-6)' }}>
            <ListRow
              icon="grip"
              title="智感握姿"
              aux={grip
                ? '主操作跟随握持手 · 当前握持' + (hand === 'left' ? '左手' : '右手')
                : '按握持手调整主操作位置'}
              right={<Switch on={grip} onToggle={() => onGrip(!grip)} label="智感握姿" />}
            />
            <ListRow
              icon="shield"
              title="防窥保护"
              aux={antiPeek
                ? '已接入 · 检测到窥视时立即隐藏内容'
                : '检测到他人窥视时隐藏内容并顶部提醒'}
              right={<Switch on={antiPeek} onToggle={() => onAntiPeek(!antiPeek)} label="防窥保护" />}
            />
          </Card>

          <p className="setting-foot" lang="zh">
            以上为 HarmonyOS 系统级能力：光感与材质来自 UI Design Kit，应用侧可在
            module.json5 配置 <code>ohos.arkui.UIMaterial.state</code>；智感握姿与防窥保护需先在
            「设置 &gt; 系统」与「设置 &gt; 隐私和安全」中开启，应用侧只负责接入与响应。
          </p>
        </div>

        <div>
          <SectionHead title="下载" />
          <Card className="card--flush">
            <div className="list__row list__row--icon" style={{ alignItems: 'flex-start' }}>
              <span className="list__icon list__icon--brand"><Icon name="download" size={20} /></span>
              <div className="list__text">
                <span className="list__title" lang="zh">同时下载数量</span>
                <span className="list__aux" lang="zh">超出的任务自动排队，范围 1–10</span>
                <div style={{ marginTop: 'var(--sp-5)' }}>
                  <Slider value={concurrency} min={1} max={10} onChange={onConcurrency} />
                </div>
              </div>
            </div>

            <ListRow
              icon="folder"
              title="文件名来源"
              aux="优先用服务器返回的文件名，其次用网页描述"
              right={<span lang="zh">服务器优先</span>}
            />
            <ListRow
              icon="archive"
              title="下载位置"
              aux="应用文件 · 图片与压缩包分开存放"
              right={<React.Fragment>
                <span lang="zh">应用文件</span>
                <Icon name="chevronRight" size={15} />
              </React.Fragment>}
            />
          </Card>
        </div>

        <div>
          <SectionHead title="数据" />
          <Card className="card--flush">
            <ListRow
              icon="trash"
              title="清理临时文件"
              aux="打包中断后残留在暂存目录的图片"
              onClick={onCleanTemp}
              right={<Icon name="chevronRight" size={15} />}
            />
            <ListRow
              icon="xCircle"
              title="清空全部下载记录"
              aux="删除应用内的文件与记录，已导出的副本不受影响"
              onClick={onClearAll}
              right={<Icon name="chevronRight" size={15} />}
            />
          </Card>
        </div>

        <p className="tiny" style={{ textAlign: 'center', paddingTop: 'var(--sp-2)' }} lang="zh">
          图片下载管理 · 1.0.0
        </p>
      </div>

      <Toast text={notice} />
    </div>
  );
}

Object.assign(window, { SettingsScreen });