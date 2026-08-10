# GameLog 实现与验收审计

> 版本：1.2.2  
> 审计日期：2026-07-30  
> 对照文档：`GameLog-PRD.md`、`GameLog-Interaction-Spec.md`、`GameLog-Technical-Architecture.md`

## 1. 结论

GameLog `1.2.2` 已完成 P0–P2 本地能力与 P2.1 精修，并将 Universal ADB、许可材料和版本来源内置到 App。新安装无需 Android SDK；设置中仍保留外部 ADB 高级覆盖，发行脚本对嵌套 ADB 和外层 App 分层签名与验证。

云端归档、实时团队评论和问题单系统未接入：这些能力需要新增外部服务、账号权限和数据治理授权，不属于 1.2 的本地 P2 交付范围。

工程仍有五类发行资格工作依赖发布环境、真实无线设备或较长测试窗口：Developer ID/Apple 公证、30 分钟交互式 soak、无线 ADB 真机配对矩阵、物理 USB 拔插矩阵、VoiceOver 与辅助显示模式人工复核。这些不是本地实现缺口，必须在向外部分发前完成。

## 2. P0 需求逐项映射

| 需求 | 状态 | 实现与验证证据 |
| --- | --- | --- |
| FR-ADB-001 | ✅ | `ADBLocator` 按外部覆盖、App 内置、PATH/SDK 环境变量和常见目录查找；`ADBExecutor` 仅使用 executable URL + arguments，并校验 `adb version`。 |
| FR-ADB-002 | ✅ | ADB Settings 使用 `NSOpenPanel` 选择外部覆盖，并提供“恢复内置 ADB”。 |
| FR-ADB-003 | ✅ | `MissingADBView`、`FailedADBView` 展示内置资源故障、重新安装和选择外部 ADB 入口。 |
| FR-ADB-004 | ✅ | Xcode Archive 嵌入 Universal ADB、NOTICE 与来源版本；脚本逐层签名，预检验证来源哈希、双架构、版本、签名和 ZIP 内容。 |
| FR-DEV-001 | ✅ | `DeviceService` 解析 `adb devices -l`，并发补充 Android 版本/API；设备行展示 Serial、USB/Wi‑Fi/模拟器、状态和版本。 |
| FR-DEV-002 | ✅ | 未授权状态显示 RSA 解锁说明及“重新检查”。设备解析单元测试覆盖 unauthorized。 |
| FR-DEV-003 | ✅ | 2 秒设备监测；断开进入 recovering，同 Serial 在线后恢复 PID、日志流和待恢复录屏。Logcat 子进程单独意外结束时也会自动重启。 |
| FR-DEV-004 | ✅ | 每个日志窗口的活动会话期间禁止切换设备和目标；共享 ADB/目录设置在任一窗口活动时锁定。 |
| FR-PROC-001 | ✅ | 运行进程菜单、包名输入和按设备保存的历史包名三种入口。 |
| FR-PROC-002 | ✅ | 优先 `pidof`，回退 `ps -A`，返回全部匹配 PID；单元测试覆盖多 PID。 |
| FR-PROC-003 | ✅ | 2 秒 PID 监测，区分退出、首次启动和重启，插入系统事件并恢复目标过滤。 |
| FR-PROC-004 | ✅ | `recentPackagesByDevice` 按 Serial 保存最近 10 项。 |
| FR-SES-001 | ✅ | 会话记录 UUID、主机时间/时区、设备、ADB 路径/版本、包名、初始 PID、缓冲区、预设和完整初始过滤条件。 |
| FR-SES-002 | ✅ | ready、starting、capturing、followingPaused、recovering、stopping、stopped、failed 全状态；暂停只改变自动跟随。 |
| FR-SES-003 | ✅ | 停止时结束录屏、截图、日志和监测任务并同步磁盘；提供 Finder、完整/过滤/所选导出及带确认的永久丢弃。 |
| FR-SES-004 | ✅ | `.inprogress` 发现、恢复 banner、只加载末尾内存窗口、保留完整 JSONL、待恢复录屏和带确认清理。 |
| FR-LOG-001 | ✅ | 运行时探测 `logcat --help`，优先 `threadtime,year,zone`；解析时间、Level、PID/TID、Tag、Message、Buffer、Raw Text。 |
| FR-LOG-002 | ✅ | 无新日志头的连续行合并到上一事件；分块、多行、年份/时区、跨年均有测试。 |
| FR-LOG-003 | ✅ | 10k/50k/100k 有界缓冲；采用延迟压缩而非每批 `removeFirst`；淘汰计数与 logd/chatty 报告的传输丢失行数独立。 |
| FR-LOG-004 | ✅ | ADB 后台持续读取，AppModel 每 100 ms 合并刷新；过滤在可取消的后台 Task 中执行。 |
| FR-LOG-005 | ✅ | 本地清屏只清 UI buffer，并持久化“设备 Logcat 缓冲区未改变”系统标记。 |
| FR-VIEW-001 | ✅ | AppKit `NSTableView`、22 pt 固定行高，默认时间/等级/PID-TID/Tag/消息列，列宽/顺序/显隐持久化。 |
| FR-VIEW-002 | ✅ | 底部自动跟随；向上滚动后暂停；状态栏显示“回到最新”及 `⌘↓`。 |
| FR-VIEW-003 | ✅ | 单选、多选、键盘移动、原始文本/消息/结构化 TSV 复制。 |
| FR-VIEW-004 | ✅ | 表格保持单行紧凑，多行堆栈在 Inspector 完整显示。 |
| FR-FLT-001 | ✅ | 最低等级与多选等级组合；等级始终显示字符，颜色仅作辅助。 |
| FR-FLT-002 | ✅ | Tag 包含/排除、目标 PID、全部设备和指定 PID；切换范围不重启底层 ADB 流。 |
| FR-FLT-003 | ✅ | 普通/大小写/正则搜索、错误提示、匹配数、上一个/下一个，150 ms 防抖。 |
| FR-FLT-004 | ✅ | 保存、应用、重命名、确认删除；可见省略号菜单和 Context Menu 均可管理。 |
| FR-INSP-001 | ✅ | 完整时间、主机接收时间、Level、PID/TID、Tag、Buffer、类型、Message、Raw Text 和书签。 |
| FR-INSP-002 | ✅ | 按时间距离排序相关截图/录屏；展示尺寸、大小、时长、设备和无音频说明，可跳到录屏开始/结束日志。 |
| FR-INSP-003 | ✅ | Toolbar、视图菜单、`⌥⌘I` 显隐 Inspector，隐藏后日志区释放宽度。 |
| FR-CAP-001 | ✅ | `exec-out screencap -p`、PNG 魔数校验、原子写入、缩略图、证据标记和 Inspector 自动展示。真机 1080×2400 验证。 |
| FR-CAP-002 | ✅ | 离线、命令失败、非 PNG 均产生非阻塞状态及失败系统事件；明确说明受保护黑屏限制。 |
| FR-CAP-003 | ✅ | 单设备一次一个截图任务，按钮显示/禁用进行中状态，`⌘.` 可取消。 |
| FR-REC-001 | ✅ | 检查在线会话、本地 500 MB 空间、会话目录可写和设备 `/sdcard` 可写，再启动 `screenrecord`。 |
| FR-REC-002 | ✅ | 语义红色录制按钮、文字、计时和“录屏开始”时间线标记，并发送可访问性公告。 |
| FR-REC-003 | ✅ | 用户停止后拉取 `.partial`、校验非空、合并续录分段，成功后才删除远端文件并插入结束标记。 |
| FR-REC-004 | ✅ | 手动开始/停止、无音频、设备原生/720p、自动/4/8 Mbps；原生每 180 秒自动续段，厂商原生崩溃时逐帧流式 H.264 兼容录制。 |
| FR-REC-005 | ✅ | 中断远端路径持久化到 `pending-recordings.json`；重连后拉取、校验时长/大小，校验前不删除远端文件。 |
| FR-REC-006 | ✅ | 录屏期间每 5 秒读取 Mac/设备可用空间，按较小值显示有效余量和保守剩余时长；2 GB/500 MB 分级告警但不替用户停止。 |
| FR-EXP-001 | ✅ | `session.json`、`logs.jsonl`、`logs.txt`、`screenshots/`、`.thumbnails/`、`recordings/`、书签及待恢复清单。 |
| FR-EXP-002 | ✅ | 完整会话、当前过滤结果、当前选择三种范围；每种同时生成 TXT 和 JSONL。 |
| FR-EXP-003 | ✅ | 在目标目录的隐藏临时目录完成写入后一次移动；失败清理临时目标并保留源会话。完整会话采用流式 JSONL→TXT 转换。 |
| FR-EXP-004 | ✅ | 异常会话默认保留 7 天；设置可调 1–30 天并支持清理过期/全部；当前会话丢弃有不可撤销确认。 |
| FR-INC-001 | ✅ | Toolbar 固定“标记问题”和 `⌥⌘M`；立即插入时间线、记录录屏偏移、自动截图，并在 Inspector 内联编辑标题与说明。 |
| FR-INC-002 | ✅ | 原子问题包包含时间窗口日志、问题清单、会话摘要、诊断、脱敏清单及关联截图/录屏，不复制无关媒体。 |
| FR-DIAG-001 | ✅ | 聚合 Java/Native Crash 与 ANR，规范化动态地址/数字后折叠；以观察 PID 或目标包名约束归属。 |
| FR-PRV-001 | ✅ | 导出前 Sheet 预览 Token、账号、邮箱、IP、设备序列号和本地路径命中，可逐类关闭；全程仅本地处理。 |

