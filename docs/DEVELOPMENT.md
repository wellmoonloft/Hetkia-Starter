# 时光 · Hetkia 开发文档

版本：1.0（现状汇总）
整理日期：2026-10-23
目标读者：后续维护该 Xcode 工程的开发者。
产品范围和优先级以 [`PRODUCT_REQUIREMENTS.md`](PRODUCT_REQUIREMENTS.md) 为准。

## 1. 工程概况

- 工程：`Hetkia.xcodeproj`
- Scheme：`Hetkia`
- App target：`Hetkia`
- 技术栈：Swift、SwiftUI、SwiftData、PhotoKit/PhotosUI、CoreGraphics、Foundation Models。
- Bundle ID 当前占位：`com.hetkia.app`；签名/上架前需换成开发者控制的反向域名 ID。
- iOS/iPadOS Deployment Target：27.0。
- macOS Deployment Target：14.0。
- 支持平台：`iphoneos`、`iphonesimulator`、`macosx`；不使用 Mac Catalyst。
- Swift 语言版本设置为 Swift 5。
- iPhone Info.plist 仅声明竖屏；iPad Info.plist 声明全部方向以满足 iPadOS 27 检查，`HetkiaApplicationDelegate` 为 app 请求竖屏。Xcode 生成静态 Launch Screen 配置；macOS 页面采用纵向滚动结构。

## 2. 目录结构

```text
Hetkia-Starter/
├── Hetkia.xcodeproj/                 # Xcode 工程与构建设置
├── Hetkia/
│   ├── App/                          # App 入口、SwiftData 容器、语言选择
│   ├── Features/
│   │   ├── Onboarding/               # 首次启动、30日索引与历史索引选择
│   │   ├── Timeline/                 # SwiftData 时间轴、年/月/全部、照片墙
│   │   ├── Journal/                  # 持久化手札、详情、页面排版与模型
│   │   ├── Photos/                   # 用户选图导入、PhotoKit 解析及预览回退
│   │   ├── Search/                   # 搜索界面
│   │   └── Settings/                 # 权限、每日时间、存储与 AI 状态
│   ├── Assets.xcassets/              # App 图标和资源
│   ├── Resources/                    # String Catalog
│   ├── en.lproj/                     # 英文应用名称与权限说明
│   ├── zh-Hans.lproj/                # 简体中文应用名称与权限说明
│   ├── zh-Hant.lproj/                # 繁体中文应用名称与权限说明
│   ├── es.lproj/                     # 西班牙语应用名称与权限说明
│   └── th.lproj/                     # 泰语应用名称与权限说明
├── Design/                           # 设计源稿
├── Tests/                            # 当前可运行的状态流 smoke test 源码
├── Scripts/                          # 本地验证脚本
├── docs/                             # 产品需求与开发文档
└── README.md                         # 环境、构建和当前状态摘要
```

目录实际文件可能随迭代扩展；新增 Swift 文件时应在 Xcode 工程中登记。当前 `.pbxproj` 使用显式文件引用。

## 3. 主要组件

### App 与本地化

- `Hetkia/App/HetkiaApp.swift`
  - 创建 SwiftData ModelContainer，注册 `JournalRecord`、`JournalPhotoRecord`、`JournalGenerationTask`。
  - 根据 onboarding 完成状态选择引导页或时间轴。
  - 启动/恢复时把持久化队列中残留的 `processing` 任务恢复为 `pending`，修复旧日期键后运行前台 catch-up。
  - `HetkiaSystemLanguage` 将系统首选语言映射到五种支持语言，其余默认 `en`。
- `Hetkia/Resources/Localizable.xcstrings`：界面 String Catalog。
- 各 `*.lproj/InfoPlist.strings`：应用显示名及系统权限弹窗本地化。

### 首次启动

