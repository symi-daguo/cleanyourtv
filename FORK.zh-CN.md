# CleanYourTV 中文 / 光峰 FengOS / 海信 VIDAA 低版本 Fork

本仓库 fork 自 [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv)，基于上游 **v3.0**。
保留上游全部功能和构建方式，增加简体中文补全、光峰/峰米 FengOS 的 Home 键适配，以及
**Android 6.0（API 23）低版本支持**（海信 VIDAA）。

默认构建与上游完全一致（`minSdk 26`），低版本适配只在显式传参时启用，因此上游同步与 CI 体积门都不受影响。

## 改了什么

| 改动 | 文件 |
|---|---|
| 简体中文文案补全到 **136/136** 条（上游 2.7 原有 61 条，缺少模块卡片、壁纸、快捷设置、F1 赛事、VPN 等） | `launcher/app/src/main/res/values-zh-rCN/strings.xml` |
| `HomeKeyService.openHome()` 直接启动 `MainActivity`，不再发 `CATEGORY_HOME` 隐式 Intent。FengOS 不把第三方包视为 HOME candidate，原写法会抛 `ActivityNotFoundException` | `launcher/app/src/main/java/com/gathin/tvhome/HomeKeyService.java` |
| 默认启用 `stock_home_redirect = com.tvfengmi.launcher`，让 2.7 已有的窗口事件、开机 ProbeActivity 和 Home 键重定向指向本桌面 | `launcher/app/src/main/res/values/config.xml` |
| **低版本构建开关**：`./gradlew assembleRelease -PlauncherMinSdk=23`。默认仍为 26，低于 26 时自动启用 `coreLibraryDesugaring`（`java.time` 是 API 26，8 个类在用） | `launcher/app/build.gradle` |
| **无外部存储的机型**：`Config.dir` 退回应用内部目录；min23 包内自带 5 张图（`src/min23/assets/wallpapers/`），按一分钟轮换并带动态效果，因为这类机器推不了照片也推不了配置 | `Config.java`、`WallpaperPlayer.java`、`launcher/app/src/min23/assets/` |
| **壁纸动画走 RenderThread**：`ViewPropertyAnimator` 替代 `ValueAnimator`，海信 maxim 上 31fps → 60fps；硬件层保留（去掉会掉回 30fps），代价是 GL 0x500 日志 | `WallpaperPlayer.java` |
| **内存回收后重载**：`onTrimMemory` 会清空壁纸，`start()` 检查 `current == null` 后重新解码 | `WallpaperPlayer.java` |
| **按使用频率排序**：读系统使用统计（需 `appops set ... GET_USAGE_STATS allow`），用得多的排前面，最常用 4 个自动进 dock，无授权时退回字母序 | `AppAdapter.java`、`AndroidManifest.xml` |
## 跟上上游

```bash
./tools/fork-sync.sh
```

只读，不改任何文件。它逐一比对 `launcher/` 下的 Java 文件，分三类报出来：

- **一致**：和上游一样，不用管
- **落后**：上游加了东西我们没跟（需要手动搬过来）
- **领先**：我们改的（分两路：够小的提 PR，其余留 Fork）
- **本地独有**：Fork 特供（当前只有 `Compat.java`）

第一次跑的结果（2026-10-27）：

```
一致：46 个文件
落后上游：12 个
领先上游：4 个
本地独有：1 个
```

**`RemoteKeys.java` 少的 132 行，核对过了：不用同步。** 逐行 diff 的结果是 135 行新增、15 行改写，新增的全是上游的按键增强（`front:` 前缀、「已在前台时行为不同」、`hold:` 长按、`guide:<package>`、`back/home/recents/mute/sleep/settings/wifi` 动作词、`package/.Activity` 直开），改写的是把 `holdEntries()` 这类私有方法抽象成通用的 `prefixed()`。**没有一处 bug 修复。**

我们的基础映射（`input_key_keycodes` / `app_keys`）是完整可用的，把这些搬过来反而会和 Fork 自己的按键处理交叉。**结论：留着不动，但仍然要留在这个列表里当已知差异。**

领先的四个是 `WallpaperPlayer`（+195，动态壁纸整套）、`WallpaperCaptions`（+10）、`UiFont`（+7）、`MainActivity`。

看单个文件的差异：

```bash
gh api repos/Gathin23/cleanyourtv/contents/launcher/app/src/main/java/com/gathin/tvhome/RemoteKeys.java \
  --jq .content | base64 -d > /tmp/up.java
diff -u /tmp/up.java launcher/app/src/main/java/com/gathin/tvhome/RemoteKeys.java
```

**同步节奏**：上游发新版后跑一次这个脚本，先把"落后"的搬过来，再看"领先"有没有该回馈的。别等积了十几个版本再一次性追，那时候 `RemoteKeys` 这类文件会彻底对不上。

