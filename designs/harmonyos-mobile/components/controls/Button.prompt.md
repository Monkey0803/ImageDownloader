The system's button: brand-filled primary, neutral surface, toggle pair and destructive variant, in two control heights.

```jsx
<Button type="emphasized" onClick={save}>保存</Button>
<Button type="normal" size="small" icon="plus">新建</Button>
<Button type="warning">删除</Button>
<Button type="emphasized" loading>提交中</Button>
```

`emphasized` is the only variant that should carry the primary action on a screen. Buttons opt into the light effect by default — that is the spec's focal-component rule, not a decoration.
