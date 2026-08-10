# GameLog

GameLog 是一款面向 Android 游戏测试与客户端开发的原生 macOS Logcat 工具。它把实时日志、测试机截图、测试机录屏和导出材料组织在同一个调试会话中，不需要先打开 Android Studio 或创建空工程。

当前版本为 `1.2.2`，目标系统为 macOS 26 及以上。界面采用 SwiftUI 多窗口、Sidebar、Toolbar、Search、Inspector、会话归档和 Settings；高吞吐日志区由 `NSTableView` 承担。

## 已实现功能

- App 内置 Universal ADB，安装后无需单独配置 Android SDK；设置中仍可选择外部 ADB 作为高级覆盖，并显示实际来源、路径、版本和故障恢复入口。
- 每 2 秒监测 USB、Wi‑Fi 和模拟器设备，展示在线、未授权、离线及 Android 版本/API。
- 从运行中进程、手动输入和按设备保存的最近包名中选择目标；支持多 PID 与进程重启跟踪。
- 通过设置中的 Android 11+ 无线调试流程执行 `adb pair`、`adb connect` 和断开连接。
- 使用 `⌘N` 创建独立日志窗口，每个窗口可选择不同设备、目标和活动会话。
- 持续读取 `main`、`system`、`crash`，运行时探测 Logcat 能力，解析年份、时区、PID/TID、Level、Tag、Buffer、多行堆栈和 Raw Event。
- 10,000/50,000/100,000 条有界日志缓存、100 ms UI 批次刷新、自动跟随与滚动离开检测。
- Level、Tag 包含/排除、目标/全部/指定 PID、文本、大小写和正则过滤；支持过滤预设管理及匹配导航。
- 内置 Unity 与 Unreal Engine 目标进程过滤预设。
- 真机截图、缩略图、证据时间线标记、Quick Look 和 Finder 定位。
- 手动开始/停止的无音频录屏；Android 原生单段达到上限时自动续录并在停止后合并，厂商实现异常时以约 3 FPS 边采边编码 H.264。
- 录屏期间每 5 秒检查 Mac 与设备空间，在状态栏显示有效余量和保守可录时长；空间告警不会替用户自动停止。
- AppKit `AVPlayerView` 内嵌播放、媒体尺寸/时长/大小信息，以及跳转到录屏起止日志。
- 一键“标记问题”会写入时间线、自动截图，并在 Inspector 中编辑标题和复现说明；问题包只包含附近日志、关联证据和诊断结果。
- 自动聚合目标 App 的 Java Crash、Native Crash 和 ANR，并按规范化签名折叠重复问题；目标 PID/包名范围可避免录屏系统进程造成假阳性。
- 会话持续写入 JSONL，异常退出恢复，设备端未拉取录屏恢复，正常退出自动收口。
- 原子导出完整会话、当前过滤结果、所选日志或单个问题包；导出前本地预览 Token、账号、邮箱、IP、序列号和路径的脱敏命中。
- 支持按精确包名或 `com.example.*` 范围配置项目级正则脱敏规则，导出预览逐条显示命中数。
- 独立会话归档窗口提供统计、跨会话 Crash/ANR 趋势、双会话指标/Tag/诊断差异、本地注释和 `⇧⌘I` 会话导入；导入前在页面内预览目标、设备、日志、证据、大小、完整性及合并策略。
- 可按目标包索引 NDK 未剥离 `.so`，通过 Build ID/ABI 匹配和 `llvm-symbolizer` 将 Native 地址还原为函数、内联帧及源码位置；结果提供覆盖率、失败解释、筛选、复制与文本导出。
- 相同目标包的会话支持诊断/唯一事件/开始时间三级时间轴对齐，可设为本地正式基线；错误、Tag 与日志量阈值可按项目调整，并可忽略/恢复已知告警。
- 导出写入含 SHA-256 的 `collaboration-manifest.json`；导入会校验摘要、路径和媒体类型，同 UUID 只合并注释而不覆盖日志。
- 独立 Settings、应用图标、Hardened Runtime、发行打包及可选 Developer ID/公证流程。

## 使用 Xcode

工程入口是 `GameLog.xcodeproj`，它包含：

- `GameLog`：标准 macOS App Target。
- `GameLogTests`：单元测试 Target。
- `GameLog` Shared Scheme：支持 Run、Test、Profile、Analyze 和 Archive。
- Debug / Release 构建配置、Hardened Runtime、Bundle ID、版本号、图标和 Info.plist。

