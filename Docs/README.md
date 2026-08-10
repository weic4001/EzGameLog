# GameLog 文档索引

> 当前基线：方案 1（Sidebar + 高密度日志表格 + Inspector）  
> 平台：macOS 26 及以上  
> 更新日期：2026-07-30

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

## 当前阶段

P0、P1 与 P2 已完成，`1.2.2` 已完成内置 ADB、外部覆盖、嵌套签名和发行完整性预检。下一阶段是发行资格验证：Developer ID/公证、30 分钟多窗口 soak、无线 ADB 真机配对矩阵、物理 USB 拔插与辅助功能复核。
