#!/usr/bin/env bash
# 仓库守卫：把几条「踩过一次、不想再踩」的规则变成可执行检查。
#
# 只依赖 git / grep / bash，不碰 DevEco SDK —— 所以能在 GitHub Actions 上跑（见
# .github/workflows/ci.yml）。ArkTS 的编译与单测要 HarmonyOS SDK，只能在本地按
# AGENT.md 的「构建与测试」一节跑。
#
#   scripts/check-guards.sh
#
# 每条规则失败都会打印「哪条、为什么、怎么修」，退出码 1。
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

fail=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }

echo "仓库守卫："

# ---------------------------------------------------------------- 1. 状态管理家族
# 整个应用已经迁到 V2。V1 的装饰器一旦回流，就会和 V2 的组件混进同一个 struct（编译报错），
# 或者在普通成员上静默失效（V2 不允许父组件初始化普通成员）—— 两种都很难从界面看出来。
v1=$(grep -rnE "^[[:space:]]*@(Component|Prop|State|Link|ObjectLink|Observed|StorageProp|StorageLink|Watch|Provide|Consume)([[:space:]]|$)" \
      entry/src/main/ets --include='*.ets' 2>/dev/null)
if [ -n "$v1" ]; then
  bad "entry/ 下出现了 V1 状态装饰器（应用已整体迁到 V2，见 AGENT.md「状态管理 V2」）："
  printf '%s\n' "$v1" | sed 's/^/      /'
else
  pass "entry/ 下没有 V1 状态装饰器（@Component/@Prop/@State/@Link/@ObjectLink/@Observed/@StorageProp/@Watch）"
fi

# ------------------------------------------------- 2. 落盘不许直接 stringify 模型实例
# @ObservedV2 的 @Trace 字段在观察代理上不是普通可枚举属性，直接 JSON.stringify 会写成
# __ob_ 前缀，读侧读的是原名 —— 记录会在下次启动时静默变成空白。真机踩过，见 AGENT.md 坑 19。
if grep -qE "JSON\.stringify\(\s*state\s*\)" entry/src/main/ets/service/DownloadStore.ets 2>/dev/null; then
  bad "DownloadStore 又在直接 JSON.stringify(state) 了：@Trace 字段会被写成 __ob_ 前缀，改用 StoreState.serialize()"
elif ! grep -qE "StoreState\.serialize\(" entry/src/main/ets/service/DownloadStore.ets 2>/dev/null; then
  bad "DownloadStore 里找不到 StoreState.serialize()：落盘必须走显式线格式"
else
  pass "落盘走 StoreState.serialize()，没有直接 stringify 模型实例"
fi

# --------------------------------------------------------- 3. 私有资产不入库（字体）
# HMSymbolVF_1.ttf 是 HarmonyOS 的字体资产、且 1.7 MB，公开仓库不再分发；原型按相对路径引用，
# 自行放入 assets/ 即生效（两处 assets/README.md 有说明）。
if git ls-files | grep -q 'HMSymbolVF_1\.ttf'; then
  bad "仓库里又跟踪了 HMSymbolVF_1.ttf：它是 HarmonyOS 字体资产，不该随公开仓库分发（.gitignore 里已忽略该路径）"
else
  pass "没有跟踪 HMSymbolVF_1.ttf"
fi

# ------------------------------------------------------------ 4. 不写内网设备地址
# 设备地址一律走参数或 $DEVICE_TARGET（见 scripts/device.sh 头部说明），仓库里不留私网 IP。
lan=$(git grep -nIE "10\.155\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\." -- . 2>/dev/null)
if [ -n "$lan" ]; then
  bad "仓库里出现了私网地址（设备/服务器地址请走参数或环境变量）："
  printf '%s\n' "$lan" | sed 's/^/      /'
else
  pass "没有硬编码的私网地址"
fi

# -------------------------------------------------------------------------- 汇总
if [ "$fail" -ne 0 ]; then
  echo
  echo "守卫未通过。每条规则的来龙去脉在 AGENT.md 的「几个容易踩的坑」里。"
  exit 1
fi
echo "全部通过。"
