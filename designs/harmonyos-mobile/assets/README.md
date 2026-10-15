# assets（本目录不进版本库的内容）

这里原本放 `HMSymbolVF_1.ttf`（HarmonyOS Symbol 字体，1.7 MB）。它是 HarmonyOS 的字体资产，
**不随本仓库分发**，所以仓库里只保留相对路径引用：

- 设计系统 `fonts.css` → `assets/HMSymbolVF_1.ttf`
- 原型 `index.html` → `assets/HMSymbolVF_1.ttf`

要用原型，把你自己的 `HMSymbolVF_1.ttf` 放到本目录即可，其它什么都不用改；
没有这个文件时浏览器会忽略那条 `@font-face`，图标退化成文字/方块，样式其余部分不受影响。
