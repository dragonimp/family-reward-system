# iOS 干饭导航地图弹层样式

本次仅调整推荐餐厅卡片“带我过去”的地图选择弹层，原按钮位置、地图调用逻辑、路程模式、餐厅推荐及收藏页面的导航入口保持原样。安卓未修改；工作区原有安卓故障修正和 application/ocr_recipe.py 保留，不包含在本次提交中。

系统 Menu 无法精确控制每行字号，因此改为 SwiftUI 原生紧凑 popover，iPhone 上保持弹层呈现。

| 元素 | 实现 |
| --- | --- |
| 选择导航地图 | 18，semibold |
| 高德地图、百度地图、苹果地图 | 统一 18，medium，不设置缩小比例 |
| 地图说明 | 13，regular |
| 右侧箭头 | 18 |
| 选项行 | 70 高度 |
| 图标区域 | 36 × 36 |
| 卡片 | 白底，18 圆角，低透明度柔和阴影 |

使用现有系统符号，三个地图仍调用原 provider：amap、baidu、apple。点击选项先关闭弹层；点外部可关闭。新增标题和说明同步加入中英文资源，不删除既有翻译。

## 文件

- parent-app/ios/HappyLifeParent/DiningView.swift：替换推荐卡片中的 Menu，新增 DiningNavigationPicker 私有视图。
- parent-app/ios/HappyLifeParent.xcodeproj/project.pbxproj：iOS/Watch/分享扩展匹配版本 1.3.49（249）。
- localization/linko-moment.v1.json 与三端中英文 Localizable.strings：四条新文案。
- scripts/build-moment-ios.sh：冻结各 SDK 正式 GitHub 主分支提交，不依赖其他任务工作树当前 HEAD，不修改其工作区。

## 验证

- git diff --check、构建脚本语法检查、前端 lint 通过。
- 正式原生库来源校验、1.3.49（249）签名/包身份预检通过。
- 原生模型检查通过，覆盖干饭记录、离线原件、原文件完整性、日期/时区、运动轨迹及删除行为。
- 本次属于低影响视觉调整，不增加重复实现样式常量的测试。
- 真机弹层视觉、触摸和系统地图跳转未实测；编译、签名与 TestFlight 可获取状态分别记录，不将发布视为真机验收。

## 发布

- 构建源码 `70e0675d36ab0a24370ef31c148a11f3cfb973f7` 已推送 origin/main。
- iOS 1.3.49（249）正式签名归档及导出通过，包标识 net.impx.happylife，iPhone/Watch/分享扩展版本与分发描述文件匹配。
- Atlas版本ID `1b397343-c8d4-4c56-bd7c-855244b0ab01`，published；IPA SHA256 `35959c7ccec00b034ebf5a20073a5ec6ef44f6e2533cb42d76a374c2bcc2e67f`，12,051,492 字节。
- TestFlight尝试 `eb07e2aa-b687-492e-8be8-96b80bb05e51`，Apple处理及邀请页读回另行追加。
- IPA、符号包、源码和SDK回执均已从 Atlas 独立下载核对大小及 SHA256。正式包与符号保留在 Atlas；清理本机及远端上传暂存的重复 IPA/符号包，本机释放 22,449,516 字节，保留精简回执。构建包装器已清理本次临时源码及编译目录。
- 没有新建 worktree；原有安卓未提交修正及未跟踪 OCR 文件保持原样。
- App Store 正式审核不在本次范围。


## 最终发布读回

- Apple构建 `0f431a38-7823-42fc-8019-aea726251f1d`，VALID / testflight_visible，内部测试组可获取。
- 测试材料更新 `a596c7a8-d3dc-4390-98be-caa9507a426c` 成功；独立读回 HTTP 200、ready=true、issues=[]，目标构建图标已提取。
- 邀请同步 `8dacd562-eefd-4c8d-9d23-b84902f68d88` verified；独立查询正式状态与公开邀请页数据均为 iOS 1.3.49（249）。其他平台入口未更新。
- 更新入口：https://home.ai.impx.net/invite/SW2wL0kd3pX20t6xSNLXsDK4
- 本次未提交外部 Beta 或正式 App Store 审核。真机弹层视觉与地图跳转仍待设备验收。
