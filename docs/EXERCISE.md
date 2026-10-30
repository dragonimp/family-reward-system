# Moment 运动

手机端一级“运动”入口提供散步、慢跑与自由运动；开始、暂停、继续、结束并保存。时长为所有运动区间之和，排除暂停；步数来自本机系统传感器，未授权或不支持时允许单独计时，明确标注步数不可用。

## iOS

底部五个入口为群组、活动、运动、AI 对话、我的。首次开始运动时申请系统“运动与健身”权限，通过 Core Motion CMPedometer 读取本次运动各区间步数。锁屏、切换页面或应用被终止后，从保存的区间恢复计时；回前台重新读取区间步数，排除暂停时间。系统仅提供最近七天的历史步数，超过保留期的未完成区间标注步数不完整。

运动中切到后台不运行计时器保活；显示时长根据区间时间重新计算。结束时补读步数与距离后保存。不采集 GPS、健康档案、心率或手表数据。步数可能延迟，模拟器不能验证真实计步。

## Android

手机主菜单增加“运动”。使用系统 STEP_DETECTOR 和运行时 ACTIVITY_RECOGNITION 权限，记录前台运动步数。锁屏或应用进入后台自动暂停，回来后手动继续；没有后台常驻服务。进程意外终止后恢复到最近保存点的暂停状态。界面明确显示此限制。

## 存储及时间

按用户中心 unifiedUserId 派生文件名，账号分别存储；仅保存在本机应用私有目录，暂不跨设备同步。JSON 时间以 ISO 8601 UTC 保存，历史列表按设备当前时区显示，并标注“当地时间”。保存失败显示错误与重试入口；读取失败保留原文件，禁止用空记录覆盖。

## 验证

`parent-app/ios/Tests/ExerciseSessionTests.swift` 检查暂停/继续、重复操作、分段步数、结束后不可继续、序列化恢复，以及洛杉矶/东京跨日显示。构建通过统一 host-build-queue 与 host-build-output 执行，临时输出结束后自动清理。

真实手机权限允许/拒绝、连续行走步数、锁屏恢复仍需真机验收；编译和模型检查不替代传感器验收。

系统契约参考：[Apple CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)、[Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion)。

## 公里数

运动中与历史记录显示公里数，保留两位小数。iOS 读取 CMPedometer 的 distance（米）并按实际运动区间累加，再除以 1000；系统基于步行/跑步估算，非 GPS 测距。暂停区间排除，结束时补读，锁屏恢复同步读取距离。不支持距离或数据不完整时显示“距离未获取”，不将缺失数据当作零公里。已补读完整的封闭区间保留，不因七天缓存期限删除已保存数据。

Android 根据前台步数乘本次步长估算，默认 70 厘米/步，开始前可在 20–200 厘米范围调整；运动中和记录明确标注“估算”。步长随本次运动保存，暂停不累计。旧记录无距离/步长字段时可继续读取，显示“距离未获取”，不追溯编造历史公里数。没有新增定位权限。

公里数模型验证覆盖多区间求和、暂停排除、零距离、缺失数据、旧记录兼容与重启恢复。iOS 版本 1.2.57 (66)。

### 发布到现有 TestFlight 应用

`MOMENT_IOS_RELEASE_FLAVOR=existing-testflight` 使用 `scripts/build-moment-ios.sh` 为现有 `linko-family-ios` 应用生成更新包。构建在临时源码副本中映射主应用、Watch、分享扩展、App Group 和钥匙串服务到已绑定的 `net.impx.happylife.parent` 身份，保留现有安装的数据入口；主工作区为后续新应用准备的标识不变。脚本按 Bundle ID、团队、有效期、分发类型和所需能力选择本机受控签名资料，缺失时在归档前失败。IPA 校验使用同一身份，正式产物保存 release-identity.json。默认 successor 仍使用新应用身份，不静默回退。
