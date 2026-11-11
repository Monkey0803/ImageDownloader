# HDS 导航与沉浸接入基线

- 基线提交：`a649c4d`；分支 `main`；接入前工作区干净。现有 49 个文件的图库、预览、下载改动已单独提交，未推送。
- 工程：Stage 模型、单个 `entry` HAP、`deviceTypes: ["phone"]`、ArkTS V2；产品目标及兼容 SDK 均为 26.0.0。沿用现有签名和权限。
- 接入前导航：`Index` 自定义四页签；发现页两个局部 `Navigation` 和批量页独立 `HdsNavigation` / `NavPathStack`；图库查看器、编辑器使用独立页面 Router。
- 接入前窗口：`EntryAbility` 已启用 `setWindowLayoutFullScreen(true)`，通过 `avoidAreaChange` 发布状态栏、导航指示条与键盘高度。
- 接入前材质：应用级 `ohos.arkui.UIMaterial.state=enable`；自定义页签只在部分页面使用 ArkUI 材质，用户设置由 `SettingsViewModel` 持有。
- 接入前验证：`./scripts/build.sh assembleHap` 成功，新增 ArkTS ERROR 为 0。批量网页、剪贴板与超分失败脚本测试分别通过 15、3、2 个用例。

接入只改导航、标题栏、页签、避让区和相关测试；保留现有业务 ViewModel、独立预览与编辑页面路由。
