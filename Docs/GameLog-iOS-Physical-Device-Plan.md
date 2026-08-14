# GameLog iOS 真机支持范围与计划

> 状态：日志与截图进入当前实现；无侵入录屏仅列入计划  
> 日期：2026-08-11  
> 主机平台：macOS 26+

## 1. 产品决策

GameLog 继续使用同一套 Sidebar、日志表格、Inspector、会话和证据时间线，不为 iOS 创建第二套主界面。用户先选择设备，再选择目标进程；工具栏根据当前设备能力启用日志、截图或录屏操作。

| 能力 | Android | iOS 真机（当前） | iOS 真机（计划） |
| --- | --- | --- | --- |
| USB 设备发现 | 已实现 | 当前实现 | — |
| 目标选择 | 包名/进程 | 运行中进程名 | 可评估 Bundle ID 映射 |
| 实时日志 | Logcat | 目标进程 syslog | 结构化字段继续精修 |
| 即时截图 | `screencap` | CoreMediaIO/AVFoundation 单帧 | 多设备识别矩阵 |
| 录屏 | 手动开始/停止 | 不提供 | 无侵入手动开始/停止 |

## 2. 当前用户流程

1. 通过 USB 连接 iPhone，解锁设备并选择“信任此电脑”。
2. 打开 GameLog；设备出现在 Sidebar，并显示 iOS 名称、型号、版本和 UDID。
3. 选择运行中进程，开始日志会话。
4. 在需要留证时点击截图。首次使用时 macOS 显示相机访问授权；只有用户确认后才建立单帧采集。
5. 截图进入当前会话的证据列表和时间线，可 Quick Look、Finder 定位或随会话导出。
6. iOS 设备上的录屏按钮保持禁用，并通过帮助文案标记为“计划中”。

## 3. 当前技术模块

| 模块 | 接口职责 | 实现方式 |
| --- | --- | --- |
| `DevicePlatform` | 区分 Android/iOS 与平台能力 | 会话模型向后兼容，旧数据默认 Android |
| `IOSDeviceToolLocator` | 定位和校验内置 iOS 工具 | App `Contents/MacOS` 优先 |
| `IOSDeviceToolExecutor` | 安全执行参数数组、超时和流式任务 | 复用既有 Process 隔离，不拼 Shell |
| `IOSDeviceService` | 设备信息、配对状态、进程与 PID | `idevice_id`、`ideviceinfo`、`idevicepair`、`idevicesyslog pidlist` |
| `IOSLogStreamingService` | 启动和取消目标进程日志流 | `idevicesyslog --process` |
| `IOSLogParser` | 分块、年份、等级和多行消息解析 | 值类型解析器，可注入测试 |
| `IOSScreenCaptureService` | 用户触发的单帧 PNG | CoreMediaIO 开放 iOS 采集源，AVFoundation 读取一帧 |
| `AppModel` | 跨平台路由与能力开关 | Android/iOS 分支独立失败，不互相阻塞 |

## 4. 工具交付与权限

- App 内置最小化 `libimobiledevice` 工具和运行库，普通用户无需 Homebrew、Xcode 或单独安装 ADB/iOS 工具。
- iOS 工具和动态库采用相对 Mach-O 依赖，打包时逐层签名；完整版本、SHA-256 和许可文本随 App 分发。
- 当前 iOS 工具为 Apple Silicon `arm64`。Intel Mac 上 Android 功能正常，iOS 工具显示为不可用。
- 日志访问依赖 iPhone 已解锁、配对并信任 Mac。
- 截图只在用户点击后请求 macOS 相机权限，因为 iPhone 屏幕以外部视频采集设备形式提供。
- App 不上传设备日志或画面，不保存配对码，也不尝试绕过系统权限。

## 5. iOS 无侵入录屏计划（当前不实现）

目标交互与 Android 一致：用户点击开始后持续录制，只有再次点击停止、设备断开、应用退出或不可恢复错误时才结束；不设置产品层面的固定时长。

进入实现前必须完成：

1. 验证 CoreMediaIO/AVFoundation 长时采集在目标 iOS/macOS 版本矩阵上的公开 API 可用性与稳定性。
2. 明确屏幕方向变化、帧率、色彩空间、设备断连和休眠恢复行为。
3. 使用 `AVAssetWriter` 边采边写 H.264/HEVC，禁止把完整帧序列积压在内存。
4. 复用现有本地磁盘空间告警、异常退出收口、证据时间线和导出能力。
5. 明确权限说明，并确保每次录制都由可见的用户操作开始，工具栏持续显示录制状态和时长。
6. 完成至少 30 分钟真机 soak、锁屏/来电/旋转/拔线和拒绝权限回归后再开放按钮。

## 6. 验收矩阵

- iPhone 至少覆盖一台 USB 真机：发现、名称/系统版本、进程列表、目标日志、截图。
- 设备锁定、未信任、拔线、目标进程退出和日志流中断均有明确状态。
- 相机权限允许、拒绝及从系统设置恢复三条路径均需人工验证。
- Android 回归必须确认设备发现、Logcat、截图和录屏未被 iOS 增量影响。
- Apple Silicon Release App 必须脱离 Homebrew/Xcode 环境执行内置 `idevice_id`。
- Intel Mac 必须确认 App 可启动、Android 可用，并对 iOS 能力显示兼容性说明。
