# 时光 · Hetkia 开发文档

版本：2.8（首页历史双 tab 与手札浏览）
更新日期：2026-11-12

## 1. 工程与平台

- 原生 SwiftUI 工程：`Hetkia.xcodeproj`。
- 主应用 target/scheme：`Hetkia`。
- 仅支持 iPhone 和 iPad，最低部署目标为 iOS/iPadOS 18.0；不支持 macOS 或 Mac Catalyst。
- AppDelegate 当前锁定竖屏；iPad Info.plist 仍声明系统要求的全部方向。
- WidgetKit 扩展 target：`HetkiaWidgetExtension`，随主 App 构建于 iOS/iPadOS。
- Bundle ID 当前为 `com.hetkia.app`；上架前需替换为开发者自己的标识与签名团队。
- String Catalog：`Hetkia/Resources/Localizable.xcstrings`；支持 `en`、`es`、`th`、`zh-Hans`、`zh-Hant`，其他语言回退英语。

## 2. 关键实现

### PhotoKit 查询

- `Hetkia/Features/Photos/OnThisDayLibrary.swift`：`OnThisDayLibrary.performFullScan` 根据 `Calendar.autoupdatingCurrent` 逐年构造当前月日的本地时间区间，先执行日期谓词，再读取 `PHAsset` 元数据并返回临时 `OnThisDayEntry`。查询不插入 SwiftData、不生成 JPEG、不调用 AI。全量扫描从 1900 年查到当前年；已有已保存日记不会跳过对应年份，因为照片集合可能已变化。
- 普通 PhotoKit fetch 不包含“最近删除”；显式排除 `isHidden`。媒体仅限 PhotoKit 可显示的 image/video，所以 Live Photo 与视频都保留。日期查询之后由 `PhotoAssetEligibility.allows` 在内存中应用截图/荧幕录影设置；默认关闭时检查 `.photoScreenshot` 与 `.videoScreenRecording` 子类型并排除，避免依赖 PhotoKit 位掩码谓词。
- `PhotoAssetEligibility.isPriorityAsset` 将普通照片/视频排在截图/荧幕录影之前；`JournalPhotoSelection.selectedAssets` 再执行最多 9、偶数减 1 的数量规则。首页、详情、持久化照片过滤和 WidgetKit 都读取共享 App Group 偏好，默认不包含截图/录屏。
- `PhotoAssetResolver.previewImage` 为界面按需请求系统图像/视频首帧；`displayImage` 不更改 SwiftData 元数据。
- 拼图继续用 PhotoKit `.aspectFill` 预览以适配格子裁切。全屏静态照片查看走独立的 `fullFrameImage`：通过 `assetLocalIdentifier` 请求 PhotoKit 原图并使用 `.aspectFit`；资源不可用时才回退到本地压缩 JPEG。新持久化 JPEG 也按完整画面比例压缩，不再保存方形裁切预览。旧日记若原图已删除且既有 JPEG 本身已裁切，无法从裁切文件恢复画面边缘。

### 首页与详情