- `Hetkia/Features/Onboarding/OnboardingFlowView.swift`：欢迎、照片授权后自动前进、最近 30 日无 AI 元数据归档进度、历史整理选择及自动进入首页。旧静态批量补录状态页保留源码以兼容旧状态，但已从引导路由移除。
- `Hetkia/Features/Onboarding/OnboardingFlowModel.swift`：UserDefaults 序列化快照，键名 `hetkia.onboarding.flow.v1`；旧今日/批量补录模拟状态模型仍留存，不再驱动当前引导。
- 引导不再展示每日目标时间页；设置页使用 `hetkia.dailyGenerationMinute`，默认凌晨 4:30。
- `OnboardingFlowView` 的照片权限由 `PhotoLibraryService` 在用户点按钮时实际请求。
- 最近 30 日由 `JournalAutomationCoordinator.indexRecentJournals` 建立照片日记，跳过 AI 生成并逐批保存进度；完成后自动进入历史整理选择页。
- 历史整理选择默认启用；用户确认后，`startHistoricalLibraryIndex` 枚举 PhotoKit 元数据、逐日幂等保存 30 日之前的照片日记，并申请有限时长的 UIKit 后台执行机会；中断后下次前台启动/恢复续做。它不是系统保证运行的 `BGTaskScheduler`。
- 旧 `beginBackfillScan()` 仍是模拟方法，但不再能从引导界面进入。

### 照片导入与回退

- `Hetkia/Features/Photos/PhotoImportView.swift`：照片选择器确认选择后自动导入并启动队列处理、导入状态、未注明日期的手动归组及已有日记列表。
- `Hetkia/Features/Photos/PhotoLibraryService.swift`：请求 PhotoKit read/write 授权；导入自定义筛选器交付的 `PHAsset`，读取可用 PHAsset/EXIF 元数据，按日期创建或更新日记，防止重复资产，生成压缩 JPEG 预览并持久化。导入校验会剔除隐藏、最近删除/不可再取回、截图、荧幕录影及无法验证的资源。
- `Hetkia/Features/Photos/PhotoAssetResolver.swift`：按 PhotoKit 原件、应用 JPEG、占位图顺序解析预览。
- 每日/“历史上的今天”AI 自动化仅在 `.authorized` 或 `.limited` 状态下按单日范围查询今天及往年同月同日。首次启动的 30 日索引和用户同意后的全历史索引会遍历可访问资产的元数据，但不读取图像内容、不调用 AI、不批量生成 JPEG。所有路径排除隐藏、删除/不可访问、截图、荧幕录影和非图片媒体。照片 GPS 使用 PHAsset/EXIF 元数据，不代表已实现 Core Location 当前位置服务。
- 当前导入图像压缩参数：最长边 1200 px，JPEG quality 0.78。路径在应用私有缩略图目录内，以相对路径持久化。

### 持久化模型与手札

- `Hetkia/Features/Journal/JournalModels.swift`
  - `JournalRecord`：来源为 `automatic` / `manual`；`storageKey` 保留原唯一列并使用 `日期|来源`，保证同日每种来源最多一篇。启动时将旧日期键升级为 `日期|manual`；`dayKey` 是从存储键解析的日期。
  - `JournalPhotoRecord`：PhotoKit ID、日期、GPS、媒体尺寸/方向、压缩预览相对路径、元数据/原件状态及排序。
  - `JournalGenerationTask`：按具体完整日期关联任务，类型含每日自动、历史上的今天和手动；保存状态、尝试次数及错误信息。