### 2.1 P1（1.1）需求映射

| 需求 | 状态 | 实现与验证证据 |
| --- | --- | --- |
| FR-WADB-001 | ✅ | `WirelessADBEndpoint` 校验主机/端口，6 位配对码校验后以参数数组调用 `adb pair/connect/disconnect`；设置页不持久化配对码。 |
| FR-MWIN-001 | ✅ | 主场景改为 `WindowGroup`；每窗独立 `AppModel`，共享 `SessionStore` actor；`FocusedValue` 将菜单动作路由到聚焦窗口。 |
| FR-PRESET-001 | ✅ | Unity/Unreal 内置预设固定出现在已存过滤器区域，默认目标 PID 并覆盖引擎/AndroidRuntime/Crash Tag。 |
| FR-PRV-002 | ✅ | 自定义规则具备项目范围、正则、替换文本、启用状态、UserDefaults 持久化和逐条导出预览计数。 |
| FR-ARC-001 | ✅ | 独立归档窗口读取轻量列表，按需生成并缓存 `analysis.json`；事件、证据、PID 或问题变化会使缓存失效。 |
| FR-ANA-001 | ✅ | `SessionAnalysisService` 按签名跨会话聚合，并提取 Java 方法/文件行及 Native 已有符号/库名提示。 |
| FR-DIFF-001 | ✅ | 比较日志/错误/诊断/问题/证据、诊断新增/消失/持续和 Tag 差异前 20。 |
| FR-NOTE-001 | ✅ | `annotation.json` 保存标题、说明和去重标签，完整会话导出包含该文件。 |

