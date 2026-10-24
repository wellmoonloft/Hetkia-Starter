# 时光 / Hetkia

时光是一款“历史上的今天”原生照片回忆应用。首页按设备本地日期显示历年同月同日的照片组合。浏览时只读 PhotoKit 并即时展示；只有用户明确生成日记、编辑日记或添加留言时，才保存日记与应用 JPEG 预览。

## 当前实现

- 首次启动直接说明并申请完整照片权限；授权后查询历年同月同日照片并显示进度。不导入整图库、不预生成缩略图、不自动调用 AI。
- 首页只显示“历史上的今天”。详情按当前 PhotoKit 结果合并照片，所以已保存日记也会显示次年新增照片。仅生成日记、保存编辑或发布留言时才保存日记和 JPEG 预览。
- Application Support 只保留当天的轻量 PhotoKit 资源索引；不缓存图片副本或日记。日期/年份/时区变化时清理旧索引并重新查询。
- 包含普通照片、Live Photo、视频、截图和屏幕录影；普通相机照片优先。每日日记照片按 1/3/5/7/9 张规则选择。
- 日记详情支持图片放大翻页、地点地图、留言、分享图片和用户主动触发的设备端 AI 草稿。详情页顶部品牌名与首页共用本地化名称；照片网格与首页卡片使用相同的 12pt 内边距。地点在后台异步反查，尽量显示国家、城市和区/街区三级信息；相距 5 公里内的坐标复用一次查询结果，失败后重试，地图仍可用原始坐标打开。
- 支持 iPhone 和 iPad，并提供桌面大尺寸及 StandBy 小尺寸 Widget：桌面大尺寸显示标题、品牌名和最多五篇同日记录首图拼成的 1/3/5 张静态拼图；小尺寸只显示满版拼图，不显示文字。每张图可打开对应日期详情。Widget 不滚动、不翻页；StandBy 外观由系统处理。
- 支持简体中文、繁体中文、英语、西班牙语和泰语。

## 构建

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

最低目标为 iOS/iPadOS 27.0；当前仅支持 iPhone 和 iPad，不提供 macOS 或 Mac Catalyst 版本。模拟器运行需在 Xcode 安装 Simulator runtime。构建结果和已知边界见 [开发文档](docs/DEVELOPMENT.md)，完整产品行为见 [产品需求](docs/PRODUCT_REQUIREMENTS.md)。

## 目录

```text
Hetkia-Starter/
├── Hetkia.xcodeproj/            # App 与 WidgetKit extension targets
├── Hetkia/                      # SwiftUI App、引导、详情、PhotoKit、设置与本地化
├── HetkiaWidget/                # 历史上的今天 WidgetKit 卡片
├── Design/                      # 设计源稿
└── docs/                        # 产品需求与开发文档
```