- `Hetkia/Features/Journal/JournalAutomationCoordinator.swift`：维护最近 30 天索引、可选全历史元数据索引，以及每日/“历史上的今天”前台 AI catch-up。元数据索引按日幂等保存、持久化进度；iOS 请求有限时长 UIKit 后台执行机会，恢复时继续。文字队列每次 catch-up 最多串行处理一项任务，失败可重试。未注册 `BGTaskScheduler`。
- `Hetkia/Features/Journal/PersistentJournalViews.swift`：真实 SwiftData 手札详情、固定页面、照片选择、内嵌留言编辑/追加、手动 AI 生成和模型状态。
- 同文件的 `PhotoLocationResolver`：按实际 GPS 距离将照片加入代表坐标 5 公里半径的查询组；每组只提交一次 MapKit 反向地理编码请求，失败时回退 Core Location。结果按代表坐标缓存并写回照片记录；队列串行执行，详情页关闭不主动取消。启动/激活时扫描已选手札照片并恢复未解析地点。失败时记录错误并保留照片 GPS 地图入口，后续激活时可重试。
- `JournalRecord.messagePostsData` 保存留言流；`JournalMessagePost` 保存文字、类型与创建时间。首次打开旧记录时，将原正文迁移为一条留言并保留记录更新时间；新生成内容和用户追加留言均写入独立时间戳。
- 留言输入位于详情页纵向滚动内容中，编辑时就地显示 `TextEditor`；键盘使用交互式滑动收起，焦点变化会滚动到当前编辑区域。
- `JournalPhotoSelection.selected(from:)` 是共用的选图入口，按 `sortOrder` 及 1/3/5/7/9 张规则为生成、详情和主时间轴缩略图提供同一组照片。
- 详情页照片可点开放大的全屏分页浏览；1 张铺满、3 张为主图加双辅图、5 张为主图加 2×2、7 张为主图加 3×2、9 张为 3×3。
- 页面正文/留言使用 `ScaledMetric` 随系统动态字体放大；页面高度从 3:4 基准按内容增长，避免大字体下截断。
- 详情打开或应用启动/激活时，用照片 GPS 坐标异步反向地理编码。5 公里内照片共用一次代表坐标查询和城市名称；距离用 `CLLocation.distance(from:)` 计算，不按经纬度网格划分。成功结果保存在本地缓存，后续复用最近且不超过 5 公里的缓存项；点击地点仍以代表照片的精确纬度/经度显示地图。MapKit 无结果/失败时回退 `CLGeocoder`，不读取设备当前位置。
- 手札分享时用与详情相同的照片选择和布局组件渲染 3:4 日记图片，交给原生系统分享流程；合成图只在操作时创建。
- `Hetkia/Features/Journal/JournalPageComponents.swift`：统一暖色调调色板、页面与网格组件；部分早期样例组件仍保留，主应用持久化时间轴路由到 `PersistentJournalDetailView`。
- 当前持久化详情页已支持 1/3/5/7/9 张目标布局、全屏照片翻页、系统动态字体和基于照片坐标的地点名称解析。

### AI

- `Hetkia/Features/AI/JournalDraftService.swift`
  - 用 `SystemLanguageModel.default.availability` 检查设备端模型状态。
  - 生成文字时提供日期、选用照片数量、可用图像和反向地理编码位置上下文；提示词要求基于可见证据、可结合位置回忆活动但不得臆测人物关系/事件/餐食，也不在正文重复日期或写时间。
  - iOS/macOS 27 及以上在可用时附带图片；不支持图片输入时改用不描述画面的纯文本草稿。
  - 当前没有调用模型的 `supportsLocale`/语言能力检查；生成语言按系统语言指定，五种语言的模型输出质量仍待实机验证。
  - 不调用第三方 AI 服务，不上传照片。
- `PersistentJournalViews.generateDraft()`：读取当前选中照片的图像样本，调用服务并写入 `aiDraftBody`；保留已编辑正文。

### 时间轴、搜索与设置

- `Hetkia/Features/Timeline/TimelineHomeView.swift`：SwiftData 查询驱动的主界面、年份/月份/全部筛选、“历史上的今天”区块、手动创建今日手札、空状态、导航、搜索和设置入口；首页标题栏只保留新建日记。
- `Hetkia/Features/Timeline/TimelineComponents.swift`：时间轴卡片、状态卡片和底部栏。
- `Hetkia/Features/Timeline/YearOverviewView.swift`、`MonthCalendarView.swift`：年/月组件；部分组件仍属独立视图，具体路由以 `TimelineHomeView` 为准。`PhotoWallView.swift` 仍在工程中，但当前没有主流程入口，不应计作可达功能。
- 首页“历史上的今天”和正式时间轴统一使用照片、日期/照片数量两行日记卡片，每篇只显示一张代表照片；仅正式时间轴使用年月分组标题。
- iOS/iPadOS 底栏用滚动几何状态控制：长内容滚动时显示、顶部/末尾隐藏；短年/月内容无法滚动时直接显示；macOS 常驻。滚动检测不通过覆盖卡片区域的手势识别器实现，以免影响导航点按。
- 时间轴在首次出现、批量索引写入通知、从详情返回、设置/照片页关闭以及应用重新激活时重新 fetch SwiftData 记录，确保新日记及时显示。
- `Hetkia/Features/Timeline/TimelineHomeView.swift` 中持久化搜索按文字或记录/照片元数据过滤；不做图像内容识别。照片墙/列表切换不在首页标题栏。
- `Hetkia/Features/Settings/SettingsView.swift`：照片图库入口、每日时间、本地/iCloud 选项、Foundation Models 状态和当前系统语言。
- 设置页把“每日手札”目标时间与独立“照片生成”面板分开；后者提供选择照片导入与全部照片元数据索引，显示持久化进度、完成或暂停状态。重新进入时刷新状态，并在前台恢复时续做尚未完成索引。
- `Hetkia/Features/Photos/FilteredPhotoPicker.swift` 排除隐藏、已删除/不可访问、截图和荧幕录影；选择已完成日记日期的照片也会被排除。导入和历史扫描遵循相同的媒体资格筛选。
- 设置页仍存在 Core Location 授权请求，但手札地点只由照片 EXIF/PhotoKit GPS 反向地理编码，不读取当前位置；此权限入口不参与当前地点功能，属于遗留入口。
- 分享按钮按现有手札版式即时渲染 3:4 图片并交给系统分享面板；不保存长期合成副本。每个 5 公里查询组使用代表照片的原始坐标打开地图。
- iCloud 选项不可用，目前没有 CloudKit/iCloud 同步实现。