- `OnThisDayScanCoordinator` 是仅限主 App 进程的 actor。键包含本地日期、时区、截图/录屏筛选设置和扫描范围；同键并发请求共用一份进行中的结果。完整扫描可满足较窄的当年刷新，但当年刷新不能代替完整扫描。扫描结果带生成序号；提交时再次检查序号和日期，并串行写入缓存，防止迟到的旧结果覆盖新结果。进度通过订阅流送给调用方，取消一个界面的订阅不会取消共享的扫描任务。
- `Hetkia/Features/Timeline/TimelineHomeView.swift`：根层叠放「历史上的今天」与「历史手札」两套 `ScrollView`，`NavigationStack(path:)` 统一承载 `TimelineRootRoute`（今日详情与已保存日记详情）。`HomeHistoryFloatingBar` 绑定 `TimelineRootTab` 与历史浏览模式；`path` 非空或 blocking sheet 时隐藏浮动条。历史浏览状态：`SavedJournalsBrowseMode`（all/year/month）+ `SavedJournalsMonthScope`（`.monthsInYear` / `.entries`）；底栏回调 `selectSavedJournalsMonth/Year/All` 与 `resetSavedJournalsBrowseToAll`（点历史 tab）实现产品约定的月·年·全部状态机，不依赖右滑。历史上的今天部分：首次读取有效缓存后先显示卡片；热启动/回到前台时保留当前内存中的卡片，只刷新今年的照片集合，不因从详情返回而重新查询。`publishEntriesIfChanged` 比较日期 ID 和有序 PhotoKit `localIdentifier`，只有内容变化才替换 `entries`。强制扫描完成后即使 SwiftUI 刷新任务被取消，也要发布查询结果并清除加载状态。
- `Hetkia/Features/Timeline/HomeHistoryFloatingBar.swift`：左侧胶囊「首页｜历史」，历史 tab 激活时右侧「月｜年｜全部」；高亮与 `SavedJournalsBrowseMode` 一致（月度列表与月内手札双列均为 `.month`）。
- `Hetkia/Features/Timeline/SavedJournalsBrowseViews.swift`：`SavedJournalsYearsBrowseView` 年度双列；`SavedJournalsMonthsInYearWaterfallView` 月度双列（卡片标题 `.year().month(.wide)`，无顶栏年份）；`SavedJournalsMonthEntriesWaterfallView` 月内手札双列（无返回、无换月 chevron）。`SavedJournalIndex` 提供有意义记录、按年/月筛选与默认年推导。
- 首页卡片由 `OnThisDayCard` 和 `OnThisDayPhotoGrid` 组成：展示当天符合条件的全部照片，拼贴几何使用 `PhotoMosaicLayout` 的三等分网格，按数量计算卡片高度并避免空格；日期白字浮在图片顶部，渐层不覆盖透明拼接缝。照片预览由 PhotoKit 提供，不保存文件。Widget timeline 仅在索引指纹变化或用户强制刷新时请求更新。
- `Hetkia/Features/Timeline/SavedJournalsView.swift`：`SavedJournalsRootContent` 供「全部」总列表复用（按 `dayKey` 合并、双列、`PersistedJournalThumbnail` 只读 Application Support JPEG）。独立 `SavedJournalsView` 仍可用于预览/调试；主流程入口在 `TimelineHomeView`。已保存详情经 `TimelineRootRoute.savedJournal` 打开，`savedOnly: true`，不扩展 PhotoKit 照片集合。
- 历史手札卡片（全部/年度/月度/月内）使用本地封面铺满，白字叠年月或日期与篇数；暗色渐层保证对比。无封面时占位图。
- `OnThisDayCacheStore` 在 Application Support 原子写入当天的年月日上下文、时区及按日排序的 PhotoKit `localIdentifier` 索引。启动先按标识向当前图库恢复 `PHAsset` 并立即显示；同一天普通刷新只查询今年并替换该年份条目，下拉刷新执行 `OnThisDayLibrary.performFullScan` 完整重查。缓存不含照片位图/JPEG 或手札数据，只保留单个 JSON 快照。日期、年份或时区变化/旧 schema 时，在新查询前删除旧快照并完整建立当天索引。午夜后台刷新、引导首次查询和首页请求经过进程内协调器复用兼容的完整扫描结果。
- 完整媒体查询与展示筛选应保持分离：索引卡片可用 `JournalPhotoSelection` 选择首页展示的优先集合；用户触发日记持久化时仍须获得该日期需要的完整照片集合。不能因为已有 `JournalRecord` 或命中展示缓存就省略照片查询、照片关系更新、JPEG 预览生成或 AI 任务。
- Widget Extension 不使用主 App 的 actor，也不连接 SwiftData 容器。主 App 与 Widget Extension 通过 App Group 的 `on-this-day-widget-index.json` 传递轻量元数据快照；Widget 依据 PhotoKit 标识恢复代表图，验证日期、时区、筛选上下文和资源可用性，失败时执行自己的查询并重建快照。Widget 时间线由系统调度，主 App 仅在内容指纹变化或强制刷新时请求重新加载。
- 点首页卡片时找相同 `dayKey` 的已保存日记；没有则构造未插入的临时 `JournalRecord`。`PersistentJournalDetailView` 合并该日 PhotoKit 资源与已保存照片。详情导航标题显示选中照片日期时间；首页标题、详情导航标题、详情卡片品牌名和分享图品牌名统一使用 `brand.name` 多语言键（简体中文“时光”、繁体中文“時光”、其他支持语言“Hetkia”）。详情卡片顶部为品牌短句/品牌名，随后显示照片拼贴、日记正文和位置。详情拼贴中的视频在图块中央显示播放图标；覆盖层不拦截原有打开视频/大图的点击。详情拼贴和独立分享视图 `JournalShareCard` 共用 `PhotoMosaicLayout` 动态高度几何并展示全部照片；分享卡片按自己的画布宽度计算高度，保留独立文字排版。
- 日记正文由 `bodyText`、`aiDraftBody` 和旧自动记录兼容读取，不再将自动生成文本写进留言数组。`posts` 仅显示 `.note` 类型留言，分享正文从日记文本取值。正文编辑调用显式持久化路径；留言新增与编辑仅操作留言数据。留言删除先移除指定 `.note`；若没有其他个人留言且 `bodyText`、`aiDraftBody` 和兼容的自动生成文本均为空，则复用整篇日记删除流程，级联删除照片关系并清理应用 JPEG 预览；否则只保存更新后的留言数组。
- `generatedDraftCard` 放在 action panel 后、message board 前。应用草稿时检查现有非空正文：空正文立即应用；非空正文显示本地化替换确认对话框，确认后更新正文并持久化。
- `JournalDraftService.defaultPrompt` 是 AI 日记生成的默认指令；用户可在设置中编辑，通过 `UserDefaults` 键 `hetkia.ai.journalPrompt` 保存。每次创建 Foundation Models 会话时读取当前值。默认提示要求依据全部照片与元数据写第一人称的 2–5 句日记，使用系统语言、不写具体日期，并避免缺乏证据的推断。
- `JournalPromptEditorView` 使用 Swift `String.count`（扩展字素簇）计数，允许最多 1,500 个用户可见字符；超限时点击保存展示本地化警告且不写入设置，空白内容不可保存。此计数面向中文及其他 Unicode 输入，不是 UTF-8 字节数限制。恢复默认按钮只重置编辑器草稿，需点击保存才生效。
- `commitJournalForUserAction()` 只在生成文字、保存编辑或添加留言路径调用。它插入临时 JournalRecord/照片关系，按需写入应用 JPEG，并保存 SwiftData。若某已保存关系缺少 JPEG，也只在显式操作时补齐。
- 仅打开详情、浏览照片或返回不调用 commit。详情打开时即将含坐标照片异步加入 `PhotoLocationResolver`；iOS 先用 `CLGeocoder` 获取国家、城市和区/街区字段，再以 MapKit 反向地理编码兜底；对请求失败执行 2、6、15、30 秒退避重试。App 启动、回到前台时，已保存日记中无地点名或仍只有城市级名称的照片再次排队。新缓存键为 `hetkia.reverseGeocoding.cache.v2`；队列和缓存按 5 公里半径合并坐标。展示地点按三级名称去重，地图仍使用照片原始坐标。地点名解析不因此保存临时日记或照片预览。

