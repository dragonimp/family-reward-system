# 生产数据库表抽样

生成时间：2026-07-05 21:13:29 CST

## 表清单
accounts
children
family_group_users
family_groups
redlines
rules
transactions

## accounts
-[ RECORD 1 ]-+---------------------------
id            | 1
child_id      | 1
points        | 108.00
cash_cny      | 230.00
items_count   | 2
items_detail  | 2个铲子
points_earned | 108.00
points_spent  | 0.00
cash_earned   | 300.00
cash_spent    | 70.00
created_at    | 2026-05-31 11:35:22.570713
updated_at    | 2026-05-31 11:35:22.570713
-[ RECORD 2 ]-+---------------------------
id            | 2
child_id      | 2
points        | 166.50
cash_cny      | 78.00
items_count   | 0
items_detail  | 水培栽培
points_earned | 157.50
points_spent  | 101.00
cash_earned   | 50.00
cash_spent    | 20.00
created_at    | 2026-05-31 11:35:22.570713
updated_at    | 2026-07-05 20:18:37.668552
-[ RECORD 3 ]-+---------------------------
id            | 3
child_id      | 3
points        | 100.00
cash_cny      | 0.00
items_count   | 0
items_detail  | 
points_earned | 100.00
points_spent  | 0.00
cash_earned   | 0.00
cash_spent    | 0.00
created_at    | 2026-05-31 11:35:22.570713
updated_at    | 2026-05-31 11:35:22.570713
-[ RECORD 4 ]-+---------------------------
id            | 4
child_id      | 4
points        | 100.00
cash_cny      | 0.00
items_count   | 0
items_detail  | 
points_earned | 100.00
points_spent  | 0.00
cash_earned   | 0.00
cash_spent    | 0.00
created_at    | 2026-05-31 11:35:22.570713
updated_at    | 2026-05-31 11:35:22.570713
-[ RECORD 5 ]-+---------------------------
id            | 5
child_id      | 5
points        | 100.00
cash_cny      | 0.00
items_count   | 0
items_detail  | 
points_earned | 100.00
points_spent  | 0.00
cash_earned   | 0.00
cash_spent    | 0.00
created_at    | 2026-05-31 11:35:22.570713
updated_at    | 2026-05-31 11:35:22.570713
-[ RECORD 6 ]-+---------------------------
id            | 28
child_id      | 28
points        | 100.00
cash_cny      | 0.00
items_count   | 0
items_detail  | 
points_earned | 2.00
points_spent  | 2.00
cash_earned   | 0.00
cash_spent    | 0.00
created_at    | 2026-06-28 12:11:38.295794
updated_at    | 2026-06-28 17:21:56.374061
-[ RECORD 7 ]-+---------------------------
id            | 81
child_id      | 76
points        | 100.00
cash_cny      | 0.00
items_count   | 0
items_detail  | 
points_earned | 0.00
points_spent  | 0.00
cash_earned   | 0.00
cash_spent    | 0.00
created_at    | 2026-07-05 13:54:32.724376
updated_at    | 2026-07-05 13:54:32.724376


## children
-[ RECORD 1 ]---+---------------------------
id              | 1
name            | 彦谦
status          | active
note            | 
created_at      | 2026-05-31 11:35:22.570713
updated_at      | 2026-05-31 11:35:22.570713
family_group_id | 1
-[ RECORD 2 ]---+---------------------------
id              | 2
name            | 玥玥
status          | active
note            | 
created_at      | 2026-05-31 11:35:22.570713
updated_at      | 2026-07-04 14:26:09.47153
family_group_id | 1
-[ RECORD 3 ]---+---------------------------
id              | 3
name            | 嘟嘟
status          | active
note            | 
created_at      | 2026-05-31 11:35:22.570713
updated_at      | 2026-05-31 11:35:22.570713
family_group_id | 1
-[ RECORD 4 ]---+---------------------------
id              | 4
name            | 薇薇
status          | active
note            | 
created_at      | 2026-05-31 11:35:22.570713
updated_at      | 2026-05-31 11:35:22.570713
family_group_id | 1
-[ RECORD 5 ]---+---------------------------
id              | 5
name            | 小宇
status          | active
note            | 
created_at      | 2026-05-31 11:35:22.570713
updated_at      | 2026-05-31 11:35:22.570713
family_group_id | 1
-[ RECORD 6 ]---+---------------------------
id              | 28
name            | 雨茉
status          | active
note            | 
created_at      | 2026-06-28 12:11:38.295794
updated_at      | 2026-06-28 12:51:41.450335
family_group_id | 1
-[ RECORD 7 ]---+---------------------------
id              | 76
name            | test1
status          | active
note            | 
created_at      | 2026-07-05 13:54:32.724376
updated_at      | 2026-07-05 13:54:32.724376
family_group_id | 5