### 2.2 P2（1.2）需求映射

| 需求 | 状态 | 实现与验证证据 |
| --- | --- | --- |
| FR-SYM-001 | ✅ | `ELFMetadataReader` 支持 ELF32/64、大小端、ABI 和 GNU Build ID；`SymbolCatalogStore` 按精确包名索引 `.so`，拒绝符号链接并限制 50,000 个文件。移除操作只改索引。 |
| FR-SYM-002 | ✅ | `NDKSymbolizerLocator` 自动定位 NDK 工具；`NativeSymbolicationService` 解析 Native 帧，按库名/Build ID/ABI 唯一匹配，并通过参数数组调用 `llvm-symbolizer`。歧义、缺失、未解析和失败状态均独立保存到 `symbolication.json`。 |
| FR-IMP-001 | ✅ | `SessionStore.importSession` 验证会话结构和全部 JSONL，拒绝根目录/内容符号链接、路径穿越、非普通媒体及超限 JSON；整个导入树共享 100,000 文件/50 GB 预算，隐藏临时目录复制后原子移动。同 UUID 先核对不可变身份，仅合并注释而不覆盖日志。 |
| FR-COL-001 | ✅ | 完整、过滤和所选导出写入 `collaboration-manifest.json`，记录应用/格式版本、导出范围和关键文件 SHA-256；导入存在清单时强制校验。 |
| FR-ALIGN-001 | ✅ | `SessionRegressionService.align` 按相同诊断、唯一规范化日志、会话开始三级锚点返回偏移、方式和置信度；对比页展示同包多会话结果。 |
| FR-REG-001 | ✅ | 目标包正式基线持久化到 `.regression-baselines.json`；对比页按严重度展示新增 Crash/ANR、重复诊断、错误、Tag 和日志量增长。 |

