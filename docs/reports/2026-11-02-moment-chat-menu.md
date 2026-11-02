# AI 对话入口调整与安装名称

## 实现

- AI 对话从 iOS 底部 Tab 移到“我的 → 应用与设置”；底部保留成长、活动、运动、我的。
- 对话页复用账号页的 NavigationStack，保留系统返回和会话管理弹窗的独立导航。
- 旧安装显示名 Linko MomentX，新安装显示名 Linko Moment；英语与简体中文保持相同名称，iPhone/iPad 与配套 Watch 同步。
- 版本 1.2.86（95），发布源码 `387f0f851a36237f483895963a68a4826b455a6c`，已独立核实包含于 GitHub origin/main。保留用户 AGENTS.md 未提交改动。

## 验证

- 两个入口的原生模型、原图流式指纹、日期与运动会话检查通过。
- 两个入口的 Xcode Release Archive、App Store 导出、独立签名/Profile、Bundle ID、版本、英文/中文安装名称及嵌入 Watch/Share 校验通过。
- 未执行本次真实设备上的菜单进入、返回与聊天验收，签名编译不替代真实流程。
- Atlas 当前版本契约已核对：通用发布版本允许字母数字点横线下划线，Apple 版本为 2–3 段数字，Build 为数字段。1.2.86 / 95 符合。

## 发布

- successor IPA SHA-256：`ceebad299064214cb271de3aead7477f8291282feb43660f96cb295d76e77881`；attempt `fff0e7ee-7024-4f49-9b42-4ccb052d0168`。
- legacy IPA SHA-256：`4c0dfe71ce88bf1665a722f8e2a1a4c5b6a9fad453ef39d214cf1db4754f6501`；attempt `99281c0a-481a-49c4-95b6-75cea0dac286`。
- 两个入口各 5 项正式制品（IPA、符号包、源码提交、SDK 依赖及安装身份）已通过 Atlas 归档。successor 经正式下载地址独立验证长度/SHA-256；legacy 公开下载返回 404，已在正式存储路径独立核对全部 5 项长度/SHA-256，不把公开可下载与正式归档混为一谈。
- successor 已独立 refresh 读回 VALID / testflight_visible，Apple build `294b2727-33bb-4ef1-af41-c3e86df9df39`；legacy 也已独立 refresh 读回 VALID / testflight_visible，Apple build `5b1ba0be-7f78-4d92-a561-2af43c7e07db`。最终核对时间 `2026-11-03T00:02:08+08:00`。不能将 Atlas 归档或上传任务受理当作 TestFlight 可安装。

## 商店名称边界

两项名称材料更新操作 `26ea852b-5240-44ea-a7fb-231564f88b96` / `c453d08a-8c41-4b53-bf0f-54a0a6c8f896` 在 preflight_verified 后由 Atlas 正式材料接口的 ArgumentException 拒绝（HTTP 400，needs_readback）；后续独立读回确认 Apple 的 AppInfoState=READY_FOR_SALE，英文与中文名称尚未变化。当前接口仅允许可编辑 AppInfo 状态修改展示名称，并且测试要点需要 Apple 已识别的 Build。未重放操作、未提交 App Store 审核、未修改 Atlas 服务绕过校验。安装包内名称已按本次要求验证，不将其等同于商店名称修改。

## 构建与清理

两个构建通过统一 host-build-queue/host-build-output 入口。构建、签名和包校验成功；收尾管理器因 ibtoold 持有本次源码目录句柄而报告清理延后，首个任务因此未继续旧入口。核对进程及文件归属后，仅释放持有本任务目录的闲置 ibtoold，再单独排队完成旧入口。未重复构建 successor，也未停止其他任务。

已在无活动进程/开放文件后删除本次两个 work，分别释放 497,322,270 与 497,211,387 字节，共 994,533,657 字节。两项构建均在正式存储逐项校验通过后，清理本地可恢复包和导出诊断 30,597,192 字节，以及远端重复暂存文件 30,504,477 字节；仅保留小型元数据、SHA 清单、精简日志及发布回执。正式 IPA 与符号包保存在 Atlas。
