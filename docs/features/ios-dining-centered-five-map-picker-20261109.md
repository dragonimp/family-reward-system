# iOS 干饭地图列表居中与新增地图入口

## 已实现

- “带我过去”不再从单个按钮旁弹出窄 popover，改为页面中央的原生浮层。
- 浮层通过 AnchorPreference 读取下层“就吃这家”整行按钮的实际宽度和水平中心，因此左右边界与下层整行控件对齐；没有用屏幕常量猜测宽度，横竖屏/iPad 可随布局重新计算。
- 点击背景关闭，选择地图后关闭，离开页面清除；小屏可滚动，保留 70 行高及 18 字号，避免为放下五项而缩小文字。
- 顺序为高德、百度、苹果、腾讯、谷歌。名称统一 18 medium、说明 13 regular、箭头 18、图标区域 36，白底/18 圆角/柔和阴影沿用。
- 谷歌接入 comgooglemaps 原生导航，继承步行/驾车模式；导入的高德坐标先用 MapKit 唯一匹配确认 GPS 目标，不能确认则提示选择其他地图，不直接把 GCJ-02 当作 GPS。
- 原高德/百度/苹果导航逻辑、收藏页原入口及其他干饭功能保持原样。

## 腾讯：入口已完成，导航待配置

已核对腾讯当前官方 URI 调起契约：qqmap://map/routeplan 的 referer 必须为应用 Key。本工程及当前服务环境未发现对应配置；用户本轮明确答复“尚未配置”。因此腾讯行显示“导航服务尚未配置”，点击给出明确提示；没有使用示例 Key、其他应用 Key 或伪造可用状态。

已预留 URI 参数构建与安装检查声明。后续仅可为本应用配置适用的公开 URI 应用 Key，通过受控打包环境 MOMENT_TENCENT_MAP_URI_KEY 注入复制出的 App Info.plist（TencentMapsURIKey），重新构建发布并进行腾讯地图实测；不得将服务器私钥或签名 Secret 注入 App。未配置时不写该字段、不发起腾讯导航。当前不宣称腾讯导航可用。

## 文件

- parent-app/ios/HappyLifeParent/DiningView.swift：居中遮罩、基于下层控件的锚点宽度、五地图列表及新地图适配。
- parent-app/ios/HappyLifeParent/DiningModels.swift：新增地图 URL 构建及配置读取。
- parent-app/ios/HappyLifeParent/Info.plist：qqmap/comgooglemaps 查询声明。
- parent-app/ios/HappyLifeParent.xcodeproj/project.pbxproj：1.3.51（251），手机/Watch/分享扩展一致。
- parent-app/ios/Tests/DiningModelTests.swift：新增原生 URL、坐标边界、模式、名称编码和缺失配置检查。
- scripts/prepare-moment-ios-release.py：可选公开 URI Key 打包注入，未设置时移除字段。
- localization/linko-moment.v1.json 及三端中英文资源：新增地图名称、说明和状态。

安卓原未提交故障修正和 application/ocr_recipe.py 保留，本次未修改或发布安卓。后端与数据库未修改。

## 验证及发布

- 前端 lint、git diff --check 通过；最终 iOS 原生模型检查、归档、签名、导出检查通过，构建流程 exitCode 0。
- 最终源码 c7e838151ba5951d9c119ebe991885ad289da9d7，已推送 origin/main；包含无障碍 escape 关闭处理。
- 最终 iOS 1.3.51（251）；Atlas 版本 858731d9-28c0-479d-808b-216dcdbda1a6。
- IPA SHA-256：dae1e8834627b07e1e64558adcfc4fed592cdaf51017017c26632e0933543685。
- Apple 任务 f03c555d-e636-4199-8198-1b8a35d0d1a0；Apple build b2d9acbb-f8fa-4970-8ee6-4670679b35dc；VALID / testflight_visible，内部测试组可见。
- Apple 材料读回 ready=true、issues=[]，成品图标存在；中英文测试说明已保存。
- 原邀请页 https://home.ai.impx.net/invite/SW2wL0kd3pX20t6xSNLXsDK4 已同步并独立公开读回内部测试版 1.3.51（251）；Android 1.0.24（33）及外部测试入口未改。
- 中间包 1.3.50（250）仅上传 Atlas，未提交 Apple/未分发 TestFlight；它不含随后补充的 escape 处理，最终版 251 已包含。
- Atlas 正式 IPA、符号包及元数据重新下载 SHA/大小验证通过；删除本机及远端 250/251 的重复 IPA 与符号 ZIP，各端合计 45,005,630 字节，合计 90,011,260 字节。正式制品/符号仍在 Atlas；构建临时工作目录由管理器清理，保留精简回执。
- 尚未进行真机布局、腾讯/谷歌实际调起、地图安装/未安装分支验收。腾讯 Key 未配置，导航不可用；谷歌仅完成代码及参数/构建验证，不宣称实际调起已验收。
- 无 Android、后端、数据库变更；未提交外部 Beta 或 App Store 审核。

## 正式协议参考

- 腾讯 iOS 调起说明：https://lbs.qq.com/webApi/uriV1/uriGuide/uriMobileGuide
- 腾讯导航及必需 Key：https://lbs.qq.com/webApi/uriV1/uriGuide/uriMobileRoute
- 腾讯历史 URI 坐标类型说明：https://lbs.qq.com/uri_v1/guide-route.html
- Google iOS scheme：https://developers.google.com/maps/documentation/urls/ios-urlscheme

发布操作回执：

- materials-request.json: 0c4511b0-d2e3-45b3-8c70-7d1a1a8bbf65
- invitation-request.json: 904b5dbf-50a6-48bd-bbcc-ed04661e7836