### 2.3 P2.1（1.2.1）精修映射

| 需求 | 状态 | 实现与验证证据 |
| --- | --- | --- |
| FR-IMP-002 | ✅ | `SessionStore.previewImport` 复用完整安全校验但不写入；页内预检展示身份、规模、完整性和新建/合并策略，确认时再次校验。测试确认取消前目标归档仍为空。 |
| FR-SYM-003 | ✅ | `SessionSymbolicationReport` 汇总覆盖率、五类状态和缺失库；符号页展示原因/建议并可筛选、复制、导出包含原始帧、内联帧、路径和错误的文本。 |
| FR-REG-002 | ✅ | `.regression-configurations.json` 按包保存归一化阈值和忽略键；告警使用稳定 `metric` 键，页面可忽略、显示隐藏数并一键恢复。 |

## 3. 设置、系统状态与可访问性

| 范围 | 状态 | 说明 |
| --- | --- | --- |
| Settings | ✅ | 通用、ADB、录制、隐私、存储五页；无线调试和项目脱敏规则已纳入原生设置窗口。 |
| 状态覆盖 | ✅ | ADB 缺失/失败、无设备、未授权、离线、未选目标、启动、采集、暂停跟随、恢复、录屏、磁盘不足、导出失败均有文字与恢复动作。 |
| 快捷键 | ✅ | `⌘F`、`⌘↓`、`⌥⌘P`、`⌥⌘S`、`⌥⌘M`、`⌥⌘R`、`⌘K`、`⌥⌘I`、`⇧⌘I`、`⇧⌘E`、`⌘.`；核心操作同时有可见控件和菜单。 |
| macOS 26 UI | ✅ | 系统 `WindowGroup`、辅助 `Window`、`NavigationSplitView`、Toolbar、Search、Inspector、Settings；内容区不自绘玻璃。 |
| 辅助技术 | ✅ 实现 | Label/Help、等级字符、录屏文字+图标+计时、截图/录屏/断连/恢复公告、系统字体和对比度颜色；归档导入预检支持 Return 确认、Escape 取消，状态、回归阈值和图标补充语义标签。人工 VoiceOver 回归列为发行资格项。 |
| 隐私 | ✅ | 本机保存、无账号/云/遥测；导出前隐私提示；应用 Logger 不记录用户 Logcat；参数数组执行 ADB。 |

## 4. 当前模块接口清单

