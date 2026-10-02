# Atlas 正式发布接入

跟踪任务：`family-reward-TASK-263`（`0ebc7b89-5c33-4d13-924b-c1aa41de61d5`）。

2026-09-16 用户允许本次反向绑定版本沿用现有部署脚本，并要求同时开始新部署流程。此次旧流程发布与新流程迁移分别记录，不将包装旧脚本视为 Atlas 生命周期接入完成。

## 已接入

- `deploy/atlas-release.json`：从 Atlas 实时目录核实的应用编码和 ID，无凭据。
- `scripts/build-atlas-release.sh <version> <new-output-dir>`：生成干净的 Linux x64 API 与 Web 构建，然后调用 Atlas 官方 `atlas-package-server.sh` 生成 API、Web、server-linux 三类制品、统一版本身份和 bundle 清单。
- `scripts/publish-atlas-release.sh <bundle.json>`：仅转交 Atlas Releases SDK 的 `publish-bundle`，使用专用发布凭据；不复制上传、审批或版本目录逻辑。

```bash
export PATH=/opt/homebrew/opt/node@24/bin:$PATH
bash scripts/build-atlas-release.sh 20260916-watch-pairing.2 /tmp/family-pair-atlas-final
# 凭据与服务地址通过现有授权配置注入；不能把其他应用凭据用于本应用。
# 配置就绪后执行：
# bash scripts/publish-atlas-release.sh /tmp/family-pair-atlas-final/bundle.json
```

实跑验证已通过：`20260916-watch-pairing.2` 生成三类制品及 `bundle.json`，目录 `/tmp/family-pair-atlas-final`。发布适配只完成参数/语法检查，尚未配置凭据或调用发布。该制品是接入验证快照；后续正式发布需从届时源码重新构建。

## 接下来

1. 为已核实的 `family-points` 应用配置专用发布/升级身份及最小权限，复用用户中心和 Atlas SDK。
2. 在 API 接入 Atlas Releases ASP.NET Core 的版本、排空和恢复接口；分别验证升级服务身份和普通用户授权边界。
3. 用已发布 Atlas 共享升级器建立 API/Web 统一 current 目录与单次原子切换；维护本应用配置和持久数据的边界，保留现有服务与站点配置备份。
4. 执行正式发布、升级、失败恢复和线上版本一致性验证，再把后续部署入口切换到新流程。

本次没有新建/扩权凭据，没有更改生产安装目录、Nginx 配置或旧部署入口；当前仅完成构建与发布适配，尚未进行 Atlas 生产生命周期切换。

## 2026-10-02 家加分 API 首次接管

- `family-points` 在 Atlas 绑定用户中心应用 `happylife.ai`；映射源码为 Atlas 提交 `cc306f8`，生产配置备份位于 `/opt/Atlas/backups/release-identities/release-identities-20261002T045118Z.json`。
- 用户中心一次性工具创建专用 publisher（凭据编号 58，`release:read release:upload release:publish`）及 upgrader（凭据编号 59，`release:read release:upgrade`）。私有凭据分别位于 `/etc/atlas/releases/family-points-publisher.json` 和 `family-points-upgrader.json`，没有进入仓库。数据库操作审计及备份已读回，`PRAGMA quick_check` 为 `ok`。
- 家加分源码提交 `acf12c2` 构建并发布 Atlas 版本 `20261002-green-native-login.2`。Atlas 目录读回三种制品，API 包 SHA-256 为 `67f88ac6023e225b6c1e48ce7256616806dee07bb3a0740058a2dcc61955612f`。
- 旧服务定义与三个 drop-in 通过 Atlas `backup-service` 保存于 `/opt/Atlas/backups/family-points-20261002-green-native-login-2/`。PostgreSQL `family_rewards` 的独立备份位于 `/var/lib/postgresql/family-reward-backups/20261002-green-native-login-2.dump`。版本化结构迁移执行一次、重复运行跳过；迁移前后 `rules=28`、`system_config=1`。
- Atlas `prepare-legacy-service` 后旧服务保持健康，`adopt-legacy-service` 完成首次 API 接管。运行进程的工作目录与 `ExecStart` 均使用 `/opt/Atlas/downloads/family-points-api/current`；本机版本接口返回 `family-points`、`20261002-green-native-login.2`、`ok`，公网 `/health` 正常。
- 公网 native 登录授权页使用一次临时授权请求进行渲染验证：HTTP 200，包含绿色主题 `--green:#126b50` 与品牌标记；请求随后取消。该检查验证页面样式，不代替真实审核账号的完整登录与授权测试。

此次接管仅切换 API。Web 仍由原 Nginx 目录提供；新 Web 制品虽已在 Atlas 发布，尚未由 Atlas 管理安装。后续无停机自动升级仍需接入受 `release:upgrade` 服务身份保护的 drain 控制和 Web 安装路径。