## 4. 技术决策记录（合并自旧技术决策文档）

- **D-001 原生优先**：使用 SwiftUI 与 Apple 框架；v1 不引入跨平台 UI 框架。
- **D-002 PhotoKit 标识 + 压缩预览**：保留 `PHAsset.localIdentifier` 和应用拥有的 JPEG 预览，显示顺序为原件、JPEG、占位图。PhotoKit 标识是图库/设备范围标识，跨设备映射留待以后设计。
- **D-003 本地优先持久化**：日记记录使用 SwiftData；压缩文件放在应用管理目录，数据库仅保留相对路径或应用管理标识。删除记录时必须协调清理文件。
- **D-004 设备端 AI 优先**：只在 Foundation Models 可用且适合当前任务时使用；实现 no-model 状态，不假定设备、系统或语言能力一致。
- **D-005 后台尽力而为**：系统可延迟或跳过后台任务；每日目标时间不是保证。设计需包括下次启动补偿和手动生成/重试。
- **D-006 单一模板、五种照片布局**：只支持 1/3/5/7/9 张版式，其他页面区域固定。
- **D-007 导出按需合成**：用户预览、分享或导出时才合成 3:4 手札图片，默认不永久保存成品图片。

## 5. 阶段计划（合并自旧构建计划文档）

以下保留原计划的阶段意图，并以本文“当前完成情况与待办”作为现状判断；阶段列出不表示功能已经完成。

| 阶段 | 目标 | 当前状态 |
| --- | --- | --- |
| 0：可构建骨架 | 原生 SwiftUI 工程、名称与 Bundle ID 占位、部署目标、图标资源、可构建启动 | 已完成；Bundle ID 仍是占位值 |
| 1：日记模板 | 纵向手札、1/3/5/7/9 布局、动态字体，并验证不同尺寸 | 目标布局与动态字体已接通；真机尺寸和大字体视觉验证待做 |
| 2：持久化 | SwiftData 日记/照片数据、压缩文件管理与清理、显示回退 | 主数据和显示路径、日记/关联任务删除及缩略图清理已实现；重复引用与孤儿文件策略仍需验证 |
| 3：照片集成 | 权限说明、照片访问、有限/撤销授权处理、压缩预览生成 | 用户选择式导入、最近 30 天索引和用户同意后的全历史元数据索引已实现；扫描不生成 AI 文字或批量预览 |
| 4：草稿生成 | 模型可用性、证据约束、可编辑草稿、手动生成与降级 | 引导与首页前台 catch-up、单条队列、失败状态已接通；设备端生成验证仍待完成 |
| 5：后台与导出 | 后台机会、启动 catch-up、按需渲染及系统分享 | UIKit 有限时长后台执行机会、前台续做和 3:4 图片系统分享已实现；尚未注册 BGTaskScheduler，运行持续性/目标时间不保证 |
| 6：QA | 覆盖资源缺失、权限、空照片日、重复导入、AI 失败、后台延迟与导出 | 部分状态流 smoke test 存在；完整 XCTest/设备验证待做 |