| 模块 | 主要接口 | 线程/隔离边界 |
| --- | --- | --- |
| AppModel | 会话、过滤、截图、录屏、导出、恢复和设置的用户意图入口 | `@MainActor` |
| ADBLocator | `locate(savedPath:)` | Sendable、异步校验 |
| ADBExecuting / ADBExecutor | `run(_:serial:timeout:)`、`stream(_:serial:)` | 每个 Process 独立取消；stdout/stderr 同时排空 |
| DeviceService | `listDevices()`、`listProcesses(serial:)`、`pids(forPackage:serial:)` | Sendable；元数据 actor cache |
| DeviceService | `availableStorageBytes(serial:)` | 解析设备 `df -k`，供录屏安全轮询 |
| LogcatCapabilities | `parse(helpText:)` | 纯值类型 |
| LogStreamingService | `events(serial:buffers:)` | detached 读取与解析，批量 AsyncThrowingStream |
| LogcatParser | `consume(_:)`、`finish()` | 值类型；保留分块尾部与 pending event |
| LogBuffer | `append(contentsOf:)`、`updateCapacity(_:)`、`removeAll()` | MainActor 所有；有界、延迟压缩 |
| LogFilterEngine | `filter(events:configuration:targetPIDs:)` | 无状态；后台可取消 Task |
| CaptureService | `takeScreenshot`、`recordScreen`、`recoverRecording` | Sendable；临时文件 + 完成校验 |
| DiagnosticAggregator | `aggregate(events:targetPIDs:targetPackage:)` | 无状态；目标范围、签名聚合与上下文收集 |
| LogRedactor | `preview`、`redact`、`redactedSession` | 无状态；仅本地分类扫描与替换 |
| RecordingSafetyEvaluator | `evaluate` | 无状态；空间等级和剩余时长估算 |
| SessionAnalysisService | `snapshot`、`trends`、`compare` | 无状态；后台分析与差异计算 |
| ArchiveModel | `refresh`、`previewImport`、`confirmPendingImport`、`symbolicateSelectedSession`、`saveRegressionThresholds` | `@MainActor`；归档、导入预检、符号和回归状态 |
| ELFMetadataReader | `read(from:)` | 有界只读 ELF 解析 |
| SymbolCatalogStore | `index`、`removeRoot`、`resolvedSymbolizerURL` | `actor`；项目级目录索引 |
| NativeSymbolicationService | `parseFrames`、`symbolicate` | 后台异步、可注入 symbolizer executor |
| SessionRegressionService | `align`、`regression` | 无状态纯计算 |
| SessionRegistry | `register`、`closeWindow`、`prepareForTermination` | `@MainActor`；多窗口生命周期 |
| ScreenshotVideoEncoder | `start`、`append`、`finish`、`cancel` | AVAssetWriter session，逐帧 detached 编码 |
| SessionStore | create/append/finalize/load/export/previewImport/import/regressionConfigurations | `actor`；JSONL、原子导入及项目回归配置 |
| LogTableView | `NSViewRepresentable` + Coordinator | MainActor/AppKit；差异插入、选择、Quick Look |
| RecordingPlayerView | AppKit `AVPlayerView` bridge | Inspector 按需加载 |

## 5. 自动化与性能证据

当前 1.2.2 完整 `swift test`：

- 73 项测试，0 failure。
- ADB 一次性命令取消与超时。
- 外部 ADB 覆盖内置版本、内置版本优先于环境路径、无效外部覆盖回退内置版本。
- 在线/未授权/离线设备和多 PID。
- Android 包名白名单校验，危险输入在到达 ADB 前被拒绝。
- Logcat 能力探测、分块、多行、年份/时区与 buffer。
- 有界日志缓存、过滤、正则错误和丢失行诊断。
- PNG 校验、缩略图、原生录屏预检查/拉取/远端删除。
- 被篡改的录屏恢复远端路径和本地文件名在调用 ADB 前被拒绝。
- 会话持续写入、初始过滤元数据、末尾恢复、待恢复录屏、原子导出。
- 问题记录持久化、脱敏问题包、Crash/ANR 聚合与目标进程范围。
- 常见敏感数据分类脱敏、录屏空间等级和保守时长估算。
- 无线 ADB 参数与危险输入拦截、项目级自定义脱敏。
- 归档注释、分析缓存、跨会话趋势、堆栈提示和双会话差异。
- ELF64 GNU Build ID/ABI、项目符号目录隔离、Build ID 精确匹配和同名库歧义拒绝。
- `llvm-symbolizer` 函数、源码和内联帧输出解析。
- 诊断、唯一事件与会话开始三级时间轴对齐；新增 Crash/ANR、错误、Tag 与日志量回归告警。
- 协作清单导出/导入、摘要篡改拒绝、符号链接拒绝、重复注释无损合并。
- 符号链接会话根目录、16 MB 以上 JSON 元数据和整个包共享导入预算。
- 回归基线和逐会话符号化报告持久化。
- 导入预检只读、新建/合并策略识别和 SHA-256 完整性状态。
- 符号化覆盖率、缺失库汇总及完整文本内容。
- 自定义回归阈值、稳定忽略键过滤和项目配置持久化。
- 100,000 条管线：约 0.23 秒。
- 5,000 行单块解析：约 0.24 秒。
- 100,000 条完整会话导出：约 4.1 秒。