| **API 23 桥接层**：`Compat.java` 收口 27 处 24/26 才有的调用，每处都降级到老版本等价路径；API 26+ 行为不变 | `launcher/app/src/main/java/com/gathin/tvhome/Compat.java` + 6 个调用文件 |
| **TV framework 缺失降级**：`Compat.tvInputs()` 探测 `TvInputManager` 底层 binder，缺失时返回 null，避免 VIDAA（无 `tv_input`）启动即崩 | `Compat.java`、`MainActivity.java` |
| 新增机型记录 | `docs/devices/fengmi-fmproja2.md`、`docs/devices/hisense-vidaa-laser.md`、`examples/README.md` |
| **中文智能体技能包**：`skills/cleanyourtv-cn/`。`install.sh` 读电视 SDK 自动选构建参数（<26 自动带 `-PlauncherMinSdk`）、`verify.sh` 给 7 项通过/警告/失败清单、`uninstall.sh` 回滚；附按报错对号入座的排查手册 | `skills/cleanyourtv-cn/` |
| README 中文说明 | `README.zh-CN.md` |

## 实机验证

### 光峰 Fengmi `FMProjA2`（FengOS / Android 9）

| 项目 | 结果 |
|---|---|
| 电视 | 光峰 Fengmi `FMProjA2`（`jerry`），FengOS，Android 9 / SDK 28，1920×1080，`zh-CN` |
| 固件 | `2.1.5.2987`（`PQ3B.190705.003`） |
| APK | `com.gathin.tvhome` v2.7，versionCode 8，debug 签名 |
| 中文 | 默认中文，首页、设置、应用库、聚焦名称均正常 |
| 开机 | 重启后直接进入 CleanYourTV，不再停在原厂桌面 |
| Home 键 | 从第三方应用（斗鱼）按 Home，回到 CleanYourTV |
| 原桌面 | `com.tvfengmi.launcher` **保持启用**，作为恢复入口 |

### 海信 VIDAA 激光电视（Android 6.0 / API 23）

| 项目 | 结果 |
|---|---|
| 电视 | 海信 `VIDAA_TV`（`MSD6A838`，MStar），Android 6.0 / SDK 23，`MRA58K` / `01.02.41.04`，1920×1080，`zh-CN` |
| 原桌面 | 聚好看 `com.jhk.tv.jutv`；`mHomeProcess` 为 `com.jamdeo.tv.vod`，两者都**未停用** |
| 安装 | 默认 `minSdk 26` 的包返回 `INSTALL_FAILED_OLDER_SDK`；`-PlauncherMinSdk=23` 的包 `Success` |
| APK | v2.7（versionCode 8），23 构建 698 KB（默认 26 构建仍为 479 KB，CI 体积门不受影响） |
| 中文 | 界面全中文：问候语、时间日期、Wi-Fi 名、设置入口、应用卡片 |
| 运行 | 启动后稳定在前台，`logcat` 无崩溃 |
| Home | 按 Home 弹出系统「选择主屏幕应用」（聚好看 / 主屏幕），点「始终」可固化 |
| 输入源 | **不可用**：VIDAA 无 TV Input Framework，`Compat.tvInputs()` 降级为空菜单 |
| 字体 | 低版本回落到系统 `sans-serif`（`res/font` 字体族是 API 26），布局不受影响 |
| 遥控器 Home | 固件日志 `map KEYCODE_HOME to KEYCODE_F12`，`HomeKeyService` 只覆盖 HOME/ALL_APPS，需实按遥控器确认 |

## 为什么系统里仍显示原桌面是默认 HOME

FengOS 的 PackageManager 会过滤第三方 HOME candidate。实测：

```text
cmd package set-home-activity --user 0 com.gathin.tvhome/com.gathin.tvhome.MainActivity
java.lang.IllegalArgumentException: ... cannot be home on user 0
```

同一个错误也出现在当贝桌面和其它包名的测试构建上。停用原桌面只会让系统落到
`com.android.tv.settings/.system/FallbackHome`，并不会接受第三方桌面。因此本 Fork 不改默认
HOME，而是使用上游 2.7 的 `stock_home_redirect` + `HomeKeyService`：

1. 原桌面仍是系统 HOME，保证电视永远有可用的恢复桌面；
2. 辅助功能服务在开机/解锁后启动 CleanYourTV；
3. 原桌面一旦出现在前台，或被按 Home 唤出，服务立即切回 CleanYourTV；
4. Home 键短按重定向，长按仍留给固件（例如快捷设置）。

## 安装

**优先用编好的包**（debug 签名，3.0，versionCode 9）。按电视的 Android 版本选一个，装不上再往下看源码构建：