## 6. 数据与处理规则

### 日记分组

- 导入照片使用拍摄日期转换为设备本地 `yyyy-MM-dd` day key。
- `JournalRecord.storageKey` 唯一，按 `dayKey|source` 编码；同一天可有一篇自动与一篇手动记录。旧版日期键在启动时规范化为手动来源。
- `localDay` 保存导入日的代表日期；代码注释明确 day key 不随未来时区变化重算。
- 没有拍摄日期的照片先保存为未归组，再由用户选日期建立关联。

### 选图规则

共享选图逻辑按 `sortOrder` 排序：照片数大于 9 取 9；否则偶数减 1、奇数保持。主时间轴卡片、详情版式和传给 AI 的样本集合共用该结果，避免首页展示未入选照片。

### 任务恢复

- App 启动/恢复时将持久化中断的 `processing` 生成任务改为 `pending`，保留中断说明供 UI 显示。
- onboarding 模型在恢复时将模拟的处理中状态重置/暂停并持久化。
- 尚未注册 `BGTaskScheduler`；任务退避/取消、旧版 SwiftData 数据库升级验证和队列端到端测试仍待完成。全历史元数据索引已通过 UIKit 有限时长后台执行机会尽力续跑。


## 6A. 新确认的日记自动化规则：每日生成 + 历史上的今天

本节记录产品方最新确认的目标行为及当前实现进度。前台 catch-up、PhotoKit 单日查询、首页区块、来源区分和持久化队列已接通；最近 30 天与用户同意后的全历史元数据索引亦已实现。`BGTaskScheduler`、旧库升级运行验证和设备端 Foundation Models 验证仍待完成。

### 6A.1 当前代码与目标行为的差距

- `JournalRecord.storageKey` 通过 `@Attribute(.unique, originalName: "dayKey")` 保留既有唯一列；自动/手动来源编码进存储键。旧键会在启动时规范化为手动来源。真实旧库迁移还未运行验证。
- `JournalGenerationTask` 已区分 `dailyAutomatic`、`onThisDayBackfill`、`manual`；启动后残留 `processing` 恢复为 `pending`。
- 引导先整理最近 30 个日历日；用户默认同意并确认后，再以可恢复任务整理其余可访问历史照片的元数据。此全历史索引只建照片日记、不生成文字；受限 PhotoKit 授权只返回用户允许访问的资源。
- onboarding 最近 30 日归档与首页使用同一 SwiftData 数据；旧批量补录演示页不能从引导路由进入。首页 catch-up 每次最多执行一项待处理 AI 任务。
- 每日目标时间仍只保存偏好；历史索引使用 UIKit 有限时长后台执行机会，尚未注册系统 `BGTaskScheduler`。

### 6A.2 每日自动生成目标流程

1. 在 App 启动/恢复时，按设备本地日历计算今天的 `dayKey`，执行幂等检查。
2. 若今天已有任何 `JournalRecord`（无论来源为自动或手动），跳过自动创建。
3. 若今天没有日记，查询今天可用的照片；有照片时排入自动生成任务，无照片时不生成。
4. AI 生成失败或模型不可用时，保存可重试状态并保留照片/元数据；不调用远程 AI。
5. 任务开始和保存结果前都要重新查询当天是否已有日记，防止用户手动创建与自动任务并发时重复。
6. 用户始终可以手动创建当天的日记，即使当天已有自动日记；因此数据模型必须允许同一天最多一篇自动日记和一篇手动日记，而不是简单禁止同一天存在多条记录。
7. 但每日自动任务的规则是：当天只要已有任意一篇日记，就不再自动创建日记。
8. 自动生成内容被用户编辑后仍保留自动来源，并标记为已编辑；自动任务绝不覆盖正文。

### 6A.3 「历史上的今天」目标流程

- 在首页顶部增加「历史上的今天」区域；主时间轴继续展示近期日记。
- 启动/恢复时，查找今天相同月日的过去年份照片。每个具体历史日期独立处理，例如 `2021-10-22` 与 `2025-10-22` 是不同目标。
- 对每个过去日期：
  - 已有自动或手动日记：展示已有日记，不重新生成。
  - 没有日记但有照片：加入该历史日期的独立生成任务。
  - 没有照片：跳过。
  - AI 不可用或生成失败：仍展示可用照片，并保留待重试/失败状态。
