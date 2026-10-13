The glass pill tab bar. The bar's width is locked by the tab count and the container reserves the 28px Home Indicator zone.

```jsx
<BottomTab variant="4" activeIndex={0} onSelect={setTab}
  items={[{icon:'house',label:'首页'},{icon:'magnifyingglass',label:'发现'},
          {icon:'heart',label:'收藏'},{icon:'person',label:'我的'}]} />
```

Never let the bar size to its content, and never place it as a flex child that takes layout height — it floats above the scrolling content so the fade can sit under it.
