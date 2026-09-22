> 发布入口调整：后续使用 `parent-app/ios` 的统一 Linko Family 工程，Watch 可独立运行。旧独立“家加分”（ASC 6812457571）按用户要求停用测试分发。以下独立工程与发布记录保留历史参考，不能作为新版发布入口。详见 `../../parent-app/ios/README.md`（从仓库根目录查看）。

# 家加分 Apple Watch 儿童端

原生 SwiftUI 独立 watchOS App，最低 watchOS 10.0。复用已有 `/api/watch/*` 设备接口，不新增登录体系、不改变家庭数据或服务端部署。Apple Watch 可自行联网使用，无需安装配套 iPhone App。

## 已实现

- 手表显示设备码及二维码，家长扫码或输入设备码后选择孩子确认绑定；设备平台记录为 `watchos`。待绑定凭据保存在钥匙串，前台自动查询批准状态。
- 查询绑定儿童的积分、现金和物品数量。
- 选择家长配置的奖励规则、填写备注并提交申请；积分由服务端规则决定。
- 查询申请记录及家长审批状态；打开 App、回到前台和点击刷新时更新。
- 参考 Web 儿童端补齐爸爸妈妈的闪光时刻、今日鼓励、好友码、添加好友、好友列表和积分榜。榜单入口遵循服务端开关。
- 表盘设置复用 Web 的主题目录、已选主题和 VIP 可用性，切换后更新 App 内主题底色；VIP 权限仍由服务端判断。
- 输入家长生成的当前设备解绑码，完成服务端解绑并清除本地凭据。
- 设备令牌存入本机钥匙串，禁止迁移到其他设备；HTTPS 请求使用令牌头，不把凭据放进 URL。禁用重定向及持久网络缓存。
- 普通网络错误保留绑定；401 清除已失效绑定。提交按钮防连点，写请求不自动重试，刷新失败不提示重复提交。

界面参考 `FamilyReward.Api/Program.cs` 中 `/watch` 的积分圆环、功能名称及流程，使用原生列表与导航适配 Digital Crown。文字输入使用 watchOS 系统输入框，可调用设备提供的听写；不单独录音或接入语音服务。表盘设置作用于 App 内外观，不安装 Apple 系统表盘，也未复刻 Web 的逐帧动态背景。

## 打开与构建

使用 Xcode 打开 `HappyLifeWatch.xcodeproj`，开发手表选择共享 Scheme `HappyLifeWatch`，分发归档选择 `HappyLife`。后者使用 Xcode 官方 `watchapp2-container` 产品类型封装独立手表 App，容器不提供 iPhone 界面。服务地址位于 `HappyLifeWatch/Info.plist` 的 `HappyLifeAPIBaseURL`，与现有 `../app-config.json` 保持一致。

- 分发容器 Bundle ID：`net.impx.happylife.watch.apple`
- 手表 Bundle ID：`net.impx.happylife.watch.apple.watchkitapp`
- App 图标复用 Web 版 SVG，按 watchOS 资产规格生成 1024px 图标。

在仓库根目录运行聚焦验证：

```bash
bash watch-app/apple/verify.sh
```

脚本运行隔离的 URLProtocol 接口测试和无签名 watchOS Release 构建，不访问生产写接口、不消耗真实认证码。构建产物位于临时目录，验证后自动清理。

保留本地构建产物：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project watch-app/apple/HappyLifeWatch.xcodeproj \
  -target HappyLifeWatch -configuration Release -sdk watchos \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$PWD/watch-app/apple/build/products" \
  OBJROOT="$PWD/watch-app/apple/build/objects" build