- 不需要用户逐篇点击才处理，但生成队列要小批次串行或有限并发，不阻塞首页，也不能在扫描全库时对所有照片调用 AI。
- 不在首次启动时默认对过去所有日期批量生成 AI 文字；用户明确同意后可索引全部可访问历史照片的元数据（见 §4.2）。每日/周年 AI 草稿仍按日历在前台逐步补齐，用户也可手动创建其他日期。
- 2 月 29 日只在闰年存在；非闰年不生成对应历史日期，不得自动映射到其他日期。

### 6A.4 数据模型、唯一性与任务状态

- `JournalRecord.storageKey` 已按“完整日期 + 来源”设置唯一值，解决同日一篇自动 + 一篇手动的冲突；启动时把旧的日期键规范化为手动来源。仍需用旧版真实 store 验证 SwiftData rename migration。
- 建议明确分离：
  - `source`: `automatic` / `manual`
  - `isUserEdited` 或现有等价编辑标记
  - 具体本地日期 `dayKey`
  - 生成任务的类型/目标日期（每日自动或历史回顾）
- 同一天允许一篇自动和一篇手动记录；同一天不允许两篇自动记录。若产品后来允许多篇手动日记，应保持其与自动任务的去重逻辑独立。
- 任务启动前与保存前都检查是否已有记录；建议为“自动来源 + 具体日期”建立可验证的唯一性保障，并测试并发/重启情况。
- 复用 `JournalGenerationTask`，必要时增加任务类型（例如 `dailyAutomatic`、`onThisDayBackfill`）和可恢复状态；避免另建重复任务系统。
- 状态至少覆盖待处理、处理中、已完成、失败、已跳过、已取消；重启后将残留 `processing` 恢复成可重试状态，而不是永久卡住。
- 自动生成成功后，任务必须与正确年份/日期的 `JournalRecord` 关联；不能仅用月日作为任务唯一键。

### 6A.5 首页与交互

- 首页顶部新增「历史上的今天」区块，展示过去年份的照片、年份标签、已有日记或生成状态。
- 页面应先显示已取得的照片和已有记录，不等待全部历史日记生成完毕。
- 生成中、待生成、失败、已完成状态应清楚但视觉克制。
- 用户可打开某年某日的日记、手动创建日记、编辑自动日记或对失败任务重试。
- 需要保持现有年/月/全部浏览、搜索、照片墙和详情路由正常工作。
- 新增的用户可见文案必须进入 String Catalog，并维护五种目标语言。

### 6A.6 实现顺序建议

1. 已检查并改造模型；需在包含旧数据的安装上验证 `originalName` 迁移和日期键规范化。
2. 已实现同日来源唯一键、日期查询、2 月 29 日精确日期校验和启动恢复。
3. 已实现当日/“历史上的今天”前台 catch-up、首页入口、串行待办与手动重试。
4. 后续实现 BackgroundTasks 最佳努力调度，并处理每日时间偏好的目标窗口。
5. 建立 SwiftData/日期规则可执行测试；在真机验证 PhotoKit 有限访问、Foundation Models 可用性及图片输入。
6. 报告中分别标注代码、构建、模拟器和真机验证状态。

## 7. 隐私权限与系统能力

### Photos

- `NSPhotoLibraryUsageDescription` 已配置并提供五种本地化文案。
- 引导页与照片导入/设置中由用户触发请求或打开系统照片选择器。
- 处理 `.authorized`、`.limited`、`.denied`、`.restricted` 和 `.notDetermined` 状态。
- 对 PhotosPicker 选出的单项内容可以进行用户选择式导入；PhotoKit 原件回读依赖授权状态及资产可用性。

### Location

- 从照片中读取 GPS 元数据不需要 Core Location 授权。
- 不申请 Always 定位，不在首次启动请求定位。
- 产品若将来新增“用当前位置补充附近地点”，必须先实现可见、真实的功能，再在该功能入口申请 When In Use，并解释用途。系统位置用来添加地点不是现有已完成能力。
- 当前工程仍含 `NSLocationWhenInUseUsageDescription`、macOS `NSLocationUsageDescription` 与设置授权入口；属于待清理的遗留配置。

