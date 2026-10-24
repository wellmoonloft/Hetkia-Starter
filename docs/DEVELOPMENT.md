# 时光 · Hetkia 开发文档

版本：2.0（轻量化需求变更）
更新日期：2026-10-24

## 1. 工程与平台

- 原生 SwiftUI 工程：`Hetkia.xcodeproj`。
- 主应用 target/scheme：`Hetkia`。
- 仅支持 iPhone 和 iPad，最低部署目标为 iOS/iPadOS 27.0；不支持 macOS 或 Mac Catalyst。
- AppDelegate 当前锁定竖屏；iPad Info.plist 仍声明系统要求的全部方向。
- WidgetKit 扩展 target：`HetkiaWidgetExtension`，随主 App 构建于 iOS/iPadOS。
- Bundle ID 当前为 `com.hetkia.app`；上架前需替换为开发者自己的标识与签名团队。
- String Catalog：`Hetkia/Resources/Localizable.xcstrings`；支持 `en`、`es`、`th`、`zh-Hans`、`zh-Hant`，其他语言回退英语。

## 2. 关键实现

### PhotoKit 查询

- `Hetkia/Features/Photos/OnThisDayLibrary.swift`：`OnThisDayLibrary.fetch` 根据 `Calendar.autoupdatingCurrent` 逐年构造当前月日的本地时间区间，读取 `PHAsset` 元数据并返回临时 `OnThisDayEntry`。查询不插入 SwiftData、不生成 JPEG、不调用 AI。
- 普通 PhotoKit fetch 不包含“最近删除”；显式排除 `isHidden`。媒体仅限 PhotoKit 可显示的 image/video，所以 Live Photo 与视频都保留。
- `PhotoAssetEligibility.isPriorityAsset` 将普通照片/视频排在截图/荧幕录影之前；`JournalPhotoSelection.selectedAssets` 再执行最多 9、偶数减 1 的数量规则。首页与详情共享该排序逻辑。
- `PhotoAssetResolver.previewImage` 为界面按需请求系统图像/视频首帧；`displayImage` 不更改 SwiftData 元数据。

### 首页与详情

- `Hetkia/Features/Timeline/TimelineHomeView.swift`：只显示历年同月同日卡片。首次进入、应用变为 active、从详情返回、记录变化及本地日期跨日时重新查询 PhotoKit。
- 首页卡片使用详情同款组合，只有日期和照片。当前图片预览由 PhotoKit 提供，不保存文件。每次首页数据重查后请求 WidgetCenter 更新同类小组件。
- `OnThisDayCacheStore` 在 Application Support 原子写入当天的年月日上下文、时区及按日排序的 PhotoKit `localIdentifier` 索引。启动先按标识向当前图库恢复 `PHAsset` 并显示，再执行实时查询并替换索引；不缓存照片位图/JPEG 或手札数据。缓存只保留单个 JSON 快照，不累积多日文件；日期、年份或时区变化/旧 schema 时，在新查询前删除旧快照。午夜后台刷新和引导首次查询共用 `OnThisDayLibrary.fetch`，查询成功即写入新索引。
- 点卡片时找相同 `dayKey` 的已保存日记；没有则构造未插入的临时 `JournalRecord`。`PersistentJournalDetailView` 合并该日 PhotoKit 资源与已保存照片。详情导航标题与首页标题都使用 `brand.name` 本地化键；卡片标题行只显示照片时间，不显示来源状态或品牌标识。详情卡片的照片网格水平内边距为 12pt，与首页卡片相同。
- `commitJournalForUserAction()` 只在生成文字、保存编辑或添加留言路径调用。它插入临时 JournalRecord/照片关系，按需写入应用 JPEG，并保存 SwiftData。若某已保存关系缺少 JPEG，也只在显式操作时补齐。
- 仅打开详情、浏览照片或返回不调用 commit。详情打开时即将含坐标照片异步加入 `PhotoLocationResolver`；iOS 先用 `CLGeocoder` 获取国家、城市和区/街区字段，再以 MapKit 反向地理编码兜底；对请求失败执行 2、6、15、30 秒退避重试。App 启动、回到前台时，已保存日记中无地点名或仍只有城市级名称的照片再次排队。新缓存键为 `hetkia.reverseGeocoding.cache.v2`；队列和缓存按 5 公里半径合并坐标。展示地点按三级名称去重，地图仍使用照片原始坐标。地点名解析不因此保存临时日记或照片预览。

### 引导和设置

- `OnboardingFlowView` 将原欢迎页和照片权限页合并为首屏，请求 PhotoKit `.readWrite` 完整授权；只在 `.authorized` 状态前进。拒绝/有限授权展示系统设置入口。
- 授权成功后展示扫描进度；扫描完成即进入首页，没有用户确认步骤。
- 设置不再展示“每日生成时间”或全图库导入/生成任务。设置保留照片/定位权限状态、存储选项、设备端 AI 状态和语言说明。
- 旧版导入、历史索引、自动队列及年份/月视图源文件仍在 target 内作为历史实现，但新首页和设置主流程不再调用它们；如后续清理，需先确认 SwiftData 旧数据兼容范围。

### 后台刷新和 WidgetKit