```

该产物未签名，不能当作可安装或已发布版本。真机调试需在 Xcode 中配置自己的开发团队、注册匹配的 Bundle ID、配置签名并选择已配对的 Apple Watch。模拟器需先在 Xcode Settings > Components 安装 watchOS 运行时。

## 验证记录（北京时间 2026-09-15）

- Xcode 26.6 / watchOS 26.5 SDK：无签名 Release 构建通过。
- 接口测试通过：积分小数解码、设备令牌请求头、绑定无令牌、规则申请参数、400/401/403/500 错误、超时不重试、拒绝 HTTP。
- Web 功能契约与状态测试通过：好友、家长选项、鼓励报告、PUT 表盘设置、VIP 可用性、钥匙串恢复接口、500 保留绑定、提交成功后刷新失败不误报、401 清除全部儿童数据。
- 已安装 watchOS 26.5 模拟器运行时；Apple Watch SE 3（40mm）已完成安装、启动和绑定页面截图检查。移除 `WKWatchOnly` 与 `WKRunsIndependentlyOfCompanionApp` 同时存在的安装冲突，并加入配置校验。尚未执行真实儿童绑定、申请与审批闭环。
- 模拟器调试需保留 ad-hoc 签名（`CODE_SIGN_IDENTITY=-`）；完全禁用签名会导致钥匙串缺少 entitlement（-34018），不能用于功能验收。Release 无签名构建仅验证编译与归档，导出时仍须正式分发签名。
- H5 校验已修复：脚本改为检查实际 8:9 方形布局的 `--watch-width` 与横屏回退规则，去除旧圆形表盘的尺寸计算；`node watch-app/scripts/verify-watch-app.mjs` 通过。浏览器基于本地原始 CSS 验证 192×192、194×368、240×240、320×360、466×466、368×194 均无外框越界；未修改生产 H5 页面。

新版反向绑定实现、验证与待发布状态见 [设备绑定说明](../../docs/WATCH-DEVICE-PAIRING.md)。当前本地签名包已更新为 1.0.0（3）；以下为首版 1.0.0（1）的历史发布记录。

## TestFlight 发布记录（北京时间 2026-09-16 更新）

```bash
bash watch-app/apple/archive.sh
```

归档输出在忽略目录 `watch-app/apple/build/HappyLife.xcarchive`，包含编译后的 AppIcon 与手表应用。Xcode 26.6 编译 watchOS 图标资产时需要安装 watchOS 模拟器运行时；当前已安装并完成最终归档验证。验证截图位于忽略目录 `build/evidence/watch-40mm.png`。

已验证团队 `JQPH54K7SD` 存在有效 Apple Distribution 证书。Xcode 自动签名流程已取得上述两个 Bundle ID 的 App Store 描述文件（仅保存在本机，不入库）。2026-09-16 改用 MyVnc 已验证的团队专用签名工具后导出成功，修复此前登录钥匙串导致的 `errSecInternalComponent` 阻塞。

- 签名包：`build/TestFlight/HappyLife.ipa`，版本 1.0.0（1）。
- SHA-256：`31e60289b6c07a0fdd4bd19496e4513fe0784b47d6e4be03d0cbe78f226e5952`。
- `codesign --verify --deep --strict` 通过；父容器和手表 Bundle ID、版本读回正确。
- App Store Connect 应用记录已创建：`6812457571`（家加分）。内部组 `7bd5d1c9-7355-41b8-9cf5-93362254580a` 仅包含用户在 MyVnc 使用的内部测试账号，未开启公开链接或自动分发未来构建。
- 首次上传被 Apple 的 90334 校验拒绝：Xcode 官方容器占位程序继承了 `com.apple.MessagesApplicationStub` 签名标识。`archive.sh` 现使用同一专用密钥显式签署两层代码对象，分别写入真实 Bundle ID。`verify-ipa.py` 同时核对最终 IPA 的深层签名、签名标识、团队、描述文件、版本、独立手表模式及编译图标，防止仅凭 codesign 验证成功误判可分发性。
- 修正后的构建于北京时间 2026-09-16 01:49:29 上传，Apple 处理状态为 `VALID`。构建 ID 为 `964efced-b3f1-4ef6-b47a-4712d9f4cd66`，已加入上述内部组，独立读回 `internalBuildState=IN_BETA_TESTING`，唯一测试员状态为 `INVITED`。API 证据保存在忽略目录 `build/evidence/`。

复用 `/Users/wengzhishan/.local/share/apple-build-tools/export-ios-archive`，其内部串行使用团队专用 `ios-build.keychain-db`，自动解锁并在结束后锁定。不得嵌套 `with-team-signing`，以免文件锁死锁。不要重建或撤销现有证书，也不要放宽登录钥匙串权限。将 `ExportOptions.example.plist` 复制到忽略的 `build/` 下，填入已确认的团队 ID，然后执行：

```bash
bash watch-app/apple/export.sh
```

示例配置的 `destination=export` 只导出，不上传。授权发布时可在独立配置中明确指定 `destination=upload`。后续上传必须验证 Apple 处理完成、TestFlight 构建状态和测试设备安装，不以归档或上传命令成功代替测试完成。团队 API 角色为 Developer，网页管理能力不足时不得擅自扩权。

测试者的 iPhone 无需位于构建 Mac 附近；上传并加入测试后，在配对 Apple Watch 的 iPhone 安装 TestFlight 并接受邀请，即可进行远程安装。家加分 1.0.0（1）已可供受邀账号安装；没有公开测试链接。真机安装、绑定和业务流程仍需在用户的 Apple Watch 上验证。

## 真机与发布验收

1. 手表显示设备码和二维码，家长扫码或输入设备码并选择孩子确认，核对手表自动进入首页及家长端设备列表显示 `watchos`；另一儿童的数据不得可见。
2. 记录当前积分，按规则提交一次申请，家长审批后刷新，核对申请状态和积分变化；断网后不可自动重复提交。
3. 退出并重开验证钥匙串恢复；关闭网络验证错误提示及恢复联网后刷新；家长撤销设备后验证重新绑定。
4. 输入错误解绑码不得解绑；正确码解绑后重开 App 应显示绑定界面。
5. 在较小和较大表盘检查文字、滚动、输入、按钮防重复点击及 VoiceOver。
6. 本次已签名、上传并分发到仅供用户自己的内部 TestFlight 测试组；App Store 正式上架仍需真机验收、截图、隐私披露和正式审核。

Apple 原生独立手表应用说明：[Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)。
