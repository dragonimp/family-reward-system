# Linko-Family 原生 iOS 家长端

SwiftUI 原生界面，iPhone / iOS 17+。版本 1.1.1（3），Bundle ID `net.impx.happylife.parent`，可更新之前的 1.0.0 WebView 测试版。业务页面不包含 WebView。

## 原生功能

- 家庭：列表、切换、新建、邀请码加入、邀请分享。
- 孩子：列表、姓名/备注编辑、积分/零用钱/物品余额。
- 奖励：原生录入表单、现有规则选择、奖励/扣除、北京时间日期、服务端幂等记账。
- 审批：孩子奖励申请及审批备注；跨家庭显示当前家长的申请，避免遗漏。
- 记录：家长所属孩子的完整记录、分页、已加载内容搜索。
- 规则：查看公共/个人规则、新建和编辑个人规则。
- 家庭成员：列表与添加。
- 成长：原生 Charts 每日记录图、活跃/连续天数、温暖瞬间和周报。
- 手表：设备列表、扫码或输入手表配对码、主动解除绑定、生成孩子授权码。
- 账号：家长角色选择、订阅权益只读、退出与清理本机凭据。

网页管理后台、Orbit 智能体对话、支付购买入口尚未提供原生界面；不以嵌入网页冒充原生能力。删除成员/规则等操作尚未列入本版原生界面。

## 公共登录/注册

直接依赖 `../../../AgentIdentity/packages/AgentIdentity-iOS` 的 Swift Package **AgentIdentity**。系统认证窗口、注册入口、授权交接、Keychain 和退出登录属于公共用户中心 SDK；业务仓库仅调用。

服务端在 `FamilyReward.Api/Program.cs` 引用公共 `AgentIdentity.Sdk` 的 `AddAgentIdentityNativeLogin` / `MapAgentIdentityNativeLogin`。复用现有用户中心 OAuth 配置和令牌，不建业务认证体系。固定无凭据回调 `linkofamily://login-complete/`，接口地址 `https://happylife.ai.impx.net/auth/native/...`。

协议与复用示例见 [公共 SDK 文档](../../../AgentIdentity/packages/AgentIdentity-iOS/README.md)。登录凭据只保存在本机 Keychain；业务 HTTP 请求带 Bearer，不带可伪造用户身份参数。401 清除登录及业务数据，家庭切换/退出时使旧请求失效。

## 构建与签发

```sh
bash parent-app/ios/verify.sh   # 模型契约检查、禁止 WebView、模拟器构建、真机 Release 归档
bash parent-app/ios/archive.sh # 统一团队签名 helper，避免和 MyVnc 构建争用钥匙串
bash parent-app/ios/export.sh  # 按 build/ExportOptions.plist 导出，独立验证签名/profile/icon
# 已授权上传时，使用 destination=upload 的本地选项文件：
HAPPYLIFE_PARENT_EXPORT_OPTIONS="$PWD/parent-app/ios/build/UploadOptions.plist" bash parent-app/ios/export.sh
```

签名团队 `JQPH54K7SD`；已存在 App Store Connect 应用 `6812475608`；沿用已签发 profile。私钥和本地导出选项不提交。

## 本次验证记录（2026-09-16，北京时间）

- SwiftUI Simulator 构建、Release Archive、App Store 导出与独立 codesign/profile 检查通过。
- 公共授权 SDK 9 项单元/HTTP 集成测试通过：proof、过期、容量、单次领取、并发、未登录拒绝、Origin/CSRF、无凭据回调。
- 公共 .NET SDK net8.0/net10.0 与消费 API 构建通过。
- Atlas `family-reward-TASK-264` 于 08:39:34 完成受控部署；备份 `/opt/backups/family-reward/20260916083854`。
- 实际线上授权 start=200、pending poll=202、错误 proof=403、非法 challenge=400、未登录 approval=302 到 `/auth/login`。
- 模拟器已安装启动并截图原生登录页。当前电脑 UI 控制返回 `cgWindowNotFound`，未完成真实用户登录、业务写入与物理 iPhone 验收；以上构建/API 检查不能代替这些验收。
- Apple 已确认 1.1.0（2）`VALID`、`IN_BETA_TESTING`，且新构建已加入原有内部组。Build ID `03b3ed6a-c977-40cc-8037-622c94cc5c24`；结果写入忽略目录 `build/evidence/native-release-result.json`。

制品：`build/TestFlight/Linko-Family.ipa`。证据：`build/evidence/native-login.png`、`native-backend-deployment.json`。生成物不提交。

## 1.1.1（3）授权修复

