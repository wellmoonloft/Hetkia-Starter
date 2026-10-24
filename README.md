# 时光 / Hetkia

时光（Hetkia）是一款专注于“历史上的今天”的 iOS 照片回忆应用。首页按设备本地日期展示历年同月同日的照片组合。浏览时只读取 PhotoKit 并按需显示系统图像；只有用户生成日记、编辑并保存文字或发布留言时，才会把日记、照片关联和 JPEG 预览保存到本机。

## 功能

- 首次启动说明并申请完整照片图库权限；授权后扫描今天及历年同日照片，显示进度并自动进入首页。
- 首页只展示“历史上的今天”。照片铺满卡片，日期以白色文字叠在图片上；照片拼贴按 1、3、5、7、9 张布局。
- 详情页支持查看照片、放大翻页、地点地图、分享图片、编辑日记、设备端 AI 草稿和留言。仅查看不创建已保存日记或 JPEG 预览。
- 设置中的“历史手札”只读取本机已保存记录，按年月分组、两列展示；卡片图片铺满，日期和照片数以白字叠加。
- 桌面大尺寸 Widget 用同日记录首图生成满版拼贴，标题与品牌名浮在图片上；StandBy/小尺寸 Widget 保持纯图片拼贴。单张图片可深链到对应日记。
- 照片、Live Photo、视频、截图和荧幕录影均可参与展示；普通相机照片优先，不排除截图或录影。隐藏照片不显示，“最近删除”不在 PhotoKit 常规图库查询中。
- 支持简体中文、繁体中文、英语、西班牙语和泰语。

照片上的文字固定使用白色并加轻微暗色渐层保证对比度。WidgetKit 会按显示情境调整小组件的渲染，但不会自动按每张照片的明暗挑选文字颜色。

## 平台与 AI

- 仅支持 iPhone 和 iPad，最低部署版本为 **iOS/iPadOS 18**；不支持 macOS 或 Mac Catalyst。
- 照片读取、系统缩略图、日记本地保存、地图、分享和 WidgetKit 等非 AI 功能可用于 iOS 18。
- Apple Foundation Models 日记文字生成需要 iOS 26 或更新版本、符合条件的设备以及已准备好的模型；项目会在用户点击生成时检查系统版本和模型状态。照片理解输入另要求 iOS 27 或更新版本。

后台刷新是系统调度的最佳努力任务，不保证恰好在午夜执行；应用前台刷新会重新查询 PhotoKit。

## 构建

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

完整产品行为见[产品需求](docs/PRODUCT_REQUIREMENTS.md)，实现结构和验证记录见[开发说明](docs/DEVELOPMENT.md)。

## 目录

```text
Hetkia-Starter/
├── Hetkia.xcodeproj/            # App 与 WidgetKit extension targets
├── Hetkia/                      # SwiftUI App、引导、详情、PhotoKit、设置与本地化
├── HetkiaWidget/                # 历史上的今天 WidgetKit
├── Design/                      # 设计源稿
└── docs/                        # 产品需求与开发说明
```
