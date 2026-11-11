# 爬山功能交付边界

运动项目增加爬山。客户端提供当前位置搜索30公里内“山”关键词景点、选中地点5公里内其他景点、地图位置及导航。地点不等于登山路线，且不证明开放或允许攀登。GPS 输入为 WGS84，使用正式高德服务转 GCJ-02；景点周边搜索使用返回的 GCJ-02 坐标，不重复转换。

POST /api/hiking/nearby 复用现有高德受控配置、HTTP 客户端、地点解析、认证及限流；scenic=false 输入设备 GPS，scenic=true 输入高德地点坐标。没有新增付费路线/高程服务。尚需真实服务额度和授权核验及线上验收。

普通 POI 不提供可靠山峰海拔、台阶/山路、登山路线时长及开放状态，字段明确为 null / unverified；这些核心资料仍需可信景区或路线数据源，不能称为完整登山推荐库。

两个客户端可导入 GPX 轨迹/路线，限制文件大小和点数，不解析外部实体；保留轨迹段，不连接断点，使用 WGS84 地图预览。仅本次预览，不写入运动记录。最高轨迹点海拔并非山顶高度。Android 在连续、完整高程路线中提供参考移动耗时（4公里/小时＋每爬升600米1小时），不含休息和天气/路况影响；缺失数据时不估算。

高德 POI 契约：https://lbs.amap.com/api/webservice/guide/api-advanced/search
估时方法：https://www.mountaineering.scot/safety-and-skills/essential-skills/navigation/planning-and-following-a-route

当前仍需：可信山峰/路面/路线资料、GPX 恶意输入回归、iOS 完整编译与本地化、正式发布、真实位置查询与设备导入验收。不要将基础编译或地点搜索当作完整业务验收。
