The card container in five sizes, with optional floating icon buttons.

```jsx
<CardView size="medium" iconButtons={[{position:'br', glyph:'arrow_up_and_rectangle_on_rectangle', label:'导出'}]}>
  <h3>旅拍志 · 京都的秋</h3>
  <p>12 张 · 14:32</p>
</CardView>
```

Cards compose content; never restyle them into buttons. Icon buttons stop propagation so tapping them does not trigger the card body.
