# Linko Moment 原件、公开介绍与消息列表交付

## 实现

- 分享记录系统相册 assetIdentifier、原始文件名及 App 原件副本索引，照片及视频均适用。正常请求先查副本，再直接查对应相册资源，核对大小及 SHA-256；不自动遍历全部相册。用户主动批量恢复时才扫描已授权范围。历史缺失的原始名称及相册标识无法凭空补回。
- iOS 原件下载或恢复完成后刷新列表及地图；Web 完整收到原件后更新列表，晚到的缩略图不会覆盖原件。列表使用下采样显示，保留原文件。
- 活动分享链接包括活动名称，先公开展示标题、简介和活动日期；进入后检验登录及成员/邀请权限。照片、成员、位置和原件仍受保护。时间按浏览器当前时区展示。
- Web 网格增大，窄屏单列，文字移到图下。下载请求通知及详情包含活动名称。
- iOS 消息列表支持全部已读、全部删除（确认后执行），设置收进菜单。批量操作限制当前账号及应用，防止等待令牌时切换账号的竞态。“我的”图标统一，用户名及昵称在同一文字区域上下排列。

## wzs 来源设备修正：包含视频

用户确认真实分享均来自之前成功提供原件的手机。依据完成记录，目标设备为 `4622956B-B1FC-4255-8B55-17E02680CCF5`，属于 wzs（subject 1），启用且型号为 iPhone18,1。

- Atlas 独立迁移 `linko-moment-wzs-shared-device-20261103-v1` 已一次性完成，SQL SHA-256 为 `170688b268dad8326eb49b42d06ef8bcdee67afeb797730b274b6e1dfad499c3`。
- 修改 13 项媒体来源及 2 条等待请求。独立读回：真实有效分享共 **33 项（29 张照片、4 个视频）**，全部指向目标设备；9 条当前等待请求同样归属该设备，其中 7 条原本正确。未更改状态或重发请求。
- 保留已撤销分享、完成历史、其他用户和四项合成 QA 来源。前置检查覆盖设备归属、已完成下载证据、预期数量、无活跃传输及指纹一致性。事务内保存逐项审计及执行记录；重复执行跳过，已执行内容校验和改变则拒绝。
- 备份：正式主机 `/opt/Linko/data/backups/linko-moment-wzs-shared-device-20261103-v1-20261102T174145871204Z.sqlite`，483,328 字节，SHA-256 `e8d3782357bed35bd831a7f5f22626e8a11fb33df698639cf879f327f5db20cf`。
- 回滚需新增独立迁移，依据审计 previous_device_id 恢复，先验证当前目标、无活跃传输及无后续变更；不能用整库旧备份覆盖并发新数据。本次未执行回滚。

**设备归属已修正，不代表全部原件已传输。** 当前电脑连接测试 iPhone 13（iPhone14,2），不是 wzs 原件手机；未在测试机盲扫，也未完成 wzs 手机真实原件传输复验。

## 源码与验证

已核对各自正式 origin/main 包含发布提交：

| 仓库 | 发布提交 |
| --- | --- |
| family-reward-system / iOS | `aba4281612b50bfdb6d5ce76d69caa04b8df2825` |
| Linko API / Web / 迁移 | `62e26aa08c5efea52b7694674a7ebaf7a15cccdc` |
| AgentIdentity / SDK | `30126ac58d22e8bf2215c0244efd72d94bc2f405` |

- Linko 223 项 HTTP/WebSocket 检查通过，包括公开字段白名单、UUID 大小写、租户活动绑定、照片权限及活动名称通知。
- 介绍页 12 项检查通过，包括 HTML 转义、邀请链接、当地时间、CSP/no-store、无凭据转发及无效对象。
- User Center 13 项通知检查通过，包括账号及应用隔离。Swift NotificationClient 原文件的 3 项 HTTP 契约检查通过。完整 SDK 的 macOS 测试受既有 UIKit 依赖限制，采用临时测试包隔离 HTTP 契约；两个真实 iOS archive 均编译完整 SDK。
- 相册匹配器检查通过，直接 assetIdentifier 查询用例断言不枚举全库。独立迁移检查覆盖错误归属、活跃传输、指纹不一致、重复执行及校验和变化。
- API/Web 构建、前端检查、两个 iOS 身份签名 archive/export、描述文件、Watch/Share 扩展及名称检查通过。旧安装名 Linko MomentX，新安装名 Linko Moment。
- 线上 QA 介绍 GET=200，无登录跳转且有活动标题及 og:title；同活动照片匿名 GET=401。线上 CSS 读回大图及图下文字规则；匿名批量删除消息为 401，验证时未删除真实消息。

## 正式部署与 TestFlight

| 应用 | 当前版本 | 正式操作与读回 |
| --- | --- | --- |
| Halo / User Center | `20261103-015240-activity-30126ac` | `halo-moment-inbox-189-30126ac` completed，运行版本一致 |
| Linko | `20261103-015551-activity-62e26aa` | `linko-inbox-189-62e26aa` completed，运行版本一致 |
| Family API / Web | `20261103-015632-activity-661e436` | `family-pipeline-20261103-015632-activity-661e436-api` 及同版本 Web completed，公网 version.json 一致 |

iOS **1.2.89（98）** 两个身份均实时 refresh 确认为 **VALID / testflight_visible**，源码均为上述 aba4281：

| 身份 | 发布任务 | Apple build ID |
| --- | --- | --- |
| legacy .parent | `6f775592-51da-4aa1-8b78-019a16c8ee08` | `e3e5270f-b0b3-4f5a-bc8e-54628aab324f` |
| successor | `c4dc00d2-fa10-4c2d-83e0-f71f7ecdbcc1` | `75458fea-c01f-4a15-afc1-85b356ba3957` |

IPA SHA-256：legacy `936f92b2286c8fe48b232bd855aed072f90a809ee5f6acd1e2b74268d6e852a1`；successor `83bc3d84212a4ab50320dd909d041976429459aea201152b29c0376dc8945d52`。未提交正式 App Store 审核。此前 1.2.88（97）也已可见。

首次 Linko 188 操作因旧 reporting 地址跳转而 failed-before-switch；核对终态后用现有正式 loopback 配置成功升级，未强停业务。Family 188 激活末尾仅展示的 source_commit 参数曾误传；实际冻结清单及构建为 `99159f32146c68fd7e37d240341ea96a232b802f`，未为显示字段重放部署。

## 清理与保留

- 使用统一主机队列及输出管理，构建临时目录已清理；未停止其他任务设备或清理共享原生 RTC 库。
- 188 服务重复归档本地与远端各清理 26,096,608 字节；首次失败 iOS work 清理 412,007,092 字节。
- 189 的 7 项服务制品及两个版本的 10 项 iOS 制品共 17 项，逐件核对 Atlas 正式存储长度及 SHA-256 后清理本地归档和远端重复暂存。正式 IPA、符号及服务制品可从 Atlas 恢复；保留小型源码、身份、校验清单、检查日志及回执。
- 保留数据库备份及迁移审计。Android 任务、各仓库 AGENTS.md、Linko SocialRelationships/packages.lock 等无关改动未纳入提交。本任务未创建 worktree。