- `Hetkia/App/HetkiaApp.swift` 注册 `com.hetkia.app.onthisday-refresh`，请求 `BGAppRefreshTask` 在下一次本地午夜之后运行；任务重新读取 PhotoKit，并请求 WidgetCenter 刷新。
- 系统只承诺在允许时机执行后台任务；`earliestBeginDate` 是最早运行时间而非准点保证。App 每次前台激活都会补做当日查询。
- `HetkiaWidget/HetkiaWidget.swift` 自行按同一日期、资格、排序和数量规则读取 PhotoKit，并为 WidgetKit 时间线生成系统管理的图像快照。UIKit/AppKit 按平台解码图片。声明 `.systemLarge` 供桌面主样式使用，另声明 `.systemSmall` 供 iPhone StandBy 使用；大尺寸显示标题、品牌和拼图，小尺寸仅渲染无内边距的满版拼图，不显示文字。WidgetKit 的 family 不能区分 StandBy 与桌面小尺寸，因此两处小尺寸都采用纯图片布局。
- Widget 生成一个静态拼图：同日年份由最早到较新排序，按 1/3/5 的奇数布局最多读取五组并各取首图。单组铺满；三组使用上方大图、下方并排双图；五组使用上方大图、下方 2×2。每张图分别使用 `hetkia://onthisday/YYYY-MM-DD` 深链打开对应详情。顶部左侧是“历史上的今天”，右侧是品牌名；不显示副标题、日期标签、滚动或翻页。
- 大尺寸使用 `containerBackground` 提供整张象牙白底色，`contentMarginsDisabled()` 取消系统默认内容缩进后由布局显式留白；不叠加内缩卡片，外缘由 WidgetKit 按组件容器圆角裁切。小尺寸关闭拼图自身圆角裁切并取消内边距，使图片铺满组件，由系统容器处理外缘。Widget 不使用滚动、分页按钮或时间线轮播；系统仍决定快照刷新的实际时机。
- StandBy 使用 `.systemSmall` family（Apple 当前 StandBy 组件上下文采用小尺寸系统组件）；WidgetKit 会按 StandBy 外观处理背景与色彩，因此系统呈现可能与桌面全彩样式不同。两种 family 使用相同时间线、图片选择和逐图深链。
- 主 App URL handler 接受该深链，并在当前 PhotoKit 查询完成后导航到对应日期。

## 3. 权限与隐私

- `Hetkia/Info.plist` 声明 `NSPhotoLibraryUsageDescription`、`NSPhotoLibraryAddUsageDescription`、后台任务标识及 URL scheme。权限说明在五种语言 `InfoPlist.strings` 中提供。
- `.limited` 不足以满足“整个图库历史上的今天”，主功能要求 `.authorized`。用户拒绝时只展示系统设置入口/受限页面，不以代码强制退出 App。
- GPS 从照片元数据读取，不因照片位置而申请 Core Location 权限。打开详情后，坐标异步进入反向地理编码队列；短暂失败会重试，未解析记录在 App 回到前台時再次排队。位置名缓存复用，浏览查询不会持久化日记或照片预览。
- 浏览中请求的显示图像仅在内存/系统媒体管线中用于渲染。WidgetKit 时间线需要系统管理的图像快照；应用不因此写入 JournalRecord 或 `JournalImages`。

## 4. 构建

要求 Xcode 27 与 iOS 27 SDK。命令：

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

模拟器实际运行还需用户在 Xcode 安装相应 Simulator runtime。无可用 runtime 时 generic destination 仍可执行编译检查，但不能替代模拟器交互或真机验证。

2026-10-24：通用 iOS Simulator 构建通过；iPad Info.plist 声明全方向。已连接的 iPhone 可供枚举，但当前未安装 Hetkia。签名配置已按 `wellmoonloft@gmail.com` 对应团队统一为 `YT2PRQ5S69`。真机自动签名构建无法取得 `com.hetkia.app` 和 `com.hetkia.app.widget` 的描述文件：本机 Xcode 当前尝试使用 `lisonictian_007@hotmail.com` 登录 Apple Developer，登录被拒。需在 Xcode 登录正确账号并为主 App、Widget 扩展刷新/生成匹配的开发描述文件，之后才能完成真机安装验证。Widget 签名 strip 提示不代表安装失败。17:15 版本再次通过通用 iOS Simulator 构建；详情地点解析使用 iOS 26 起弃用但当前 SDK 仍提供的 `CLGeocoder` 结构化字段，构建会报告弃用警告，真机网络反查尚需确认。

## 5. 目前限制与验证清单

- BGTaskScheduler 与 WidgetKit 时间线是最佳努力刷新，无法承诺每天 00:00 准时运行。
- Widget 不使用普通滚动手势、分页按钮或轮播；静态拼图按 1/3/5 布局展示最多五篇同日记录首图。大尺寸含标题/品牌，小尺寸满版纯图片；每张图片分别提供对应日期的深链。
- 逐年 PhotoKit 查询目前从 1900 年至当前年；相册较大或 iCloud 资源较多时需真机评估启动耗时和图片请求策略。
- 完成真机检查：完整授权/拒绝/有限授权；仅查看后 SwiftData 与 `JournalImages` 无新记录；生成/编辑/留言会保存当前照片；次年同日新增照片并入详情；截图/录屏优先规则；Live Photo/视频首帧；Widget 静态拼图、每张图的深链、满版圆角及午夜后刷新。
- 尚未验证既有安装数据的 SwiftData schema 迁移、App Store 签名与实际后台刷新表现。
