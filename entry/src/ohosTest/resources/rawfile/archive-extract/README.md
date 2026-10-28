# ZIP 解压测试样本

`plain.zip`、`traditional.zip` 和 `aes.zip` 都包含同一张 `photo.png` 与 `docs/readme.txt`。图片来自 `library-enhancements/similar-base.png`，SHA-256 为 `d2740fe59aa5aee700048efaf7c53499c10debca21b821c7c30195761ce255af`。传统加密与 AES-256 测试密码均为 `pass-1234`。

`traversal.zip` 含 `../outside.txt`；`symlink.zip` 含 Unix 符号链接；`too-many.zip` 含 5001 个空文件；`oversize.zip` 的中央目录声明未压缩大小超过 1 GiB；`damaged.zip` 不是 ZIP。这些样本只用于拒绝路径测试，不应解出文件。
