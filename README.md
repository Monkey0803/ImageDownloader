# 图片下载管理

鸿蒙手机应用，可在内置浏览器中扫描当前网页图片，选择单张保存或打包为 ZIP。支持 1–10 个同时下载任务、失败重试、图片与 ZIP 重命名、图库预览、分享和导出。

## 构建

工程使用 DevEco Studio SDK 26。`build-profile.json5` 是本机文件，包含调试签名配置，已被 Git 忽略；在新机器上复制 `build-profile.example.json5` 为 `build-profile.json5`，再通过 DevEco Studio 的 **Project Structure → Signing Configs** 配置调试签名。

## 设备与验证范围

**当前只做 phone**（`module.json5` 的 `deviceTypes` 为 `["phone"]`），已在 HarmonyOS 7.0.0(26.0.0) 手机模拟器上完成功能验证。

折叠屏 / 阔折叠 / 三折叠 / 平板 / 2in1 的适配与验证**挂起**：需要先扩展 `deviceTypes`，并补充分栏、折叠态重排等布局验证。在此之前不纳入验收范围。

## 测试

单元测试在 `entry/src/ohosTest`（hypium），覆盖 `DownloadStore` 的纯函数：文件名清洗、下载命名、扩展名归一、Content-Type 映射、同名去重。这些函数不依赖 `UIAbilityContext`，也不写真实文件系统。

```bash
DEVECO=/Applications/DevEco-Studio.app

# 1. 构建测试包
node "$DEVECO/Contents/tools/hvigor/bin/hvigorw.js" assembleHap \
  --mode module -p module=entry@ohosTest -p buildMode=debug

# 2. 安装测试包（主包需已安装）
hdc install entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap

# 3. 运行
hdc shell "aa test -b com.example.imagedownloader -m entry_test \
  -s unittest OpenHarmonyTestRunner -s timeout 60000"
```

结果看 `OHOS_REPORT_RESULT` 一行，例如 `Tests run: 25, Failure: 0, Error: 0, Pass: 25`。

## 使用边界

- 网页扫描读取当前页面 `img` 元素及常见懒加载地址；滚动页面后可以重新扫描。
- ZIP 下载仅保留压缩包，成功打包后清理本批次的临时图片。个别图片失败时仍打包成功项，失败项留在任务页。
- 登录页面的下载会按图片地址读取浏览器 Cookie；站点防盗链、会话过期或不允许外部请求时可能失败。
