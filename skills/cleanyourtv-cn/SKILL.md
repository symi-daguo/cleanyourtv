---
name: cleanyourtv-cn
description: 把 CleanYourTV 电视桌面装到 Android TV / Google TV / 国产电视上，并逐项验证是否正常运行。用户提到「电视桌面」「换桌面」「去广告」「去膨胀」「debloat」「CleanYourTV」「adb 装电视」「电视太卡」「家里电视广告多」，或要求检查某个电视能不能装这个桌面时使用。自动判断电视的 Android 版本选对构建参数，装完给出一份通过/警告/失败清单。只安装和验证，不停用任何系统包。
---

# CleanYourTV 中文技能包

把 [CleanYourTV](https://github.com/Gathin23/cleanyourtv) 桌面装到电视上，并核对它是否真的跑起来了。全程只用 adb，不 root、不刷机、不卸载任何东西。

这个包是中文本地化分支的一部分（[symi-daguo/cleanyourtv](https://github.com/symi-daguo/cleanyourtv)），额外支持 **Android 6.0 起的老电视**（上游只支持 Android 8.0+）。

## 先确认三件事

1. **电视和电脑在同一局域网**，电视的「网络调试 / ADB 调试」已打开（通常在 设置 → 关于 → 连点版本号进开发者选项）。
2. **电视上会弹「允许 USB 调试」**，用遥控器点允许。没点过就会卡在 `unauthorized`。
3. **电脑上有 adb**（Android SDK Platform-Tools），构建还需要 JDK 17 或 21。

## 三条命令

```bash
# 1. 安装并启动（自动按电视的 Android 版本选构建参数）
skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50

# 2. 逐项验证，给出通过/警告/失败清单
skills/cleanyourtv-cn/scripts/verify.sh 192.168.1.50

# 3. 卸载，回到原状
skills/cleanyourtv-cn/scripts/uninstall.sh 192.168.1.50
```

`install.sh` 会自动做这几件事，不需要人记：

| 电视的 SDK | 脚本行为 |
|---|---|
| ≥ 26（Android 8.0+） | 用默认构建（`minSdk 26`），APK 479 KB |
| 23–25（Android 6.0–7.1） | 自动加 `-PlauncherMinSdk=<SDK>`，打开 `coreLibraryDesugaring`，APK 698 KB |
| < 23 | 直接拒绝，说明这个桌面装不了 |

## 中英文在哪里设置

**桌面没有应用内的语言开关**，这是设计如此。语言由系统决定，分两种情况：

| 电视系统 | 怎么切语言 | 命令 |
|---|---|---|
| **Android 13+**（SDK ≥ 33） | 可以只给这个桌面单独设语言 | `adb shell cmd locale set-app-locales com.gathin.tvhome --locales zh-CN` |
| **Android 12 及以下** | 只能改系统语言，桌面跟着走 | 电视 设置 → 系统 → 语言，选「简体中文」 |

国内电视出厂系统语言基本都是 `zh-CN`，所以默认就是中文界面，不用额外操作。`install.sh` 在 Android 13+ 上会自动把应用语言设成 `zh-CN`；低版本只提示，不强行改系统设置。

想切回英文：把 `zh-CN` 换成 `en`（Android 13+），或把系统语言改成 English。

`verify.sh` 的第 5 项就是查这个：SDK ≥ 33 查 per-app 语言，以下查系统语言。

## 「装好了」的标准

`verify.sh` 全绿才算通过，7 项分别是：

1. adb 连上了
2. 包已安装，能读出 `versionName` / `versionCode`
3. 启动后**停在**前台（不是闪一下就退回原桌面）
4. 崩溃日志里没有它
5. 界面语言是中文
6. 默认桌面的归属（低版本看 `mHomeProcess`，高版本看 `cmd package resolve-activity`）
7. 没有停用任何桌面类应用 —— 保证随时能回原桌面

第 6 项报「警告」是正常的：第一次装完还没在电视上选过「始终」。让用户按一次遥控器 Home，在系统弹出的选择器里选「主屏幕」并点「始终」，再跑一次就变「通过」。

## 需要人动手的两步

脚本能装的都装完了，剩下这两件必须有人在电视前：

1. **选默认桌面**：按遥控器 Home → 选择器里选「主屏幕 / CleanYourTV」→ 点「始终」。不选的话，Home 键每次都会弹选择器。
2. **如果遥控器 Home 键不管用**：个别国产系统把 Home 键码改掉了（海信 VIDAA 把 `KEYCODE_HOME` 映射成 `KEYCODE_F12`），需要在 `launcher/app/src/main/res/values/config.xml` 里补一条映射，改完重新装。让用户实按一次遥控器确认，**不要用 `adb shell input keyevent 3` 的结果当成遥控器的结果** —— 那注入的是键码，不是物理按键。

## 装不上时

按报错对号入座，别反复重试：

| adb 报错 | 含义 | 怎么办 |
|---|---|---|
| `INSTALL_FAILED_OLDER_SDK` | APK 的 minSdk 高于电视 | 加 `--build` 重跑，脚本会按这台电视的 SDK 编 |
| `INSTALL_FAILED_VERIFICATION_FAILURE` | 厂商禁止侧载 | 这条路走不通，只能做去膨胀，见 `references/troubleshooting.md` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 签名不一致 | `adb uninstall com.gathin.tvhome` 后重装 |
| `unauthorized` | 电视没授权 | 电视上点「允许 USB 调试」 |

更多见 `references/troubleshooting.md`。

## 边界

- **不要停用任何系统包**。这个 skill 只装桌面、只验证。去膨胀是另一件事，必须走 `tools/disable.sh` 并遵守仓库 `PROMPT.md` 的安全规则（永远 `disable-user`，永不 `uninstall`，动之前先备份）。
- **不要为了装上而降 `minSdk`**。老机器用 `-PlauncherMinSdk`，改的是构建参数，不是源码默认值。
- **不要用别处编译的 APK**。签名和 minSdk 都对不上时装上了也说不清是谁的问题。
- 电视上如果已经有别的第三方桌面，先问清楚用户想留哪个再动手。
