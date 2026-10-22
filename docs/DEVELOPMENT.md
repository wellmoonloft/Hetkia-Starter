# 时光 · Hetkia 开发文档

版本：1.0（现状汇总）  
整理日期：2026-10-22  
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
- iPhone/iPad 的 Info.plist 设置为仅竖屏，iPad 全屏运行。macOS 页面采用纵向滚动结构。

## 2. 目录结构

```text
Hetkia-Starter/
├── Hetkia.xcodeproj/                 # Xcode 工程与构建设置
├── Hetkia/
│   ├── App/                          # App 入口、SwiftData 容器、语言选择
│   ├── Features/
│   │   ├── Onboarding/               # 首次启动与补录原型状态流
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
  - 启动时将持久化队列中残留的 `processing` 任务改成失败状态。
  - `HetkiaSystemLanguage` 将系统首选语言映射到五种支持语言，其余默认 `en`。
- `Hetkia/Resources/Localizable.xcstrings`：界面 String Catalog。
- 各 `*.lproj/InfoPlist.strings`：应用显示名及系统权限弹窗本地化。

### 首次启动

- `Hetkia/Features/Onboarding/OnboardingFlowView.swift`：欢迎、照片授权、每日时间、今日状态、历史邀请，以及补录范围/确认/队列/完成页。
- `Hetkia/Features/Onboarding/OnboardingFlowModel.swift`：UserDefaults 序列化快照，键名 `hetkia.onboarding.flow.v1`；当前今日处理与补录队列是模拟状态流。
- 引导页目标时间保存在该快照中；设置页另用 `@AppStorage("hetkia.dailyGenerationMinute")`。两处未共享同一个设置值，引导页选择的时间不会自动同步到设置页，需统一存储。
- `OnboardingFlowView` 的照片权限由 `PhotoLibraryService` 在用户点按钮时实际请求。
- 注意：历史邀请页面当前只有跳过入口。`beginBackfillScan()` 使用静态日期组和延迟进度；这不是 PhotoKit 历史扫描，也不是真实生成队列。模型中虽有生成演示方法，但不应将未连通流程描述为实际生成。

### 照片导入与回退

- `Hetkia/Features/Photos/PhotoImportView.swift`：照片选择器、导入状态、未注明日期的手动归组及已有日记列表。
- `Hetkia/Features/Photos/PhotoLibraryService.swift`：请求 PhotoKit read/write 授权；导入所选 `PhotosPickerItem`，读取可用 PHAsset/EXIF 元数据，按日期创建或更新日记，防止重复资产，生成压缩 JPEG 预览并持久化。
- `Hetkia/Features/Photos/PhotoAssetResolver.swift`：按 PhotoKit 原件、应用 JPEG、占位图顺序解析预览。
- 不遍历全图库；照片 GPS 使用 PHAsset/EXIF 元数据，不代表已实现 Core Location 当前位置服务。
- 当前导入图像压缩参数：最长边 1200 px，JPEG quality 0.78。路径在应用私有缩略图目录内，以相对路径持久化。

### 持久化模型与手札

- `Hetkia/Features/Journal/JournalModels.swift`
  - `JournalRecord`：按 `dayKey` 唯一识别日记；含标题、正文、独立 AI 草稿、编辑标记、地点、心情、生成状态、时间戳和照片关系。
  - `JournalPhotoRecord`：PhotoKit ID、日期、GPS、媒体尺寸/方向、压缩预览相对路径、元数据/原件状态及排序。
  - `JournalGenerationTask`：按日关联的生成任务状态、尝试次数和错误信息。当前该模型持久化任务状态，但不等于已接入后台执行器。
- `Hetkia/Features/Journal/PersistentJournalViews.swift`：真实 SwiftData 手札详情，照片选择规则、固定页面、编辑、手动 AI 生成、错误/模型状态和单独草稿显示。
- `Hetkia/Features/Journal/JournalPageComponents.swift`：统一暖色调调色板、页面与网格组件；部分早期样例组件仍保留，主应用持久化时间轴路由到 `PersistentJournalDetailView`。
- 当前持久化详情页对 1 张采用单图，对 3 张采用主图加两张辅助图，对 5 张使用两列网格，对 7/9 张使用三列网格。产品目标中的 5 张主图加四辅图、7 张主图加六辅图布局还需实现。

### AI

- `Hetkia/Features/AI/JournalDraftService.swift`
  - 用 `SystemLanguageModel.default.availability` 检查设备端模型状态。
  - 生成文字时只提供日期、选用照片数量和可用的图像输入；指令要求不臆测细节。
  - iOS/macOS 27 及以上在可用时附带图片；不支持图片输入时改用不描述画面的纯文本草稿。
  - 当前没有调用模型的 `supportsLocale`/语言能力检查；生成语言按系统语言指定，五种语言的模型输出质量仍待实机验证。
  - 不调用第三方 AI 服务，不上传照片。
- `PersistentJournalViews.generateDraft()`：读取当前选中照片的图像样本，调用服务并写入 `aiDraftBody`；保留已编辑正文。

### 时间轴、搜索与设置

- `Hetkia/Features/Timeline/TimelineHomeView.swift`：SwiftData 查询驱动的主界面、年份/月份/全部筛选、照片墙开关、空状态、导航、搜索和设置入口。
- `Hetkia/Features/Timeline/TimelineComponents.swift`：时间轴卡片、状态卡片和底部栏。
- `Hetkia/Features/Timeline/YearOverviewView.swift`、`MonthCalendarView.swift`：年/月组件；部分组件仍属独立视图，具体路由以 `TimelineHomeView` 为准。
- iOS/iPadOS 底栏初始隐藏并响应纵向手势；macOS 初始常驻。
- `Hetkia/Features/Timeline/TimelineHomeView.swift` 中持久化搜索按文字或记录/照片元数据过滤；不做图像内容识别。照片墙/列表切换按钮在主页面标题栏，不在底部栏。
- `Hetkia/Features/Settings/SettingsView.swift`：照片图库入口、每日时间、本地/iCloud 选项、Foundation Models 状态和当前系统语言。
- 设置页目前存在 Core Location 授权请求，但没有相应当前位置采集功能；在启用附近地点功能前应移除/禁用该入口及不再需要的权限声明，避免误导。
- String Catalog 的 `settings.permission.note` 仍称“本原型尚未读取照片或收集定位”，与已实现的照片导入不符；需更新五种语言的文案。定位用途说明也应在移除定位入口或实现附近地点后同步调整。
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
| 1：日记模板 | 固定 3:4 画布、1/3/5/7/9 布局、非照片区域固定，并验证不同尺寸 | 部分完成；持久化页面已存在，5/7 张布局还需对齐目标，设备尺寸实测待做 |
| 2：持久化 | SwiftData 日记/照片数据、压缩文件管理与清理、显示回退 | 主数据和显示路径已实现；删除清理与孤儿文件策略仍需补全 |
| 3：照片集成 | 权限说明、照片访问、有限/撤销授权处理、压缩预览生成 | 用户选择式导入与主要状态已实现；全库查询和真实历史扫描未实现 |
| 4：草稿生成 | 模型可用性、证据约束、可编辑草稿、手动生成与降级 | 详情页手动生成及状态已实现；引导中的真实日生成、实机验证仍待完成 |
| 5：后台与导出 | BackgroundTasks、启动 catch-up、按需渲染及系统分享 | 未完成；每日目标时间仅保存，未注册后台任务；持久化详情导出未完成 |
| 6：QA | 覆盖资源缺失、权限、空照片日、重复导入、AI 失败、后台延迟与导出 | 部分状态流 smoke test 存在；完整 XCTest/设备验证待做 |

## 6. 数据与处理规则

### 日记分组

- 导入照片使用拍摄日期转换为设备本地 `yyyy-MM-dd` day key。
- `JournalRecord.dayKey` 唯一；同一天后续导入照片归入现有记录。
- `localDay` 保存导入日的代表日期；代码注释明确 day key 不随未来时区变化重算。
- 没有拍摄日期的照片先保存为未归组，再由用户选日期建立关联。

### 选图规则

持久化详情页当前通过 `selectedPhotos` 计算：照片数大于 9 取 9；否则偶数减 1、奇数保持。排序使用 `sortOrder`。修改该规则时应同步主时间轴缩略图、详情页布局及传给 AI 的样本集合，并添加可执行验证。

### 任务恢复

- App 根 `.task` 将持久化中断的 `processing` 生成任务改为 `failed`，并保存中断错误。
- onboarding 模型在恢复时将模拟的处理中状态重置/暂停并持久化。
- 尚未实现完整可靠后台调度、取消令牌/重试退避、应用终止恢复和重复队列去重的端到端行为。

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
- README 记录此前 Xcode 27.1 iOS Simulator SDK 与 macOS SDK Debug 构建可用。本次核对读取到 Xcode 27.1；`xcrun simctl list runtimes` 因 CoreSimulatorService 连接失败而无法发现设备集/运行时，因此不能确认 runtime 是否已安装；本次没有运行构建。
- Apple Intelligence 必须在支持该功能的实际设备/系统上验证；普通编译不代表模型可用或文本质量通过验收。

## 10. 当前完成情况与待办

### 已实现

- 原生多平台 SwiftUI 工程、应用图标资源及五种语言。
- iPhone/iPad 竖屏设置和 macOS 纵向布局。
- SwiftData 日记、照片和生成任务模型。
- 用户主动挑选照片、元数据读取、日级分组、未注明日期照片手动归组、压缩 JPEG 预览及原图/预览/占位回退。
- 真实 SwiftData 时间轴、年/月/全部浏览入口、照片墙入口、文字/元数据搜索和持久化手札详情。
- 手札正文编辑、独立 AI 草稿、模型状态显示和手动生成入口。
- 每日目标时间、本地/iCloud 状态展示、照片和 AI 状态设置。
- 本地化系统语言选择与系统权限说明。

### 尚未实现或需修正

1. 把 onboarding 的历史补录邀请连接到真实 PhotoKit 查询；当前补录分组、进度和队列是模拟数据，且邀请 UI 没有开始按钮。
2. 今日手札引导状态接入真实照片/现有日记/AI 状态；当前流程未运行真实每日生成。
3. 实现明确授权后的历史范围扫描、按日确认、持久化队列及队列重启恢复。
4. 设计并实现可靠的最佳努力后台调度、前台 catch-up、手动重试；用户时间仅作为目标。
5. 设置页当前定位授权行及 Info.plist 定位声明尚未与实际功能一致，按产品决定清理；如果将来做附近地点，再实现后按需授权。
6. 更新 `settings.permission.note` 的五种语言过期文案；统一引导页和设置页的每日目标时间存储。
7. iCloud 同步尚未实现；界面继续标记不可用，不能将本地 SwiftData 误称为已同步。
8. 明确删除日记时 JPEG 预览、原件引用与数据库记录的清理生命周期；完善临时文件清理、导入失败回滚和孤儿文件清理验证。
9. 测试有限照片权限、撤销权限、iCloud-only 原件、原件删除、缺失预览、缺失拍摄日期、重复导入、空日、模型不可用/错误等情况。
10. 在支持 Apple Intelligence 的实机验证图像输入、语言质量、模型不可用/下载中状态与实际生成结果。
11. 增加正规 XCTest target，并为照片数规则、日期分组、文件回退、SwiftData 生命周期和多语言覆盖添加自动化测试。
12. 确认并修正旧样例视图/搜索组件是否仍需要保留，避免被接回主用户流程。
13. 在用户同意产品功能后再开发真正的图像语义搜索、OCR 或地点反向地理编码；当前均未实现。
14. 对齐 5 张和 7 张照片版式的“主图 + 辅图”设计，当前持久化详情页这两档使用等宽网格。
15. 实现用户主动预览/分享时的 3:4 页面图合成与系统分享入口，默认不永久保存合成图。

## 11. 迭代建议

1. **先修真实流程状态**：接入 onboarding 的今日状态与真实日期范围扫描，移除不可达/模拟的队列入口或将其明确限制在开发预览。
2. **完善数据可靠性**：导入与删除生命周期、权限撤销、原件缺失和持久化队列恢复。
3. **完成生成闭环**：背景最佳努力调度、前台补偿、用户手动生成与重试状态。
4. **验证体验**：建立 XCTest target，覆盖布局/语言/照片状态，并在 iPhone、iPad、Mac 真机或模拟器检查版面。
5. **再评估扩展项**：仅在需求确认后加入 iCloud、当前位置标签、OCR 或语义照片搜索。

## 12. 工程规范（合并自项目指引）

- 保持工程小而可构建，优先使用 SwiftUI、PhotoKit、SwiftData 等 Apple 原生框架；避免过度架构和没有明确需求的依赖。
- UI、照片读取、持久化、AI 生成和导出职责放在聚焦的类型中，避免相互耦合。
- 压缩预览路径使用应用管理目录下的相对路径或受管理标识，不把绝对沙盒路径作为持久化数据；明确记录删除/编辑时数据库记录与图片文件的生命周期。
- 在适当时为照片回退选择、版式选择和持久化行为补充测试；覆盖能力有限时明确写出未覆盖范围。
- 只有实际运行了构建或测试，才报告通过；构建成功不等于模拟器界面、真机权限、AI 输出质量或后台调度已验证。
- 开始较大范围重构前，先向用户说明简短的改动计划。除非用户明确要求，不加入分析追踪、广告、账号系统或社交功能。
