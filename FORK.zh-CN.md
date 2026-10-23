# CleanYourTV 中文 / 光峰 FengOS Fork

本仓库 fork 自 [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv)，基于上游 **v2.7**。
保留上游全部功能和构建方式，只增加简体中文补全与光峰/峰米 FengOS 的 Home 键适配。

## 改了什么

| 改动 | 文件 |
|---|---|
| 简体中文文案补全到 **136/136** 条（上游 2.7 原有 61 条，缺少模块卡片、壁纸、快捷设置、F1 赛事、VPN 等） | `launcher/app/src/main/res/values-zh-rCN/strings.xml` |
| `HomeKeyService.openHome()` 直接启动 `MainActivity`，不再发 `CATEGORY_HOME` 隐式 Intent。FengOS 不把第三方包视为 HOME candidate，原写法会抛 `ActivityNotFoundException` | `launcher/app/src/main/java/com/gathin/tvhome/HomeKeyService.java` |
| 默认启用 `stock_home_redirect = com.tvfengmi.launcher`，让 2.7 已有的窗口事件、开机 ProbeActivity 和 Home 键重定向指向本桌面 | `launcher/app/src/main/res/values/config.xml` |
| 新增机型记录 | `docs/devices/fengmi-fmproja2.md`、`examples/README.md` |
| README 中文说明 | `README.zh-CN.md` |

## 实机验证

| 项目 | 结果 |
|---|---|
| 电视 | 光峰 Fengmi `FMProjA2`（`jerry`），FengOS，Android 9 / SDK 28，1920×1080，`zh-CN` |
| 固件 | `2.1.5.2987`（`PQ3B.190705.003`） |
| APK | `com.gathin.tvhome` v2.7，versionCode 8，debug 签名 |
| 中文 | 默认中文，首页、设置、应用库、聚焦名称均正常 |
| 开机 | 重启后直接进入 CleanYourTV，不再停在原厂桌面 |
| Home 键 | 从第三方应用（斗鱼）按 Home，回到 CleanYourTV |
| 原桌面 | `com.tvfengmi.launcher` **保持启用**，作为恢复入口 |

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

已构建的 APK（debug 签名，2.7，versionCode 8）：

- Release 下载：<https://github.com/symi-daguo/cleanyourtv/releases/tag/v2.7-zh-cn.1>
- SHA-256：`a078092068dc7d043ba0eac5470b8425cb795562e586ab8faa77bd9f5652813c`

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
