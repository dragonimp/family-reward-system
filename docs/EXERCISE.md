# Moment 运动

手机端一级“运动”入口提供散步、慢跑与自由运动；开始、暂停、继续、结束并保存。时长为所有运动区间之和，排除暂停；步数来自本机系统传感器，未授权或不支持时允许单独计时，明确标注步数不可用。

## iOS

底部五个入口为群组、活动、运动、AI 对话、我的。首次开始运动时申请系统“运动与健身”权限，通过 Core Motion CMPedometer 读取本次运动各区间步数。锁屏、切换页面或应用被终止后，从保存的区间恢复计时；回前台重新读取区间步数，排除暂停时间。系统仅提供最近七天的历史步数，超过保留期的未完成区间标注步数不完整。

运动中切到后台不运行计时器保活；显示时长根据区间时间重新计算。结束时补读步数后保存。不采集 GPS、健康档案、心率或手表数据。步数可能延迟，模拟器不能验证真实计步。

## Android

手机主菜单增加“运动”。使用系统 STEP_DETECTOR 和运行时 ACTIVITY_RECOGNITION 权限，记录前台运动步数。锁屏或应用进入后台自动暂停，回来后手动继续；没有后台常驻服务。进程意外终止后恢复到最近保存点的暂停状态。界面明确显示此限制。

## 存储及时间

按用户中心 unifiedUserId 派生文件名，账号分别存储；仅保存在本机应用私有目录，暂不跨设备同步。JSON 时间以 ISO 8601 UTC 保存，历史列表按设备当前时区显示，并标注“当地时间”。保存失败显示错误与重试入口；读取失败保留原文件，禁止用空记录覆盖。

## 验证

`parent-app/ios/Tests/ExerciseSessionTests.swift` 检查暂停/继续、重复操作、分段步数、结束后不可继续、序列化恢复，以及洛杉矶/东京跨日显示。构建通过统一 host-build-queue 与 host-build-output 执行，临时输出结束后自动清理。

真实手机权限允许/拒绝、连续行走步数、锁屏恢复仍需真机验收；编译和模型检查不替代传感器验收。

系统契约参考：[Apple CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)、[Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion)。
