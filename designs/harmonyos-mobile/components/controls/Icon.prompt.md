Renders one HMSymbol glyph from the official name dictionary — the only sanctioned icon source; never draw SVG.

```jsx
<Icon name="chevron_right" size={24} />
<Icon name="trash" label="删除" />
```

Names are validated against the generated map. `size` picks the reference's icon sizes (16/20/24). Pass `label` only when the icon carries meaning; decorative icons are aria-hidden automatically.
