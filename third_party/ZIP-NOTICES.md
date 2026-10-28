# ZIP 解压原生依赖

- `libzip/`：上游 `nih-at/libzip` 的 `v1.12.1` 源码，提交 `8e037534ccd62f444abbe4ce265443ee74bbfeb3`。保留了构建所需文件；许可证见 `libzip/LICENSE`。本项目只启用 ZIP 的 stored/deflate、传统 PKWARE 与 WinZip AES 读取能力。
- OpenSSL 3.5.2：`scripts/build-zip-deps.sh` 下载官方发布包，使用脚本内固定的 SHA-256 校验，构建静态 `libcrypto.a` 和 `libssl.a` 到被 Git 忽略的 `third_party/zip-deps/`。许可证见 `openssl-LICENSE.txt`。

原生模块只打包一个应用库 `libarchiveextract.so`，目标 ABI 为 `arm64-v8a`。构建前运行 `bash scripts/build-zip-deps.sh`；`scripts/build.sh` 会在缺少依赖时自动运行它。构建依赖必须由源码生成，不能引用其他工作区的产物。
