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
3. **电脑上有 adb**（Android SDK Platform-Tools）。**不需要 JDK，也不需要 Android SDK** —— 只有走到「本地构建」那一步才需要。

## 三条命令

```bash
# 1. 安装并启动（先下现成的包，装不上才本地构建）
skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50

# 2. 逐项验证，给出通过/警告/失败清单
skills/cleanyourtv-cn/scripts/verify.sh 192.168.1.50

# 3. 卸载，回到原状
skills/cleanyourtv-cn/scripts/uninstall.sh 192.168.1.50
```

### install.sh 的顺序（不要倒过来）

**先下载，再考虑构建。** 客户和自己的智能体都不该为了装一个 500 KB 的桌面去装 JDK、拉 Android SDK、等 Gradle 跑几分钟。

| 顺序 | 做什么 | 什么时候往下走 |
|---|---|---|
| 1 | 读电视的 SDK，决定要 `min26` 还是 `min23` 包 | — |
| 2 | 从 release 下载**已经编好、验证过**的 APK，直接装 | 下载失败，或这台机器装不上 |
| 3 | 本地按这台电视的 SDK 重新构建，再装 | 只有走到这里才需要 JDK 17/21 |
| 4 | 还是不行就停手，如实说清是哪一类失败 | — |

| 电视的 SDK | 下哪个包 | 对应构建 |
|---|---|---|
| ≥ 26（Android 8.0+） | `cleanyourtv-cn-min26.apk`，517 KB | 默认 `minSdk 26` |
| 23–25（Android 6.0–7.1） | `cleanyourtv-cn-min23.apk`，736 KB | `-PlauncherMinSdk=<SDK>` + `coreLibraryDesugaring` |
| < 23 | 不下载 | 直接拒绝，这个桌面编不出来 |

下载缓存在 `~/.cache/cleanyourtv/`，同一台机器第二次装不再重新下。GitHub 慢的时候可以换镜像：`CLEANYOURTV_APK_URL=<你的镜像地址>`。

只有这三种情况会跳过下载、直接构建：加 `--build`、加 `--apk <路径>`、或者电视版本特殊到现成包装不上。**不要为了「保险」默认加 `--build`** —— 那是把客户当成了构建机。

## 把照片做成会动的桌面背景

### 需要客户提供什么

**只要一个路径** —— 照片放在哪个文件夹。其它都不用问：

```
客户：照片在 /Users/daguo/Pictures/家庭照片
你：  ./skills/cleanyourtv-cn/scripts/set-wallpaper.sh /Users/daguo/Pictures/家庭照片 192.168.1.50 --minutes 30
```

脚本自己会数够不够、裁尺寸、压体积、推上去、重启桌面。要换图就再跑一次同一条命令，它会先清掉旧的那批。

问一句就够：「照片在哪个文件夹？」不要追加分辨率、格式、张数 —— 这些都归脚本管。客户手机里的照片常见是 HEIC，脚本也认。

一条命令，照片目录直接给，剩下的自动做：

```bash
skills/cleanyourtv-cn/scripts/set-wallpaper.sh ~/Pictures/家庭照片 192.168.1.50 --minutes 1
```

它依次做这些事：

| 步骤 | 做什么 |
|---|---|
| 压缩 | 每张裁成 1920×1080、压到 300 KB 以内（HEIC 也认，ffmpeg 优先，macOS 回退 sips） |
| 写配置 | 卡片半透明、关掉第一行底板、开动态推拉、关掉光晕（见下表） |
| 推送 | 先清旧图再推，避免换了照片还轮出上一批 |
| 重启 | 停掉桌面再拉起，立刻看到新背景 |

换图时有 0.2 秒淡出、0.36 秒淡入，不是硬切。动态平移在淡入淡出期间暂停，结束从新图重新开始。

参数：

```bash
--minutes 1        # 几分钟换一张，默认 30
--dim 40           # 背景再压暗多少（0-90），照片亮就调高，白字才看得清
--tile-opacity 45  # 卡片透明度，0-100，45 就能透出照片
--captions         # 在右上角显示图片文件名（默认不显示）
--off              # 撤掉背景，回到纯色
```

### 为什么默认带这四个键