### 引导和设置

- `OnboardingFlowView` 将原欢迎页和照片权限页合并为首屏，请求 PhotoKit `.readWrite` 完整授权；只在 `.authorized` 状态前进。拒绝/有限授权展示系统设置入口。
- 授权成功后展示扫描进度；扫描完成即进入首页，没有用户确认步骤。
- 设置不再展示照片权限卡片、“每日生成时间”、全图库导入/生成任务或独立「历史手札」入口（改由首页浮动条 **历史** 进入）。设置提供存储选项、设备端 AI 状态、**相机与定位**（iOS）、**发布服务**（`PublishSettingsView`）和语言说明。App 启动及回到前台时检查完整照片授权；授权被撤销后回到合并后的照片授权引导页。
- 旧版导入、历史索引、自动队列及年份/月视图源文件仍在 target 内作为历史实现，但新首页和设置主流程不再调用它们；如后续清理，需先确认 SwiftData 旧数据兼容范围。

### 远程发布（Hugo + GitHub + R2）

- 实现位于 `Hetkia/Features/Publishing/`：`PublishCoordinator` 串行执行连通性探测 → GitHub/R2 校验 →（随笔）R2 上传 JPEG → 生成 Markdown → GitHub Contents API `PUT` 提交。
- `PublishSecretsStore` 将 GitHub PAT 与 R2 Access Key / Secret 写入 Keychain（`UserDefaults` 仅保存非敏感配置）。仓库内不包含任何真实令牌或密钥。
- `PublishConfiguration` 保存 owner、repository、branch、`essayDirectory`、`momentsDirectory`、R2 account、bucket、CDN 域名；多语言 Hugo 站点需配置带语言前缀的路径（例如 `content/cn/essay`）。
- `GitHubPublishClient` 使用 Contents API 创建/更新单文件，不实现 Git Database 七步流。
- `R2S3Client` 使用 SigV4 向 `https://{account}.r2.cloudflarestorage.com` 上传；`publicCDNURL(forStorageKey:)` 生成公开图片 URL 时去掉桶名及 CDN 域名中多余的 `/{bucket}` 前缀，使 Markdown 中的地址与自定义域名根路径一致（例如 `https://images.example.com/essay/…`）。
- `HugoMarkdownBuilder` 输出随笔/说说 Front Matter（`categories`、`date` 等）。随笔文件名 `essay-{yyyyMMddHHmmss}-{uuid8}.md`，说说 `moment-{…}.md`；时间戳来自 `RemotePublishDraft.contentCreatedAt`。
- `EssayPublishSheet` 提供「现在 / 当年」日期模式：现在使用提交时刻；当年取已勾选照片中最早的 `capturedAt`，否则回退详情页的 `displayedCaptureDate`。`MomentPublishSheet` 仅正文，不得带图。
- 发布成功自动 `dismiss` 发布 sheet；设置页 GitHub/R2「测试连接」在各自卡片下方展示结果（成功文案含「设置已保存」），测试前会先 `persist`。
- `PublishTask`（SwiftData）记录任务状态与错误；成功发布不调用 `commitJournalForUserAction()`。

