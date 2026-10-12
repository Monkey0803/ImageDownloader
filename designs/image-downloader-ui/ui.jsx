/* ============================================================
   ui.jsx — presentational shell components
   (HarmonyOS floating title bar, glass bottom tab, list rows…)
   ============================================================ */
const { useState, useEffect, useRef, useCallback } = React;

/* ---------- image with graceful fallback + loading skeleton ---------- */
function Img(props) {
  const { src, alt, className, style, fallback } = props;
  const [state, setState] = useState('loading');
  useEffect(() => { setState(src ? 'loading' : 'error'); }, [src]);
  if (state === 'error' || !src) {
    return <span className={'img-fallback ' + (className || '')} style={style}>{fallback || 'IMG'}</span>;
  }
  return (
    <img
      src={src}
      alt={alt || ''}
      className={(className || '') + (state === 'loading' ? ' is-loading' : '')}
      style={style}
      loading="lazy"
      decoding="async"
      onLoad={() => setState('loaded')}
      onError={() => setState('error')}
    />
  );
}

/* ---------- floating title bar ---------- */
function Titlebar(props) {
  const { title, subtitle, actions } = props;
  return (
    <header className="titlebar" data-component="titlebar">
      <div className="titlebar__row">
        <div className="titlebar__text">
          <h2 className="titlebar__title" lang="zh">{title}</h2>
          {subtitle ? <p className="titlebar__sub" lang="zh">{subtitle}</p> : null}
        </div>
        <div className="row" style={{ gap: 'var(--sp-3)' }}>
          {(actions || []).map((action) =>
            <button
              key={action.label}
              type="button"
              className="iconbtn"
              data-light
              aria-label={action.label}
              title={action.label}
              onClick={action.onClick}
            >
              <Icon name={action.icon} size={21} />
            </button>
          )}
        </div>
      </div>
    </header>
  );
}

/* ---------- glass pill bottom tab ---------- */
function TabBar(props) {
  const { items, active, onSelect } = props;
  return (
    <nav className="tabbar" data-component="bottomtab">
      <div className="tabbar__bar" data-variant={items.length}>
        {items.map((item) =>
          <button
            key={item.key}
            type="button"
            className={'tabbar__tab' + (active === item.key ? ' tabbar__tab--active' : '')}
            data-light
            aria-pressed={active === item.key}
            onClick={() => onSelect(item.key)}
          >
            <span style={{ position: 'relative', display: 'grid', placeItems: 'center' }}>
              <Icon name={item.icon} size={23} stroke={active === item.key ? 2 : 1.7} />
              {item.badge > 0 ?
                <span className="tabbar__badge tnum">{item.badge}</span> : null}
            </span>
            <span className="tabbar__label" lang="zh">{item.label}</span>
          </button>
        )}
      </div>
    </nav>
  );
}

/* ---------- search pill ---------- */
function SearchPill(props) {
  const { value, placeholder, onChange, onSubmit, actionLabel, icon } = props;
  const [focus, setFocus] = useState(false);
  return (
    <div className={'search' + (focus ? ' search--focus' : '')}>
      <span className="search__icon"><Icon name={icon || 'search'} size={18} /></span>
      <input
        className="search__input"
        value={value}
        placeholder={placeholder}
        lang="zh"
        onChange={(event) => onChange(event.target.value)}
        onFocus={() => setFocus(true)}
        onBlur={() => setFocus(false)}
        onKeyDown={(event) => { if (event.key === 'Enter' && onSubmit) { onSubmit(); } }}
      />
      {actionLabel ?
        <button className="search__go" type="button" onClick={onSubmit} disabled={!value || !value.trim()}>
          {actionLabel}
        </button> : null}
    </div>
  );
}

/* ---------- buttons ---------- */
function Btn(props) {
  const { variant = 'ghost', size, icon, children, onClick, disabled, className, style } = props;
  const classes = ['btn', 'btn--' + variant];
  if (size === 'sm') { classes.push('btn--sm'); }
  if (className) { classes.push(className); }
  return (
    <button className={classes.join(' ')} type="button" data-light onClick={onClick} disabled={disabled} style={style}>
      {icon ? <Icon name={icon} size={size === 'sm' ? 15 : 17} stroke={1.9} /> : null}
      {children}
    </button>
  );
}

function IconBtn(props) {
  const { icon, label, onClick, size = 21, plain } = props;
  return (
    <button
      type="button"
      className={'iconbtn iconbtn--sm' + (plain ? ' iconbtn--plain' : '')}
      data-light
      aria-label={label}
      title={label}
      onClick={onClick}
    >
      <Icon name={icon} size={size} />
    </button>
  );
}

/* ---------- layout helpers ---------- */
function Card(props) {
  const { children, className, style, onClick } = props;
  return (
    <div className={'card ' + (className || '')} style={style} onClick={onClick}>
      {children}
    </div>
  );
}

function SectionHead(props) {
  return (
    <div className="section-head">
      <span className="section-head__title" lang="zh">{props.title}</span>
      {props.meta ? <span className="section-head__meta tnum">{props.meta}</span> : null}
      <span className="section-head__spacer" />
      {props.children}
    </div>
  );
}

/* ---------- chip ---------- */
function Chip(props) {
  const { tone, icon, children } = props;
  return (
    <span className={'chip ' + (tone || '')}>
      {icon ? <Icon name={icon} size={12} stroke={2.2} /> : null}
      {children}
    </span>
  );
}

function StatusChip(props) {
  const { status } = props;
  const meta = KD.STATUS[status] || KD.STATUS.queued;
  const pulsing = KD.PULSING_STATUS.indexOf(status) >= 0;
  return <Chip tone={meta.chip} icon={pulsing ? null : meta.icon}>
    {pulsing ? <span className="chip__dot" /> : null}
    {meta.label}
  </Chip>;
}

