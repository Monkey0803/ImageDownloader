The device canvas every screen mounts into. It carries the theme and material attributes and runs the light-effect delegate.

```jsx
<SizeFrame theme="dark" materialType="immersive" materialLevel="exquisite"
           statusbar={<StatusBar time="09:41" />}>
  <Titlebar variant="normal" title="发现" />
  <BottomTab variant="3" items={tabs} activeIndex={0} />
</SizeFrame>
```

Put `data-material-level` / `data-material-type` HERE and nowhere else: material tokens are composed on this element, so moving the attributes deeper silently disables the material system.

The frame also owns PLACEMENT of the floating shell layers — pass them as `titlebar`
and `bottomBar` rather than as children. A title bar placed as a child lands in the
content flow (its own CSS is `position: relative`), which overlaps the first content
item and silently breaks the mandatory 8px gap.

```jsx
<SizeFrame titlebar={<Titlebar variant="normal" title="首页" />}
           bottomBar={<BottomTab variant="4" items={tabs} activeIndex={0} />}>
  ...content...
</SizeFrame>
```

Leave `statusbar` empty when a Titlebar is present: the title bar carries its own
36px status row, and providing both reserves that band twice.