### 后台刷新和 WidgetKit

- `Hetkia/App/HetkiaApp.swift` 注册 `com.hetkia.app.onthisday-refresh`，请求 `BGAppRefreshTask` 在下一次本地午夜之后运行；任务使用主 App 扫描协调器执行完整 PhotoKit 查询，仅在小组件索引变化时请求 WidgetKit 刷新。
- 系统只承诺在允许时机执行后台任务；`earliestBeginDate` 是最早运行时间而非准点保证。App 每次前台激活都会补做当日查询。
- `HetkiaWidget/HetkiaWidget.swift` 注册两个 kind：`Hetkia.OnThisDay`（`.systemSmall` 与 `.systemLarge`）与 `Hetkia.PublishQuick`（仅 `.systemSmall`）。`OnThisDay` 小尺寸为无内边距满版拼图（StandBy 与桌面拼图样式共用）；大尺寸在拼图上叠磨砂顶栏（日期/品牌）与底栏（统计 + 横排发布按钮）。`PublishQuick` 在 `containerBackground` 铺当年代表图，前景为系统 content margins 内的标题/统计与底部固定发布按钮，深链 `hetkia://publish/*`。拼图块间距为 0、背景透明。
- Widget 生成固定画布静态拼图：从同日年份倒序取最多九组，再按较早到较新排列；代表图规则与主 App `widgetRepresentativeAsset` 一致。`WidgetMosaicLayout` 为 1–9 张提供三等分网格；每格 `hetkia://onthisday/YYYY-MM-DD` 深链。主 App 扫描经 App Group 写入 `on-this-day-widget-index.json`（含总张数、年数、hero 图标识）；指纹变化时同时 reload `Hetkia.OnThisDay` 与 `Hetkia.PublishQuick`。
- `OnThisDay` 拼图使用 `contentMarginsDisabled()` 铺满；`PublishQuick` 保留系统 content margins。Widget 无滚动/轮播；刷新由午夜 BG 与系统 WidgetKit 时间线调度。
- StandBy 应使用 `OnThisDay` 小尺寸拼图；桌面「时光仪表盘」使用 `PublishQuick` 小尺寸。
- 主 App URL handler 接受该深链，并在当前 PhotoKit 查询完成后导航到对应日期。

