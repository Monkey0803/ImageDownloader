The floating title bar, in the reference's four variants.

```jsx
<Titlebar variant="normal" title="发现"
  actions={[{ glyph: "slider_horizontal_2", label: "偏好", onClick: openSettings }]} />
<Titlebar variant="secondary" title="设置" subtitle="下载偏好" onLeading={back} />
```

Pick the variant by the title block's semantics: a title plus a subtitle is `secondary`, never `normal` with a hand-rolled subtitle element. The bar is a floating layer — content scrolls under it, so do not make it a normal flex child.