额外执行 `script/run_stress_test.sh`：

- 3,600,000 条事件（等价 2,000 行/秒 × 30 分钟的事件量）；
- 50,000 条有界保留和过滤；
- 4.677 秒完成，0 failure。

这些是加速数据管线基线，不替代发行前 30 分钟真实 UI soak。

## 6. 真机与 UI 验收记录

环境：

- macOS 26.5.2
- Xcode 26.6
- Swift 6.3.3
- OnePlus 9 LE2110
- ADB Serial `1d14f6ed`

已验证：

1. GUI 自动识别设备，并读取 234+ 个应用进程。
2. 目标包 `net.openvpn.openvpn`、PID `18589` 启动会话并读取 main/system/crash。
3. 目标 PID 与全部设备日志在本地切换，ADB 流不重启。
4. 截图生成 `1080×2400` PNG、缩略图和 `HH:mm:ss.SSS` 时间线标记。
5. 该设备原生 `screenrecord` 返回 139 后自动切换兼容录屏；流式编码产物为 H.264、`576×1280`、`10.0667s`，可在 Inspector 的 `AVPlayerView` 播放。
6. Inspector 显示日志、媒体元数据、Quick Look、导出、Finder 及录屏起止跳转。
7. `⇧⌘E` 完成真实系统面板整包导出；导出目录包含 session、JSONL、TXT、书签、截图/缩略图和 MP4，未遗留 `.GameLog-export-*`。
8. 停止会话移除 `.inprogress`；活动会话中 `⌘Q` 会写入 `endedAt`、停止自有任务并移除恢复标记。
9. 丢弃当前会话会先显示明确的不可撤销确认；验收时选择取消，源会话被保留。

2026-07-24 增量真机与 UI 回归：

1. Samsung SM A146U1、Android 15 / API 35，目标进程 `escape.arrow.dash.inner`、PID `7725`。
2. “标记问题”立即插入时间线并自动保存 `1080×2408` PNG；Inspector 同屏显示标题、复现说明、保存和问题包导出。
3. 问题包导出先显示脱敏预览；六类规则、命中数量、本地处理提示、取消和“选择位置并导出…”均可通过键盘/辅助树访问。
4. 录屏由同一 Toolbar 按钮手动开始和结束，验证成品时长 `22.8s`；录制中状态栏显示 `707.42 GB` 有效余量和保守剩余时长。
5. 回归发现设备 `screencap` 辅助进程的 fatal signal 曾产生假阳性。诊断现只接受会话观察 PID 或明确包含目标包名的锚点，专项测试已覆盖。
6. P1 主界面可见 Unity/Unreal 内置预设、归档入口和设置入口；高级过滤保持页面内联分组。`⌘N` 创建第二个独立 `session-AppWindow`，窗口菜单同时列出两个日志窗口。
7. `⇧⌘O` 成功创建单例“会话归档”窗口；归档索引、趋势、对比和注释的数据行为由 SessionStore/SessionAnalysisService 的专项测试覆盖。
8. 回归发现 Debug 分发产物曾以 Hardened Runtime ad-hoc 签名，导致 Xcode 26 生成的 `GameLog.debug.dylib` 被 Library Validation 拒绝。开发脚本现使用普通 ad-hoc 签名，发行脚本仍保留 Hardened Runtime；稳定启动二次检查已纳入 `--verify`。