## 3. 权限与隐私

- 远程发布仅向用户配置的 GitHub 与 Cloudflare R2 端点发起 HTTPS 请求；凭证仅存本机 Keychain。日志与仓库代码中不得硬编码 PAT、R2 密钥或部署私钥。
- `Hetkia/Info.plist` 声明 `NSPhotoLibraryUsageDescription`、`NSPhotoLibraryAddUsageDescription`、后台任务标识及 URL scheme。权限说明在五种语言 `InfoPlist.strings` 中提供。
- `.limited` 不足以满足“整个图库历史上的今天”，主功能要求 `.authorized`。用户拒绝时只展示系统设置入口/受限页面，不以代码强制退出 App。
- GPS 从照片元数据读取，不因照片位置而申请 Core Location 权限。打开详情后，坐标异步进入反向地理编码队列；短暂失败会重试，未解析记录在 App 回到前台時再次排队。位置名缓存复用，浏览查询不会持久化日记或照片预览。
- 浏览中请求的显示图像仅在内存/系统媒体管线中用于渲染。WidgetKit 时间线需要系统管理的图像快照；应用不因此写入 JournalRecord 或 `JournalImages`。

## 4. 构建

要求支持 Swift 5 与 iOS 18 SDK 的 Xcode。当前验证使用 Xcode 27/iOS 27 SDK，并将 App 和 Widget Extension 的部署目标设为 iOS 18。命令：

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

模拟器实际运行还需用户在 Xcode 安装相应 Simulator runtime。无可用 runtime 时 generic destination 仍可执行编译检查，但不能替代模拟器交互或真机验证。

2026-10-24：`Hetkia` 与 `HetkiaWidgetExtension` 均以 iOS 18.0 deployment target 通过通用 iOS Simulator Debug 构建，`git diff --check` 通过。该检查确认当前 SDK 下可编译并正确标注 iOS 18 最低目标，不替代 iOS 18 真机交互测试。Widget、PhotoKit、保存日记和地点基础路径使用 iOS 18 可用 API；Foundation Models 仅在 iOS 26 及以上调用，图片理解输入仅在 iOS 27 及以上调用。iOS 18 的照片地点反查走 Core Location；iOS 26 以上可使用 MapKit 新反查 API。

## 5. 目前限制与验证清单

- README 中的代表性界面截图使用仓库 `screenshot/` 下按内容命名的 JPEG（`首页.jpg`、`日记详情.jpg`、`桌面小工具.jpg`、`分享日记图片.jpeg`、`历史日记.jpg`、`设置.jpg` 等）。文件经缩放与质量压缩，单张不超过 512 KB；发布流程演示保留为 `发布到github的hugo仓库.gif`（压缩后同限）。其余截图（如 `待机小工具.jpg`、`home-empty-state.jpg`、`hugo已发文展示.jpg`）用于参考，不要求全部嵌入 README。

- BGTaskScheduler 与 WidgetKit 时间线是最佳努力刷新，无法承诺每天 00:00 准时运行。
- Widget 不使用普通滚动手势、分页按钮或轮播。`OnThisDay` 大图含统计与发布按钮，小图纯拼图；`PublishQuick` 小图含代表图与发布入口。拼图每格提供对应日期深链。
- 逐年 PhotoKit 全量查询仍从 1900 年至当前年，不因本地已有日记而跳过年份；这是为发现次年/后续新增照片并保留日记任务所需照片集合而接受的成本。缓存优先、当年增量查询、并发扫描合并和按变化更新 Widget 已减少常规启动及重复后台工作。继续评估应以真机实测为依据，不改变现有首页、详情或持久化语义。
- 完成真机检查：iOS 18 完整授权/拒绝/有限授权；仅查看后 SwiftData 与 `JournalImages` 无新记录；生成/编辑/留言会保存当前照片；次年同日新增照片并入详情；截图/录屏优先规则；Live Photo/视频首帧；满版图片卡片的文字对比与裁切；Widget 静态拼图、每张图的深链、StandBy 外观及后台刷新时机。
- 尚未验证既有安装数据的 SwiftData schema 迁移、App Store 签名与实际后台刷新表现。
