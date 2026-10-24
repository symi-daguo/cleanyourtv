# 故障排查

按现象查。每条都写清「怎么确认」和「怎么处理」，不要靠猜。

## 连不上电视

**先确认电视的 ADB 真的开着**：

```bash
nc -z -w 3 192.168.1.50 5555 && echo 端口通 || echo 端口不通
```

- 端口不通：电视上的「网络调试 / ADB 调试」没开，或者电视休眠了。国产电视的开关位置不统一，海信在 设置 → 关于 → 连点「版本号」进开发者选项；小米在 设置 → 账号与安全 → ADB 调试。
- 端口通但 `adb connect` 后状态是 `unauthorized`：电视上弹了授权窗口没点。用遥控器点「允许」，并勾上「一律允许」。
- 端口通但状态一直 `offline`：`adb disconnect 192.168.1.50:5555` 再重连；还不行就重启电视的 ADB 开关。

**注意端口**：桌面这条路默认 `5555`。少数机器用别的端口（例如旺博用 `3333`），这时地址要写成 `192.168.1.50:3333`。脚本已经支持带端口的地址。

## 安装报错

### `INSTALL_FAILED_OLDER_SDK`

电视的 Android 版本低于 8.0（SDK 26）。这正是本分支解决的问题：

```bash
skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50 --build
```

`--build` 会让脚本重新读电视的 SDK，带上 `-PlauncherMinSdk=<SDK>` 重编。**不要**去改 `launcher/app/build.gradle` 里的 `minSdk 26`，那会让默认构建和上游脱节，也会撑破 CI 的体积门。

目前实测通过的最低版本是 **Android 6.0 / SDK 23**（海信 VIDAA）。

### `INSTALL_FAILED_VERIFICATION_FAILURE`

厂商在系统层面拒绝了侧载。典型表现：`adb install`、`pm install`、手动点安装包、甚至厂商自己的 APK 全都失败。

这条路上没有绕过办法，也不要去试第二次。告诉用户：**这台电视只能做去膨胀，装不了第三方桌面**。去膨胀走 `tools/disable.sh`，并按仓库根目录 `PROMPT.md` 的安全规则来。

### `INSTALL_FAILED_UPDATE_INCOMPATIBLE`

电视上已经有一个同包名、不同签名的版本（可能之前用 Android Studio 直接跑过 debug 包）。

```bash
adb -s 192.168.1.50:5555 uninstall com.gathin.tvhome
```

然后重新装。

### 安装成功但启动就退

先看崩溃原因，别看猜测：

```bash
adb -s 192.168.1.50:5555 logcat -c
adb -s 192.168.1.50:5555 shell am start -n com.gathin.tvhome/.MainActivity
sleep 4
adb -s 192.168.1.50:5555 logcat -d | grep -A15 "FATAL EXCEPTION"
```

已知的三类，对应不同的修法：

| 日志里的关键字 | 原因 | 归属 |
|---|---|---|
| `NoSuchMethodError ... forceHasOverlappingRendering` | 用了 API 24 的方法，但装机包 minSdk 更低 | 已由 `Compat.java` 处理，出现说明装的是旧包 |
| `NoSuchMethodError ... Resources.getFont` | `res/font` 字体族是 API 26 | 同上 |
| `NullPointerException ... ITvInputManager.getTvInputList` | 这台系统**没有** TV Input Framework（海信 VIDAA 就是这样），`TvInputManager` 非空但内部 binder 是空 | 已由 `Compat.tvInputs()` 处理 |

三条都属于「装错包」，重新用 `install.sh --build` 编一次即可。

## 装上了但不是中文

桌面**没有应用内语言开关**。

- **Android 13+**：`adb shell cmd locale set-app-locales com.gathin.tvhome --locales zh-CN`
  想切英文就换 `en`。查当前值：`adb shell cmd locale get-app-locales com.gathin.tvhome`
- **Android 12 及以下**：只能改系统语言，桌面跟着走。国内电视出厂就是 `zh-CN`，一般不用动。

如果 Android 13+ 上命令报错（少数定制系统裁掉了 `cmd locale`），退回改系统语言。

## Home 键不回到新桌面

分三种情况，别混为一谈：

1. **按 Home 弹出选择器**：正常，说明系统认得这个桌面。让用户选「主屏幕」并点「始终」。
2. **按 Home 直接回原桌面，不弹选择器**：系统把第三方桌面过滤掉了。光峰 FengOS 就是这样，只能用辅助功能服务做重定向（见仓库 `docs/devices/fengmi-fmproja2.md`）。
3. **`adb shell input keyevent 3` 有效，但遥控器无效**：遥控器的 Home 键码被固件改掉了。海信 VIDAA 的日志会打印 `map KEYCODE_HOME to KEYCODE_F12 for hisense internal usage.`。

第 3 种必须**让用户实按遥控器**确认。注入键命令发的是 `KEYCODE_HOME`，走的不是遥控器那条路，不能用它的结果当证据。

确认是键码问题后，在 `launcher/app/src/main/res/values/config.xml` 里把对应键码加进 Home 键列表，重新装。

## 输入源菜单是空的

这台系统没有 TV Input Framework。判断依据：

```bash
adb -s 192.168.1.50:5555 shell dumpsys tv_input | head -5    # 没有输出
adb -s 192.168.1.50:5555 shell pm list features | grep -i tv_input   # 没有 leanback 相关
```

海信 VIDAA 就是这种。桌面的 `Compat.tvInputs()` 会降级成空菜单，不影响其他功能。HDMI 切换得走电视自己的入口。

## 想回到原状

```bash
skills/cleanyourtv-cn/scripts/uninstall.sh 192.168.1.50
```

本 skill 全程没有执行过 `pm disable`，所以不存在「要重新启用哪些包」的问题。如果用户之前用别的工具停用过包，那是另一件事，走 `tools/restore.sh` 和备份文件。

## 什么时候该停手

出现下面任一情况，停下来如实告诉用户，不要继续试：

- `pm disable-user` 对所有包都被拒绝
- 侧载一律 `INSTALL_FAILED_VERIFICATION_FAILURE`
- 电视 SDK 低于 23，这个桌面根本编不出来
- 已经装上了但遥控器完全没有反应（可能是桌面没适配这台的输入设备）

反复重试和换着法子绕过，只会让用户更长时间面对一台不能用的电视。