2026-07-24 P2 / P2.1 本地集成验证：

1. 开发机从 `ANDROID_HOME/ndk/26.0.10792818` 自动定位 `llvm-symbolizer` 17.0.2，并以与应用相同的参数形式对 Android `.so` 完成进程级调用。
2. Fake symbolizer 覆盖函数、源码、行列和内联帧；最小 ELF fixture 覆盖 ABI 与 GNU Build ID。当前没有随仓库分发第三方项目的真实未剥离符号文件。
3. 临时会话目录覆盖完整导出后再导入、SHA-256 篡改拦截、重复 UUID 注释合并和符号链接媒体拒绝，均由自动化测试验证。
4. `build_and_run.sh --verify` 完成 Xcode App/Test Target、Info.plist、版本、图标、内置 ADB、ad-hoc 签名和启动存活检查；73 项 Xcode 测试通过。
5. `package_release.sh` 生成 `GameLog-1.2.2.xcarchive`、Universal（arm64 + x86_64）Hardened Runtime ad-hoc `GameLog.app` 和校验无损的 `GameLog-1.2.2-macOS.zip`；内置 ADB 35.0.1 同为 Universal。
6. 导入预检测试确认预览阶段不创建目标归档，确认后正确导入，再次预览同 UUID 时识别为仅合并注释；项目回归阈值、忽略键和符号化文本均有持久化/纯值专项测试。
7. 主窗口辅助树可确认“会话归档与对比”入口和内联高级过滤；打开归档后 Computer Use 原生桥接断开，但 GameLog 进程持续运行。归档四分段的最终视觉与 VoiceOver 人工检查仍保留为发行资格项，不能用自动化数据行为测试替代。
8. `release_preflight.sh` 可重复验证源配置、App、xcarchive 与 ZIP 的版本/Build 一致性、Bundle ID、macOS 目标、Universal 架构、Hardened Runtime、App Sandbox 和压缩包路径安全；1.2.2 进一步验证受管 ADB 来源哈希、版本、双架构、嵌套签名、NOTICE 及归档/ZIP 内容。严格模式会拒绝 ad-hoc 签名，并可进一步要求 staple 与 Gatekeeper 通过。
9. 当前开发机 `security find-identity -p codesigning -v` 返回 0 个有效签名身份。本机 ad-hoc 预检通过，Developer ID 严格预检按预期停止并报告缺少发行签名。
10. Shared Scheme 的 Analyze 动作只分析 App Target，避免将仅在 Debug 开启 `@testable` 的测试模块错误带入 Release 分析；Release arm64/x86_64 静态分析通过。

## 7. 发行资格待办

以下工作不阻塞本地功能开发完成，但阻塞对外正式发布：

1. 使用真实 `Developer ID Application` 证书运行 `script/package_release.sh`。
2. 使用团队 `notarytool` keychain profile 完成公证、staple 和 Gatekeeper 校验。
3. 在目标 Mac/Android 设备矩阵上完成 30 分钟 2,000 行/秒交互式 UI soak，并记录 RSS、滚动和 Inspector 响应。
4. 在 Android 11+ 设备矩阵上完成真实 `adb pair`、`adb connect`、断开和配对码失效回归。
5. 进行物理 USB 拔插、设备重启、RSA 重新授权和多 ROM `screenrecord` 回归。
6. 使用 VoiceOver、Increase Contrast、Reduce Transparency、Reduce Motion、浅色和深色完成视觉/键盘人工复核。
7. 人工打开归档窗口，复核“会话/趋势/对比/符号”四分段在最小窗口宽度下的排版和键盘顺序。
