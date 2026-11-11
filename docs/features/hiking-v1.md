# 爬山功能交付边界

运动项目增加爬山。客户端提供当前位置搜索30公里内“山”关键词景点、选中地点5公里内其他景点、地图位置及导航。地点不等于登山路线，且不证明开放或允许攀登。GPS 输入为 WGS84，使用正式高德服务转 GCJ-02；景点周边搜索使用返回的 GCJ-02 坐标，不重复转换。

POST /api/hiking/nearby 复用现有高德受控配置、HTTP 客户端、地点解析、认证及限流；scenic=false 输入设备 GPS，scenic=true 输入高德地点坐标。没有新增付费路线/高程服务。尚需真实服务额度和授权核验及线上验收。

普通 POI 不提供可靠山峰海拔、台阶/山路、登山路线时长及开放状态，字段明确为 null / unverified；这些核心资料仍需可信景区或路线数据源，不能称为完整登山推荐库。

两个客户端可导入 GPX 轨迹/路线，限制文件大小和点数，不解析外部实体；保留轨迹段，不连接断点，使用 WGS84 地图预览。仅本次预览，不写入运动记录。最高轨迹点海拔并非山顶高度。Android 在连续、完整高程路线中提供参考移动耗时（4公里/小时＋每爬升600米1小时），不含休息和天气/路况影响；缺失数据时不估算。

高德 POI 契约：https://lbs.amap.com/api/webservice/guide/api-advanced/search
估时方法：https://www.mountaineering.scot/safety-and-skills/essential-skills/navigation/planning-and-following-a-route

当前仍需：可信山峰/路面/路线资料、GPX 恶意输入回归、iOS 完整编译与本地化、正式发布、真实位置查询与设备导入验收。不要将基础编译或地点搜索当作完整业务验收。

## 2026-11-11 合并与发布

- 功能源代码 `f4b5a8829a37d17c6b3015f2d466d4886e2f1fed` 已在 GitHub main。Android 发布脚本改为从项目版本生成包名与回执，提交 `9d1dc937ee1bd4daeb0942a02bd29e2d5ab26304` 同样已推送 main。用户无关的 `application/ocr_recipe.py` 保留未提交；无新 worktree。
- 服务端 `20261111-151136-activity-f4b5a88`，部署任务 `9decae11-46bd-44e7-9bc5-a97f1afc196d` 为 stored / exitCode=0；独立读回 current 指针匹配本版本，公开健康检查正常，未登录 hiking 请求为401。此项不等于已认证的真实地点查询验收。
- iOS 1.3.52（252），Bundle ID `net.impx.happylife`，来源 f4b5a88。IPA SHA256 `3e46c5052cb75752220d4e36c70845c05ec9afd07d0f6808a7085cceaca9f273`。Atlas Apple 尝试 `2a27d07c-8361-4c9e-a319-7432cb6ed7f3` 已 VALID / testflight_visible，Apple build `c6582ae4-37a3-4835-9f26-8a8366d954d9`。中英文测试要点操作 `07364531-0a70-4975-bc8a-01e7935827b7` 已读回 ready=true；本次未提交外部 Beta 或 App Store 审核。
- 健康主题年龄分级调整的独立操作 `8530de56-99c7-4c2f-9b1d-72b046708e0e` 在 preflight_verified 后失败，读回确认未修改任何材料。正式接口源码说明 READY_FOR_SALE 的 App 信息不允许修改年龄分级；仅缩小范围补齐本版本测试要点。后续正式 App Store 草稿需按实际新增健康主题更新披露，没有创建或提交 App Store 草稿。
- Android 1.0.26（35），来源 9d1dc93。APK SHA256 `71ab95832e3d9143206ef8044de2e584660f1a759cc7c9c10a0e578d5e5e4818`，从 Atlas 下载后再次核对包名、versionName、versionCode、v2 签名及正式证书 SHA256 `4596cdb1ea8a5eea1a2567c6800d2bf4f90f051198a5518beb13abb7ac359c83`。
- 原邀请链接保持 https://home.ai.impx.net/invite/SW2wL0kd3pX20t6xSNLXsDK4 。iOS 同步操作 `3266de84-d0c7-44fa-b354-e6233850ed74`、Android 绑定操作 `9498f6d4-f239-4ef4-a485-01895952bbf2` 均 verified；公开邀请 API 独立读回内部测试 1.3.52（252）及 Android 1.0.26（35）。原外部 TestFlight 渠道未冒充新版本可用。
- 验证包含两端构建、原生模型检查、GPX 分段/非法坐标/非有限数/点数上限检查、配套274项HTTP/WebSocket检查。未执行设备定位、导航终点、GPX文件选择及运动流程的真机验收。山峰官方海拔、路面、开放状态等可信资料仍待补齐。
- Atlas 已重新读取服务端全部制品、IPA及符号文件并校验大小和 SHA256，Android 包已单独下载核验。清理本地重复包203,814,328字节、远端传输副本173,087,974字节；构建中间物由 host-build-output 清理，保留版本清单与回执，正式制品和符号仍在 Atlas。