### Apple Intelligence / Foundation Models

- 无单独的 Hetkia 隐私权限弹窗，不新增类似 Photos/Location 的权限键。
- 系统设置中的 Apple Intelligence 开关、设备/区域资格、模型下载/就绪和语言能力属于可用性条件。用模型前查询 availability 并给出说明或降级路径。
- 不可用时允许手动编辑；不应伪装成权限拒绝，也不得静默改用云端模型。

## 8. 本地化与界面约束

- 所有用户可见字符串加入 String Catalog，并维护五个目标语言的翻译。
- 系统权限原因文案另维护在对应 `.lproj/InfoPlist.strings`。
- 界面颜色使用 `HetkiaPalette` 的象牙纸色、深暖灰和柔和琥珀色。
- 页面内容设置合理最大宽度并按设备可用宽度适配；避免固定宽度导致横向溢出。
- iOS、iPadOS、macOS 的内容均以纵向阅读优先，不实现横向分页浏览。

## 9. 构建与运行

要求 Xcode 27（含 iOS 27 SDK）或更新版本。打开工程后选择 `Hetkia` scheme。iOS/iPadOS 需选择 iOS Simulator 或 iOS 设备；macOS 选 macOS destination。设备签名开发时按需要配置 Team；命令行无签名构建可用 `CODE_SIGNING_ALLOWED=NO`。

### iOS/iPadOS Simulator 构建

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### macOS 构建

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -sdk macosx -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

### onboarding 状态流 smoke test

```sh
./Scripts/run-onboarding-smoke-tests.sh
```

此脚本验证 onboarding 状态模型中的持久化、队列暂停/继续及重试等路径，不覆盖 SwiftData、真实 PhotoKit 导入、权限弹窗、Foundation Models 生成或真实后台行为。项目尚未配置 XCTest target。应先确认脚本存在且可执行，再运行。

### 验证报告约定

- 先读取当前 Xcode 和 simulator runtime 状态；编译与模拟器运行是不同验证结果。
- 仅在实际命令返回成功后报告构建通过。
- 本轮地点聚类及队列恢复改动完成后，Xcode 27.1 macOS Debug 构建实际成功（`xcodebuild ... -destination 'generic/platform=macOS' ... build`，退出码 0），`git diff --check` 通过。iOS Simulator 构建此前通过，本轮未重跑；模拟器启动、权限弹窗、地图查询结果和 Foundation Models 真机行为不由本轮 macOS 构建覆盖。
- Apple Intelligence 必须在支持该功能的实际设备/系统上验证；普通编译不代表模型可用或文本质量通过验收。

## 10. 当前完成情况与待办

### 已实现

- 原生多平台 SwiftUI 工程、应用图标资源及五种语言。
- iPhone/iPad 竖屏设置和 macOS 纵向布局。
- SwiftData 日记、照片和生成任务模型。
- 用户主动挑选照片、元数据读取、日级分组、未注明日期照片手动归组、压缩 JPEG 预览及原图/预览/占位回退。
- 真实 SwiftData 时间轴、年/月/全部浏览入口、文字/元数据搜索和持久化手札详情；照片墙视图代码存在但当前未从主流程开放。
- 首页历史回顾与正式时间轴统一采用单张照片加日期/数量两行卡片；首页标题栏只保留新建日记，正式时间轴按年月分段。短内容的 iOS/iPadOS 年/月视图中底栏可直接显示；返回首页、批量索引变化和应用重新激活时刷新记录。
- 内嵌留言流：生成文字带生成时间，用户可就地编辑或追加带时间的新留言；旧正文在打开详情时迁移到留言流。
- 详情页右上角提供删除日记操作，删除数据库记录及关联生成任务并尝试清理缩略图文件；原件仍由 Photos 管理。
- 仍保留独立 AI 草稿、模型状态显示和手动生成入口。
- 每日目标时间、本地/iCloud 状态展示、照片和 AI 状态设置。
- 独立照片生成面板，提供选择照片与全部照片元数据索引；进度/状态持久化，离开设置页不主动取消任务，应用启动或激活时续做。
- 照片地点异步反向地理编码：5 公里内照片共用代表坐标的一次城市查询并复用成功缓存；MapKit 查询失败回退 Core Location，失败仍保留照片精确 GPS 地图入口。
- 本地化系统语言选择与系统权限说明。

