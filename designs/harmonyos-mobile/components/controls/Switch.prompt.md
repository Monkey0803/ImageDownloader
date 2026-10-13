The system toggle: brand-filled track when on, neutral when off.

```jsx
<Switch on={enabled} label="沉浸光感" onChange={setEnabled} />
<Switch on disabled label="不可用" />
```

Rendered as `<button role="switch">` (the template uses a div) so it is keyboard reachable. Always pass `label` — the control has no text of its own.