打开与运行：

```bash
open GameLog.xcodeproj
```

在 Xcode 中选择 `GameLog` Scheme 和 `My Mac`，按 `⌘R` 运行、`⌘U` 测试。正式打包前，在 Target → Signing & Capabilities 中选择自己的 Apple Developer Team；然后使用 Product → Archive，完成后可在 Organizer 中选择 Developer ID 分发。

`Package.swift` 仅作为兼容 SwiftPM 测试/命令行工作流的辅助入口，不再是主工程入口。

## 命令行构建与运行

要求：

- macOS 26+
- Xcode 26+
- Swift 6.2+
- 无需另外安装 Android Platform Tools；ADB 已随 GameLog 提供

```bash
./script/build_and_run.sh
```

常用命令：

```bash
# 构建但不启动
./script/build_and_run.sh --build

# 使用 Xcode App/Test Target 构建、运行测试、校验签名/Info.plist/图标/版本并启动
./script/build_and_run.sh --verify

# Release 构建
./script/build_and_run.sh --release

# 360 万条事件的加速压力基线，可用环境变量覆盖数量
./script/run_stress_test.sh
```

应用产物位于 `dist/GameLog.app`。默认会话目录为：

```text
~/Library/Application Support/GameLog/Sessions/
```

也可以在 GameLog → 设置 → 存储中选择其他可写目录。

开发脚本会为 Debug 产物进行可本机运行的 ad-hoc 签名，并验证应用启动后持续
存活；正式发布仍由下方 Release Archive 流程启用 Hardened Runtime、Developer
ID 签名和公证。

## 打包、签名与公证

没有发行证书时，以下命令生成本机可验证的 ad-hoc 签名 ZIP：

```bash
./script/package_release.sh
```

正式分发时：

```bash
GAMELOG_SIGNING_IDENTITY="Developer ID Application: Your Team" \
GAMELOG_NOTARY_PROFILE="gamelog-notary" \
./script/package_release.sh
```

脚本会执行 Xcode Release Archive，先签名内置 ADB、再签名外层 App，随后完成 ZIP 打包；在提供公证配置时还会调用 `notarytool`、staple 和 Gatekeeper 校验。Developer ID 证书和 Apple 公证凭据不包含在仓库中。

发行脚本会自动调用预检；也可以单独复核已有产物：

```bash
# 版本、Build、Bundle ID、macOS 目标、Universal 架构、签名、Hardened
# Runtime、App Sandbox、xcarchive 和 ZIP 完整性
./script/release_preflight.sh

# 对外分发前要求 Developer ID Application
GAMELOG_REQUIRE_DEVELOPER_ID=1 ./script/release_preflight.sh

# 公证完成后同时要求 staple 和 Gatekeeper 通过
GAMELOG_REQUIRE_DEVELOPER_ID=1 \
GAMELOG_REQUIRE_NOTARIZATION=1 \
./script/release_preflight.sh
```

默认预检允许 ad-hoc 签名，用于本机验收；严格模式会明确拒绝 ad-hoc
产物，避免误把本机构建当成可分发版本。

当前工程面向 Developer ID 站外分发，App Sandbox 保持关闭，以便启动 ADB 并访问用户选择的会话目录。如果后续改为 Mac App Store 分发，需要单独设计沙箱权限和 ADB 交付方式。

## 文档

- [产品需求](Docs/GameLog-PRD.md)
- [macOS 26 交互规格](Docs/GameLog-Interaction-Spec.md)
- [技术架构与模块接口](Docs/GameLog-Technical-Architecture.md)
- [实现与验收审计](Docs/GameLog-Implementation-Audit.md)
- [选定的 macOS 26 界面稿](Docs/Assets/gamelog-macos26-selected-concept.png)

## 已知产品约束

- 每个窗口仍限制为单设备、单活动会话；可通过多个窗口并行采集。
- 录屏不包含设备音频；旋转屏幕时 Android 原生录屏可能裁切。
- 旧设备需要每 180 秒切换原生录屏分段，切换点可能出现很短的画面间隔。
- 受保护内容的截图可能为黑屏，应用无法可靠区分系统保护与真实黑色画面。
- 数据默认只保存在本机，不上传、不登录、不采集用户 Logcat 遥测。
- 云端归档、实时团队评论和问题单同步不属于 1.2；当前协作边界是可校验的本地会话包。