### 尚未实现或需修正

1. 旧日期范围批量补录的演示视图/模型仍在代码中；引导路由已移除，需决定是否删除这段未使用代码。
2. 为每次 App 激活补足超过一项的历史任务处理策略；当前每次 catch-up 最多处理一项，未完成项留到下一次前台机会。
3. 评估为历史照片整理及每日目标时间注册 `BGTaskScheduler` 最佳努力调度；目前只有 UIKit 有限时长后台执行机会与前台续做，系统不保证准点执行或不中断。
4. 验证真实旧 SwiftData store 的 schema rename 和启动键规范化，确保用户现有日记与照片关系完整。
5. 设置页定位授权行及 Info.plist 定位声明不参与照片 GPS 反向地理编码，属于遗留项；后续应移除，或等真实当前位置功能实现后再使用。
6. 更新 `settings.permission.note` 的五种语言过期文案。
7. iCloud 同步尚未实现；界面继续标记不可用，不能将本地 SwiftData 误称为已同步。
8. 删除日记时已删除数据库记录及关联生成任务，并尝试移除 JPEG 预览；仍需验证重复引用文件、删除失败回滚、临时文件及孤儿文件清理生命周期。
9. 测试有限照片权限、撤销权限、iCloud-only 原件、原件删除、缺失预览、缺失拍摄日期、重复导入、空日、模型不可用/错误等情况。
10. 在支持 Apple Intelligence 的实机验证图像输入、语言质量、模型不可用/下载中状态与实际生成结果。
11. 增加正规 XCTest target，并为照片数规则、日期分组、文件回退、SwiftData 生命周期和多语言覆盖添加自动化测试。
12. 确认并修正旧样例视图/搜索组件是否仍需要保留，避免被接回主用户流程。
13. 在用户同意产品功能后再开发真正的图像语义搜索或 OCR；当前均未实现。
14. 在真机验证 5/7 张主图加辅图的视觉比例、全屏照片翻页、大字体排版、5 公里位置合并/跨城市地点及首页底栏/刷新行为。
15. 持续检查手札分享图在不同照片数量、长文本与系统分享目标下的版式和兼容性；3:4 合成及系统分享入口已实现。

## 11. 迭代建议

1. **验证并稳固自动流程**：测试已有 SwiftData 数据升级、PhotoKit 有限授权和同日双来源唯一性。
2. **完善调度闭环**：评估 `BGTaskScheduler` 最佳努力调度和目标时间窗口，保留现有 UIKit 有限时长执行、前台补偿与用户手动重试。
3. **完善数据可靠性**：导入与删除生命周期、权限撤销、原件缺失和持久化队列恢复。
4. **验证体验**：建立 XCTest target，覆盖布局/语言/照片状态，并在 iPhone、iPad、Mac 真机或模拟器检查版面。
5. **再评估扩展项**：仅在需求确认后加入 iCloud、当前位置标签、OCR 或语义照片搜索。

## 12. 工程规范（合并自项目指引）

- 保持工程小而可构建，优先使用 SwiftUI、PhotoKit、SwiftData 等 Apple 原生框架；避免过度架构和没有明确需求的依赖。
- UI、照片读取、持久化、AI 生成和导出职责放在聚焦的类型中，避免相互耦合。
- 压缩预览路径使用应用管理目录下的相对路径或受管理标识，不把绝对沙盒路径作为持久化数据；明确记录删除/编辑时数据库记录与图片文件的生命周期。
- 在适当时为照片回退选择、版式选择和持久化行为补充测试；覆盖能力有限时明确写出未覆盖范围。
- 只有实际运行了构建或测试，才报告通过；构建成功不等于模拟器界面、真机权限、AI 输出质量或后台调度已验证。
- 开始较大范围重构前，先向用户说明简短的改动计划。除非用户明确要求，不加入分析追踪、广告、账号系统或社交功能。
