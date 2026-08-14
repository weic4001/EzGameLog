# GameLog 文档索引

> 当前基线：方案 1（Sidebar + 高密度日志表格 + Inspector）  
> 平台：macOS 26 及以上  
> 更新日期：2026-08-14

## 文档

1. [产品需求文档（PRD）](GameLog-PRD.md)
   - 产品目标、范围、详细功能、状态、非功能需求和 P0–P2 验收清单。
2. [macOS 26 页面与交互规格](GameLog-Interaction-Spec.md)
   - 主窗口区域、Toolbar、Sidebar、日志表、Inspector、交互流程、键盘和可访问性。
3. [技术架构与 Swift 模块接口清单](GameLog-Technical-Architecture.md)
   - 技术选型、并发边界、领域模型、Service Protocol、NSTableView Bridge、测试和开发顺序。
4. [选定视觉方向](Assets/gamelog-macos26-selected-concept.png)
   - 表达方案 1 的信息架构和界面密度；详细行为以交互规格为准。
5. [实现与验收审计](GameLog-Implementation-Audit.md)
   - P0–P2 逐项映射、自动化测试、真机/UI 验收记录和发行前外部检查项。
6. [iOS 真机支持范围与计划](GameLog-iOS-Physical-Device-Plan.md)
   - 当前日志/截图范围、系统权限、工具交付、兼容性边界，以及暂不实现的无侵入录屏计划。
7. [开发者指南](Development.md)
   - Xcode/SwiftPM 构建、测试、代码边界、本地化、真实设备验收和常见问题。
8. [发布与公证指南](Release.md)
   - 版本准备、ad-hoc 验收、Developer ID、公证、GitHub Release 和第三方组件更新。
9. [隐私与数据处理](Privacy.md)
   - 本地会话目录、日志/媒体范围、脱敏预览、权限和删除方式。
10. [第三方组件声明](Third-Party-Notices.md)
    - 内置 ADB、iOS 工具及其许可证、版本、来源和更新义务。
11. [开源贡献指南](../CONTRIBUTING.md)
    - 开发环境、测试、分支、PR 检查清单和数据安全要求。
12. [安全策略](../SECURITY.md) / [支持](../SUPPORT.md) / [变更记录](../CHANGELOG.md)
    - 漏洞私下报告、问题反馈和版本变更说明。

## 已确认决策

- 产品工作名称为 GameLog。
- 使用原生 macOS 桌面应用形态。
- 首版目标系统为 macOS 26 及以上。
- 主界面采用 Sidebar + Log Table + Inspector。
- 日志主场景使用 `WindowGroup`，允许多个设备/目标窗口并行采集。
- 会话归档使用独立单例窗口，承载会话、趋势、对比、符号化、导入和注释。
- SwiftUI 负责窗口、系统 Toolbar、Sidebar、Search、Inspector 和 Settings。
- 中央高速日志表通过 `NSViewRepresentable` 包装 `NSTableView`。
- Liquid Glass 只用于系统导航和控制层。
- 截图和录屏以固定高度证据标记进入日志时间线。
- 标记问题直接进入时间线并在 Inspector 内联编辑，不使用打断式编辑弹窗。
- 问题包只包含附近日志和关联证据，导出前提供本地脱敏预览。
- 自动诊断仅聚合目标 App 的 Java/Native Crash 与 ANR。
- 媒体只在 Inspector 按需加载，不嵌入高频日志行。
- 日志默认保留最近 50,000 条内存事件。
- 录屏由用户手动开始和停止；Android 原生单段达到 180 秒时后台续录，停止后合并为一个无音频视频。
- 录屏空间护栏只告警，不替用户自动停止。
- 每个日志窗口采集一个设备和目标；P1 支持创建多个并行窗口。
- 数据默认仅保存在本机，不提供账号或云同步。
- P1 项目级脱敏规则和会话注释均只保存在本机；注释随完整导出文件共享。
- P2 会话导入、SHA-256 协作清单、NDK 符号化、时间轴对齐和回归基线均在本机完成。
- 云端归档、实时团队评论和问题单系统不属于 1.2，后续启用前需单独确定服务与数据策略。
- 首版优先采用 Developer ID 签名、公证后直接分发。
- `1.2.2` 起内置 Universal ADB，普通用户安装 GameLog 后无需另配 Android SDK；外部 ADB 仅作为高级覆盖与故障恢复。
- iOS 真机当前只交付日志与即时截图；无侵入录屏显示为“计划中”，不进入当前实现。
- iOS 工具随 App 内置，当前受管二进制仅支持 Apple Silicon；Intel 兼容构建属于后续交付项。

## 当前阶段

P0、P1 与 P2 已完成，`1.2.2` 已完成内置 ADB、外部覆盖、嵌套签名和发行完整性预检；当前基线同时包含 iOS 真机日志与用户触发截图。下一阶段仍包含 Developer ID/公证、30 分钟多窗口 soak、Android/iOS 物理 USB 拔插与辅助功能复核。

仓库已按开源协作整理贡献、行为准则、安全、支持、隐私和发布文档；从根目录的 [README](../README.md) 或 [英文 README](../README.en.md) 开始即可。