## family_group_users
-[ RECORD 1 ]---+---------------------------
id              | 1
family_group_id | 1
user_id         | local-admin
role            | owner
created_at      | 2026-07-05 13:51:40.725668
updated_at      | 2026-07-05 20:18:24.681162
-[ RECORD 2 ]---+---------------------------
id              | 3
family_group_id | 1
user_id         | 2
role            | owner
created_at      | 2026-07-05 13:53:54.368785
updated_at      | 2026-07-05 13:54:01.294006
-[ RECORD 3 ]---+---------------------------
id              | 5
family_group_id | 5
user_id         | 2
role            | owner
created_at      | 2026-07-05 13:54:17.18861
updated_at      | 2026-07-05 13:54:17.18861
-[ RECORD 4 ]---+---------------------------
id              | 7
family_group_id | 1
user_id         | chopperDaShanJun
role            | owner
created_at      | 2026-07-05 13:56:37.346019
updated_at      | 2026-07-05 13:56:37.346019
-[ RECORD 5 ]---+---------------------------
id              | 9
family_group_id | 1
user_id         | 1
role            | owner
created_at      | 2026-07-05 19:58:20.860982
updated_at      | 2026-07-05 19:58:20.862656


## family_groups
-[ RECORD 1 ]---------------------------
id          | 1
name        | WWXYhome
description | 
created_by  | local-admin
created_at  | 2026-07-05 13:51:40.710832
updated_at  | 2026-07-05 20:18:24.666281
-[ RECORD 2 ]---------------------------
id          | 5
name        | test
description | 
created_by  | 2
created_at  | 2026-07-05 13:54:17.187004
updated_at  | 2026-07-05 13:54:17.187004


## redlines
-[ RECORD 1 ]--+---------------------------------------
id             | 1
order_num      | 1
rule           | 不大喊大叫
proposer       | 彦谦
description    | 无论什么原因都不允许大喊大叫、乱发脾气
penalty_points | 10
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 2 ]--+---------------------------------------
id             | 2
order_num      | 2
rule           | 不跟紧大人
proposer       | 
description    | 外出时必须紧跟父母，不得独自跑开、躲藏
penalty_points | 15
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 3 ]--+---------------------------------------
id             | 3
order_num      | 3
rule           | 不碰危险物品
proposer       | 
description    | 不碰剪刀、刀具、火源、药品、电源插座
penalty_points | 20
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 4 ]--+---------------------------------------
id             | 4
order_num      | 4
rule           | 不私自下水
proposer       | 
description    | 靠近水边必须有大人陪同，不得独自下水
penalty_points | 20
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 5 ]--+---------------------------------------
id             | 5
order_num      | 5
rule           | 不跟陌生人走
proposer       | 
description    | 无论什么理由，不得跟随陌生人离开
penalty_points | 20
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 6 ]--+---------------------------------------
id             | 6
order_num      | 6
rule           | 不打人/不骂人
proposer       | 
description    | 不得伤害他人身体或语言侮辱
penalty_points | 15
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 7 ]--+---------------------------------------
id             | 7
order_num      | 7
rule           | 不撒谎
proposer       | 
description    | 做错事必须承认，不得隐瞒欺骗
penalty_points | 10
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 8 ]--+---------------------------------------
id             | 8
order_num      | 8
rule           | 不破坏公物
proposer       | 
description    | 不得故意损坏公共设施或他人物品
penalty_points | 15
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 9 ]--+---------------------------------------
id             | 9
order_num      | 9
rule           | 不爬高危险处
proposer       | 
description    | 不攀爬栏杆、假山、树木、高楼窗户
penalty_points | 20
created_at     | 2026-05-31 11:35:22.570713
-[ RECORD 10 ]-+---------------------------------------
id             | 10
order_num      | 10
rule           | 不乱吃东西
proposer       | 
description    | 不吃陌生人给的食物，不乱吃不明物品
penalty_points | 15
created_at     | 2026-05-31 11:35:22.570713


