The floating toolbar for contextual actions inside a screen.

```jsx
<Toolbar variant="4" activeIndex={0} onSelect={setTool}
  items={[{icon:'square_and_pencil',label:'重命名'},{icon:'share',label:'分享'},
          {icon:'trash',label:'删除'},{icon:'more',label:'更多'}]} />
```

The item count locks the width. Items are focal components, so they carry the light effect.
