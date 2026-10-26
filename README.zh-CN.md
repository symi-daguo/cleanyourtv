<p align="center">
  <a href="https://cleanyour.tv"><img src="docs/banner.png" alt="CleanYourTV：让电视桌面回归简洁" width="800"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文 · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.ja.md">日本語</a> · <a href="README.it.md">Italiano</a>
</p>

<p align="center">
  <a href="https://cleanyour.tv">项目网站</a> ·
  <a href="PROMPT.md">操作提示词</a> ·
  <a href="examples/README.md">机型清单</a> ·
  <a href="SHOWCASE.md">社区作品</a>
</p>

# CleanYourTV 中文使用指南

通过局域网连接 Android TV 或 Google TV，停用不需要的预装应用、广告和遥测服务，并在兼容设备上安装简洁的原生桌面。无需 root、刷机或 USB 数据线；清理工具采用停用方式，不卸载系统应用，并提供恢复脚本。

本文介绍通用功能和使用方法。不同机型、地区和固件的应用包及限制可能不同，请先核对自己的设备。功能变化以[英文 README](README.md)为准，具体机型记录见[机型清单](examples/README.md)。

> **本 Fork**：在 v2.7 基础上补全简体中文（136/136），并加入光峰/峰米 FengOS 的 Home 键重定向。实机为光峰 FMProjA2（Android 9）。安装步骤、限制和恢复方法见 [FORK.zh-CN.md](FORK.zh-CN.md)；已构建 APK 见 [Release](https://github.com/symi-daguo/cleanyourtv/releases/tag/v2.7-zh-cn.1)。

![原生 Google TV 桌面与 CleanYourTV 桌面对比](docs/stock-vs-new-side.jpg)

## 工作原理

电视开启开发者选项中的 USB 调试，建立并授权网络 ADB 连接后，就可以完成以下步骤：

1. **备份**已安装应用列表及相关设置。使用[操作提示词](PROMPT.md)时，先让助手保存完整快照；手动使用 `tools/disable.sh` 时，工具仅保存恢复该停用列表所需的状态。
2. **按需停用**厂商遥测、广告服务、推荐内容和不需要的预装应用，使用的是 `pm disable-user`。
3. **安装简洁桌面**，并将其设为默认 HOME。

各品牌需要保留的系统组件不同。[操作提示词](PROMPT.md)会引导编程助手先检查实际设备，再确认你使用哪些应用和功能。

## 快速开始

准备一台与电视连接同一局域网的电脑，以及可以运行终端命令的编程助手，例如 [Claude Code](https://claude.com/product/claude-code)、[Codex](https://github.com/openai/codex) 或 [Gemini CLI](https://github.com/google-gemini/gemini-cli)。

| 步骤 | 操作 |
|---|---|
| 1. 电视端 | 打开「设置 → 设备偏好设置 → 关于」，在「版本号 / Build」上连续按七次确定，返回后进入开发者选项，开启 USB 调试。如果另有网络调试或 ADB 调试开关，也需要开启。菜单名称因机型而异。 |
| 2. 电脑端 | 先克隆仓库并在助手中打开该文件夹（`git clone https://github.com/Gathin23/cleanyourtv`），再将 [`PROMPT.md`](PROMPT.md) 的内容交给助手，填写电视型号。 |
| 3. 确认需求 | 在电视上接受调试授权，告诉助手常用应用、底部快捷栏中的应用，以及是否保留语音助手、Chromecast 和系统更新。 |
| 4. 检查结果 | 按提示完成备份、清理和安装，检查应用启动、遥控器操作、输入源和恢复路径。 |

先克隆仓库的意义在于：助手会直接使用本仓库的 `tools/disable.sh` 和 `launcher/build-and-install.sh`，不会另写一套；备份、默认桌面保护和恢复记录都在其中。

## 桌面功能

- **简洁首页**：深色背景，默认四个常用应用组成底部快捷栏。
- **应用聚焦展示**：显示当前应用名称；环境色优先从应用横幅提取，没有横幅时才从图标提取。
- **应用网格**：按向下键进入更多应用，支持每行 4、5、6 或 7 个。
- **遥控器排序**：从设置按钮的长按菜单进入排序模式，调整应用位置。
- **可选应用库**：浏览已安装且可启动的应用，用遥控器添加或移除首页快捷方式。
- **动效控制**：可开关动态效果，也可单独启用高级动态效果。
- **常用入口**：Wi-Fi / 以太网和系统设置；设备有可识别的 HDMI、AV、直播电视或已配置来源面板时，还会显示输入源入口。HDMI 名称沿用电视系统中的命名。
- **时钟与屏保**：问候语、时间、日期，以及配套的时钟屏保。
- **主题**：通过配置文件调整颜色、壁纸、快捷栏和列数，无需重新编译。
- **模块卡片**：其他应用可以提供桌面卡片，需用户同意才会显示。

![应用聚焦效果](docs/focus-2-up-netflix.png)

### 在电视上调整设置

默认短按「设置」打开电视系统设置，长按后可进入「简洁桌面设置」。在配置或主题中启用 `launcher_settings_button` 后，顶部改为独立的「简洁桌面设置」按钮，短按即可进入；长按仍可打开模块卡片和应用排序工具，电视系统设置也可从设置页面或下方应用图标进入。

启用独立按钮后，页面还提供「调整应用顺序」，点击即可返回桌面进入移动模式。

可调整：

| 选项 | 作用 |
|---|---|
| 每行应用数量 | 选择 4、5、6 或 7 个，列数增加时卡片相应缩小。 |
| 动态效果 | 开启或关闭桌面动画。 |
| 高级动态效果 | 增加卡片上浮、图标缩放和背景颜色平滑过渡。可能增加内存占用，实际影响取决于电视。 |
| 跟随主题（重置电视端设置） | 清除电视端的布局与动效选择，恢复当前主题或内置配置。推送或重置主题也会清除这些选择。 |
| 默认桌面入口 | 打开 Android 的默认桌面选择页，切换到原始桌面或 CleanYourTV。 |

默认桌面入口不负责重新启用已停用的原始桌面。如果原始桌面已被安装脚本停用，需要先按下文恢复。部分电视不提供系统桌面选择页。还可以通过 `show_home_settings_shortcut` 配置单独显示该入口。

### 排序与应用库

在桌面「设置」按钮上长按确定，通过菜单进入排序模式。按确定选中要移动的应用，用方向键调整位置，再按确定或返回放下；没有拿起应用时，按返回退出排序并保存。顶部独立排序按钮默认隐藏，可通过配置或主题的 `reorder_button` 开启。

应用库默认关闭，在配置或主题中启用 `app_library` 后，入口显示在首页应用的最后一行之后。它可以列出具有电视或普通 Android 启动入口的应用；普通 Android 应用可能仍需触摸或鼠标操作。

另可启用默认关闭的 `app_library_selection`：按确定直接切换右上角勾选，选择是否在首页显示。已勾选和未勾选分别按显示名称排序，勾选组排在前面；取消后焦点选相邻的下一个，末尾则选前一个，不跟随隐藏的应用移到后组。

- 对尚未添加到首页的应用按确定，可添加快捷方式。
- 对已经在首页的应用按确定，可打开应用；长按可打开操作菜单，添加或移除首页快捷方式，也可查看应用信息。
- 从首页移除不会卸载应用。相关选择在重启、应用更新及推送或重置主题后保留。

详见[应用库说明](docs/app-library.md)。

## 支持哪些设备

清理清单面向 **Android TV / Google TV**；上游桌面 APK 要求 **Android 8.0（API 26）或更高版本**。本 Fork 额外支持 **Android 6.0（API 23）起的老电视**：构建时带 `-PlauncherMinSdk=23`，已实测海信 VIDAA（Android 6.0）跑通，详见 [海信机型记录](docs/devices/hisense-vidaa-laser.md)。社区提供了多种电视与电视盒子的配置；其中一些设备运行的 Android 版本低于桌面的最低要求，清理清单不代表桌面可安装。请在[机型清单](examples/README.md)中核对型号、地区和固件，阅读对应目录的说明，再使用停用列表。

- Samsung Tizen 和 LG webOS 不能直接运行本项目的 Android 桌面；[docs/devices/samsung-tizen.md](docs/devices/samsung-tizen.md) 记录了一台 2021 年 Tizen 机型在局域网里暴露的接口（没有 ADB，因而无法停用应用），社区移植项目可参考[社区作品](SHOWCASE.md)。
- Fire TV 的清理记录可供手动适配；[操作提示词](PROMPT.md)不适用于 Fire TV，Fire OS 也限制替换默认桌面。
- 部分中国大陆版电视会拒绝侧载 APK 或安装第三方 HOME 桌面，已记录的 TCL 机型只是其中的例子。不能仅凭品牌判断兼容性。
- 没有现成清单时，可以让助手检查实际设备，并按[贡献指南](CONTRIBUTING.md)提交经过验证的机型记录。

## 让智能体一键装（skill 包）

如果你用的是 Claude Code、Codex、Cursor 或其它支持 skill 的智能体，把 `skills/cleanyourtv-cn/` 整个目录放进它的技能目录，然后一句话交代需求即可，例如「把电视桌面装到 192.168.1.50 上并确认能用」。

也可以在仓库根目录直接跑，不需要智能体：

```bash
# 安装并启动：自动读电视的 Android 版本，选对构建参数
skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50

# 逐项核对，输出「通过 / 警告 / 失败」清单，退出码 0 表示没有失败项
skills/cleanyourtv-cn/scripts/verify.sh 192.168.1.50

# 卸载，回到原状
skills/cleanyourtv-cn/scripts/uninstall.sh 192.168.1.50
```

`install.sh` **先下载我们编好、验证过的包**，装上就结束 —— 不需要 JDK、不需要 Android SDK、不用等 Gradle 下载依赖。只有下载不到、或者这个包在这台机器上装不上时，才按电视的 Android 版本本地构建再试一次。

| 电视版本 | 下载的包 | 大小 |
|---|---|---|
| Android 8.0 及以上 | `cleanyourtv-cn-min26.apk` | 517 KB |
| Android 6.0 – 7.1 | `cleanyourtv-cn-min23.apk`（多了 `java.time` 的兼容层） | 736 KB |
| 低于 Android 6.0 | 直接拒绝，不浪费你的时间 | — |

包缓存在 `~/.cache/cleanyourtv/`，同一台机器第二次装不再重新下载。GitHub 直连慢的时候可以换镜像：`CLEANYOURTV_APK_URL=<你的镜像地址>`。也可以直接从[最新 release](https://github.com/symi-daguo/cleanyourtv/releases/latest) 手动下载，用 `--apk` 指定。

验证清单共 7 项，只有全部「通过」才算装好：连接、已安装、停在前台、无崩溃、界面中文、默认桌面归属、原桌面仍启用可回退。

技能包还包含一封[故障排查手册](skills/cleanyourtv-cn/references/troubleshooting.md)，按 adb 报错对号入座，包括侧载被拒、签名冲突、Home 键不生效、输入源菜单为空等。

**本 skill 只安装和验证，不停用任何系统包。** 去膨胀是另一件事，必须走 `tools/disable.sh` 并遵守[操作提示词](PROMPT.md)的安全规则。

## 手动操作

以下命令从仓库根目录运行。`192.168.1.50` 是示例地址，请替换为电视的局域网地址。`tools/tv.py` 默认连接传统 TCP ADB 的 5555 端口；如果电视只提供需要配对的「无线调试」，须先按[操作提示词中的连接步骤](PROMPT.md)配对并开启 5555 端口，才能使用下列命令。

### 1. 准备连接工具

连接工具需要 Python 3：

```bash
python3 -m venv tools/venv
tools/venv/bin/pip install -r tools/requirements.txt
export TV_HOST=192.168.1.50

# 读取型号、Android 版本和固件
tools/venv/bin/python -I tools/tv.py --probe

# 查看已安装的应用包
tools/venv/bin/python -I tools/tv.py 'pm list packages'
```

### 2. 按需应用停用列表

**下面的小米路径仅为示例，请替换为与你的电视匹配且已核对的列表。** 不要将其他机型的列表直接用于自己的电视。

```bash
tools/disable.sh examples/xiaomi-mi-tv-4a/debloat.txt
```

列表路径相对于运行命令时所在的目录，也可以使用绝对路径。保留原列表及工具生成的恢复记录，方便撤销。手动流程若还需要完整的应用和设置快照，应在停用前另行保存；`tools/disable.sh` 不会生成该快照。

### 3. 编译和安装桌面

桌面使用 Java 和 AndroidX RecyclerView，应用包名为 `com.gathin.tvhome`。编译需要 JDK 17、Android SDK Platform 34 和 Build Tools 34.0.0。macOS 可安装：

```bash
brew install openjdk@17 android-commandlinetools
sdkmanager "platforms;android-34" "build-tools;34.0.0"
```

Linux 安装脚本可查找 `~/Android/Sdk` 和 `PATH` 中的 Java。准备好环境后运行：

```bash
TV_HOST=192.168.1.50 launcher/build-and-install.sh
```

> **光峰/峰米 FengOS 例外**：该固件不允许第三方应用成为系统 HOME，`build-and-install.sh` 会在 `set-home-activity` 处失败。请改用 [FORK.zh-CN.md](FORK.zh-CN.md) 的手动安装步骤；原桌面保持启用，通过辅助功能 Home 键重定向进入本桌面。

**此 Shell 脚本不仅安装 APK，还会切换默认 HOME，并按检测结果停用原始桌面。** 它先确认新桌面能够启动，再完成切换；切换失败时尝试回退。自动识别仅支持 `com.google.android.tvlauncher`、`com.google.android.apps.tv.launcherx`、`com.google.android.leanbacklauncher` 和 `com.mitv.tvhome`；若识别失败，需核对设备后指定 `STOCK_LAUNCHER=<包名>`，或使用 `none`。

可使用 `STOCK_LAUNCHER=<包名>` 指定原始桌面；如果希望保留原始桌面的启用状态，使用：

```bash
TV_HOST=192.168.1.50 STOCK_LAUNCHER=none launcher/build-and-install.sh
```

`none` 只表示不停用原始桌面，**仍会将 CleanYourTV 设为默认 HOME**。

### Windows

仓库提供对应的 PowerShell 脚本。安装 Python 和 Android Studio，并确认上述 JDK、SDK 组件可用后：

```powershell
python -m venv tools\venv
tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt
powershell -ExecutionPolicy Bypass -File launcher\build-and-install.ps1 -TvHost 192.168.1.50
```

PowerShell 安装脚本使用 `-StockLauncher <包名>` 指定原始桌面，或使用 `-StockLauncher none` 保留其启用状态。当前 PowerShell 脚本会先请求设置新 HOME，再检查新桌面是否启动，与上述 Shell 脚本的顺序不同；操作前请确认 ADB 恢复路径可用。清理与恢复分别使用 [`tools/disable.ps1`](tools/disable.ps1) 和 [`tools/restore.ps1`](tools/restore.ps1)。

### 工具索引

| 工具 | 用途 |
|---|---|
| [`tools/tv.py`](tools/tv.py) | Python ADB 客户端，支持执行命令、批处理、上传和下载。 |
| [`tools/b64push.py`](tools/b64push.py) | 分块上传 APK 等大文件并校验。 |
| [`tools/disable.sh`](tools/disable.sh) / [`tools/restore.sh`](tools/restore.sh) | 应用停用列表，或按照操作前记录恢复。 |
| [`tools/recovery.py`](tools/recovery.py) | 保存恢复记录并生成恢复命令。 |
| [`tools/theme.sh`](tools/theme.sh) | 推送或重置主题，并重新启动桌面。 |
| [`launcher/build-and-install.sh`](launcher/build-and-install.sh) | 编译、安装桌面并切换 HOME。 |

## 更多配置

### 布局与主题

内置配置位于 [`config.xml`](launcher/app/src/main/res/values/config.xml)，可设置快捷栏顺序、隐藏应用、直播电视包名、列数、快捷栏下方的行数、网络按钮关联的 VPN 应用，以及 `reduced_motion` 等选项。

还可通过 `show_stats` 尝试显示 CPU、可用内存和可用存储空间，默认关闭，开启后仅在首页显示期间刷新。设备禁止读取 CPU 数据时会省略 CPU 一项。`greeting_name` 可设置问候语中的名字。

主题通过 `config.json` 覆盖内置配置，还可提供背景色和壁纸。使用示例：

```bash
TV_HOST=192.168.1.50 tools/theme.sh themes/aurora
```

恢复内置主题：

```bash
TV_HOST=192.168.1.50 tools/theme.sh --reset
```

### 用家里的照片做背景（自动轮播）

桌面背景由主题的 `wallpapers/` 目录提供：放几张照片、设一个间隔，它就会自动换。只保留当前这一张在内存里，换图时在后台线程解码并按屏幕尺寸缩放。

**1. 建目录**

```
themes/family/
├── config.json
└── wallpapers/
    ├── 001.jpg
    ├── 002.jpg
    └── captions.txt     # 可选，给照片起名字
```

**2. 写 `config.json`**

```json
{
  "wallpaper": true,
  "wallpaper_rotation_minutes": 30,
  "wallpaper_order": "shuffle",
  "wallpaper_dim": 35,
  "wallpaper_captions": true
}
```

| 键 | 作用 |
|---|---|
| `wallpaper` | 打开背景图。只要单张不轮播，放一个 `wallpaper.jpg` 即可 |
| `wallpaper_rotation_minutes` | 多少分钟换一张；`0` 是不轮播 |
| `wallpaper_order` | `shuffle` 随机且不连着重复（默认），`sequential` 按文件名顺序 |
| `wallpaper_dim` | 压暗百分比 0–90。照片偏亮时调到 35–50，白字才看得清 |
| `wallpaper_captions` | 在右上角显示照片名，从 `wallpapers/captions.txt` 读 |

**3. 给照片起名（可选）**：`captions.txt` 一行一张，文件名和名字用 Tab 隔开。

```
001.jpg	三亚海边
002.jpg	去年冬天
```

**4. 推上去**

```bash
TV_HOST=192.168.1.50 tools/theme.sh themes/family
```

没有 Python 环境时用 adb 直接写同样的目录结构：

```bash
D=/sdcard/Android/data/com.gathin.tvhome/files
adb shell mkdir -p $D/wallpapers
adb push config.json $D/config.json
adb push wallpapers/*.jpg $D/wallpapers/
adb shell am force-stop com.gathin.tvhome
adb shell am start -n com.gathin.tvhome/.MainActivity
```

**照片怎么准备才不占资源**

- **1920×1080、单张 300 KB 以内**，竖构图先裁成 16:9，免得被居中裁切。
- 最多 100 张、单张最多 10 MB；超过约 840 万像素的图不显示。
- 文件名只用字母、数字、下划线、点和短横线。
- 实测（1280×800 的一台 Android 9 盒子）：开背景比纯色多约 **4.8 MB** 原生内存，轮播本身不再增长。
- 1 GB 内存的老电视别开 `wallpaper_true_color`（32 位色，1080p 多占 8 MB）和 `fade_rows`（多占约 6 MB 图形内存），默认值最省。
- 开机后只在首页可见期间轮换，切到别的应用不会在后台换图。

**卡片和第一行图标外面那圈底板，会把照片盖住**

默认的深色卡片是按纯色背景设计的，放到照片上就是一块块黑斑。两个键处理掉：

| 键 | 作用 | 建议值 |
|---|---|---|
| `tile_opacity` | 应用卡片背景的不透明度，0–100，100 是原来那块实心卡片 | 45 |
| `dock_band` | 第一行那四个图标外面有一块固定的底板和描边，焦点移到下面几行时它不动，很容易被当成"焦点框卡在第一行"。设 `false` 让所有图标直接浮在照片上 | `false` |

`tile_opacity` 只调背景填充，图标和名字仍然完全不透明，不会看不清。`set-wallpaper.sh` 生成配置时默认就带这两个值（`--tile-opacity` 可改），不用手写。

**让静态照片慢慢动起来**

`wallpaper_motion` 打开后，每张照片做一轮 20 秒的缓慢平移：画面整体朝一个随机方向推出去再退回来，幅度约屏幕宽度的 5%，同时有 7% 的轻微推拉。平移比缩放在肉眼里明显得多 —— 同样幅度下缩放几乎看不出来。

它**不额外占内存** —— 只改图片视图自己的变换矩阵，照片在内存里还是那一张。代价是首页可见期间后台每帧重绘一次。实测在 1280×800 的盒子上跑起来 PSS 25.8 MB，和静态时一样。

`set-wallpaper.sh` 默认就带上 `"wallpaper_motion": true`。不想要就在配置里改成 `false`，或者直接删掉这一行（默认关闭）。


**少数电视没有可用的外部存储**

主题走的是应用的**外部**文件目录。海信 VIDAA 这类把 `/sdcard` 裁掉的系统上这个目录建不出来，`logcat` 里会看到 `SecurityException: Invalid mkdirs path`，照片推不上去。这类机器只能把背景编译进 APK：图放进 `launcher/app/src/main/res/drawable/`，在 `config.xml` 里指定，重新构建安装。

主题格式和可用配置见 [`themes/README.md`](themes/README.md)。

### 语言、屏保与遥控器

以下 ADB 命令使用 macOS/Linux 的虚拟环境路径；Windows 将前缀 `tools/venv/bin/python -I tools/tv.py` 换为 `tools\venv\Scripts\python.exe -I tools\tv.py`。

- **语言**：桌面**没有应用内语言开关**，语言由系统决定。本 Fork 已补全全部简体中文文案（135 条字符串 + 1 条复数规则），光峰 FMProjA2 与海信 VIDAA 实机均默认显示中文。
  - **Android 13 及以上**可以只给桌面单独设语言：`adb shell cmd locale set-app-locales com.gathin.tvhome --locales zh-CN`（切英文把 `zh-CN` 换成 `en`）。查当前值用 `cmd locale get-app-locales com.gathin.tvhome`。
  - **Android 12 及以下**只能改系统语言，桌面跟着走：电视 → 设置 → 系统 → 语言。国内电视出厂就是 `zh-CN`，通常不用动。
- **时钟屏保**可在电视的屏保设置中选择 Clock；也可执行：`tools/venv/bin/python -I tools/tv.py 'settings put secure screensaver_components com.gathin.tvhome/.ClockDream; settings put secure screensaver_enabled 1'`。
- **输入源键**可在 macOS/Linux 安装时使用 `INPUT_KEY_SERVICE=1` 启用辅助功能服务，以适配 Google TV 的遥控器输入源按钮；Windows 使用 `-InputKeyService`。
- **HOME / 设置键**可在 macOS/Linux 安装时使用 `HOME_KEY_SERVICE=1`，并通过 `config.xml` 中的按键配置适配部分设备；Windows 使用 `-HomeKeyService`。`settings_key_panel` 可启用快捷设置面板，提供电视设置、显示、网络、应用和桌面设置入口。重装时需重新传入所需的服务选项。

### 模块卡片

应用可声明自己的卡片名称、说明和环境色。桌面会询问是否显示，默认保持隐藏，并按应用签名及卡片名称保存选择。在桌面「设置」按钮上长按确定，选择模块卡片菜单即可管理。

开发说明见 [`docs/modules.md`](docs/modules.md)，接口约定见 [`docs/specs/card.md`](docs/specs/card.md)。

## 恢复原始桌面和应用

`tools/disable.sh` 在停用前记录列表内各应用的状态（启用、已停用或未安装）、当时的默认 HOME 和三项系统动画缩放设置。它还会记录当时拥有 HOME 的包，但不会保存完整应用列表或全部系统设置。记录位于电脑的 `~/.cleanyourtv/`，按电视和列表分别保存。重复运行同一列表不会覆盖最初记录；新增列表项会补充记录。

将以下路径替换为**实际使用过的列表**后恢复：

```bash
TV_HOST=192.168.1.50 tools/restore.sh examples/xiaomi-mi-tv-4a/debloat.txt
```

如需指定原始桌面的备用包名，可增加最后一个参数。Google TV 常用的是 `com.google.android.apps.tv.launcherx`，但应以实际设备为准：

```bash
TV_HOST=192.168.1.50 tools/restore.sh "examples/你的机型/debloat.txt" com.google.android.apps.tv.launcherx
```

- 有记录时，优先恢复当时实际拥有 HOME 的组件；当时没有解析到 HOME 或 HOME 已属于 CleanYourTV 时，使用指定的备用包名，未指定则默认尝试 `com.google.android.tvlauncher`。
- 记录中操作前已经停用的包会保持停用。恢复脚本还会尝试启用备用桌面包；如果它不在记录中，脚本无法判断其操作前状态。请先核对备用包名。
- 缺少记录时，脚本会提示并回退为启用列表内应用、将动画缩放恢复为 `1.0`；这不等同于精确恢复操作前状态。
- 恢复脚本不会卸载 CleanYourTV，也无法恢复列表之外的手动修改。若要卸载，可在电视「设置 → 应用」中操作。
- 无法连接 ADB 时，也可以尝试从电视系统设置中重新启用相关应用。

## 故障排查

完整说明见 [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)。

- **macOS 提示 `No route to host`**：检查本地网络隐私权限；可尝试通过 `tools/venv/bin/python -I tools/tv.py` 使用仓库的 Python ADB 工具。
- **替换后 HOME 异常**：应先确认新桌面已安装且能够运行，再停用原始桌面。Shell 安装脚本按这个顺序执行；Windows 脚本的现有顺序见上文。
- **Google TV 设置向导抢占 HOME**：`com.google.android.tungsten.setupwraith` 可能在原始桌面停用后抢占 HOME。先按故障排查文档检查它是否拥有当前 Wi-Fi 配置；直接停用可能删除该网络。清理工具会在这种情况下跳过它，需先在系统设置中忘记该 Wi-Fi，再重新加入。若已经异常，可尝试重新启用 Google TV 原始桌面：`tools/venv/bin/python -I tools/tv.py 'pm enable --user 0 com.google.android.apps.tv.launcherx'`。

## 常见问题

**会刷机或删除系统应用吗？**

不会。清理通过停用应用实现，但停用系统依赖仍可能造成故障，因此需要按机型核对、分批处理，并保留恢复路径。

**系统更新和应用更新会受影响吗？**

部分停用列表包含系统更新服务，需要重新启用后才能接收固件更新。常用流媒体应用仍可通过保留的应用商店更新；具体取决于设备和所用列表。

**能远程帮助其他人操作吗？**

可以通过私有 Tailscale 网络连接，详见[远程操作说明](docs/REMOTE.md)。不要在路由器上将 ADB 端口暴露到互联网。

**完成后要关闭调试吗？**

需要。本工具使用的传统 TCP ADB（默认 5555 端口）为明文连接，部分固件甚至不强制授权。完成后关闭 USB 调试及网络 / ADB 调试，撤销调试授权，并按[英文 README 的检查步骤](README.md#questions-people-ask)确认端口已关闭。

**支持私有 DNS 或 AirPlay 吗？**

私有 DNS 是部分 Android 版本提供的系统功能，并非桌面的广告过滤能力，也无法屏蔽所有视频广告。AirPlay 不属于桌面内置功能，需要另行安装和配置。相关可选方案见[英文常见问题](README.md#questions-people-ask)。

**有现成 APK 吗？**

目前仓库的使用方式是通过安装脚本编译并安装，方便根据设备调整配置。

## 参与贡献

欢迎提交经过实际设备验证的机型清单、桌面改进、文档修正和主题。提交前请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)，每个 PR 保持一个主题，并说明验证范围。衍生项目和不同风格的桌面可登记在 [`SHOWCASE.md`](SHOWCASE.md)。

如果英文说明发生变化，也欢迎同步修订本文。机型数量、支持列表和主题列表直接参考对应目录，以减少重复维护。

## 联系与安全报告

电视使用问题可在 [GitHub Discussions](https://github.com/Gathin23/cleanyourtv/discussions) 讨论。媒体与合作联系方式见[英文联系说明](README.md#contact)。安全漏洞请通过仓库 [Security 页面](https://github.com/Gathin23/cleanyourtv/security) 私下报告，详见 [`SECURITY.md`](SECURITY.md)。

## 许可证

项目采用 [MIT 许可证](LICENSE)。Outfit 字体采用 [SIL Open Font License](launcher/FONT-LICENSE-OFL.txt)。
