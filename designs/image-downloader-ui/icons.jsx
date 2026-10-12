/* ============================================================
   icons.jsx — one consistent 24px line-icon set
   (prototype stand-in for the HMSymbol glyph font)
   ============================================================ */

const ICONS = {
  search: (<><circle cx="11" cy="11" r="7" /><path d="M16.6 16.6 21 21" /></>),
  globe: (<><circle cx="12" cy="12" r="9" /><path d="M3 12h18" /><path d="M12 3c2.6 3 2.6 15 0 18" /><path d="M12 3c-2.6 3-2.6 15 0 18" /></>),
  refresh: (<><path d="M20.5 12a8.5 8.5 0 1 1-2.6-6.1" /><path d="M20.5 4.6V10H15" /></>),
  check: (<path d="M5 12.6 10 17.5 19 6.8" />),
  close: (<><path d="M6 6 18 18" /><path d="M18 6 6 18" /></>),
  download: (<><path d="M12 3.5v11" /><path d="M7.4 10.2 12 14.8l4.6-4.6" /><path d="M4.5 19.8h15" /></>),
  image: (<><rect x="3" y="4.5" width="18" height="15" rx="3" /><circle cx="8.6" cy="9.6" r="1.5" /><path d="M4.5 18l4.8-4.6 3 2.9 3.4-3.4 3.8 3.6" /></>),
  layers: (<><path d="M12 3.5 3.5 8l8.5 4.5L20.5 8z" /><path d="M3.5 12.6 12 17.1l8.5-4.5" /><path d="M3.5 16.9 12 21.4l8.5-4.5" /></>),
  archive: (<><rect x="3" y="4" width="18" height="4.6" rx="1.8" /><path d="M4.8 8.6v9.2a2 2 0 0 0 2 2h10.4a2 2 0 0 0 2-2V8.6" /><path d="M10 12.6h4" /></>),
  sliders: (<><path d="M4 7.5h8.4" /><path d="M18.4 7.5H20" /><circle cx="15.4" cy="7.5" r="2.2" /><path d="M4 16.5h3.4" /><path d="M13.4 16.5H20" /><circle cx="10.4" cy="16.5" r="2.2" /></>),
  trash: (<><path d="M4.5 7h15" /><path d="M9.5 7V5.4a1.4 1.4 0 0 1 1.4-1.4h2.2a1.4 1.4 0 0 1 1.4 1.4V7" /><path d="M6.6 7l.9 11.6a2 2 0 0 0 2 1.9h5a2 2 0 0 0 2-1.9L17.4 7" /><path d="M10.4 11v5.6" /><path d="M13.6 11v5.6" /></>),
  share: (<><circle cx="17.8" cy="5.6" r="2.6" /><circle cx="6.2" cy="12" r="2.6" /><circle cx="17.8" cy="18.4" r="2.6" /><path d="M8.5 10.7 15.5 7" /><path d="M8.5 13.3 15.5 17" /></>),
  export: (<><path d="M12 15.5V4" /><path d="M7.8 8.2 12 4l4.2 4.2" /><path d="M4.5 15.4v2.8a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-2.8" /></>),
  pencil: (<><path d="M4 20h4.2L19.4 8.8a2.6 2.6 0 0 0-3.7-3.7L4.5 16.3 4 20z" /><path d="M14.6 6.2l3.7 3.7" /></>),
  chevronRight: (<path d="M9.5 5.5 16 12l-6.5 6.5" />),
  grid: (<><rect x="4" y="4" width="7" height="7" rx="1.8" /><rect x="13" y="4" width="7" height="7" rx="1.8" /><rect x="4" y="13" width="7" height="7" rx="1.8" /><rect x="13" y="13" width="7" height="7" rx="1.8" /></>),
  chevronDown: (<path d="M5.5 9.5 12 16l6.5-6.5" />),
  play: (<path d="M8.2 5.6v12.8L18.6 12z" />),
  pause: (<><path d="M9.4 5.5v13" /><path d="M14.6 5.5v13" /></>),
  retry: (<><path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1" /><path d="M3.5 4.6V10H9" /></>),
  plus: (<><path d="M12 5.4v13.2" /><path d="M5.4 12h13.2" /></>),
  folder: (<path d="M3 7.2a2 2 0 0 1 2-2h3.5l2.1 2.2H19a2 2 0 0 1 2 2v8.4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />),
  sun: (<><circle cx="12" cy="12" r="4.2" /><path d="M12 2.6v2.2" /><path d="M12 19.2v2.2" /><path d="M4.4 4.4 6 6" /><path d="M18 18l1.6 1.6" /><path d="M2.6 12h2.2" /><path d="M19.2 12h2.2" /><path d="M4.4 19.6 6 18" /><path d="M18 6l1.6-1.6" /></>),
  moon: (<path d="M20.2 14.6A8.6 8.6 0 1 1 9.4 3.8a7 7 0 0 0 10.8 10.8z" />),
  clock: (<><circle cx="12" cy="12" r="8.4" /><path d="M12 7.4V12l3.4 2" /></>),
  alert: (<><circle cx="12" cy="12" r="8.6" /><path d="M12 7.8v4.8" /><path d="M12 16.1h.01" /></>),
  checkCircle: (<><circle cx="12" cy="12" r="8.6" /><path d="M8.2 12.3 11 15.1l5-5.2" /></>),
  xCircle: (<><circle cx="12" cy="12" r="8.6" /><path d="M9.4 9.4 14.6 14.6" /><path d="M14.6 9.4 9.4 14.6" /></>),
  scan: (<><path d="M4 9V6.5A2.5 2.5 0 0 1 6.5 4H9" /><path d="M15 4h2.5A2.5 2.5 0 0 1 20 6.5V9" /><path d="M20 15v2.5a2.5 2.5 0 0 1-2.5 2.5H15" /><path d="M9 20H6.5A2.5 2.5 0 0 1 4 17.5V15" /><path d="M4 12h16" /></>),
  window: (<><rect x="3" y="4.5" width="18" height="15" rx="2.6" /><path d="M3 9h18" /><path d="M6.4 6.8h.01" /><path d="M9.2 6.8h.01" /></>),
  inbox: (<><path d="M3.6 13.6 6 5.6a2 2 0 0 1 1.9-1.4h8.2A2 2 0 0 1 18 5.6l2.4 8" /><path d="M3.6 13.6H8l1.2 2.4h5.6l1.2-2.4h4.4v4.4a2 2 0 0 1-2 2H5.6a2 2 0 0 1-2-2z" /></>),
  sparkle: (<><path d="M12 3.4l1.7 4.9 4.9 1.7-4.9 1.7L12 16.6l-1.7-4.9L5.4 10l4.9-1.7z" /><path d="M18.4 16.4l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z" /></>),
  copy: (<><rect x="9" y="9" width="11.4" height="11.4" rx="2.4" /><path d="M5.6 15.4H4.6a1.6 1.6 0 0 1-1.6-1.6V5.6A1.6 1.6 0 0 1 4.6 4h8.2a1.6 1.6 0 0 1 1.6 1.6v1" /></>),
  grip: (<><rect x="7.6" y="3.2" width="8.8" height="17.6" rx="2.7" /><path d="M10.7 6.2h2.6" /><circle cx="4.3" cy="8.9" r="1.7" /><circle cx="19.7" cy="15.1" r="1.7" /></>),
  shield: (<><path d="M12 3.2 19 5.8v5.9c0 4.2-2.9 7.6-7 9.1-4.1-1.5-7-4.9-7-9.1V5.8z" /><path d="M9.3 12.1 11.4 14.2l3.5-3.6" /></>),
  eye: (<><path d="M2.9 12S6.5 5.9 12 5.9 21.1 12 21.1 12 17.5 18.1 12 18.1 2.9 12 2.9 12z" /><circle cx="12" cy="12" r="3" /></>),
  dot: (<circle cx="12" cy="12" r="3" />),
};

function Icon(props) {
  const { name, size = 24, stroke = 1.7, className, style } = props;
  return (
    <svg
      className={className}
      style={style}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={stroke}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {ICONS[name] || ICONS.dot}
    </svg>
  );
}

Object.assign(window, { Icon, ICONS });