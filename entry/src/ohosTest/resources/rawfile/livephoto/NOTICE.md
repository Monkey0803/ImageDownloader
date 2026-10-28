# 实况照片包测试夹具

`sample.livp`

- 由本仓库此前验收生成：`cover.jpg`（9,910 B）+ `motion.mov`（6,305 B）打成的 ZIP 包，
  不含第三方素材。
- SHA-256：`4297bd9a05006aedad2217f2f4fd556b2b4328027709210fc895bb880862f905`
- 用途：`ohosTest` 验证 `LivePhoto.unpack` 能找到静图/视频并清理临时 ZIP，不进入生产 HAP。
