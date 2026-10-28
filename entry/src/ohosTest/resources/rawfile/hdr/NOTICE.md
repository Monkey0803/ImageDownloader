# HDR 原生测试夹具

`gainmap-hevc-16x16.heic`

- 来源：google/libultrahdr 仓库 `tests/data/gainmap_hevc_16x16.heic`
  <https://github.com/google/libultrahdr/blob/main/tests/data/gainmap_hevc_16x16.heic>
- 上游说明：同一目录的 `GAINMAP_FIXTURE_README.md` 说明该文件由仓库自身的 HEIF 编码器
  从程序生成的 16×16 P010 HLG 像素合成，无第三方素材。
- 许可：`SPDX-License-Identifier: Apache-2.0 OR MIT`（上游对该夹具的单独声明）
- SHA-256：`6dd810ee6d118d3ce876936d9b265338b94d44cde187bce2ba384ce93edb1b8e`
- 实测：真机 `ImageSource.getImageInfo()` 读出主图为 64×64、`isHdr=true`；上游文件名中的 16×16
  指生成时的 P010 像素尺寸，不是解码后的主图尺寸。
- 用途：仅用于 `ohosTest` 的 HDR 解码探测，不进入生产 HAP。