- 修复公共授权页 `no-referrer` 与同源 Origin 校验冲突造成的空白 403；保持 Origin/CSRF 校验并返回可理解的失败提示。
- 成功显示“登录完成，可以关闭窗口”，保留返回客户端与关闭按钮。公共 iOS SDK 独立轮询授权结果，成功后关闭系统认证窗口。
- 登录和注册等待显示状态及取消按钮；取消会停止网络与浏览器等待、使迟到结果失效，并按 proof 撤销服务端尝试。
- 公共 .NET SDK 的同一协议已接入 MyVnc 服务端；MyVnc Windows/iOS 共用代码引用 `AgentIdentity.NativeClient`，不再在业务客户端实现挑战和轮询。
- 本版本的上传及实机验证以独立 release evidence 为准，不能沿用 1.1.0 的通过记录。

- 1.1.1（3）已由 Apple 处理 VALID 并加入原内部测试组（IN_BETA_TESTING）；Build ID `525a9de4-43e1-4bc1-a4c8-04320cbeabf4`，独立证据 `build/evidence/login-fix-release-result.json`。

## 1.1.2（4）规则响应解析修复

修复家庭首页加载孩子后弹出“服务返回的数据格式不正确”：`GET /api/rules` 的正式响应是包含 `rules` 的对象，原生客户端现在明确解析该字段。缺失字段或非数组仍报错，不把异常转换成空列表。新增非空、空列表、缺字段和非法字段类型回归；原生模型检查、Simulator 构建和 Release 归档通过。签发结果见后续发布记录；不将构建通过视为真机验证。

发布结果：2026-09-16 14:41:33 上传成功；Apple build `59db4b52-6c73-4d42-a5a7-2cd70c488667`，版本 1.1.2（4），状态 VALID，已加入既有内部测试组，独立查询为 IN_BETA_TESTING。证据保存在 `build/evidence/rules-fix-build.json`、`rules-fix-beta.json`。真机家庭首页复测尚未执行。

## 1.1.3（5）：扫码绑定与名称调整

应用显示名及产物名改为 `Linko Family`，Bundle ID 保持不变。孩子详情 → 连接手表新增原生相机扫描按钮，读取正式 `/children?watchCode=` 二维码或有效设备码，回填后仍由家长确认绑定。保留手动输入；支持取消，对无权限、不支持、扫描中断和无效二维码提供提示。新增相机用途说明及二维码解析回归测试。发布前提交并推送源码，再构建签发。公共 Swift SDK 对应 AgentIdentity GitHub main 提交 `2ac21a2097676181b2f626e24d633d821fa6e4ac`；该目录需保持与此提交一致。发布状态以 Apple 独立查询和 Atlas 发布记录为准，真机扫码尚待验收。

## 1.2.0（6）：配套且独立的 Apple Watch

统一入口为本目录 HappyLifeParent scheme；归档同时包含 iPhone 和 Watch App。Watch Target 直接引用 `watch-app/apple/HappyLifeWatch` 源文件及资产，不复制业务实现。新手表 Bundle ID 为 `net.impx.happylife.parent.watchkitapp`，配套 iPhone 为 `net.impx.happylife.parent`；`WKRunsIndependentlyOfCompanionApp=true`，不设置 `WKWatchOnly`。手表直接联网并保留独立钥匙串和扫码绑定，不共享家长令牌。

新 Watch 标识与旧独立“家加分”不是同一安装身份，旧版用户需要安装新版并重新绑定；服务端家庭和孩子数据不迁移、不删除。旧 Watch App（ASC 6812457571）的测试构建在统一版本内部可安装后按用户要求停用。旧工程保留历史用途，后续发布仅使用统一入口。

发布前运行 `verify.sh` 及 `watch-app/apple/tests/WatchAPITests.swift` 接口回归，提交推送到 GitHub 后从相同源码归档。`archive.sh` 从内到外签名，导出配置必须包含父应用和新 Watch 标识的 App Store profiles；`verify-ipa.py` 验证嵌入手表、独立运行配置、两端版本及签名。配置/编译验证不替代真机安装、家庭设置手表独立安装和绑定验收。TestFlight 申请不等于正式 App Store 上架。

## 1.2.0（7）：手表换绑与家长解绑

已绑定的 Apple Watch 可选择“更换绑定孩子”并显示新的设备码。家长扫码确认后，服务端在同一事务内撤销该手表的旧绑定并建立新绑定；新孩子已有手表或旧绑定失效时整个操作回滚。iPhone 的“手表设备”记录对有效绑定提供“解除绑定”及确认提示。手表换绑挑战连同旧令牌保存在本机 Keychain，重启后可继续轮询；新绑定成功后旧令牌失效。