| 键 | 值 | 不设会怎样 |
|---|---|---|
| `tile_opacity` | 45 | 卡片是实心深灰，照片被一格一格盖住 |
| `dock_band` | `false` | 第一行图标外面有条固定底板，焦点移到下面几行它不动，很容易被当成"焦点框卡住了" |
| `wallpaper_motion` | `true` | 静态照片像卡住的画面；开了之后 20 秒一轮缓慢平移加轻微推拉 |
| `ambient_glow` | `false` | 聚焦应用的光晕糊在照片上，图标是绿色时整张照片泛绿 |

### 照片怎么准备

- 至少 10 张，一分钟一张的话十分钟内不重复
- 单张压到 300 KB 以内；桌面一次只解码一张，超过 4K 的图直接不显示
- 文件名随便，`shuffle` 模式不看名字

### 海信 VIDAA 这类机器

`/sdcard` 是个指向不存在挂载点的符号链接，应用建不出外部目录，照片推不进去，配置也一样。这类机器只能用 **min23 包里自带的那 5 张图**（`src/min23/assets/wallpapers/`），它们自己按一分钟轮换、自带动态效果，但换不了图。

`set-wallpaper.sh` 会先探测外部存储，遇到这种机器直接说明原因，不会推一屏错误。

## 应用按使用习惯排序

桌面默认按字母排。装一次授权后，它会读系统自己的使用统计，把**用得最多的排在前面**，最常用的 4 个还会自动占住底部那一行（因为这台电视通常没装 Netflix/YouTube，空槽位本来就会拿前排应用补）。

```bash
adb shell appops set com.gathin.tvhome GET_USAGE_STATS allow
```

- 只读本机已有的统计，**不联网、不上传**
- 没有这个授权时，完全退回字母序，和原来一样
- 按最近 30 天的前台时长排；手动拖过顺序的应用仍然优先（拖过的不会被频率覆盖）
- 安卓的「设置 → 应用 → 特殊权限 → 使用情况访问」里也能开，但电视上这条路常常被裁掉，用上面的命令最省事

## 进 app 后暂停，回到桌面接着走

- 进了别的 app，轮播**暂停**，那段时间不计入间隔
- 回到桌面，从暂停处继续，不会因为离开太久而立刻换图
- 动态平移也是从暂停的位置继续，不会跳回起点

看照片的人不会觉得"每次回来都从头开始"。

## 中英文在哪里设置

**桌面没有应用内的语言开关**，这是设计如此。语言由系统决定，分两种情况：

| 电视系统 | 怎么切语言 | 命令 |
|---|---|---|
| **Android 13+**（SDK ≥ 33） | 可以只给这个桌面单独设语言 | `adb shell cmd locale set-app-locales com.gathin.tvhome --locales zh-CN` |
| **Android 12 及以下** | 只能改系统语言，桌面跟着走 | 电视 设置 → 系统 → 语言，选「简体中文」 |

国内电视出厂系统语言基本都是 `zh-CN`，所以默认就是中文界面，不用额外操作。`install.sh` 在 Android 13+ 上会自动把应用语言设成 `zh-CN`；低版本只提示，不强行改系统设置。

想切回英文：把 `zh-CN` 换成 `en`（Android 13+），或把系统语言改成 English。

`verify.sh` 的第 5 项就是查这个：SDK ≥ 33 查 per-app 语言，以下查系统语言。

## 开机自启与第一次 Home 选择

**开机自己回到桌面**

桌面有个 `power_on_home` 键：开机后趁没人动遥控器，把前台抢回来。不少电视开机会自己跳到 Live TV 或推荐页，没这个键就得每次手动按一次 Home。`set-wallpaper.sh` 写配置时默认带上。

**第一次按 Home 会弹选择框**

装好后遥控器按 Home，系统会问「用哪个桌面」。这一步只能这样，因为 Android 的默认桌面是系统设置里的东西：

`install.sh` 会在 Android 8.0 及以上尝试 `cmd package set-home-activity`，**但这不保证成功**：有的电视把 `systemui` 或自家桌面注册成 HOME 且 `isDefault=true`，命令返回 `Success`、按 Home 还是回原厂（实测中兴 ZXV10 就是这样）。

所以脚本最后会让你**按一次 Home 键确认**，按结果分三种：

| 现象 | 说明 |
|---|---|
| 回到本桌面 | 已生效，完成 |
| 回到原厂桌面 / 弹选择框 | 在框里选本应用并勾**「始终」**；没有勾选项就去 设置 → 应用 → 默认应用 → 主屏幕 |
| Android 6.0 – 7.1 | 没有命令行可用，只能走上面第二种 |

没勾「始终」的话，以后每次按 Home 都会问一遍。

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