| 文件 | 适用 | 大小 | SHA-256 |
|---|---|---|---|
| `cleanyourtv-cn-min26.apk` | Android 8.0 及以上 | 530,141 字节 | `bc02886403c18bf21b022c2497afcae61bbe93619f65f56faa4470de54931e0d` |
| `cleanyourtv-cn-min23.apk` | Android 6.0 – 7.1 | 754,049 字节 | `2d7951e4e2c93cb55d34ef35dc04a00b9d7842e11432c7308fd79aa95fad2344` |

下载地址：<https://github.com/symi-daguo/cleanyourtv/releases/latest>（文件名固定，`latest` 永远指向当前版本）

```bash
adb connect <电视地址>:5555
adb install -r cleanyourtv-cn-min23.apk     # 按上表选一个
```

装错包只会返回 `INSTALL_FAILED_OLDER_SDK`，换另一个即可，不会损坏任何东西。

`skills/cleanyourtv-cn/scripts/install.sh` 会自动判断电视版本、下对应的包、安装并验证，不用手工挑，也不需要 JDK。

也可以从源码构建：

```bash
# 1. 编译
cd launcher
./gradlew assembleRelease

# 2. 安装（不要用 build-and-install.sh，它会在 set-home-activity 处失败）
adb install -r app/build/outputs/apk/release/app-release.apk

# 3. 启用开机与 Home 键重定向
adb shell settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService
adb shell settings put secure accessibility_enabled 1

# 4. 打开一次，确认中文界面
adb shell am start -n com.gathin.tvhome/.MainActivity
```

然后重启电视验证。首次开机后，原桌面可能闪现几秒，随后自动进入 CleanYourTV。

## 恢复原状

原桌面从未被停用，所以恢复只需要关掉辅助功能并卸载 APK：

```bash
adb shell settings put secure accessibility_enabled 0
adb shell settings put secure enabled_accessibility_services ''
adb shell am start -n com.tvfengmi.launcher/com.gala.video.app.epg.HomeActivity
adb uninstall com.gathin.tvhome
```

如果只是想临时回原桌面，按 Home 后立刻用遥控器选择原桌面，或临时关闭辅助功能即可。

## 已知限制

- 不是系统意义上的默认 HOME，而是“开机自动进入 + Home 键重定向”。这是在不 root、不刷机前提下的可行方案。
- 依赖辅助功能服务。若电视的安全/清理功能把该服务移除，会回到原桌面，重新执行上面的第 3 步即可。
- 本 Fork 只验证了光峰 `FMProjA2` 这一台机器；其它 FengOS 机型可能使用不同的原桌面包名，需要把 `stock_home_redirect` 改成对应的包名。
- 输入源菜单能读到 HDMI 1/2/3、AV、ADTV；未逐口验证信号切换。
- APK 使用 Android debug 签名，适合侧载，不适合上架应用商店。

## 构建环境

- JDK 17 或 21
- Android SDK Platform 34
- Build Tools 34.0.0
- Gradle 8.9（wrapper 自动下载）

## 给上游的 PR 建议

建议拆成两个 PR，降低 review 成本：

1. **简体中文补全**：只包含 `values-zh-rCN/strings.xml`，136/136 条，附实机截图。这个最容易合并。
2. **FengOS / 光峰适配**：包含 `HomeKeyService.openHome()` 的直接启动修复、`stock_home_redirect` 的可配置方式、`docs/devices/fengmi-fmproja2.md` 和机型表。上游可能希望把 `stock_home_redirect` 留在主题/设备配置里，而不是写死默认值，PR 里应说明这一点。

如果只想要中文、不需要光峰适配，第一个 PR 单独提交即可。

**低版本（API 23）适配不进上游 PR。** 上游 `CONTRIBUTING.md` 把「lower minSdk」明确归到「你自己的仓库」，`PROMPT.md` 也写死「不要降低 minSdk，不要交付别处构建的 APK」。所以这部分留在本 Fork：

- 默认构建仍是 `minSdk 26`，与上游逐字一致，`Compat.java` 在 26+ 上走的都是原来的调用；
- 只有 `-PlauncherMinSdk=23` 才启用 desugar 和低版本分支，CI 体积门不受影响；
- 若上游愿意接受，唯一可能被 merge 的是「TV framework 缺失时不要崩」这一处（`Compat.tvInputs()` 的探测），因为它对任何缺 `tv_input` 的机器都是纯健壮性修复。

**海信这台不能出 debloat 清单进 `examples/`**，因为本轮没有停用任何包（聚好看和 `com.jamdeo.tv.vod` 都保持启用），只记录了桌面适配，放在 `docs/devices/`。
