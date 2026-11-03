# 活动分享页：App、网页和测试安装

## 实现与权限

- 公开介绍页保留活动名称、简介和当地活动时间，提供“在 App 中打开”“继续网页版”和测试版安装入口。网页入口沿用原保护路由，不自动跳转或伪造“已安装”检测结果。
- Safari 使用 Apple Smart App Banner 指向正式新入口（Apple app 6828813434）；显式打开使用现有 linkofamily scheme，兼容两个安装身份。另为新/旧入口分别注册 linkomoment / linkomomentx 活动 Scheme，保留原登录回调。
- App 冷启动或未登录时暂存活动目标，登录及资料加载完成后切换活动页。普通活动只从当前账号可访问活动中定位；未加入时提示邀请。邀请链接先显示确认，随后调用既有受保护的接受接口，并以服务端回执进入活动。不使用分享参数直接授予成员权限。
- 浏览器未唤起 App 时显示安装与浏览器指引；网页始终可继续打开。安装后需返回原分享页再次点击，不承诺安装后的自动延迟跳转。

## 测试邀请与实际边界

安装按钮复用现有 Atlas 公开安装邀请 https://home.ai.impx.net/invite/TvXoL3UTV60fnciLC1bjISYx（公开 API 已确认应用为 linko-family-ios、iOS/Android/网页入口启用），不在活动页复制 Apple 安装地址。当前 Atlas 管理的 iOS 目的地为 https://testflight.apple.com/join/dAHHKXM7。Apple 实时网页标题为“Join the LinkoXMoment beta - TestFlight - Apple”，没有显示停止接收；现有外部邀请仍对应旧入口；Atlas 负责展示当前获取方式，不冒充新入口的公开邀请。Apple 实际可安装版本可能晚于内部测试版。

浏览器不保证能检测任意 App 安装状态；Safari 的系统横幅由操作系统处理。微信等内嵌浏览器可能限制唤起，可从菜单转系统浏览器，或继续网页。没有向联系人发送测试消息，没有宣称已完成所有浏览器/真实设备的唤起验收。

## 源码与检查

源码 `bf1e976a8a935608a393b8a4ee73371fb7235f4b` 已推送正式 origin/main。介绍页 20 项实际 HTTP 检查通过，包含 HTML 编码、App/网页/安装入口、Smart Banner、邀请保留、UUID 大小写、CSP/no-store 和无效对象。原生 ActivityLinkTests 覆盖三种 Scheme、UUID 大小写、邀请字符往返、排除登录回调、无效/重复/注入参数。两个 iOS 身份签名 archive/export 通过；服务端最终安装入口源码为后续 e721a11 提交，仅涉及 HTML 和检查，不改变 iOS 代码。服务端最终包已发布、激活并独立核验。

首次 Family bf1e976 制品已登记但未激活；发现安装地址应复用 Atlas 邀请页面后，以 e721a11 重新生成最终制品。线上 version.json 独立确认仍是原服务版本，没有为改文案重放旧部署。旧 iOS 首次提交返回 publisher_authentication / HTTP 500，读回无发布任务且主机绑定 ready 后正式提交成功，没有重复任务。

13 项初始制品（10 项 iOS 和 3 项未激活服务包）已逐件核对 Atlas 正式存储长度及 SHA-256；本地重复包和导出日志清理 50,272,142 字节，远端重复暂存清理 50,177,784 字节。保留正式 IPA、符号、元数据和检查回执；最终批次在激活完成及正式存储校验后另行清理，见下文。

## 最终服务上线

Family `20261103-123840-activity-e721a11` 已由 `family-pipeline-20261103-123840-activity-e721a11-api` 和同版本 Web journal 完成激活。公网 version.json 独立读回一致；匿名 QA 活动介绍 200，实际显示三个入口及标题，相同活动媒体仍 401。

浏览器访问主机不可用时改用原生 Chrome 新标签页核验，AX 和截图均确认活动名、App/网页/安装三个按钮及旧入口展开项可见；随后关闭本次标签页。未操作 Safari 原有认证弹窗，未改动其他浏览器页面。浏览器视觉验证仅为桌面 Chrome，不代表 iPhone/微信唤起验收。

原生复查补充了权限拒绝提示的独立展示及消息列表收起，最终 iOS 为 1.2.94（103），源码 `ec7e4efe786c05eaebafaa6ad7daceae3648786d`；1.2.93 先前已上传，按最终版本核验交付。服务器保持 e721a115b32d43e0bf0d4671ccd75681a923c158 源码，两处后续原生 UI 调整不涉及服务器。

## 最终 TestFlight 与清理

1.2.94（103）两个安装身份均经 Apple 实时 refresh 确认为 `VALID / testflight_visible`：

| 身份 | 任务 | Apple build | IPA SHA-256 |
| --- | --- | --- | --- |
| legacy | `537676b0-b02d-425d-871a-10bfa1863bb9` | `54cb634a-66bd-4ed5-91ef-212891b97036` | `af5fc5e60ea5a417b764255de680222d86a624c070bd915eb3f1db3d9d4ec2ea` |
| successor | `0e040faa-aaba-4930-b90f-be4ce22c69a9` | `5a809ca0-c177-495b-81d8-f14d935f29ae` | `5eda76c35c5d241f32483741d63bbda7c32891ff48a577ae2a4adb3ddec7aa46` |

最终批次 13 项制品（10 项 iOS 与 3 项最终服务包）已核对正式存储长度和 SHA-256，清理本地重复包/导出日志 50,273,441 字节及远端重复暂存 50,178,867 字节。两批合计本地 100,545,583 字节、远端 100,356,651 字节；构建 work 由统一输出管理清理。正式 IPA、符号、服务包与小型清单可从 Atlas 恢复。

源码分别为 iOS ec7e4efe786c05eaebafaa6ad7daceae3648786d、API/Web e721a115b32d43e0bf0d4671ccd75681a923c158，均已在正式 GitHub main 核实。没有修改无关 Android/AGENTS.md 内容或生产媒体归属，没有创建新 worktree。内部测试可见不等于公开 TestFlight 已审核相同版本；安装邀请页以 Apple 当前实际可安装版本为准。本次未提交正式 App Store 审核。
