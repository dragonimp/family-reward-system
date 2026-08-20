# 家加分 MCP 工具清单

## 网关配置

- 服务名：`family-reward-mcp`
- MCP 地址：`https://happylife.ai.impx.net/api/mcp`
- 服务版本：`3.1.0`
- 工具数量：40
- 导入文件：`application/mcp/family-reward-mcp-tool-library-split.json`
- 身份参数：每个工具都必须由网关注入当前登录家长的 `username`，不得允许模型或最终用户指定他人身份。

## 概念与权限

- 家庭：当前家长自己的家庭成员和名下孩子，不随圈子切换。
- 圈子：多个家庭协作查看孩子积分的空间；旧界面和旧接口中的 `family_group`、`family_group_id` 继续作为兼容技术名。
- 默认孩子/积分查询：只返回当前家长名下孩子。
- 指定圈子查询：先校验当前家长是圈子创建者或成员，才可查看圈内孩子及余额。
- 孩子资料、积分明细、积分写入、设备、好友和申请：即使孩子在可访问圈子中，仍只允许孩子所属家长操作或查看。
- 规则：公共规则和当前家长自己的个人规则可见；其他家长的个人规则不可见。

## 完整清单

| # | 工具名 | 工具描述 |
| ---: | --- | --- |
| 1 | `family_reward_add_child` | 家庭管理/新增孩子：为当前家长创建全局孩子档案并建立所属关系，可设置初始积分、现金和物品。新孩子会同步进入该家长已创建或加入的圈子；`family_group_id` 只用于指定初始圈子且必须可访问。 |
| 2 | `family_reward_update_child` | 家庭管理/修改孩子：仅允许修改当前家长名下孩子的姓名、备注、状态和账户余额；同圈子的其他家庭只能查看。 |
| 3 | `family_reward_query_children` | 查询孩子：默认只返回当前家长名下孩子；指定 `family_group_id` 时校验圈子访问权后返回圈内全部孩子。 |
| 4 | `family_reward_list_children` | 列出孩子清单：默认列出本人名下有效孩子；指定圈子时列出该圈子全部有效孩子。 |
| 5 | `family_reward_delete_child` | 家庭管理/删除孩子所属关系：仅孩子所属家长可删除，不因圈子成员身份获得删除权。 |
| 6 | `family_reward_adjust_score` | 调整积分：仅允许给当前家长名下孩子加分或减分。 |
| 7 | `family_reward_query_score` | 查询积分余额：默认仅本人孩子；指定圈子可看圈内余额；`include_transactions` 明细仍仅孩子所属家长可看。 |
| 8 | `family_reward_log_score_record` | 写入积分明细并同步余额：仅允许操作当前家长名下孩子。 |
| 9 | `family_reward_create_record` | 新增账户记录：为本人孩子新增积分、现金或物品记录，并同步全局账户。 |
| 10 | `family_reward_update_record` | 修改账户记录：仅允许修改本人孩子记录，回滚旧影响后应用新记录。 |
| 11 | `family_reward_delete_record` | 删除账户记录：仅允许删除本人孩子记录，并回滚账户影响。 |
| 12 | `family_reward_query_operation_records` | 查询积分明细：仅查询当前家长名下孩子的积分交易，不向其他圈子成员开放。 |
| 13 | `family_reward_query_rules` | 查询规则：返回公共规则、本人个人规则和当前生效模板。 |
| 14 | `family_reward_create_rule` | 新增当前家长的个人积分规则，并自动加入个人规则模板。 |
| 15 | `family_reward_update_rule` | 修改当前家长自己的个人规则；公共规则不可修改。 |
| 16 | `family_reward_delete_rule` | 删除当前家长自己的个人规则；公共规则不可删除。 |
| 17 | `family_reward_query_family_groups` | 圈子管理/查询圈子：只返回当前家长创建或已加入的圈子，并标明管理员或成员角色。 |
| 18 | `family_reward_create_family_group` | 圈子管理/新增圈子：当前家长成为管理员，名下有效孩子同步进入新圈子。 |
| 19 | `family_reward_update_family_group` | 圈子管理/修改圈子：仅圈子创建者或 owner 管理员可修改名称和说明。 |
| 20 | `family_reward_delete_family_group` | 圈子管理/删除圈子：仅管理员可删除，不删除孩子全局档案、家庭归属和账户。 |
| 21 | `family_reward_get_family_group_invite` | 圈子管理/获取邀请码：仅管理员可生成或查看 8 位邀请码。 |
| 22 | `family_reward_join_family_group` | 圈子管理/加入圈子：使用邀请码加入，并同步当前家长名下有效孩子。 |
| 23 | `family_reward_remove_family_group_child` | 圈子管理/移除孩子：仅管理员可移出圈子，不删除孩子家庭归属和账户。 |
| 24 | `family_reward_query_family_members` | 家庭管理/查询家庭成员：仅返回当前家长自己的成员清单，不随圈子切换。 |
| 25 | `family_reward_create_family_member` | 家庭管理/新增家庭成员：只加入当前家长自己的家庭清单。 |
| 26 | `family_reward_update_family_member` | 家庭管理/修改家庭成员：仅允许修改当前家长自己的成员。 |
| 27 | `family_reward_delete_family_member` | 家庭管理/删除家庭成员：仅可删除本人家庭中的非当前用户成员。 |
| 28 | `family_reward_update_rule_template` | 规则管理/更新模板：保存有序规则清单，只能选择公共规则或本人个人规则。 |
| 29 | `family_reward_generate_child_auth_code` | 生成儿童认证码：仅孩子所属家长可为本人孩子生成手表绑定码。 |
| 30 | `family_reward_query_child_devices` | 查询孩子手表设备：仅孩子所属家长可查看本人孩子设备。 |
| 31 | `family_reward_revoke_child_device` | 解绑孩子手表：仅孩子所属家长可撤销本人孩子的设备。 |
| 32 | `family_reward_generate_device_unbind_code` | 生成设备解绑码：仅孩子所属家长可为本人孩子设备生成短期解绑码。 |
| 33 | `family_reward_query_child_friends` | 查询孩子好友：仅孩子所属家长可查看本人孩子好友和好友积分榜。 |
| 34 | `family_reward_query_friend_notifications` | 查询好友通知：只返回当前家长名下孩子收到的通知。 |
| 35 | `family_reward_mark_friend_notification_read` | 标记好友通知已读：仅允许处理当前家长名下孩子的通知。 |
| 36 | `family_reward_query_reward_requests` | 查询积分申请：只返回当前家长名下孩子提交的申请，可按圈子和状态筛选。 |
| 37 | `family_reward_approve_reward_request` | 确认积分申请：仅孩子所属家长可审批本人孩子申请并生成积分流水。 |
| 38 | `family_reward_query_circle_dashboard` | 圈子统计/查询总览：仅圈子成员可查看孩子余额和最近记录汇总。 |
| 39 | `family_reward_query_circle_leaderboard` | 圈子统计/查询积分榜：仅圈子成员可查看圈内孩子积分排名。 |
| 40 | `family_reward_query_circle_categories` | 圈子统计/查询分类汇总：仅圈子成员可查看圈内积分记录分类汇总。 |

JSON 导入文件中的每个工具还包含完整 `inputSchema`、必填字段和服务端权限说明，应以该文件为网关工具库的实际配置来源。
