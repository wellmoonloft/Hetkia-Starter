# 时光 · Hetkia

一个本地优先的原生日记应用：将每天的照片整理成只属于自己的日记页，支持 iPhone、iPad 与 Mac。

## 当前状态

完整的当前产品要求与开发现状分别整理在 [`docs/PRODUCT_REQUIREMENTS.md`](docs/PRODUCT_REQUIREMENTS.md) 和 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。它们标出已实现、原型和待办范围；本 README 保留为构建与状态摘要。

主时间轴、年/月/全部视图、照片墙、搜索和手札详情现在读取用户导入并保存在 SwiftData 中的真实照片与日记，不再展示虚拟日记。没有数据时显示导入引导。照片导入按拍摄日期的本地日历日分组；缺少拍摄日期的照片需由用户手动指定。导入通过系统照片选择器完成，不会自动扫描整个照片库。照片原件优先显示，原件不可用时回退到应用内 JPEG 预览，再回退到占位图。已编辑正文与 AI 草稿分开保存，重新生成不会覆盖用户编辑的正文。

已分别加入五种语言的照片与定位用途说明。照片授权可在首次引导或设置中由用户主动发起；定位权限目前只在设置页提供申请入口，照片 GPS 只读取照片元数据，不需要系统定位授权。定位入口尚未连接实际的当前位置功能，后续应在提供附近地点功能前清理或改为按需申请。导入的照片会保存压缩预览和可用的 PhotoKit 标识及元数据。

最低部署目标为 **iOS/iPadOS 27.0、macOS 14.0**。全新安装会显示首次启动引导；今日生成状态目前没有连接真实照片/生成流程，历史补录状态和队列仍属模拟原型，历史邀请页尚未连接真实扫描入口。界面依据系统首选语言选择简体中文、繁体中文、西班牙语、泰语或英语，其他语言默认英语。Foundation Models 按运行时设备资格、Apple Intelligence 设置和模型准备状态检测可用性；应用不会把日记或照片发送到第三方 AI 服务。手札照片按拍摄时间排序，展示和生成使用 1/3/5/7/9 张规则（双数减一，超过 9 张取 9 张）；5 张和 7 张的主图/辅图版式仍需对齐设计。草稿需要在详情页手动触发；生成正文显示在手札中，编辑过正文时 AI 草稿会单独显示。照片导入由用户在系统选择器中选择，不自动扫描全库，也没有接入自动历史补录后台队列。照片搜索目前匹配日期、文字和已保存元数据，不做图像内容识别。每日时间仅保存偏好，不会安排后台任务；iCloud 尚未配置或同步。原照片删除后的清理策略、后台续传、队列崩溃恢复及实际设备上的 Apple Intelligence 验证仍待完成。

应用显示名称按系统语言显示为 **Hetkia**、**时光 · Hetkia** 或 **時光 · Hetkia**；工程名为 `Hetkia`，Bundle ID 当前占位为 `com.hetkia.app`（上架前应替换为开发者自己的反向域名标识）。

## 构建

要求 Xcode 27 或更新版本（含 iOS 27 SDK）。打开 `Hetkia.xcodeproj`，选择 `Hetkia` scheme 后运行。iPhone 和 iPad 通过 iOS Simulator/iOS 设备 destination 构建，Mac 选择 macOS destination。

命令行 iOS/iPadOS 模拟器构建：

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

原生 macOS 构建：

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -sdk macosx -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

最低部署目标：**iOS/iPadOS 27.0、macOS 14.0**。iOS/iPadOS 项目设置已同步更新为 27.0；macOS 部署目标保持 14.0。

Xcode 27.1 的 iOS Simulator SDK 与 macOS SDK Debug 构建可用于验证工程编译。iOS/iPadOS 只声明竖屏方向；iPad 以全屏运行以保持方向限制。macOS 默认窗口为 620×1000 pt，窗口可按 macOS 常规方式调整大小，但页面内容不会切换为横向布局。照片卡片根据可用宽度计算尺寸，手札页面仅纵向滚动。当前机器没有可用的 CoreSimulator runtime，因此不能在模拟器中检查实际页面效果；下载 runtime 后可从 Xcode 运行 iPhone 与 iPad 模拟器。引导状态流 smoke test：`./Scripts/run-onboarding-smoke-tests.sh`，覆盖新安装引导状态、显式生成状态变化、补录模型队列暂停/继续、重试和 UserDefaults 恢复。它不覆盖 SwiftData、PhotoKit 或设备端 Foundation Models；项目尚未配置 XCTest target。

## 目录结构

```text
Hetkia-Starter/
├── Hetkia.xcodeproj/
├── Hetkia/
│   ├── App/                         # 应用入口
│   ├── Features/Onboarding/          # 首次启动与历史补录状态流
│   ├── Features/Journal/             # 固定版式日记与完整手札详情
│   ├── Features/Timeline/            # 基于 SwiftData 的时间轴、年/月视图与照片墙
│   ├── Features/Search/              # 日记文字与照片元数据搜索
│   ├── Features/Settings/            # 权限、生成时间、存储与 AI 状态
│   ├── Assets.xcassets/              # iOS/iPadOS 与 macOS 图标
│   ├── Resources/                    # String Catalog 与设计源稿
│   ├── en.lproj/                     # 英语应用名称与权限说明
│   ├── zh-Hans.lproj/                # 简体中文应用名称与权限说明
│   ├── zh-Hant.lproj/                # 繁体中文应用名称与权限说明
│   ├── es.lproj/                     # 西班牙语应用名称与权限说明
│   └── th.lproj/                     # 泰语应用名称与权限说明
├── Design/                           # 原始设计材料
├── Tests/                             # 可运行的流程 smoke test
├── Scripts/                           # 本地验证脚本
└── docs/                              # 产品需求与开发文档
```

图标设计源稿 `Design/Hetkia-App-Icon-Concept.png` 已保留在 `Hetkia/Resources/Branding/`，并用于 iOS/iPadOS 与 macOS AppIcon asset catalog。正式发布前仍应在目标设备上检查图标裁切和视觉效果。

## 下一阶段

下一阶段建议实现用户授权后的全库历史扫描与分组确认，并接入持久化补录队列；随后补齐后台任务恢复、原件删除后的清理与 iCloud 决策。最后在支持 Apple Intelligence 的真机验证文本与图片草稿生成，并覆盖照片受限授权、权限撤销和模型不可用状态。
