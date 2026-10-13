Horizontally scrolling category chips, with an optional trailing utility button.

```jsx
<FloatingChipsTab chips={[{title:'推荐'},{title:'壁纸',count:12}]} activeIndex={0} onSelect={setTab} />
<FloatingChipsTab variant="icontab" chips={chips} trailingIcon="list_bullet" />
```

The container's width is locked by the variant, not by content — do not set a width on it.