/* ---------- progress ---------- */
function Progress(props) {
  const { value, tone } = props;
  return (
    <div className="progress" role="progressbar" aria-valuenow={Math.round(value)} aria-valuemin={0} aria-valuemax={100}>
      <div
        className={'progress__fill' + (tone ? ' progress__fill--' + tone : '')}
        style={{ width: Math.max(2, value) + '%' }}
      />
    </div>
  );
}

/* ---------- list ---------- */
function ListRow(props) {
  const { icon, iconTone, title, aux, right, onClick, divider } = props;
  return (
    <div
      className={'list__row' + (icon ? ' list__row--icon' : '') + (onClick ? ' list__row--tap' : '')}
      data-light={onClick ? true : undefined}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (event) => { if (event.key === 'Enter') { onClick(); } } : undefined}
    >
      {icon ? <span className={'list__icon' + (iconTone === 'brand' ? ' list__icon--brand' : '')}>
        <Icon name={icon} size={20} />
      </span> : null}
      <div className="list__text">
        <span className="list__title" lang="zh">{title}</span>
        {aux ? <span className="list__aux" lang="zh">{aux}</span> : null}
      </div>
      <span className="list__right">{right}</span>
    </div>
  );
}

function Switch(props) {
  const { on, onToggle, label } = props;
  return (
    <button
      type="button"
      className={'switch' + (on ? ' switch--on' : '')}
      data-light
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={onToggle}
    >
      <span className="switch__knob" />
    </button>
  );
}

function Slider(props) {
  const { value, min, max, step = 1, onChange } = props;
  return (
    <div className="slider">
      <input
        className="slider__input"
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        aria-label="同时下载数量"
        onChange={(event) => onChange(Number(event.target.value))}
      />
      <span className="slider__value tnum">{value}</span>
    </div>
  );
}

function Segmented(props) {
  const { options, value, onChange, idPrefix } = props;
  return (
    <div className="seg">
      {options.map((option) =>
        <button
          key={option.value}
          type="button"
          className={'seg__item' + (value === option.value ? ' seg__item--on' : '')}
          data-light
          aria-pressed={value === option.value}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      )}
    </div>
  );
}

/* ---------- overlays ---------- */
function Sheet(props) {
  const { title, body, children, onClose } = props;
  return (
    <div className="scrim" onClick={onClose}>
      <div className="sheet" onClick={(event) => event.stopPropagation()}>
        <span className="sheet__grab" />
        {title ? <h3 className="sheet__title" lang="zh">{title}</h3> : null}
        {body ? <p className="sheet__body" lang="zh">{body}</p> : null}
        {children}
      </div>
    </div>
  );
}

function ConfirmDialog(props) {
  const { title, body, confirmLabel, cancelLabel = '取消', tone, onConfirm, onClose } = props;
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" onClick={(event) => event.stopPropagation()}>
        <h3 className="dialog__title" lang="zh">{title}</h3>
        <p className="dialog__body" lang="zh">{body}</p>
        <div className="dialog__actions">
          <Btn variant="ghost" onClick={onClose}>{cancelLabel}</Btn>
          <Btn variant={tone === 'danger' ? 'danger' : 'primary'} onClick={onConfirm}>{confirmLabel}</Btn>
        </div>
      </div>
    </div>
  );
}

function RenameDialog(props) {
  const { title, initial, onSave, onClose } = props;
  const [value, setValue] = useState(initial);
  const inputRef = useRef(null);
  useEffect(() => {
    if (inputRef.current) { inputRef.current.focus(); inputRef.current.select(); }
  }, []);
  const submit = () => { const next = value.trim(); if (next.length > 0) { onSave(next); } };
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" onClick={(event) => event.stopPropagation()}>
        <h3 className="dialog__title" lang="zh">{title}</h3>
        <input
          ref={inputRef}
          className="dialog__field"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') { submit(); } }}
        />
        <div className="dialog__actions">
          <Btn variant="ghost" onClick={onClose}>取消</Btn>
          <Btn variant="primary" onClick={submit} disabled={!value.trim()}>保存</Btn>
        </div>
      </div>
    </div>
  );
}

function Toast(props) {
  if (!props.text) { return null; }
  return <div className="toast" role="status" lang="zh">{props.text}</div>;
}

function Empty(props) {
  return (
    <div className="empty">
      <span className="empty__icon"><Icon name={props.icon || 'inbox'} size={30} /></span>
      <span className="empty__title" lang="zh">{props.title}</span>
      {props.body ? <span className="empty__body" lang="zh">{props.body}</span> : null}
      {props.action}
    </div>
  );
}

/* ---------- image tile ---------- */
function ImageTile(props) {
  const { image, selected, onToggle, index } = props;
  return (
    <button
      type="button"
      className={'tile' + (selected ? ' tile--on' : '')}
      aria-pressed={selected}
      aria-label={image.description || image.name}
      onClick={() => onToggle(image)}
    >
      <Img src={image.thumb} alt={image.description} fallback={image.kind.toUpperCase()} />
      <span className="tile__veil" />
      <span className="tile__check"><Icon name="check" size={13} stroke={2.6} /></span>
      <span className="tile__idx tnum">{String(index + 1).padStart(2, '0')}</span>
    </button>
  );
}

Object.assign(window, {
  Img, Titlebar, TabBar, SearchPill, Btn, IconBtn, Card, SectionHead,
  Chip, StatusChip, Progress, ListRow, Switch, Slider, Segmented,
  Sheet, ConfirmDialog, RenameDialog, Toast, Empty, ImageTile,
});