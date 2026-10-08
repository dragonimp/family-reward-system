# Linko Dear：家庭与共同生活入口

Linko Dear 沿用现有家庭积分应用的安装身份和业务数据。家庭积分、亲子互动、成长记录、家族族谱继续由 FamilyReward API 管理。共同生活空间、活动、邀请和活动照片来自 Linko Social 的正式 API；Dear 不复制 Linko 的表和照片存储。

## 首批用户流程

- 家长从 Dear 进入孩子的亲子互动和家族族谱，也可以建立生活空间与活动，邀请亲友。
- 孩子使用用户中心身份进入 Dear 日常页；积分和手表业务仍由原有权限控制。
- 参与者通过用户名或七天链接确认加入活动。加入同一空间或活动不自动建立好友关系。
- 活动成员可查看 Linko Social 中的活动照片和缩略图。原图的本机传输仍由 Linko Social 客户端负责；Dear 当前不声称已接入其 P2P 原图传输。

## 身份与权限

Dear 的 `/api/dear/social/*` 是受限适配层。它使用 AgentIdentity.NativeClient 的 `NativeSsoClient`，将当前用户的 `happylife.ai` 令牌换为受众为 `linko.ai` 的服务令牌，再向 Linko Social 转发白名单接口。适配层不存储令牌，不创建账号，也不绕过 Linko Social 的空间和活动成员校验。

生产配置要求用户中心应用 `happylife.ai` 和 `linko.ai` 有同一个非空的独立 `CrossApplicationId`；两应用还必须对当前用户处于可用状态。用户中心缺少该授权时，接口明确返回 403，不回退到伪造身份或数据。

## 发布与验收

- 先核实用户中心跨应用授权及目标服务两个 `/auth/native/configuration` 的权威地址、Client ID，再部署 API 和网页。
- 真实验收使用两个不同用户中心账号：创建空间和活动、用户名邀请、对方确认、双方读取同一活动、分享照片后在 Dear 查看缩略图、撤销分享后消失。
- iOS 验收需分别检查 iPhone 和 iPad 的原生空间/活动/邀请/相册界面，Apple `VALID`、测试组可见性和实体设备操作分别记录。
- 原图本机请求、完整动态流与双方确认的好友关系仍属 Linko Social 后续能力，不能将活动成员当作好友或把缩略图当作原图存储。
