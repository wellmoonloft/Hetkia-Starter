# 时光 · Hetkia

一个本地优先的原生日记应用：将每天的照片整理成只属于自己的日记页，支持 iPhone、iPad 与 Mac。

## 当前状态

完整的当前产品要求与开发现状分别整理在 [`docs/PRODUCT_REQUIREMENTS.md`](docs/PRODUCT_REQUIREMENTS.md) 和 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。它们标出已实现、原型和待办范围；本 README 保留为构建与状态摘要。

主时间轴、年/月/全部视图、照片墙、搜索和手札详情读取 SwiftData 中的真实记录。用户可通过系统照片选择器导入照片；获得 PhotoKit 完整或有限访问后，应用会在前台启动/恢复时查询今天和往年同月同日的照片。首次引导先建立最近 30 天的照片日记（仅索引照片与元数据，不生成 AI 文字）；用户默认同意后，还可启动可恢复的全历史照片元数据整理。不会对这两项索引任务批量调用 AI，也不会预先下载全图库原图。首页另以持久化队列处理每日及“历史上的今天”文字草稿。当天可创建一篇自动和一篇手动手札，自动内容经用户编辑后不会被覆盖。照片原件优先显示，原件不可用时回退到应用内 JPEG 预览，再回退到占位图。

时间轴卡片和手札详情使用同一套自动选图结果（最多 9 张，偶数减 1）。详情包含带本地日期时间的留言流：生成文字作为首条留言，用户可在照片详情中直接编辑或追加留言；输入区域随详情纵向滚动并响应键盘。

手札照片布局为 1 张铺满、3 张主图加双辅图、5 张主图加 2×2、7 张主图加 3×2、9 张九宫格；点按照片可全屏滑动浏览。正文按系统动态字体缩放。照片 GPS 元数据可用时会解析地点；同一城市合并显示，不同城市分别显示，每个地点按该城市首张照片的精确坐标打开地图。分享会按 3:4 手札版式即时渲染图片并交给系统分享面板，不永久保存合成图。

已分别加入五种语言的照片与定位用途说明。照片授权可在首次引导或设置中由用户主动发起；定位权限目前只在设置页提供申请入口，照片 GPS 只读取照片元数据，不需要系统定位授权。定位入口尚未连接实际的当前位置功能，后续应在提供附近地点功能前清理或改为按需申请。导入的照片会保存压缩预览和可用的 PhotoKit 标识及元数据。

最低部署目标为 **iOS/iPadOS 27.0、macOS 14.0**。首次引导在照片授权后自动前进，移除了每日时间选择页；每日目标时间默认凌晨 4:30，可在设置修改。最近 30 天照片日记索引完成后自动进入历史整理邀请，历史整理默认选择“是”，用户确认后进入首页并开始可恢复的元数据索引。iOS 使用有限时长的 UIKit 后台执行机会，并在下次启动/恢复时续做；未注册 `BGTaskScheduler`，系统不能保证任务持续或准时运行。前台每日与“历史上的今天”草稿队列逐条处理；失败项可重试，残留处理中任务会恢复。String Catalog 支持简体中文、繁体中文、英语、西班牙语和泰语。Foundation Models 按设备资格、Apple Intelligence 设置和模型准备状态检测可用性；实际生成仍需支持设备验证。照片搜索目前匹配日期、文字和已保存元数据，不做图像内容识别。iCloud 尚未配置或同步。SwiftData 从旧版日期唯一键迁移到“日期 + 来源”键的启动迁移代码已加入，但尚未用含旧数据的安装包升级场景验证。

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

Xcode 27.1 下 macOS Debug 与通用 iOS Simulator Debug 构建均已通过。当前尚未进行模拟器交互验证、旧数据升级验证或 Foundation Models 真机验证。页面保持纵向阅读；iPhone 仅声明竖屏，iPad 为满足 iPadOS 27 窗口方向检查而声明支持全部方向，并由应用方向回调请求竖屏。启动画面使用 Xcode 生成的静态 Launch Screen 配置。macOS 默认窗口为 620×1000 pt。现有 onboarding smoke test 不覆盖 SwiftData、PhotoKit 或设备端 Foundation Models；项目尚未配置 XCTest target。

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

下一阶段建议验证 SwiftData 旧库迁移及有限图库授权行为，评估是否加入 `BGTaskScheduler` 最佳努力调度并完善队列退避/取消。再补充可执行数据测试，并在支持 Apple Intelligence 的真机验证文本与图片草稿生成；之后处理原件删除后的清理和 iCloud 决策。
