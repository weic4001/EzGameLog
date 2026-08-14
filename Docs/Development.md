# GameLog Development Guide

本文档说明如何在本地构建、测试和调试 GameLog。面向第一次参与项目的贡献者；产品范围和模块边界分别见 [PRD](GameLog-PRD.md) 与 [技术架构](GameLog-Technical-Architecture.md)。

## 环境要求

- macOS 26 或更高版本。
- Xcode 26 或更高版本。
- Swift 6.2 或更高版本。
- Apple Silicon 推荐用于完整验证；Intel Mac 可构建 Android 功能，但当前内置 iOS 辅助工具只有 `arm64`。
- Android 真机或模拟器用于 Android 设备验收；已解锁并信任此 Mac 的 iPhone 用于 iOS 真机验收。

正常开发不需要额外安装 Android SDK Platform-Tools 或 `libimobiledevice`。仓库中的受管二进制位于 `ThirdParty/`，由 App Target 复制到应用包中。

## 两个工程入口

`GameLog.xcodeproj` 是正式 App 工程，负责：

- macOS App Target、Test Target、Shared Scheme。
- App 图标、Info.plist、本地化资源和 Hardened Runtime 配置。
- ADB、iOS 辅助工具、动态库和第三方许可文件的 Bundle Resources。
- Run、Test、Profile、Analyze 和 Archive。

`Package.swift` 只保留 SwiftPM 兼容测试/命令行工作流。不要用 SwiftPM 可执行目标代替 Xcode App Target 做发布验证。

## 常用命令

```bash
# 打开正式工程
open GameLog.xcodeproj

# 构建并启动 Debug App
./script/build_and_run.sh

# 仅构建 Debug App
./script/build_and_run.sh --build

# 构建、测试、校验 Bundle 并启动
./script/build_and_run.sh --verify

# SwiftPM 测试
swift test

# Release Archive、签名、压缩和预检
./script/package_release.sh

# 运行 360 万条事件的压力基线
./script/run_stress_test.sh
```

Debug 产物默认复制到 `dist/GameLog.app`。测试会话数据默认位于 `~/Library/Application Support/GameLog/Sessions/`；不要将真实会话目录加入 Git。

## 代码结构

| 路径 | 边界 |
| --- | --- |
| `Sources/GameLog/App` | App 生命周期、窗口注册和应用级路由 |
| `Sources/GameLog/Models` | Codable 领域模型、过滤器、偏好和证据元数据 |
| `Sources/GameLog/Services/ADB` | Android ADB 定位、执行和设备查询 |
| `Sources/GameLog/Services/iOS` | iOS 工具定位、设备信息、日志流和截图 |
| `Sources/GameLog/Services/LogPipeline` | 日志解析、能力探测、缓冲和过滤 |
| `Sources/GameLog/Services/Capture` | Android 截图/录屏及媒体元数据 |
| `Sources/GameLog/Services/Diagnostics` | Crash、ANR、符号化、会话分析和回归 |
| `Sources/GameLog/Stores` | 会话持久化、恢复、导入/导出和符号目录 |
| `Sources/GameLog/Views` | SwiftUI 屏幕和 Inspector |
| `Sources/GameLog/AppKitBridge` | 仅用于高吞吐日志表和媒体播放的 AppKit 桥接 |
| `Tests/GameLogTests` | 协议替身、解析器、存储、捕获和设备服务测试 |

## 运行时边界

- UI 状态由 `@MainActor` 管理。
- 设备命令由 `Foundation.Process` 启动，参数使用数组传递，不经过用户可控 Shell 字符串。
- 日志解析、缓冲、会话写入和设备工具执行保持在各自的并发边界内。
- `NSTableView` 负责高频行渲染；不要把无限日志流直接绑定到 SwiftUI `List`。
- 会话数据持续写入 JSONL，内存仅保留有界窗口；导出不依赖日志是否仍在内存中。
- iOS 截图是用户主动请求的单帧采集；当前版本没有 iOS 无侵入录屏路径。

## 测试策略

单元测试优先覆盖不依赖设备的边界：

- `LogcatParserTests`、`IOSLogParserTests`：分块输入、多行堆栈、时间/级别解析。
- `LogFilterEngineTests`：级别、Tag、PID、文本、大小写和正则组合。
- `DeviceServiceTests`、`IOSDeviceServiceTests`：设备状态、参数验证和元数据。
- `CaptureServiceTests`：截图校验、分段录屏、恢复和远端文件清理。
- `SessionStoreTests`、`P2SessionStoreTests`：原子导出、恢复、摘要校验、导入合并和脱敏。
- `LocalizationCatalogTests`：中英文覆盖和格式占位符。

设备相关改动至少完成一次真实设备手工验收：

1. 连接、授权或配对设备。
2. 选择目标进程并启动日志会话。
3. 让目标进程重启，确认日志流恢复或正确提示。
4. 请求截图并检查证据时间线与导出内容。
5. Android 录屏改动需要验证开始、持续、手动停止、分段合并和空间告警。
6. iOS 改动需要验证信任状态、进程过滤、多行日志和相机权限。

## 本地化

用户可见文案集中在 `Sources/GameLog/Resources/Localizable.xcstrings`。新增文案时：

1. 使用稳定、语义明确的 key。
2. 同时补齐 `en` 与 `zh-Hans` 翻译。
3. 保持 `%@`、`%lld` 等格式占位符一致。
4. 运行 `swift test`，确认 `LocalizationCatalogTests` 通过。
5. 需要更新菜单、Info.plist 或权限说明时同步检查 `en.lproj/InfoPlist.strings` 和 `zh-Hans.lproj/InfoPlist.strings`。

## 常见问题

### Xcode 找不到目标或资源

确认打开的是 `GameLog.xcodeproj`，而不是只打开 `Package.swift`。清理 `.build/xcode` 后重新运行 `./script/build_and_run.sh --verify`。

### ADB 设备显示未授权

解锁设备并确认设备端 RSA 提示；无线调试需要在 GameLog 设置中完成配对与连接。外部 ADB 只用于高级覆盖，默认仍应使用 Bundle 内的 ADB。

### iOS 工具在 Intel Mac 不可用

这是当前兼容性边界：`ThirdParty/iOSDeviceTools` 只有 `arm64`。不要用 Rosetta 绕过检查或替换未审查的二进制；完整 Intel 支持需要单独构建、签名和验收。

### 本地签名与正式签名

`build_and_run.sh` 使用 ad-hoc 签名便于本机运行；正式发布使用 `package_release.sh` 配置 Developer ID 和公证。不要把证书、密钥、Keychain profile 或 provisioning profile 提交到仓库。