## rules
-[ RECORD 1 ]---------------------------
id          | 1
name        | 按时/及时完成作业
category    | 学习
points      | 5.00
cash_cny    | 0.00
description | 规定时间内完成
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 2 ]---------------------------
id          | 2
name        | 主动完成作业
category    | 学习
points      | 3.00
cash_cny    | 0.00
description | 不用催促
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 3 ]---------------------------
id          | 3
name        | 作业优秀/全对
category    | 学习
points      | 2.00
cash_cny    | 0.00
description | 额外奖励
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 4 ]---------------------------
id          | 4
name        | 主动刷牙
category    | 规矩
points      | 2.00
cash_cny    | 0.00
description | 早晚各一次
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 5 ]---------------------------
id          | 5
name        | 好好吃饭
category    | 规矩
points      | 2.00
cash_cny    | 0.00
description | 不挑食、按时吃
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 6 ]---------------------------
id          | 6
name        | 自己收拾玩具
category    | 规矩
points      | 2.00
cash_cny    | 0.00
description | 玩完归位
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 7 ]---------------------------
id          | 7
name        | 按时睡觉
category    | 规矩
points      | 2.00
cash_cny    | 0.00
description | 不拖延
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 8 ]---------------------------
id          | 8
name        | 主动看书
category    | 学习
points      | 3.00
cash_cny    | 0.00
description | 自己拿起书看
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 9 ]---------------------------
id          | 9
name        | 帮忙做家务
category    | 帮忙
points      | 3.00
cash_cny    | 0.00
description | 倒垃圾、擦桌子等
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 10 ]--------------------------
id          | 10
name        | 分享玩具
category    | 规矩
points      | 2.00
cash_cny    | 0.00
description | 不抢不争
created_at  | 2026-05-31 11:35:22.570713


## transactions
-[ RECORD 1 ]---------------------------
id          | 1
date        | 2026-05-01
child_id    | 1
type        | points
direction   | +
category    | 学习
description | 按时/及时完成作业
points      | 5.00
cash_cny    | 0.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 2 ]---------------------------
id          | 2
date        | 2026-05-04
child_id    | 1
type        | points
direction   | +
category    | 学习
description | 写字课认真写
points      | 3.00
cash_cny    | 0.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 3 ]---------------------------
id          | 3
date        | 2026-05-04
child_id    | 1
type        | cash
direction   | +
category    | 历史
description | 去年搏饼获得
points      | 0.00
cash_cny    | 300.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 4 ]---------------------------
id          | 4
date        | 2026-05-04
child_id    | 1
type        | cash
direction   | -
category    | 历史
description | 沙滩买铲子花费
points      | 0.00
cash_cny    | 50.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 5 ]---------------------------
id          | 5
date        | 2026-05-04
child_id    | 1
type        | cash
direction   | -
category    | 游玩
description | 双鱼岛开红色小车
points      | 0.00
cash_cny    | 20.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 6 ]---------------------------
id          | 6
date        | 2026-05-05
child_id    | 2
type        | cash
direction   | +
category    | 初始化
description | 账户初始化
points      | 0.00
cash_cny    | 50.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 7 ]---------------------------
id          | 7
date        | 2026-05-05
child_id    | 2
type        | cash
direction   | -
category    | 游玩
description | 双鱼岛消费
points      | 0.00
cash_cny    | 20.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 8 ]---------------------------
id          | 8
date        | 2026-05-10
child_id    | 1
type        | points
direction   | +
category    | 初始化
description | 每人加100积分
points      | 100.00
cash_cny    | 0.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 9 ]---------------------------
id          | 9
date        | 2026-05-10
child_id    | 2
type        | points
direction   | +
category    | 初始化
description | 每人加100积分
points      | 100.00
cash_cny    | 0.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713
-[ RECORD 10 ]--------------------------
id          | 10
date        | 2026-05-10
child_id    | 3
type        | points
direction   | +
category    | 初始化
description | 每人加100积分
points      | 100.00
cash_cny    | 0.00
items       | 
notes       | 
created_at  | 2026-05-31 11:35:22.570713

