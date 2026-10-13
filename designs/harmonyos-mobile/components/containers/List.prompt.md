The list row in the reference's six height variants, with dividers that skip the icon area.

```jsx
<List variant="icon2lines" appIconSrc="/logo.png" title="文件名来源"
      aux="优先用服务器返回的文件名" rightText="服务器优先" rightIcon="chevron" onClick={open} />
<List variant="single" title="同时下载数量" rightIcon="arrow-down" rightText="3" />
```

`variant` decides the row height and the left layout — there are exactly six, and the divider inset follows from the variant, so do not hand-tune line positions. A tappable row opts into the light effect automatically.
