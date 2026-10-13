The floating search pill (328×40, r24) with its full state set.

```jsx
<FloatingSearch placeholder="搜索文件名" onChange={setQ} />
<FloatingSearch mode="typing" value={q} on on={true} cancel actionLabel="搜索" onAction={run} />
```

`mode` drives which text/caret layer renders; `on` reveals the trailing action region. The mandatory `__overlay` layer carries hover/pressed/focus.
