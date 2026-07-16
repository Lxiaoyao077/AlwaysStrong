## v2.3.3

- 修复 ptrace 启动路径：改为通过 rezygisk symlink 路径启动
  - /proc/self/exe 指向 rezygisk 目录后，ptrace 能正确找到 lib64/libzygisk.so

## v2.3.3

- 修复 ptrace 启动路径：改为通过 rezygisk symlink 路径启动
  - /proc/self/exe 指向 rezygisk 目录后，ptrace 能正确找到 lib64/libzygisk.so

## v2.3.2

- 修复 ReZygisk 不启动：post-fs-data.sh 创建 `/data/adb/modules/rezygisk/module.prop`
  - zygiskd64 daemon 遍历模块目录时需要 module.prop 来识别模块
  - v2.3.1 仅创建了 symlink 但没有 module.prop，导致 rezygisk 被跳过

## v2.3.1

- ReZygisk 真正集成：runtime symlink（不产生额外 Magisk 模块）
- WebUI 路径指回 tricky_store（module.prop / lang 不再依赖 rezygisk）
- 清理 v2.3.0 的 compat stub 残留逻辑

## v2.2.2

- 修复 WebUI 空白问题：customize.sh 现在提取完整 webroot 目录（CSS/JS/fonts/assets/lang 共 72 个文件），之前只提取了 index.html
- ReZygisk 集成保持与 integrated_v2 一致
