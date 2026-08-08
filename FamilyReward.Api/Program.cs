using AgentIdentity.Sdk;
using Microsoft.AspNetCore.HttpOverrides;
using System.Data;
using System.Globalization;
using System.Text.Encodings.Web;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
using NpgsqlTypes;

var apiUrls = Environment.GetEnvironmentVariable("FAMILY_REWARD_API_URLS") ?? "http://0.0.0.0:5102";
var apiUri = new Uri(apiUrls.Replace("0.0.0.0", "localhost", StringComparison.OrdinalIgnoreCase));
Environment.SetEnvironmentVariable("ASPNETCORE_URLS", apiUrls);
const string FamilyRewardMcpQueryChildrenToolName = "family_reward_query_children";
const string FamilyRewardMcpListChildrenToolName = "family_reward_list_children";
const string FamilyRewardMcpAddChildToolName = "family_reward_add_child";
const string FamilyRewardMcpUpdateChildToolName = "family_reward_update_child";
const string FamilyRewardMcpDeleteChildToolName = "family_reward_delete_child";
const string FamilyRewardMcpAdjustScoreToolName = "family_reward_adjust_score";
const string FamilyRewardMcpQueryScoreToolName = "family_reward_query_score";
const string FamilyRewardMcpCreateRecordToolName = "family_reward_create_record";
const string FamilyRewardMcpUpdateRecordToolName = "family_reward_update_record";
const string FamilyRewardMcpDeleteRecordToolName = "family_reward_delete_record";
const string FamilyRewardMcpLogScoreOperationToolName = "family_reward_log_score_record";
const string FamilyRewardMcpQueryScoreOperationToolName = "family_reward_query_operation_records";
const string FamilyRewardMcpQueryRulesToolName = "family_reward_query_rules";
const string FamilyRewardMcpCreateRuleToolName = "family_reward_create_rule";
const string FamilyRewardMcpUpdateRuleToolName = "family_reward_update_rule";
const string FamilyRewardMcpDeleteRuleToolName = "family_reward_delete_rule";
const string FamilyRewardMcpQueryFamilyGroupsToolName = "family_reward_query_family_groups";
const string FamilyRewardMcpCreateFamilyGroupToolName = "family_reward_create_family_group";
const string FamilyRewardMcpServiceName = "family-reward-mcp";
const string DefaultFamilyGroupName = "WWXYhome";
const string DefaultUserId = "local-admin";

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls(apiUrls);
builder.WebHost.ConfigureKestrel(options =>
{
    if (apiUri.Host is "127.0.0.1" or "localhost")
    {
        options.ListenLocalhost(apiUri.Port);
    }
    else
    {
        options.ListenAnyIP(apiUri.Port);
    }
});

builder.Services.AddOpenApi();
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping;
});
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});
builder.Services.AddHttpClient();
builder.Services.AddAgentIdentityJwtCookieAuthentication(new AgentIdentityOptions
{
    Authority = (Environment.GetEnvironmentVariable("AGENTIDENTITY_AUTHORITY") ?? "https://auth.ai.xmkurt.com").TrimEnd('/'),
    ClientId = Environment.GetEnvironmentVariable("AGENTIDENTITY_CLIENT_ID") ?? "happylife.ai",
    CookieName = Environment.GetEnvironmentVariable("AGENTIDENTITY_COOKIE_NAME") ?? "happylife_access_token",
    LogoutCompletedPath = "/auth/logged-out"
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost
});
app.UseCors();
app.UseAgentIdentity();
app.MapAgentIdentityAuthEndpoints();

var connectionString = BuildConnectionString(builder.Configuration);
await InitDatabase(connectionString);

app.MapGet("/health", () => Results.Json(new
{
    status = "ok",
    version = "3.0.0",
    stack = "aspnet-core",
    db = "postgresql"
}));

app.MapGet("/watch/manifest.json", (HttpRequest request) => Results.Json(BuildWatchWebManifest(request)));
app.MapGet("/api/watch/app-info", (HttpRequest request) => Results.Json(BuildWatchAppInfo(request)));
app.MapGet("/watch/icon.svg", () => Results.Content("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
      <rect width="512" height="512" rx="96" fill="#16643a"/>
      <circle cx="256" cy="256" r="162" fill="#eef5ef"/>
      <path d="M174 270l50 50 116-134" fill="none" stroke="#16643a" stroke-width="42" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M184 58h144l24 72H160l24-72zm-24 324h192l-24 72H184l-24-72z" fill="#8fd19e"/>
    </svg>
    """, "image/svg+xml; charset=utf-8"));

app.MapGet("/api/user/profile", async (HttpRequest request) =>
{
    if (!HasUnifiedIdentity(request))
    {
        return Results.Json(new { error = "请先登录", code = "login_required" }, statusCode: StatusCodes.Status401Unauthorized);
    }
    var channel = NormalizeIdentityChannel(request.Query.String("channel"), IsWatchRequest(request) ? "watch" : "pc");
    var role = NormalizeAppRole(request.Query.String("role"));
    var autoCreate = channel == "watch" || string.Equals(request.Query.String("autoCreate"), "true", StringComparison.OrdinalIgnoreCase);
    var profile = await GetOrCreateAppUserProfile(connectionString, request, channel, role, autoCreate);
    return Results.Json(profile);
});

app.MapPost("/api/user/profile", async (JsonObject body, HttpRequest request) =>
{
    if (!HasUnifiedIdentity(request))
    {
        return Results.Json(new { error = "请先登录", code = "login_required" }, statusCode: StatusCodes.Status401Unauthorized);
    }
    var channel = NormalizeIdentityChannel(body.String("channel"), IsWatchRequest(request) ? "watch" : "pc");
    var role = NormalizeAppRole(body.String("role"));
    if (string.IsNullOrWhiteSpace(role))
    {
        return Results.BadRequest(new { error = "请选择身份" });
    }

    var profile = await GetOrCreateAppUserProfile(connectionString, request, channel, role, autoCreate: true, body);
    return Results.Json(profile);
});

app.MapGet("/api/family-groups", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    return Results.Json(await GetFamilyGroups(connectionString, access.Profile!.AppUserId));
});

app.MapPost("/api/family-groups", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var userId = body.String("user_id");
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = body.String("userId");
    }
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = access.Profile!.AppUserId;
    }

    var created = await CreateFamilyGroup(connectionString, body.String("name"), userId, body.String("description"));
    if (!created.Success)
    {
        return Results.BadRequest(new { error = created.Error });
    }

    return Results.Created($"/api/family-groups/{GetInt(created.Group!, "id")}", created.Group);
});

app.MapGet("/api/family-groups/{id:int}/invite", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var invite = await GetOrCreateFamilyGroupInvite(connectionString, id, access.Profile!.AppUserId);
    if (!invite.Success)
    {
        return invite.Forbidden
            ? Results.Json(new { error = invite.Error }, statusCode: StatusCodes.Status403Forbidden)
            : Results.NotFound(new { error = invite.Error });
    }

    var origin = $"{request.Scheme}://{request.Host}";
    var inviteUrl = $"{origin}/family-groups?inviteCode={invite.InviteCode}";
    return Results.Json(new
    {
        familyGroupId = id,
        familyGroupName = invite.FamilyGroupName,
        inviteCode = invite.InviteCode,
        inviteUrl,
        qrImageUrl = $"https://api.qrserver.com/v1/create-qr-code/?size=180x180&data={Uri.EscapeDataString(inviteUrl)}"
    });
});

app.MapPost("/api/family-groups/join", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var inviteCode = body.String("invite_code");
    if (string.IsNullOrWhiteSpace(inviteCode))
    {
        inviteCode = body.String("inviteCode");
    }
    inviteCode = NormalizeFamilyGroupInviteCode(inviteCode);
    if (inviteCode.Length != 8 || inviteCode.Any(ch => !char.IsAsciiDigit(ch)))
    {
        return Results.BadRequest(new { error = "请输入 8 位数字邀请码" });
    }

    var joined = await JoinFamilyGroupByInviteCode(connectionString, inviteCode, access.Profile!.AppUserId);
    return joined.Success
        ? Results.Json(new
        {
            ok = true,
            familyGroupId = joined.FamilyGroupId,
            familyGroupName = joined.FamilyGroupName,
            linkedChildCount = joined.LinkedChildCount
        })
        : Results.NotFound(new { error = joined.Error });
});

app.MapPut("/api/family-groups/{id:int}/users", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var userId = body.String("user_id");
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = body.String("userId");
    }
    if (string.IsNullOrWhiteSpace(userId))
    {
        return Results.BadRequest(new { error = "缺少 userId" });
    }

    var role = body.String("role", "member");
    var linked = await UpsertFamilyGroupUser(connectionString, id, userId, role);
    return linked ? Results.Json(new { ok = true }) : Results.NotFound(new { error = "家庭组不存在" });
});

app.MapGet("/api/children", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    return Results.Json(await GetChildren(connectionString, familyGroupId));
});

app.MapGet("/api/children/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var child = (await GetChildren(connectionString, familyGroupId)).FirstOrDefault(c => GetInt(c, "id") == id);
    return child is null ? Results.NotFound(new { error = "不存在" }) : Results.Json(child);
});

app.MapGet("/api/watch/score", async (HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request);
    if (binding.Error is not null) return binding.Error;
    var device = binding.Binding!;
    var children = await GetChildren(connectionString, device.FamilyGroupId, device.ChildProfileKey);
    var familyGroupName = children
        .Select(c => Convert.ToString(c["familyGroupName"], CultureInfo.InvariantCulture) ?? "")
        .FirstOrDefault(name => !string.IsNullOrWhiteSpace(name)) ?? "";
    return Results.Json(new
    {
        familyGroupId = device.FamilyGroupId,
        familyGroupName,
        deviceId = device.Id,
        updatedAt = DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture),
        children = children.Select(c => new
        {
            id = GetInt(c, "id"),
            name = Convert.ToString(c["name"], CultureInfo.InvariantCulture) ?? "",
            points = GetDecimal(c, "score"),
            cash = GetDecimal(c, "cash"),
            items = GetInt(c, "items")
        })
    });
});

app.MapGet("/api/watch/rules", async (HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request, touch: false);
    if (binding.Error is not null) return binding.Error;
    var rulesPayload = await GetRules(connectionString);
    var rules = ((List<Dictionary<string, object?>>)rulesPayload["rules"])
        .Where(rule => GetDecimal(rule, "points") > 0)
        .Select(rule => new
        {
            id = GetInt(rule, "id"),
            name = Convert.ToString(rule["name"], CultureInfo.InvariantCulture) ?? "",
            category = Convert.ToString(rule["category"], CultureInfo.InvariantCulture) ?? "",
            points = GetDecimal(rule, "points"),
            description = Convert.ToString(rule["description"], CultureInfo.InvariantCulture) ?? ""
        });
    return Results.Json(new { rules });
});

app.MapGet("/api/watch/requests", async (HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request);
    if (binding.Error is not null) return binding.Error;
    var device = binding.Binding!;
    var childId = request.Query.Int("childId") ?? request.Query.Int("child_id");
    var limit = Math.Clamp(request.Query.Int("limit") ?? 20, 1, 50);
    return Results.Json(new
    {
        familyGroupId = device.FamilyGroupId,
        requests = await GetWatchRewardRequests(connectionString, device.FamilyGroupId, childId, limit, device.ChildProfileKey)
    });
});

app.MapPost("/api/watch/requests", async (JsonObject body, HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request);
    if (binding.Error is not null) return binding.Error;
    var device = binding.Binding!;
    body["child_id"] = device.ChildId;
    body["family_group_id"] = device.FamilyGroupId;
    var result = await CreateWatchRewardRequest(connectionString, body, device.FamilyGroupId, $"watch-device:{device.Id}", device.ChildProfileKey);
    return result.ContainsKey("error")
        ? Results.BadRequest(result)
        : Results.Created($"/api/watch/requests/{GetInt(result, "id")}", result);
});

app.MapPost("/api/watch/device-bind", async (JsonObject body, HttpRequest request) =>
{
    var result = await BindWatchDevice(connectionString, body, request);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPost("/api/watch/device-unbind", async (JsonObject body, HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request, touch: false);
    if (binding.Error is not null) return binding.Error;
    var result = await UnbindWatchDeviceWithCode(connectionString, binding.Binding!, body.String("code"));
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPost("/api/watch/requests/{id:int}/approve", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    var result = await ApproveWatchRewardRequest(connectionString, id, familyGroupId, body.String("reviewNote"));
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapGet("/watch", () =>
{
    var html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <meta name="theme-color" content="#16643a">
          <meta name="mobile-web-app-capable" content="yes">
          <link rel="manifest" href="/watch/manifest.json">
          <link rel="icon" href="/watch/icon.svg" type="image/svg+xml">
          <title>手表积分</title>
          <style>
            *{box-sizing:border-box}body{min-height:100vh;margin:0;overflow-x:hidden;background:#dce8e2;color:#102019;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.wrap{width:min(100vw,390px);margin:0 auto;padding:10px 9px}.watch-shell{position:relative;margin:0 auto;width:min(calc(100vw - 52px),346px);max-width:346px}.watch-face{position:relative;aspect-ratio:1/1;overflow:hidden;border-radius:50%;border:10px solid #17231b;background:#f9fbf7;box-shadow:0 12px 30px rgba(16,32,25,.2),inset 0 0 0 1px #cad7ce}.watch-face:before{content:"";position:absolute;inset:14px;border:1px solid #d8e2dc;border-radius:50%;pointer-events:none}.screen{position:absolute;inset:24px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}.topline{position:absolute;top:23px;left:58px;right:58px;display:flex;align-items:center;justify-content:center;gap:4px;color:#65736b;font-size:11px;white-space:nowrap}.brand{font-size:12px;font-weight:900;color:#245138;letter-spacing:0}.home-child{max-width:170px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:24px;font-weight:900}.score-ring{display:grid;place-items:center;width:150px;height:150px;margin:10px 0 6px;border-radius:50%;border:7px solid #1f7a48;background:#fff}.score{width:100%;padding:0 4px;color:#0c6f3b;font-size:clamp(28px,10vw,38px);font-variant-numeric:tabular-nums;font-weight:900;letter-spacing:-1.5px;line-height:.95;white-space:nowrap}.unit{margin-top:5px;color:#5c6b62;font-size:12px;font-weight:800}.metric-row{display:grid;grid-template-columns:1fr 1fr;gap:6px;width:170px}.metric{min-width:0;border:1px solid #d7e1da;border-radius:8px;padding:5px 6px;background:#eef5f0}.metric b{display:block;color:#24352b;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.metric span{display:block;margin-top:1px;color:#65736b;font-size:10px}.menu-dock{position:absolute;right:-3px;top:50%;z-index:3;display:grid;gap:6px;transform:translateY(-50%)}.menu-btn{display:grid;place-items:center;width:42px;height:42px;border:2px solid #17231b;border-radius:50%;background:#fff;color:#17231b;font-size:11px;font-weight:900;box-shadow:0 4px 10px rgba(16,32,25,.16)}.menu-btn.active{background:#1f7a48;color:#fff}.panel{display:none;width:205px;max-height:222px;overflow:auto;text-align:left}.panel.active{display:block}.panel[data-panel=home],#bind-panel .panel{text-align:center}.panel h1,.panel h2{margin:0 0 8px;text-align:center;font-size:18px;line-height:1.1}.bind-title{font-size:20px;font-weight:900}.bind-sub{margin:5px 0 10px;color:#65736b;font-size:12px}.rules{display:grid;gap:6px}.rule-btn{display:flex;align-items:center;justify-content:space-between;gap:6px;width:100%;min-height:34px;border:1px solid #d3ded7;border-radius:8px;background:#fff;color:#17231b;padding:6px 8px;font-size:12px;text-align:left}.rule-btn span{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rule-btn b{color:#0c6f3b;white-space:nowrap}label{display:block;margin:7px 0 3px;color:#44544a;font-size:11px;font-weight:700}input,textarea{width:100%;border:1px solid #cbd8cf;border-radius:8px;background:#fff;color:#17231b;padding:7px;font-size:14px}textarea{min-height:44px;resize:vertical}.submit,.ghost{width:100%;margin-top:8px;border:0;border-radius:8px;padding:9px;font-size:14px;font-weight:900}.submit{background:#1f7a48;color:#fff}.ghost{background:#e7efe9;color:#17462c}.msg{min-height:16px;margin:6px 0 0;text-align:center;color:#16643a;font-size:11px}.requests{list-style:none;margin:0;padding:0;display:grid;gap:5px}.requests li{display:grid;grid-template-columns:1fr auto;gap:6px;border-top:1px solid #e3ebe6;padding-top:5px;color:#25362c;font-size:11px}.requests span{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.requests b{color:#71601b;white-space:nowrap}.empty,.empty-row{color:#64746a;text-align:center;font-size:12px}.code{text-align:center;letter-spacing:3px;font-size:22px;font-weight:900;text-transform:uppercase}.hidden{display:none!important}@media(max-width:260px){.wrap{padding:6px}.watch-face{border-width:8px}.screen{inset:20px}.topline{top:20px;left:48px;right:48px;font-size:10px}.home-child{font-size:20px}.score-ring{width:112px;height:112px}.score{font-size:28px;padding:0 2px}.metric-row{width:148px}.panel{width:176px;max-height:192px}.panel h1,.panel h2{font-size:16px}.menu-btn{width:35px;height:35px;font-size:10px}.rules{gap:4px}input,textarea{font-size:13px;padding:6px}}
          </style>
        </head>
        <body>
          <main class="wrap">
            <div class="watch-shell">
              <div class="watch-face">
                <div class="topline"><span class="brand">家加分</span><span id="updated-at"></span></div>
                <section class="screen" id="bind-panel">
                  <div class="panel active">
                    <div class="bind-title">设备绑定</div>
                    <p class="bind-sub">儿童认证码登录</p>
                    <form id="bind-form">
                      <label for="auth-code">认证码</label>
                      <input id="auth-code" name="code" class="code" maxlength="12" autocomplete="one-time-code" placeholder="输入">
                      <button class="submit" type="submit">绑定</button>
                      <p id="bind-msg" class="msg"></p>
                    </form>
                  </div>
                </section>
                <section class="screen hidden" id="app-panel">
                  <div class="panel active" data-panel="home">
                    <div class="home-child" id="child-name">--</div>
                    <div class="score-ring">
                      <div><div class="score" id="score">0</div><div class="unit">积分</div></div>
                    </div>
                    <div class="metric-row">
                      <div class="metric"><b id="cash">0</b><span>现金</span></div>
                      <div class="metric"><b id="items">0</b><span>物品</span></div>
                    </div>
                  </div>
                  <div class="panel" data-panel="request">
                    <h2>申请奖励</h2>
                    <form id="request-form">
                      <input type="hidden" name="rule_id" id="rule-id">
                      <div class="rules" id="rules"></div>
                      <label for="title">申请事项</label>
                      <input id="title" name="title" maxlength="80" placeholder="比如 好好吃饭">
                      <label for="points">积分</label>
                      <input id="points" name="points" inputmode="decimal" placeholder="比如 5">
                      <label for="note">说明</label>
                      <textarea id="note" name="note" maxlength="200" placeholder="可以写一句说明"></textarea>
                      <button class="submit" type="submit">提交</button>
                      <p id="msg" class="msg"></p>
                    </form>
                  </div>
                  <div class="panel" data-panel="requests">
                    <h2>最近申请</h2>
                    <ul class="requests" id="requests"></ul>
                  </div>
                  <div class="panel" data-panel="device">
                    <h2>设备</h2>
                    <div class="requests">
                      <li><span>绑定状态</span><b>已绑定</b></li>
                      <li><span>设备</span><b id="device-id">--</b></li>
                    </div>
                    <label for="unbind-code">家长端解绑认证码</label>
                    <input id="unbind-code" class="code" maxlength="12" autocomplete="one-time-code" placeholder="输入">
                    <button class="ghost" id="unbind" type="button">解除绑定</button>
                    <p id="unbind-msg" class="msg"></p>
                  </div>
                </section>
              </div>
              <nav class="menu-dock hidden" id="menu" aria-label="功能菜单">
                <button class="menu-btn active" type="button" data-view="home">积分</button>
                <button class="menu-btn" type="button" data-view="request">申请</button>
                <button class="menu-btn" type="button" data-view="requests">记录</button>
                <button class="menu-btn" type="button" data-view="device">设备</button>
              </nav>
            </div>
          </main>
          <script>
            const form = document.getElementById('request-form');
            const msg = document.getElementById('msg');
            const bindForm = document.getElementById('bind-form');
            const bindMsg = document.getElementById('bind-msg');
            const tokenKey = 'happylife_watch_device_token';
            const token = () => localStorage.getItem(tokenKey) || '';
            const authHeaders = () => ({ 'X-Watch-Device-Token': token() });
            const escapeText = (value) => String(value || '').replace(/[&<>"']/g, (ch) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
            const formatPoints = (value) => {
              const points = Number(value);
              return Number.isFinite(points)
                ? points.toLocaleString('zh-CN', { useGrouping: false, minimumFractionDigits: 0, maximumFractionDigits: 1 })
                : '0';
            };
            const showBound = (bound) => {
              document.getElementById('bind-panel').classList.toggle('hidden', bound);
              document.getElementById('app-panel').classList.toggle('hidden', !bound);
              document.getElementById('menu').classList.toggle('hidden', !bound);
            };
            const setView = (view) => {
              document.querySelectorAll('[data-panel]').forEach((panel) => panel.classList.toggle('active', panel.dataset.panel === view));
              document.querySelectorAll('.menu-btn').forEach((button) => button.classList.toggle('active', button.dataset.view === view));
            };
            const fetchJson = async (url, options = {}) => {
              const response = await fetch(url, options);
              const payload = await response.json().catch(() => ({}));
              if (!response.ok) throw new Error(payload.error || '请求失败');
              return payload;
            };
            const load = async () => {
              if (!token()) { showBound(false); return; }
              try {
                const [score, rulesPayload, requestsPayload] = await Promise.all([
                  fetchJson('/api/watch/score', { headers: authHeaders() }),
                  fetchJson('/api/watch/rules', { headers: authHeaders() }),
                  fetchJson('/api/watch/requests?limit=6', { headers: authHeaders() })
                ]);
                showBound(true);
                const child = (score.children || [])[0] || {};
                document.getElementById('updated-at').textContent = new Date(score.updatedAt).toLocaleTimeString('zh-CN', { hour12: false, hour: '2-digit', minute: '2-digit' });
                document.getElementById('child-name').textContent = child.name || '暂无孩子';
                document.getElementById('score').textContent = formatPoints(child.points);
                document.getElementById('cash').textContent = child.cash ?? 0;
                document.getElementById('items').textContent = child.items ?? 0;
                document.getElementById('device-id').textContent = '#' + escapeText(score.deviceId);
                document.getElementById('rules').innerHTML = (rulesPayload.rules || []).slice(0, 8).map((rule) => `
                  <button type="button" class="rule-btn" data-rule-id="${rule.id}" data-points="${rule.points}" data-title="${escapeText(rule.name)}">
                    <span>${escapeText(rule.name)}</span><b>+${escapeText(rule.points)}</b>
                  </button>`).join('') || '<div class="empty">暂无可申请规则</div>';
                document.querySelectorAll('.rule-btn').forEach((button) => {
                  button.addEventListener('click', () => {
                    document.getElementById('rule-id').value = button.dataset.ruleId || '';
                    document.getElementById('title').value = button.dataset.title || '';
                    document.getElementById('points').value = button.dataset.points || '';
                  });
                });
                document.getElementById('requests').innerHTML = (requestsPayload.requests || []).map((item) => `
                  <li><span>${escapeText(item.childName)} · ${escapeText(item.title)}</span><b>${escapeText(item.statusText)}</b></li>`).join('') || '<li class="empty-row">暂无申请</li>';
              } catch (error) {
                localStorage.removeItem(tokenKey);
                showBound(false);
                bindMsg.textContent = error.message || '请重新绑定';
              }
            };
            bindForm.addEventListener('submit', async (event) => {
              event.preventDefault();
              bindMsg.textContent = '正在绑定...';
              try {
                const payload = await fetchJson('/api/watch/device-bind', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ code: document.getElementById('auth-code').value, deviceName: navigator.userAgent })
                });
                localStorage.setItem(tokenKey, payload.deviceToken);
                bindMsg.textContent = '';
                await load();
              } catch (error) {
                bindMsg.textContent = error.message || '绑定失败';
              }
            });
            form.addEventListener('submit', async (event) => {
              event.preventDefault();
              msg.textContent = '正在提交...';
              const data = Object.fromEntries(new FormData(form).entries());
              try {
                const response = await fetch('/api/watch/requests', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', ...authHeaders() },
                  body: JSON.stringify(data)
                });
                const payload = await response.json();
                if (!response.ok) throw new Error(payload.error || '提交失败');
                msg.textContent = '已提交，等待家长确认';
                form.reset();
                document.getElementById('rule-id').value = '';
                await load();
                setView('requests');
              } catch (error) {
                msg.textContent = error.message || '提交失败';
              }
            });
            document.getElementById('unbind').addEventListener('click', async () => {
              const unbindMsg = document.getElementById('unbind-msg');
              unbindMsg.textContent = '正在验证...';
              try {
                await fetchJson('/api/watch/device-unbind', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', ...authHeaders() },
                  body: JSON.stringify({ code: document.getElementById('unbind-code').value })
                });
                localStorage.removeItem(tokenKey);
                location.reload();
              } catch (error) {
                unbindMsg.textContent = error.message || '解绑失败';
              }
            });
            document.querySelectorAll('.menu-btn').forEach((button) => {
              button.addEventListener('click', () => setView(button.dataset.view || 'home'));
            });
            load();
          </script>
        </body>
        </html>
        """;
    return Results.Content(html, "text/html; charset=utf-8");
});

app.MapPost("/api/children", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    body["user_id"] = access.Profile!.AppUserId;
    body["parent_app_user_id"] = access.Profile!.AppUserId;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    var created = await CreateChildCore(connectionString, body, familyGroupId);
    if (!created.Success)
    {
        return Results.BadRequest(new { error = created.Error });
    }
    return Results.Created($"/api/children/{GetInt(created.Child!, "id")}", created.Child);
});

app.MapPut("/api/children/{id:int}", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    await using var cmd = new NpgsqlCommand("""
        SELECT c.profile_key
        FROM children c
        JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
        WHERE c.id = @id
          AND c.family_group_id = @family_group_id
          AND cub.parent_app_user_id = @parent_app_user_id
        LIMIT 1
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.AddWithValue("parent_app_user_id", access.Profile!.AppUserId);
    var profileKeyValue = await cmd.ExecuteScalarAsync();
    if (profileKeyValue is null || profileKeyValue is DBNull)
    {
        await tx.RollbackAsync();
        return Results.Json(new { error = "孩子不存在，或只有孩子的所属账号可以修改全局信息" }, statusCode: StatusCodes.Status403Forbidden);
    }
    var profileKey = Convert.ToString(profileKeyValue, CultureInfo.InvariantCulture) ?? "";

    await using (var profileCmd = new NpgsqlCommand("""
        UPDATE child_profiles
        SET name = @name, note = @note, status = @status, updated_at = CURRENT_TIMESTAMP
        WHERE profile_key = @profile_key
        """, conn, tx))
    {
        profileCmd.Parameters.AddWithValue("profile_key", profileKey);
        profileCmd.Parameters.AddWithValue("name", body.String("name"));
        profileCmd.Parameters.AddWithValue("note", body.String("note"));
        profileCmd.Parameters.AddWithValue("status", body.String("status", "active"));
        await profileCmd.ExecuteNonQueryAsync();
    }

    await using (var membershipCmd = new NpgsqlCommand("""
        UPDATE children
        SET name = @name, note = @note, status = @status, updated_at = CURRENT_TIMESTAMP
        WHERE profile_key = @profile_key
        """, conn, tx))
    {
        membershipCmd.Parameters.AddWithValue("profile_key", profileKey);
        membershipCmd.Parameters.AddWithValue("name", body.String("name"));
        membershipCmd.Parameters.AddWithValue("note", body.String("note"));
        membershipCmd.Parameters.AddWithValue("status", body.String("status", "active"));
        await membershipCmd.ExecuteNonQueryAsync();
    }

    await using var accountCmd = new NpgsqlCommand("""
        INSERT INTO accounts (child_id, profile_key, points, cash_cny, items_count)
        SELECT @child_id, profile_key, COALESCE(@points, 0), COALESCE(@cash_cny, 0), COALESCE(@items_count, 0)
        FROM children
        WHERE id = @child_id
        ON CONFLICT (profile_key) DO UPDATE SET
            points = COALESCE(@points, accounts.points),
            cash_cny = COALESCE(@cash_cny, accounts.cash_cny),
            items_count = COALESCE(@items_count, accounts.items_count),
            updated_at = CURRENT_TIMESTAMP
        """, conn, tx);
    accountCmd.Parameters.AddWithValue("child_id", id);
    accountCmd.Parameters.AddWithValue("points", body.Decimal("score") is decimal score ? score : DBNull.Value);
    accountCmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash") is decimal cash ? cash : DBNull.Value);
    accountCmd.Parameters.AddWithValue("items_count", body.Int("items") is int items ? items : DBNull.Value);
    await accountCmd.ExecuteNonQueryAsync();
    await tx.CommitAsync();

    var updated = (await GetChildren(connectionString, familyGroupId)).First(c => GetInt(c, "id") == id);
    return Results.Json(updated);
});

app.MapDelete("/api/children/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var result = await DeleteChildMembership(connectionString, id, familyGroupId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapPost("/api/children/{id:int}/auth-code", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    var minutes = Math.Clamp(body.Int("expiresInMinutes") ?? 24 * 60, 10, 24 * 60);
    var result = await CreateChildAuthCode(connectionString, id, familyGroupId, access.Profile!.AppUserId, minutes);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapGet("/api/children/{id:int}/devices", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var result = await GetChildWatchDevices(connectionString, id, familyGroupId, access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapDelete("/api/children/{id:int}/devices/{deviceId:int}", async (int id, int deviceId, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var result = await RevokeChildWatchDevice(connectionString, id, deviceId, familyGroupId, access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapPost("/api/children/{id:int}/devices/{deviceId:int}/unbind-code", async (int id, int deviceId, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    var minutes = Math.Clamp(body.Int("expiresInMinutes") ?? 10, 5, 30);
    var result = await CreateWatchDeviceUnbindCode(connectionString, id, deviceId, familyGroupId, access.Profile!.AppUserId, minutes);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapGet("/api/transactions", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var query = request.Query;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var childId = query.Int("childId") ?? query.Int("child_id");
    var type = NormalizeTransactionType(query.String("type"));
    var category = query.String("category");
    var search = query.String("search");
    var startDate = query.String("startDate");
    var endDate = query.String("endDate");
    var page = query.Int("page") ?? 1;
    var pageSize = query.Int("pageSize") ?? query.Int("page_size") ?? 50;
    if (!TryParseDateFilter(startDate, out var startDateValue))
    {
        return Results.BadRequest(new { error = "startDate 日期格式无效，请使用 yyyy-MM-dd" });
    }
    if (!TryParseDateFilter(endDate, out var endDateValue))
    {
        return Results.BadRequest(new { error = "endDate 日期格式无效，请使用 yyyy-MM-dd" });
    }

    var where = new List<string> { "1=1", "c.family_group_id = @family_group_id" };
    var parameters = new List<NpgsqlParameter>();
    parameters.Add(new NpgsqlParameter("family_group_id", familyGroupId));
    AddFilter(where, parameters, childId is null, "t.child_id = @child_id", "child_id", childId ?? 0);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(type), "t.type = @type", "type", type);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(category), "t.category = @category", "category", category);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(search), "t.description ILIKE @search", "search", $"%{search}%");
    AddFilter(where, parameters, startDateValue is null, "t.date >= @start_date", "start_date", startDateValue);
    AddFilter(where, parameters, endDateValue is null, "t.date <= @end_date", "end_date", endDateValue);

    var whereSql = string.Join(" AND ", where);
    await using var conn = await OpenConnection(connectionString);

    await using var countCmd = new NpgsqlCommand($"""
        SELECT COUNT(*)
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE {whereSql}
        """, conn);
    countCmd.Parameters.AddRange(parameters.Select(CloneParameter).ToArray());
    var total = Convert.ToInt32(await countCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);

    await using var cmd = new NpgsqlCommand($"""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE {whereSql}
        ORDER BY t.date DESC, t.id DESC
        LIMIT @limit OFFSET @offset
        """, conn);
    cmd.Parameters.AddRange(parameters.Select(CloneParameter).ToArray());
    cmd.Parameters.AddWithValue("limit", pageSize);
    cmd.Parameters.AddWithValue("offset", Math.Max(0, page - 1) * pageSize);

    var items = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        items.Add(ReadTransaction(reader));
    }

    return Results.Json(new { data = new { items, total, page, page_size = pageSize } });
});

app.MapPost("/api/transactions", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    var result = await CreateTransaction(connectionString, body, familyGroupId);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPost("/api/transactions/batch", async (JsonArray body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var results = new List<object>();
    foreach (var node in body.OfType<JsonObject>())
    {
        var familyGroupId = await ResolveFamilyGroupId(connectionString, request, node);
        var result = await CreateTransaction(connectionString, node, familyGroupId);
        results.Add(new
        {
            child_id = node.Int("child_id") ?? node.Int("childId"),
            success = !result.ContainsKey("error"),
            error = result.TryGetValue("error", out var error) ? error : null
        });
    }

    return Results.Json(new { results });
});

app.MapDelete("/api/transactions/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var result = await DeleteTransaction(connectionString, id, familyGroupId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapGet("/api/rules", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    return Results.Json(await GetRules(connectionString));
});

app.MapPost("/api/rules", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO rules (name, category, points, cash_cny, description)
        VALUES (@name, @category, @points, @cash_cny, @description)
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("name", body.String("name"));
    cmd.Parameters.AddWithValue("category", body.String("category"));
    cmd.Parameters.AddWithValue("points", body.Decimal("points") ?? body.Decimal("score") ?? 0);
    cmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash_cny") ?? 0);
    cmd.Parameters.AddWithValue("description", body.String("description"));
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return Results.Created("/api/rules", ReadRule(reader));
});

app.MapPut("/api/rules/{id:int}", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE rules
        SET name = @name, category = @category, points = @points, cash_cny = @cash_cny, description = @description
        WHERE id = @id
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("name", body.String("name"));
    cmd.Parameters.AddWithValue("category", body.String("category"));
    cmd.Parameters.AddWithValue("points", body.Decimal("points") ?? body.Decimal("score") ?? 0);
    cmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash_cny") ?? 0);
    cmd.Parameters.AddWithValue("description", body.String("description"));
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return Results.NotFound(new { error = "不存在" });
    }

    return Results.Json(ReadRule(reader));
});

app.MapDelete("/api/rules/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM rules WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", id);
    await cmd.ExecuteNonQueryAsync();
    return Results.Json(new { status = "ok" });
});

app.MapGet("/api/stats/dashboard", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var children = await GetChildren(connectionString, familyGroupId);
    var transactions = await GetRecentTransactions(connectionString, 20, familyGroupId);
    return Results.Json(new { children, recent = transactions });
});

app.MapGet("/api/stats/leaderboard", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var children = await GetChildren(connectionString, familyGroupId);
    return Results.Json(children
        .Select(c => new { id = GetInt(c, "id"), name = c["name"], points = GetDecimal(c, "score") })
        .OrderByDescending(c => c.points));
});

app.MapGet("/api/stats/categories", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT category, COALESCE(SUM(points), 0) AS total
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE c.family_group_id = @family_group_id
        GROUP BY category
        ORDER BY category
        """, conn);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            category = reader.String("category"),
            total = reader.Decimal("total")
        });
    }

    return Results.Json(rows);
});

var configStore = new SystemConfigStore(app.Environment.ContentRootPath);

app.MapGet("/api/system/config", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    return Results.Json(configStore.Load());
});

app.MapPut("/api/system/config", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var saved = configStore.Save(body);
    return Results.Json(saved);
});

app.MapPost("/api/agent/parse-reward", async (JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var transcript = body.String("text").Trim();
    if (string.IsNullOrWhiteSpace(transcript))
    {
        return Results.BadRequest(new { ok = false, error = "缺少语音文本" });
    }

    var config = configStore.Load();
    var agent = config["agent"]!.AsObject();
    if (!agent.Bool("enabled"))
    {
        return Results.BadRequest(new { ok = false, error = "智能体服务未开启，请先到系统配置页开启并保存" });
    }

    var endpoint = agent.String("endpoint").Trim();
    if (string.IsNullOrWhiteSpace(endpoint))
    {
        return Results.BadRequest(new { ok = false, error = "未配置智能体服务地址，请先到系统配置页填写并保存" });
    }

    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    var children = await GetChildren(connectionString, familyGroupId);
    var rules = await GetRules(connectionString);
    var prompt = $$$"""
        你是家加分的语音纠错和结构化解析智能体。
        用户语音识别文本可能把孩子名字、规则名称识别错。请根据候选孩子和规则语义，选择最可能的孩子和操作。

        候选孩子 JSON:
        {{JsonSerializer.Serialize(children, FamilyRewardJson.CreateOptions())}}

        候选规则 JSON:
        {{JsonSerializer.Serialize(rules, FamilyRewardJson.CreateOptions())}}

        语音识别文本:
        {{transcript}}

        只返回 JSON 对象，不要解释。格式：
        {{
          "childId": 数字或 null,
          "childName": "候选孩子姓名或 null",
          "type": "score|cash|item",
          "amount": 带符号数字，加分为正，扣分为负,
          "category": "分类",
          "description": "用于交易记录的描述",
          "confidence": 0到1之间的数字
        }}
        """;

    var payload = new JsonObject
    {
        ["model"] = agent.String("model", "gpt-4o-mini"),
        ["temperature"] = 0,
        ["response_format"] = new JsonObject { ["type"] = "json_object" },
        ["messages"] = new JsonArray
        {
            new JsonObject { ["role"] = "system", ["content"] = "你只输出合法 JSON。" },
            new JsonObject { ["role"] = "user", ["content"] = prompt }
        }
    };

    var agentRequest = new HttpRequestMessage(HttpMethod.Post, endpoint)
    {
        Content = new StringContent(payload.ToJsonString(FamilyRewardJson.CreateOptions()), Encoding.UTF8, "application/json")
    };
    var apiKey = agent.String("apiKey");
    if (!string.IsNullOrWhiteSpace(apiKey))
    {
        agentRequest.Headers.Authorization = AuthenticationHeaderValue.Parse(
            apiKey.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? apiKey : $"Bearer {apiKey}");
    }

    var client = httpClientFactory.CreateClient();
    client.Timeout = TimeSpan.FromSeconds(agent.Int("timeout_seconds") ?? 20);
    try
    {
        var response = await client.SendAsync(agentRequest);
        var text = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            return Results.Json(new { ok = false, status = (int)response.StatusCode, error = text }, statusCode: 502);
        }

        JsonNode? providerJson = null;
        try { providerJson = JsonNode.Parse(text); } catch { }
        var modelText = ExtractAgentText(providerJson, text);
        var command = ParseJsonObjectFromText(modelText);
        if (command is null)
        {
            return Results.Json(new { ok = false, error = "智能体未返回可解析 JSON", raw = modelText }, statusCode: 502);
        }

        NormalizeRewardCommand(command, children, transcript);
        return Results.Json(new { ok = true, command, raw = modelText });
    }
    catch (Exception ex)
    {
        return Results.Json(new { ok = false, error = $"智能体服务网络异常: {ex.Message}" }, statusCode: 502);
    }
});

app.MapPost("/api/agent/invoke", async (JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var config = configStore.Load();
    var agent = config["agent"]!.AsObject();
    if (!agent.Bool("enabled"))
    {
        return Results.BadRequest(new { ok = false, error = "智能体服务未开启" });
    }

    var endpoint = agent.String("endpoint").Trim();
    if (string.IsNullOrWhiteSpace(endpoint))
    {
        return Results.BadRequest(new { ok = false, error = "未配置智能体服务地址" });
    }

    var prompt = body.String("prompt");
    var payload = body["payload"]?.DeepClone() as JsonObject ?? new JsonObject
    {
        ["model"] = agent.String("model", "gpt-4o-mini"),
        ["messages"] = new JsonArray
        {
            new JsonObject { ["role"] = "system", ["content"] = agent.String("systemPrompt") },
            new JsonObject { ["role"] = "user", ["content"] = prompt }
        }
    };

    if (!payload.ContainsKey("model"))
    {
        payload["model"] = agent.String("model", "gpt-4o-mini");
    }

    var agentRequest = new HttpRequestMessage(HttpMethod.Post, endpoint)
    {
        Content = new StringContent(payload.ToJsonString(FamilyRewardJson.CreateOptions()), Encoding.UTF8, "application/json")
    };
    var apiKey = body.String("apiKey");
    if (string.IsNullOrWhiteSpace(apiKey))
    {
        apiKey = agent.String("apiKey");
    }
    if (!string.IsNullOrWhiteSpace(apiKey))
    {
        agentRequest.Headers.Authorization = AuthenticationHeaderValue.Parse(
            apiKey.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? apiKey : $"Bearer {apiKey}");
    }

    var client = httpClientFactory.CreateClient();
    client.Timeout = TimeSpan.FromSeconds(agent.Int("timeout_seconds") ?? 20);
    try
    {
        var response = await client.SendAsync(agentRequest);
        var text = await response.Content.ReadAsStringAsync();
        JsonNode? parsed = null;
        try { parsed = JsonNode.Parse(text); } catch { }
        return Results.Json(new
        {
            ok = response.IsSuccessStatusCode,
            status = (int)response.StatusCode,
            response = parsed,
            error = response.IsSuccessStatusCode ? null : text
        }, statusCode: response.IsSuccessStatusCode ? 200 : 502);
    }
    catch (Exception ex)
    {
        return Results.Json(new { ok = false, error = $"智能体服务网络异常: {ex.Message}" }, statusCode: 502);
    }
});

app.MapGet("/api/mcp", () => Results.Json(BuildMcpServiceDescriptor()));
app.MapPost("/api/mcp", async (JsonObject body) =>
{
    var method = body.String("method").Trim();
    if (string.IsNullOrWhiteSpace(method))
    {
        var directToolName = body.String("name");
        if (string.IsNullOrWhiteSpace(directToolName) || !IsKnownMcpTool(directToolName))
        {
            return Results.BadRequest(new { ok = false, error = "缺少有效 MCP 工具 name" });
        }
        var directArgs = body["arguments"]?.AsObject() ?? new JsonObject();
        var directResult = await SafeInvokeFamilyRewardMcpTool(directToolName, directArgs, connectionString);
        return Results.Json(directResult);
    }

    var id = body["id"];
    var parameters = body["params"]?.AsObject();
    var isNotification = id is null;
    switch (method)
    {
        case "initialize":
            if (isNotification)
            {
                return Results.NoContent();
            }

            var clientProtocol = parameters?.String("protocolVersion")?.Trim();
            var protocolVersion = string.Equals(clientProtocol, "2024-11-05", StringComparison.Ordinal)
                ? "2024-11-05"
                : "2025-03-26";
            return Results.Json(BuildMcpRpcResponse(id, new
            {
                protocolVersion,
                capabilities = new
                {
                    tools = new { listChanged = false }
                },
                serverInfo = new
                {
                    name = FamilyRewardMcpServiceName,
                    version = "3.0.0"
                },
                instructions = "Use tools/list and tools/call with separated tools for children, score/accounts, records/transactions, rules, and family groups. 不要把不同对象合并到一个工具里。"
            }));
        case "initialized":
        case "notifications/initialized":
            return isNotification ? Results.NoContent() : Results.Json(BuildMcpRpcResponse(id, new { ok = true }));
        case "ping":
            return Results.Json(BuildMcpRpcResponse(id, new { }));
        case "tools/list":
            if (isNotification)
            {
                return Results.NoContent();
            }

            var cursor = parameters?.String("cursor");
            return Results.Json(BuildMcpRpcResponse(id, BuildMcpToolList(cursor)));
        case "tools/call":
            {
            var toolName = parameters?.String("name") ?? body.String("name");
            if (string.IsNullOrWhiteSpace(toolName))
            {
                return Results.BadRequest(BuildMcpRpcResponse(
                        id,
                        null,
                        "Invalid params: missing tools/call name",
                        -32602
                    ));
                }

                if (!IsKnownMcpTool(toolName))
                {
                    return Results.BadRequest(BuildMcpRpcResponse(
                        id,
                        null,
                        $"Tool '{toolName}' 不存在",
                        -32601
                    ));
                }

                var arguments = parameters?["arguments"]?.AsObject() ?? body["arguments"]?.AsObject();
                if (arguments is null)
                {
                    arguments = new JsonObject();
                }
                var toolResult = await SafeInvokeFamilyRewardMcpTool(toolName, arguments, connectionString);
                return Results.Json(BuildMcpRpcResponse(id, BuildMcpToolCallResult(toolResult)));
            }
        default:
            return Results.BadRequest(BuildMcpRpcResponse(
                id,
                null,
                $"不支持的 MCP method: {method}",
                -32601
            ));
    }
});

app.Run();

static JsonObject BuildWatchWebManifest(HttpRequest request)
{
    var baseUrl = GetPublicBaseUrl(request);
    return new JsonObject
    {
        ["id"] = "/watch",
        ["name"] = "家加分手表积分",
        ["short_name"] = "手表积分",
        ["description"] = "给孩子在手表端查询积分和提交积分申请的家加分手表应用。",
        ["lang"] = "zh-CN",
        ["start_url"] = $"{baseUrl}/watch?source=watch-app",
        ["scope"] = $"{baseUrl}/watch",
        ["display"] = "standalone",
        ["orientation"] = "portrait",
        ["theme_color"] = "#16643a",
        ["background_color"] = "#eef5ef",
        ["categories"] = new JsonArray { "kids", "education", "lifestyle" },
        ["icons"] = new JsonArray
        {
            new JsonObject
            {
                ["src"] = $"{baseUrl}/watch/icon.svg",
                ["sizes"] = "any",
                ["type"] = "image/svg+xml",
                ["purpose"] = "any maskable"
            }
        }
    };
}

static JsonObject BuildWatchAppInfo(HttpRequest request)
{
    var baseUrl = GetPublicBaseUrl(request);
    return new JsonObject
    {
        ["appName"] = "家加分手表积分",
        ["packageId"] = "net.impx.happylife.watch",
        ["versionName"] = "1.0.0",
        ["versionCode"] = 100,
        ["entryUrl"] = $"{baseUrl}/watch?source=watch-app",
        ["manifestUrl"] = $"{baseUrl}/watch/manifest.json",
        ["apiBaseUrl"] = baseUrl,
        ["supportedPlatforms"] = new JsonArray { "xiaotiancai", "xiaomi", "huawei" },
        ["supportedScreens"] = new JsonArray { "192x192", "240x240", "280x280", "320x320", "360x360" },
        ["watchFeatures"] = new JsonArray { "积分查询", "积分申请", "最近申请状态", "儿童认证码设备绑定", "家长解绑认证码校验" },
        ["requiredPermissions"] = new JsonArray { "INTERNET", "ACCESS_NETWORK_STATE" },
        ["privacy"] = new JsonObject
        {
            ["collectsPreciseLocation"] = false,
            ["collectsContacts"] = false,
            ["collectsMicrophone"] = false,
            ["collectsCamera"] = false,
            ["childAccountOnly"] = true
        },
        ["releaseReadiness"] = new JsonObject
        {
            ["webEntry"] = "ready",
            ["androidWrapper"] = "ready_for_sdk_build",
            ["storeListingAssets"] = "prepared",
            ["blockedBy"] = "平台开发者账号、签名证书、真机截图和平台后台提交"
        }
    };
}

static string GetPublicBaseUrl(HttpRequest request)
{
    var scheme = request.Headers.TryGetValue("X-Forwarded-Proto", out var forwardedProto) && !string.IsNullOrWhiteSpace(forwardedProto.ToString())
        ? forwardedProto.ToString().Split(',')[0].Trim()
        : request.Scheme;
    var host = request.Headers.TryGetValue("X-Forwarded-Host", out var forwardedHost) && !string.IsNullOrWhiteSpace(forwardedHost.ToString())
        ? forwardedHost.ToString().Split(',')[0].Trim()
        : request.Host.Value;
    return $"{scheme}://{host}".TrimEnd('/');
}

static object BuildMcpServiceDescriptor()
{
    return new
    {
        service = new
        {
            name = FamilyRewardMcpServiceName,
            version = "3.0.0",
            title = "家加分 MCP 服务（能力拆分）",
            description = "按能力提供独立工具：新增孩子、修改孩子、积分增减、积分查询、积分明细写入与查询。"
        },
        endpoint = "/api/mcp",
        protocols = new[] { "initialize", "initialized", "notifications/initialized", "ping", "tools/list", "tools/call" },
        tools = BuildMcpToolCatalog()
    };
}

static object BuildMcpToolCatalog()
{
    return new
    {
        tools = new object[]
        {
            new
            {
                name = FamilyRewardMcpAddChildToolName,
                description = "新增孩子：创建孩子档案并可设置初始积分/现金/物品。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        name = new
                        {
                            type = "string",
                            description = "孩子姓名（必填）"
                        },
                        family_group_id = new { type = "integer", description = "家庭组ID；不传则使用默认家庭组" },
                        note = new { type = "string", description = "备注" },
                        status = new { type = "string", description = "状态：active / inactive" },
                        score = new { type = "number", description = "初始积分（默认为 0）" },
                        cash = new { type = "number", description = "初始现金（默认为 0）" },
                        items = new { type = "integer", description = "初始物品数（默认为 0）" }
                    },
                    required = new[] { "name" }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateChildToolName,
                description = "修改孩子信息：按 id 或姓名定位后更新。至少更新一个字段。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）" },
                        name = new { type = "string", description = "更新后的姓名" },
                        note = new { type = "string", description = "更新后的备注" },
                        status = new { type = "string", description = "更新后的状态，示例：active / inactive" },
                        score = new { type = "number", description = "更新后的积分余额（覆盖，不是增量）" },
                        cash = new { type = "number", description = "更新后的现金余额（覆盖，不是增量）" },
                        items = new { type = "integer", description = "更新后的物品数（覆盖，不是增量）" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryChildrenToolName,
                description = "查询孩子列表：传 family_group_id 返回该家庭组的全部孩子；也可继续传 child_id 或 child_name 定位单个孩子。若按某个孩子查询返回 ok:false/未找到，智能体必须再调用 family_reward_list_children（只传 family_group_id）取得完整孩子清单，并把用户输入与清单中的 ID/姓名逐一比较后再回复，避免别名、错别字或输入差异导致误判。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；可选。只传此字段时返回该家庭组全部孩子" },
                        child_id = new { type = "integer", description = "孩子ID（可选）。未找到时不要直接结束，应再查完整孩子清单进行对比" },
                        child_name = new { type = "string", description = "孩子姓名（可选）。未找到时不要直接结束，应再查完整孩子清单进行对比" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpListChildrenToolName,
                description = "列出孩子清单：当用户说“查询孩子列表 / 列出孩子 / 有哪些孩子 / 全部孩子”时优先调用。传 family_group_id 返回该家庭组全部 active 孩子；不传则返回全部 active 孩子。不要传 child_id 或 child_name。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；可选。只传此字段时返回该家庭组全部孩子" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteChildToolName,
                description = "删除孩子：按 id 或姓名定位后删除孩子及其账户/记录。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）" },
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpAdjustScoreToolName,
                description = "积分增减：按孩子 +/ - 积分（支持负数）",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）" },
                        delta = new { type = "number", description = "积分变更量；正数加分、负数减分" },
                        direction = new { type = "string", description = "可选：\"+\" 或 \"-\"，不传则按 delta 正负判断" },
                        date = new { type = "string", description = "交易日期，格式 YYYY-MM-DD（默认今天）" },
                        category = new { type = "string", description = "分类（adjust_score）" },
                        description = new { type = "string", description = "交易描述（adjust_score）" },
                    },
                    required = new[] { "delta" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryScoreToolName,
                description = "积分查询：不传 child_id/child_name 时返回孩子积分清单；传 family_group_id 时返回该家庭组全部孩子的积分清单；传具体孩子时返回单个孩子积分，可选返回最近交易明细。若指定孩子返回未找到，必须再调用 family_reward_list_children（只传 family_group_id）获取完整孩子清单，比较用户输入与全部孩子 ID/姓名后再说明最可能的匹配或请用户确认。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；可选。只传此字段时返回该家庭组全部孩子的积分清单" },
                        child_id = new { type = "integer", description = "孩子ID；可选。传入时返回单个孩子积分；未找到时必须再查完整孩子清单对比" },
                        child_name = new { type = "string", description = "孩子姓名；可选。传入时返回单个孩子积分；未找到时必须再查完整孩子清单对比" },
                        include_transactions = new { type = "boolean", description = "是否返回最近交易明细，默认 false" },
                        limit = new { type = "integer", description = "交易明细返回数量，默认 20，最大 200" },
                        start_date = new { type = "string", description = "交易开始日期 YYYY-MM-DD（可选）" },
                        end_date = new { type = "string", description = "交易结束日期 YYYY-MM-DD（可选）" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpLogScoreOperationToolName,
                description = "写入积分明细（加/减分记录），并同步更新账户积分。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）" },
                        delta = new { type = "number", description = "积分增减量；正数加分，负数减分" },
                        direction = new { type = "string", description = "可选：\"+\" 或 \"-\"，不传则按 delta 正负判断" },
                        date = new { type = "string", description = "交易日期，格式 YYYY-MM-DD（默认今天）" },
                        category = new { type = "string", description = "分类（默认：积分调整）" },
                        description = new { type = "string", description = "明细描述" },
                        notes = new { type = "string", description = "备注" }
                    },
                    required = new[] { "delta" }
                }
            },
            new
            {
                name = FamilyRewardMcpCreateRecordToolName,
                description = "新增记录/交易：支持积分、现金、物品记录，并同步更新孩子账户。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）" },
                        type = new { type = "string", description = "记录类型：points、cash、items" },
                        direction = new { type = "string", description = "方向：+ 或 -" },
                        date = new { type = "string", description = "交易日期 YYYY-MM-DD（默认今天）" },
                        points = new { type = "number", description = "积分记录的积分数" },
                        delta = new { type = "number", description = "积分增减量，正负号可决定 direction" },
                        cash_cny = new { type = "number", description = "现金金额" },
                        items = new { type = "string", description = "物品描述" },
                        category = new { type = "string", description = "分类" },
                        description = new { type = "string", description = "描述" },
                        notes = new { type = "string", description = "备注" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateRecordToolName,
                description = "修改记录/交易：按记录ID更新，并自动回滚旧记录影响后重新应用新记录。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        transaction_id = new { type = "integer", description = "记录ID" },
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID（可选）" },
                        child_name = new { type = "string", description = "孩子姓名（可选）" },
                        type = new { type = "string", description = "记录类型：points、cash、items" },
                        direction = new { type = "string", description = "方向：+ 或 -" },
                        date = new { type = "string", description = "交易日期 YYYY-MM-DD" },
                        points = new { type = "number", description = "积分数" },
                        delta = new { type = "number", description = "积分增减量" },
                        cash_cny = new { type = "number", description = "现金金额" },
                        items = new { type = "string", description = "物品描述" },
                        category = new { type = "string", description = "分类" },
                        description = new { type = "string", description = "描述" },
                        notes = new { type = "string", description = "备注" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteRecordToolName,
                description = "删除记录/交易：按记录ID删除，并自动回滚该记录对孩子账户的影响。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        transaction_id = new { type = "integer", description = "记录ID" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryScoreOperationToolName,
                description = "查询积分加减明细记录（交易日志），支持按孩子、日期、分类、分页筛选。若指定孩子返回未找到，必须再调用 family_reward_list_children（只传 family_group_id）获取完整孩子清单，比较用户输入与全部孩子 ID/姓名后再回复，不能直接说不存在。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "家庭组ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID；未找到时必须再查完整孩子清单对比" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）；未找到时必须再查完整孩子清单对比" },
                        category = new { type = "string", description = "分类模糊匹配（可选）" },
                        search = new { type = "string", description = "描述模糊匹配（可选）" },
                        start_date = new { type = "string", description = "开始日期 YYYY-MM-DD（可选）" },
                        end_date = new { type = "string", description = "结束日期 YYYY-MM-DD（可选）" },
                        page = new { type = "integer", description = "页码，默认 1" },
                        page_size = new { type = "integer", description = "每页数量，默认 20，最大 200" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryRulesToolName,
                description = "查询积分规则和红线规则。",
                inputSchema = new { type = "object", properties = new { } }
            },
            new
            {
                name = FamilyRewardMcpCreateRuleToolName,
                description = "新增积分规则。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        name = new { type = "string", description = "规则名称" },
                        category = new { type = "string", description = "分类" },
                        points = new { type = "number", description = "积分" },
                        cash_cny = new { type = "number", description = "现金" },
                        description = new { type = "string", description = "描述" }
                    },
                    required = new[] { "name" }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateRuleToolName,
                description = "修改积分规则。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        rule_id = new { type = "integer", description = "规则ID" },
                        name = new { type = "string", description = "规则名称" },
                        category = new { type = "string", description = "分类" },
                        points = new { type = "number", description = "积分" },
                        cash_cny = new { type = "number", description = "现金" },
                        description = new { type = "string", description = "描述" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteRuleToolName,
                description = "删除积分规则。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        rule_id = new { type = "integer", description = "规则ID" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryFamilyGroupsToolName,
                description = "查询家庭组列表。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        user_id = new { type = "string", description = "用户ID（默认 local-admin）" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpCreateFamilyGroupToolName,
                description = "新增家庭组。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        name = new { type = "string", description = "家庭组名称" },
                        description = new { type = "string", description = "描述" },
                        user_id = new { type = "string", description = "创建用户ID（默认 local-admin）" }
                    },
                    required = new[] { "name" }
                }
            }
        }
    };
}

static bool IsKnownMcpTool(string toolName) => toolName is
    FamilyRewardMcpQueryChildrenToolName or
    FamilyRewardMcpListChildrenToolName or
    FamilyRewardMcpAddChildToolName or
    FamilyRewardMcpUpdateChildToolName or
    FamilyRewardMcpDeleteChildToolName or
    FamilyRewardMcpAdjustScoreToolName or
    FamilyRewardMcpQueryScoreToolName or
    FamilyRewardMcpCreateRecordToolName or
    FamilyRewardMcpUpdateRecordToolName or
    FamilyRewardMcpDeleteRecordToolName or
    FamilyRewardMcpLogScoreOperationToolName or
    FamilyRewardMcpQueryScoreOperationToolName or
    FamilyRewardMcpQueryRulesToolName or
    FamilyRewardMcpCreateRuleToolName or
    FamilyRewardMcpUpdateRuleToolName or
    FamilyRewardMcpDeleteRuleToolName or
    FamilyRewardMcpQueryFamilyGroupsToolName or
    FamilyRewardMcpCreateFamilyGroupToolName;

static object BuildMcpRpcResponse(JsonNode? id, object? result = null, string? error = null, int code = -32602)
{
    if (!string.IsNullOrWhiteSpace(error))
    {
        return new
        {
            jsonrpc = "2.0",
            id = id?.DeepClone(),
            error = new { code, message = error }
        };
    }

    return new
    {
        jsonrpc = "2.0",
        id = id?.DeepClone(),
        result
    };
}

static object BuildMcpToolList(string? cursor)
{
    var catalog = BuildMcpToolCatalog();
    var catalogNode = JsonSerializer.SerializeToNode(catalog, FamilyRewardJson.CreateOptions()) as JsonObject;
    var tools = catalogNode?["tools"];
    return new
    {
        tools,
        nextCursor = (string?)null
    };
}

static object BuildMcpToolCallResult(object toolResult)
{
    var toolPayload = JsonSerializer.Serialize(toolResult, FamilyRewardJson.CreateOptions());
    var isError = false;

    try
    {
        using var doc = JsonDocument.Parse(toolPayload);
        if (doc.RootElement.TryGetProperty("ok", out var ok))
        {
            isError = ok.ValueKind == JsonValueKind.False;
        }
    }
    catch
    {
        // Keep isError false for unknown payload types
    }

    return new
    {
        content = new[]
        {
            new { type = "text", text = BuildMcpReadableText(toolResult) }
        },
        structuredContent = toolResult,
        isError
    };
}

static string BuildMcpReadableText(object toolResult)
{
    var node = JsonSerializer.SerializeToNode(toolResult, FamilyRewardJson.CreateOptions()) as JsonObject;
    if (node is null)
    {
        return Convert.ToString(toolResult, CultureInfo.InvariantCulture) ?? string.Empty;
    }

    var ok = node["ok"]?.GetValue<bool?>() ?? true;
    if (!ok)
    {
        return $"失败：{node.String("error", "操作失败")}";
    }

    var action = node.String("action", "操作完成");
    var parts = new List<string> { $"成功：{action}" };
    if (node["child"] is JsonObject child)
    {
        AppendJsonValue(parts, child, "name", "孩子");
        AppendJsonValue(parts, child, "score", "积分");
        AppendJsonValue(parts, child, "cash", "现金");
        AppendJsonValue(parts, child, "items", "物品");
    }
    if (node["children"] is JsonArray children)
    {
        parts.Add($"孩子数量 {children.Count}");
        var childLines = children
            .OfType<JsonObject>()
            .Select(FormatMcpChildLine)
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .ToArray();
        if (childLines.Length > 0)
        {
            parts.Add("孩子清单：" + string.Join("；", childLines));
        }
    }
    if (node["transaction"] is JsonObject transaction)
    {
        AppendJsonValue(parts, transaction, "description", "明细");
        AppendJsonValue(parts, transaction, "points", "积分变动");
    }
    if (node["total"] is JsonNode total)
    {
        parts.Add($"记录数 {total}");
    }
    if (node["data"] is JsonObject data)
    {
        AppendJsonValue(parts, data, "total", "记录数");
        AppendJsonValue(parts, data, "page", "页码");
        AppendJsonValue(parts, data, "page_size", "每页");
        if (data["items"] is JsonArray items)
        {
            var itemLines = items
                .OfType<JsonObject>()
                .Select(FormatMcpTransactionLine)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .Take(10)
                .ToArray();
            if (itemLines.Length > 0)
            {
                parts.Add("明细：" + string.Join("；", itemLines));
            }
        }
    }

    return string.Join("，", parts);
}

static string FormatMcpChildLine(JsonObject child)
{
    var fields = new List<string>();
    AppendJsonValue(fields, child, "id", "ID");
    AppendJsonValue(fields, child, "name", "姓名");
    AppendJsonValue(fields, child, "score", "积分");
    AppendJsonValue(fields, child, "cash", "现金");
    AppendJsonValue(fields, child, "items", "物品");
    return string.Join(" ", fields);
}

static string FormatMcpTransactionLine(JsonObject transaction)
{
    var fields = new List<string>();
    AppendJsonValue(fields, transaction, "date", "日期");
    AppendJsonValue(fields, transaction, "child_name", "孩子");
    AppendJsonValue(fields, transaction, "direction", "方向");
    AppendJsonValue(fields, transaction, "points", "积分");
    AppendJsonValue(fields, transaction, "category", "分类");
    AppendJsonValue(fields, transaction, "description", "描述");
    return string.Join(" ", fields);
}

static void AppendJsonValue(List<string> parts, JsonObject source, string key, string label)
{
    if (source[key] is JsonNode value)
    {
        parts.Add($"{label} {value}");
    }
}

static async Task<object> SafeInvokeFamilyRewardMcpTool(string toolName, JsonObject arguments, string connectionString)
{
    var unknownArguments = GetUnknownMcpArguments(toolName, arguments).ToArray();
    if (unknownArguments.Length > 0)
    {
        return new
        {
            ok = false,
            action = "validate_arguments",
            error = $"未知参数：{string.Join(", ", unknownArguments)}。请只使用 tools/list 中声明的 snake_case 字段。"
        };
    }

    try
    {
        return await InvokeFamilyRewardMcpTool(toolName, arguments, connectionString);
    }
    catch (Exception ex)
    {
        return new { ok = false, action = toolName, error = ex.Message };
    }
}

static IEnumerable<string> GetUnknownMcpArguments(string toolName, JsonObject arguments)
{
    var allowed = GetAllowedMcpArguments(toolName);
    return arguments.Select(item => item.Key).Where(key => !allowed.Contains(key, StringComparer.Ordinal));
}

static HashSet<string> GetAllowedMcpArguments(string toolName) => toolName switch
{
    FamilyRewardMcpAddChildToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "name", "note", "status", "score", "cash", "items"
    },
    FamilyRewardMcpUpdateChildToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "name", "note", "status", "score", "cash", "items"
    },
    FamilyRewardMcpQueryChildrenToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name"
    },
    FamilyRewardMcpListChildrenToolName => new(StringComparer.Ordinal)
    {
        "family_group_id"
    },
    FamilyRewardMcpDeleteChildToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name"
    },
    FamilyRewardMcpAdjustScoreToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "delta", "direction", "date", "category", "description"
    },
    FamilyRewardMcpLogScoreOperationToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "delta", "direction", "date", "category", "description", "notes"
    },
    FamilyRewardMcpQueryScoreToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "include_transactions", "limit", "start_date", "end_date"
    },
    FamilyRewardMcpCreateRecordToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "type", "direction", "date", "points", "delta", "cash_cny", "items", "category", "description", "notes"
    },
    FamilyRewardMcpUpdateRecordToolName => new(StringComparer.Ordinal)
    {
        "transaction_id", "family_group_id", "child_id", "child_name", "type", "direction", "date", "points", "delta", "cash_cny", "items", "category", "description", "notes"
    },
    FamilyRewardMcpDeleteRecordToolName => new(StringComparer.Ordinal)
    {
        "transaction_id"
    },
    FamilyRewardMcpQueryScoreOperationToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "category", "search", "start_date", "end_date", "page", "page_size"
    },
    FamilyRewardMcpQueryRulesToolName => new(StringComparer.Ordinal),
    FamilyRewardMcpCreateRuleToolName => new(StringComparer.Ordinal)
    {
        "name", "category", "points", "cash_cny", "description"
    },
    FamilyRewardMcpUpdateRuleToolName => new(StringComparer.Ordinal)
    {
        "rule_id", "name", "category", "points", "cash_cny", "description"
    },
    FamilyRewardMcpDeleteRuleToolName => new(StringComparer.Ordinal)
    {
        "rule_id"
    },
    FamilyRewardMcpQueryFamilyGroupsToolName => new(StringComparer.Ordinal)
    {
        "user_id"
    },
    FamilyRewardMcpCreateFamilyGroupToolName => new(StringComparer.Ordinal)
    {
        "name", "description", "user_id"
    },
    _ => new(StringComparer.Ordinal)
};

static async Task<object> InvokeFamilyRewardMcpTool(string toolName, JsonObject arguments, string connectionString)
{
    return toolName switch
    {
        FamilyRewardMcpAddChildToolName => await McpAddChild(connectionString, arguments),
        FamilyRewardMcpUpdateChildToolName => await McpUpdateChild(connectionString, arguments),
        FamilyRewardMcpQueryChildrenToolName => await McpQueryChildren(connectionString, arguments),
        FamilyRewardMcpListChildrenToolName => await McpQueryChildren(connectionString, arguments),
        FamilyRewardMcpDeleteChildToolName => await McpDeleteChild(connectionString, arguments),
        FamilyRewardMcpAdjustScoreToolName => await McpAdjustScore(connectionString, arguments),
        FamilyRewardMcpQueryScoreToolName => await McpQueryScore(connectionString, arguments),
        FamilyRewardMcpCreateRecordToolName => await McpCreateRecord(connectionString, arguments),
        FamilyRewardMcpUpdateRecordToolName => await McpUpdateRecord(connectionString, arguments),
        FamilyRewardMcpDeleteRecordToolName => await McpDeleteRecord(connectionString, arguments),
        FamilyRewardMcpLogScoreOperationToolName => await McpLogScoreOperation(connectionString, arguments),
        FamilyRewardMcpQueryScoreOperationToolName => await McpQueryScoreOperations(connectionString, arguments),
        FamilyRewardMcpQueryRulesToolName => await McpQueryRules(connectionString),
        FamilyRewardMcpCreateRuleToolName => await McpCreateRule(connectionString, arguments),
        FamilyRewardMcpUpdateRuleToolName => await McpUpdateRule(connectionString, arguments),
        FamilyRewardMcpDeleteRuleToolName => await McpDeleteRule(connectionString, arguments),
        FamilyRewardMcpQueryFamilyGroupsToolName => await McpQueryFamilyGroups(connectionString, arguments),
        FamilyRewardMcpCreateFamilyGroupToolName => await McpCreateFamilyGroup(connectionString, arguments),
        _ => new { ok = false, error = $"Tool '{toolName}' 不存在" }
    };
}

static async Task<object> McpAddChild(string connectionString, JsonObject arguments)
{
    var result = await CreateChildCore(connectionString, arguments, arguments.Int("family_group_id"));
    if (!result.Success)
    {
        return new { ok = false, error = result.Error };
    }

    return new
    {
        ok = true,
        action = "add_child",
        child = result.Child
    };
}

static async Task<object> McpAdjustScore(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, error = "未找到目标孩子" };
    }

    var delta = arguments.Decimal("delta");
    if (delta is null || delta == 0)
    {
        return new { ok = false, error = "adjust_score 需要提供非0的 delta" };
    }
    if (!TryParseDateFilter(arguments.String("date"), out _))
    {
        return new { ok = false, error = "date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    var direction = arguments.String("direction");
    if (direction != "+" && direction != "-")
    {
        direction = delta > 0 ? "+" : "-";
    }

    var txBody = new JsonObject
    {
        ["child_id"] = GetInt(target, "id"),
        ["type"] = "score",
        ["direction"] = direction,
        ["points"] = Math.Abs(delta.Value),
        ["category"] = arguments.String("category", delta > 0 ? "奖励" : "扣分"),
        ["description"] = arguments.String("description", $"积分{(direction == "+" ? "增加" : "扣减")}"),
        ["date"] = arguments.String("date", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
    };
    var tx = await CreateTransaction(connectionString, txBody);
    if (tx.ContainsKey("error"))
    {
        return new { ok = false, error = tx["error"] };
    }

    var updated = (await GetMcpChildren(connectionString, arguments)).FirstOrDefault(c => GetInt(c, "id") == GetInt(target, "id"));
    return new { ok = true, action = "adjust_score", child = updated, transaction = tx["transaction"] };
}

static async Task<object> McpLogScoreOperation(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, error = "未找到目标孩子" };
    }

    var delta = arguments.Decimal("delta");
    if (delta is null || delta == 0)
    {
        return new { ok = false, error = "log_score_record 需要提供非0的 delta" };
    }
    if (!TryParseDateFilter(arguments.String("date"), out _))
    {
        return new { ok = false, error = "date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    var direction = arguments.String("direction");
    if (direction != "+" && direction != "-")
    {
        direction = delta > 0 ? "+" : "-";
    }

    var txBody = new JsonObject
    {
        ["child_id"] = GetInt(target, "id"),
        ["type"] = "points",
        ["direction"] = direction,
        ["points"] = Math.Abs(delta.Value),
        ["category"] = arguments.String("category", "积分调整"),
        ["description"] = arguments.String("description", $"积分{(direction == "+" ? "增加" : "扣减")}"),
        ["notes"] = arguments.String("notes"),
        ["date"] = arguments.String("date", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
    };
    var tx = await CreateTransaction(connectionString, txBody);
    if (tx.ContainsKey("error"))
    {
        return new { ok = false, error = tx["error"] };
    }

    var updated = (await GetMcpChildren(connectionString, arguments)).FirstOrDefault(c => GetInt(c, "id") == GetInt(target, "id"));
    return new { ok = true, action = "log_score_record", child = updated, transaction = tx["transaction"] };
}

static async Task<object> McpUpdateChild(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, error = "未找到目标孩子" };
    }

    var childId = GetInt(target, "id");
    var hasName = arguments.ContainsKey("name");
    var hasNote = arguments.ContainsKey("note");
    var hasStatus = arguments.ContainsKey("status");
    var hasScore = arguments.ContainsKey("score");
    var hasCash = arguments.ContainsKey("cash");
    var hasItems = arguments.ContainsKey("items");

    if (!hasName && !hasNote && !hasStatus && !hasScore && !hasCash && !hasItems)
    {
        return new { ok = false, error = "请至少提交一个待更新字段" };
    }

    var name = arguments.String("name").Trim();
    if (hasName && string.IsNullOrWhiteSpace(name))
    {
        return new { ok = false, error = "name 不能空" };
    }

    var score = arguments.Decimal("score");
    var cash = arguments.Decimal("cash");
    var items = arguments.Int("items");

    if (hasScore && score is null)
    {
        return new { ok = false, error = "score 格式不合法" };
    }

    if (hasCash && cash is null)
    {
        return new { ok = false, error = "cash 格式不合法" };
    }

    if (hasItems && items is null)
    {
        return new { ok = false, error = "items 格式不合法" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        await using (var cmd = new NpgsqlCommand("""
            UPDATE children
            SET name = COALESCE(@name, name),
                note = COALESCE(@note, note),
                status = COALESCE(@status, status),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = @id
            RETURNING id, name, status, note, profile_key, created_at, updated_at
            """, conn, tx))
        {
            cmd.Parameters.AddWithValue("id", childId);
            cmd.Parameters.AddWithValue("name", hasName ? name : DBNull.Value);
            cmd.Parameters.AddWithValue("note", hasNote ? arguments["note"]!.ToString() : DBNull.Value);
            cmd.Parameters.AddWithValue("status", hasStatus ? arguments.String("status") : DBNull.Value);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
            {
                await tx.RollbackAsync();
                return new { ok = false, error = "孩子不存在" };
            }
            await reader.CloseAsync();
        }

        await using (var accountCmd = new NpgsqlCommand("""
            INSERT INTO accounts (child_id, profile_key, points, cash_cny, items_count)
            SELECT @child_id, profile_key, COALESCE(@points, 0), COALESCE(@cash_cny, 0), COALESCE(@items_count, 0)
            FROM children
            WHERE id = @child_id
            ON CONFLICT (profile_key) DO UPDATE SET
                points = COALESCE(@points, points),
                cash_cny = COALESCE(@cash_cny, cash_cny),
                items_count = COALESCE(@items_count, items_count),
                updated_at = CURRENT_TIMESTAMP
            """, conn, tx))
        {
            accountCmd.Parameters.AddWithValue("child_id", childId);
            accountCmd.Parameters.AddWithValue("points", hasScore ? score!.Value : DBNull.Value);
            accountCmd.Parameters.AddWithValue("cash_cny", hasCash ? cash!.Value : DBNull.Value);
            accountCmd.Parameters.AddWithValue("items_count", hasItems ? items!.Value : DBNull.Value);
            await accountCmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        var updated = (await GetMcpChildren(connectionString, arguments)).FirstOrDefault(c => GetInt(c, "id") == childId);
        return new { ok = true, action = "update_child", child = updated };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new { ok = false, error = ex.Message };
    }
}

static async Task<object> McpDeleteChild(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, error = "未找到目标孩子" };
    }

    var familyGroupId = GetInt(target, "family_group_id");
    var result = await DeleteChildMembership(connectionString, GetInt(target, "id"), familyGroupId);
    return !result.ContainsKey("error")
        ? new { ok = true, action = "delete_child", child = target }
        : new { ok = false, error = result["error"] };
}

static async Task<object> McpQueryScore(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    var familyGroupId = arguments.Int("family_group_id");
    if (HasChildReference(arguments) && target is null)
    {
        return ChildReferenceNotFound("query_score", familyGroupId);
    }

    var limit = arguments.Int("limit") ?? 20;
    var includeTransactions = arguments.Bool("include_transactions");
    var startDate = arguments.String("start_date");
    var endDate = arguments.String("end_date");
    if (!TryParseDateFilter(startDate, out _))
    {
        return new { ok = false, error = "start_date 日期格式无效，请使用 yyyy-MM-dd" };
    }
    if (!TryParseDateFilter(endDate, out _))
    {
        return new { ok = false, error = "end_date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    if (target is null)
    {
        return new
        {
            ok = true,
            action = "query_score",
            family_group_id = familyGroupId,
            count = children.Count,
            children
        };
    }

    var records = (await GetRecentTransactions(connectionString, Math.Clamp(limit, 1, 200)))
        .Where(tx => GetInt(tx, "child_id") == GetInt(target, "id"))
        .Where(tx => string.IsNullOrWhiteSpace(startDate) || string.Compare(Convert.ToString(tx["date"], CultureInfo.InvariantCulture), startDate, StringComparison.Ordinal) >= 0)
        .Where(tx => string.IsNullOrWhiteSpace(endDate) || string.Compare(Convert.ToString(tx["date"], CultureInfo.InvariantCulture), endDate, StringComparison.Ordinal) <= 0)
        .ToList();
    return new
    {
        ok = true,
        action = "query_score",
        child = target,
        transactions = includeTransactions ? records : null,
        total = records.Count
    };
}

static async Task<object> McpQueryScoreOperations(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (HasChildReference(arguments) && target is null)
    {
        return ChildReferenceNotFound("query_operation_records", arguments.Int("family_group_id"));
    }

    var familyGroupId = arguments.Int("family_group_id") ?? (target is not null && target.TryGetValue("family_group_id", out var groupIdValue)
        ? Convert.ToInt32(groupIdValue, CultureInfo.InvariantCulture)
        : (int?)null);

    var page = arguments.Int("page") ?? 1;
    var pageSize = arguments.Int("page_size") ?? 20;
    var category = arguments.String("category");
    var search = arguments.String("search");
    var startDate = arguments.String("start_date");
    var endDate = arguments.String("end_date");

    page = Math.Max(page, 1);
    pageSize = Math.Clamp(pageSize, 1, 200);
    if (!TryParseDateFilter(startDate, out var startDateValue))
    {
        return new { ok = false, error = "start_date 日期格式无效，请使用 yyyy-MM-dd" };
    }
    if (!TryParseDateFilter(endDate, out var endDateValue))
    {
        return new { ok = false, error = "end_date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    int? childId = target is null ? null : GetInt(target, "id");
    var where = new List<string> { "1=1", "t.type = 'points'" };
    var parameters = new List<NpgsqlParameter>();
    AddFilter(where, parameters, familyGroupId is null, "c.family_group_id = @family_group_id", "family_group_id", familyGroupId ?? 0);
    AddFilter(where, parameters, childId is null, "t.child_id = @child_id", "child_id", childId ?? 0);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(category), "t.category ILIKE @category", "category", $"%{category}%");
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(search), "t.description ILIKE @search", "search", $"%{search}%");
    AddFilter(where, parameters, startDateValue is null, "t.date >= @start_date", "start_date", startDateValue);
    AddFilter(where, parameters, endDateValue is null, "t.date <= @end_date", "end_date", endDateValue);

    var whereSql = string.Join(" AND ", where);
    await using var conn = await OpenConnection(connectionString);

    await using var countCmd = new NpgsqlCommand($"""
        SELECT COUNT(*)
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE {whereSql}
        """, conn);
    countCmd.Parameters.AddRange(parameters.Select(CloneParameter).ToArray());
    var total = Convert.ToInt32(await countCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);

    await using var cmd = new NpgsqlCommand($"""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE {whereSql}
        ORDER BY t.date DESC, t.id DESC
        LIMIT @limit OFFSET @offset
        """, conn);
    cmd.Parameters.AddRange(parameters.Select(CloneParameter).ToArray());
    cmd.Parameters.AddWithValue("limit", pageSize);
    cmd.Parameters.AddWithValue("offset", Math.Max(0, (page - 1) * pageSize));

    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(ReadTransaction(reader));
    }

    return new
    {
        ok = true,
        action = "query_operation_records",
        child = target,
        data = new
        {
            items = rows,
            total,
            page,
            page_size = pageSize
        }
    };
}

static async Task<object> McpCreateRecord(string connectionString, JsonObject arguments)
{
    if (!TryParseDateFilter(arguments.String("date"), out _))
    {
        return new { ok = false, error = "date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    var body = await NormalizeRecordArguments(connectionString, arguments);
    var result = await CreateTransaction(connectionString, body);
    if (result.ContainsKey("error"))
    {
        return new { ok = false, error = result["error"] };
    }

    return new { ok = true, action = "create_record", transaction = result["transaction"] };
}

static async Task<object> McpUpdateRecord(string connectionString, JsonObject arguments)
{
    var id = arguments.Int("transaction_id");
    if (id is null)
    {
        return new { ok = false, error = "缺少记录ID" };
    }
    if (!TryParseDateFilter(arguments.String("date"), out _))
    {
        return new { ok = false, error = "date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    var body = await NormalizeRecordArguments(connectionString, arguments, allowMissingChild: true);
    var result = await UpdateTransaction(connectionString, id.Value, body);
    if (result.ContainsKey("error"))
    {
        return new { ok = false, error = result["error"] };
    }

    return new { ok = true, action = "update_record", transaction = result["transaction"] };
}

static async Task<object> McpDeleteRecord(string connectionString, JsonObject arguments)
{
    var id = arguments.Int("transaction_id");
    if (id is null)
    {
        return new { ok = false, error = "缺少记录ID" };
    }

    var result = await DeleteTransaction(connectionString, id.Value);
    if (result.ContainsKey("error"))
    {
        return new { ok = false, error = result["error"] };
    }

    return new { ok = true, action = "delete_record", transaction = result["transaction"] };
}

static async Task<object> McpQueryChildren(string connectionString, JsonObject? arguments = null)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = arguments is null ? null : ResolveChildByReference(children, arguments);
    var familyGroupId = arguments?.Int("family_group_id");
    var hasChildReference = HasChildReference(arguments);
    if (hasChildReference && target is null)
    {
        return ChildReferenceNotFound("query_children", familyGroupId);
    }

    return new
    {
        ok = true,
        action = "query_children",
        family_group_id = familyGroupId,
        count = target is null ? children.Count : 1,
        child = target,
        children = target is null ? children : null
    };
}

static async Task<object> McpQueryRules(string connectionString)
{
    return new { ok = true, action = "query_rules", data = await GetRules(connectionString) };
}

static async Task<object> McpCreateRule(string connectionString, JsonObject arguments)
{
    var name = arguments.String("name").Trim();
    if (string.IsNullOrWhiteSpace(name))
    {
        return new { ok = false, error = "规则名称不能为空" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO rules (name, category, points, cash_cny, description)
        VALUES (@name, @category, @points, @cash_cny, @description)
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("name", name);
    cmd.Parameters.AddWithValue("category", arguments.String("category"));
    cmd.Parameters.AddWithValue("points", arguments.Decimal("points") ?? 0);
    cmd.Parameters.AddWithValue("cash_cny", arguments.Decimal("cash_cny") ?? 0);
    cmd.Parameters.AddWithValue("description", arguments.String("description"));
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return new { ok = true, action = "create_rule", rule = ReadRule(reader) };
}

static async Task<object> McpUpdateRule(string connectionString, JsonObject arguments)
{
    var id = arguments.Int("rule_id");
    if (id is null)
    {
        return new { ok = false, error = "缺少规则ID" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE rules
        SET name = COALESCE(@name, name),
            category = COALESCE(@category, category),
            points = COALESCE(@points, points),
            cash_cny = COALESCE(@cash_cny, cash_cny),
            description = COALESCE(@description, description)
        WHERE id = @id
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("id", id.Value);
    cmd.Parameters.AddWithValue("name", arguments.ContainsKey("name") ? arguments.String("name") : DBNull.Value);
    cmd.Parameters.AddWithValue("category", arguments.ContainsKey("category") ? arguments.String("category") : DBNull.Value);
    cmd.Parameters.AddWithValue("points", arguments.ContainsKey("points") ? arguments.Decimal("points") ?? 0 : DBNull.Value);
    cmd.Parameters.AddWithValue("cash_cny", arguments.ContainsKey("cash_cny") ? arguments.Decimal("cash_cny") ?? 0 : DBNull.Value);
    cmd.Parameters.AddWithValue("description", arguments.ContainsKey("description") ? arguments.String("description") : DBNull.Value);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return new { ok = false, error = "规则不存在" };
    }
    return new { ok = true, action = "update_rule", rule = ReadRule(reader) };
}

static async Task<object> McpDeleteRule(string connectionString, JsonObject arguments)
{
    var id = arguments.Int("rule_id");
    if (id is null)
    {
        return new { ok = false, error = "缺少规则ID" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM rules WHERE id = @id RETURNING *", conn);
    cmd.Parameters.AddWithValue("id", id.Value);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return new { ok = false, error = "规则不存在" };
    }
    return new { ok = true, action = "delete_rule", rule = ReadRule(reader) };
}

static async Task<object> McpQueryFamilyGroups(string connectionString, JsonObject arguments)
{
    var userId = arguments.String("user_id", DefaultUserId);
    return new { ok = true, action = "query_family_groups", familyGroups = await GetFamilyGroups(connectionString, userId) };
}

static async Task<object> McpCreateFamilyGroup(string connectionString, JsonObject arguments)
{
    var userId = arguments.String("user_id", DefaultUserId);
    var result = await CreateFamilyGroup(connectionString, arguments.String("name"), userId, arguments.String("description"));
    return result.Success
        ? new { ok = true, action = "create_family_group", familyGroup = result.Group }
        : new { ok = false, error = result.Error };
}

static async Task<List<Dictionary<string, object?>>> GetMcpChildren(string connectionString, JsonObject? arguments)
{
    return await GetChildren(connectionString, arguments?.Int("family_group_id"));
}

static async Task<JsonObject> NormalizeRecordArguments(string connectionString, JsonObject arguments, bool allowMissingChild = false)
{
    var body = new JsonObject();
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is not null)
    {
        body["child_id"] = GetInt(target, "id");
    }
    else if (!allowMissingChild)
    {
        body["child_id"] = arguments.Int("child_id") ?? 0;
    }

    var type = NormalizeTransactionType(arguments.String("type"));
    if (string.IsNullOrWhiteSpace(type))
    {
        type = arguments.ContainsKey("cash_cny")
            ? "cash"
            : allowMissingChild ? "" : "points";
    }

    var delta = arguments.Decimal("delta");
    var direction = arguments.String("direction");
    if (direction != "+" && direction != "-")
    {
        direction = delta is not null && delta < 0 ? "-" : "+";
    }

    if (!string.IsNullOrWhiteSpace(type)) body["type"] = type;
    if (!allowMissingChild || arguments.ContainsKey("direction") || arguments.ContainsKey("delta")) body["direction"] = direction;
    if (!allowMissingChild || arguments.ContainsKey("date")) body["date"] = arguments.String("date", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
    if (!allowMissingChild || arguments.ContainsKey("category")) body["category"] = arguments.String("category");
    if (!allowMissingChild || arguments.ContainsKey("description")) body["description"] = arguments.String("description");
    if (!allowMissingChild || arguments.ContainsKey("notes")) body["notes"] = arguments.String("notes");
    if (type == "cash")
    {
        body["cash_cny"] = Math.Abs(arguments.Decimal("cash_cny") ?? 0);
    }
    else if (type == "items")
    {
        body["items"] = arguments.String("items");
    }
    else if (!allowMissingChild || arguments.ContainsKey("points") || arguments.ContainsKey("delta"))
    {
        body["points"] = Math.Abs(arguments.Decimal("points") ?? delta ?? 0);
    }

    return body;
}

static async Task<Dictionary<string, object?>> UpdateTransaction(string connectionString, int id, JsonObject body)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var existing = await ReadTransactionForUpdate(conn, tx, id);
        if (existing is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "记录不存在" };
        }

        await ReverseTransactionAccountEffect(conn, tx, existing);

        var childId = body.Int("child_id") ?? GetInt(existing, "child_id");
        var type = NormalizeTransactionType(body.String("type", Convert.ToString(existing["rawType"], CultureInfo.InvariantCulture) ?? "points"));
        var direction = body.String("direction", Convert.ToString(existing["direction"], CultureInfo.InvariantCulture) ?? "+");
        var points = body.Decimal("points") ?? GetDecimal(existing, "points");
        var cash = body.Decimal("cash_cny") ?? GetDecimal(existing, "cash_cny");
        var items = body.String("items", Convert.ToString(existing["items"], CultureInfo.InvariantCulture) ?? "");

        await using var cmd = new NpgsqlCommand("""
            UPDATE transactions
            SET date = @date,
                child_id = @child_id,
                type = @type,
                direction = @direction,
                category = @category,
                description = @description,
                points = @points,
                cash_cny = @cash_cny,
                items = @items,
                notes = @notes
            WHERE id = @id
            RETURNING *
            """, conn, tx);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("date", DateOnly.Parse(body.String("date", Convert.ToString(existing["date"], CultureInfo.InvariantCulture) ?? DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)), CultureInfo.InvariantCulture));
        cmd.Parameters.AddWithValue("child_id", childId);
        cmd.Parameters.AddWithValue("type", type);
        cmd.Parameters.AddWithValue("direction", direction);
        cmd.Parameters.AddWithValue("category", body.String("category", Convert.ToString(existing["category"], CultureInfo.InvariantCulture) ?? ""));
        cmd.Parameters.AddWithValue("description", body.String("description", Convert.ToString(existing["description"], CultureInfo.InvariantCulture) ?? ""));
        cmd.Parameters.AddWithValue("points", type == "points" ? Math.Abs(points) : 0);
        cmd.Parameters.AddWithValue("cash_cny", type == "cash" ? Math.Abs(cash) : 0);
        cmd.Parameters.AddWithValue("items", items);
        cmd.Parameters.AddWithValue("notes", body.String("notes", Convert.ToString(existing["notes"], CultureInfo.InvariantCulture) ?? ""));

        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        var updated = ReadTransaction(reader);
        await reader.CloseAsync();

        await UpdateAccount(conn, tx, childId, type, direction, points, cash, items);
        await tx.CommitAsync();
        return new Dictionary<string, object?> { ["transaction"] = updated, ["status"] = "ok" };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> DeleteTransaction(string connectionString, int id, int? familyGroupId = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var existing = await ReadTransactionForUpdate(conn, tx, id, familyGroupId);
        if (existing is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "记录不存在" };
        }

        await ReverseTransactionAccountEffect(conn, tx, existing);
        await using var cmd = new NpgsqlCommand("DELETE FROM transactions WHERE id = @id", conn, tx);
        cmd.Parameters.AddWithValue("id", id);
        await cmd.ExecuteNonQueryAsync();
        await tx.CommitAsync();
        return new Dictionary<string, object?> { ["transaction"] = existing, ["status"] = "ok" };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>?> ReadTransactionForUpdate(NpgsqlConnection conn, NpgsqlTransaction tx, int id, int? familyGroupId = null)
{
    await using var cmd = new NpgsqlCommand("""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE t.id = @id
          AND (@family_group_id IS NULL OR c.family_group_id = @family_group_id)
        FOR UPDATE OF t
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
    {
        Value = familyGroupId is null ? DBNull.Value : familyGroupId.Value
    });
    await using var reader = await cmd.ExecuteReaderAsync();
    return await reader.ReadAsync() ? ReadTransaction(reader) : null;
}

static async Task ReverseTransactionAccountEffect(NpgsqlConnection conn, NpgsqlTransaction tx, IReadOnlyDictionary<string, object?> transaction)
{
    var type = Convert.ToString(transaction["rawType"], CultureInfo.InvariantCulture) ?? "points";
    var wasCredit = string.Equals(Convert.ToString(transaction["direction"], CultureInfo.InvariantCulture), "+", StringComparison.Ordinal);
    var sql = (type, wasCredit) switch
    {
        ("points", true) => "UPDATE accounts SET points = points - @points, points_earned = GREATEST(points_earned - @points, 0), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        ("points", false) => "UPDATE accounts SET points = points + @points, points_spent = GREATEST(points_spent - @points, 0), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        ("cash", true) => "UPDATE accounts SET cash_cny = cash_cny - @cash, cash_earned = GREATEST(cash_earned - @cash, 0), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        ("cash", false) => "UPDATE accounts SET cash_cny = cash_cny + @cash, cash_spent = GREATEST(cash_spent - @cash, 0), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        ("items", true) => "UPDATE accounts SET items_count = GREATEST(items_count - 1, 0), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        ("items", false) => "UPDATE accounts SET items_count = items_count + 1, updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        _ => ""
    };
    if (string.IsNullOrWhiteSpace(sql))
    {
        return;
    }

    await using var cmd = new NpgsqlCommand(sql, conn, tx);
    cmd.Parameters.AddWithValue("child_id", GetInt(transaction, "child_id"));
    cmd.Parameters.AddWithValue("points", Math.Abs(GetDecimal(transaction, "points")));
    cmd.Parameters.AddWithValue("cash", Math.Abs(GetDecimal(transaction, "cash_cny")));
    await cmd.ExecuteNonQueryAsync();
}

static Dictionary<string, object?>? ResolveChildByReference(List<Dictionary<string, object?>> children, JsonObject arguments)
{
    var childId = arguments.Int("child_id");
    if (childId is not null)
    {
        return children.FirstOrDefault(c => GetInt(c, "id") == childId);
    }

    var childName = arguments.String("child_name");
    if (string.IsNullOrWhiteSpace(childName))
    {
        return null;
    }

    var target = childName.Trim();
    return children.FirstOrDefault(c =>
            string.Equals(Convert.ToString(c["name"], CultureInfo.InvariantCulture) ?? string.Empty, target, StringComparison.OrdinalIgnoreCase))
        ?? children.FirstOrDefault(c =>
            Convert.ToString(c["name"], CultureInfo.InvariantCulture)?
                .Contains(target, StringComparison.OrdinalIgnoreCase) == true);
}

static bool HasChildReference(JsonObject? arguments)
{
    return arguments is not null
        && (arguments.Int("child_id") is not null || !string.IsNullOrWhiteSpace(arguments.String("child_name")));
}

static object ChildReferenceNotFound(string action, int? familyGroupId)
{
    return new
    {
        ok = false,
        action,
        family_group_id = familyGroupId,
        count = 0,
        child = (object?)null,
        children = (object?)null,
        requires_child_list_retry = true,
        retry_tool = FamilyRewardMcpListChildrenToolName,
        retry_arguments = familyGroupId is null
            ? new JsonObject()
            : new JsonObject { ["family_group_id"] = familyGroupId.Value },
        retry_instruction = "指定孩子未命中。智能体必须继续调用 retry_tool 查询完整孩子清单，并将用户输入与清单中的 ID/姓名逐一比较，判断是否存在别名、错别字、同音或输入差异，再向用户说明最可能的匹配或请用户确认。",
        error = "未找到匹配的孩子；不要直接结束。请先查询完整孩子清单并与用户输入比较，避免由于别名、错别字或输入差异导致误判。"
    };
}

static async Task<(bool Success, Dictionary<string, object?>? Child, string? Error)> CreateChildCore(string connectionString, JsonObject body, int? familyGroupId = null)
{
    var name = body.String("name").Trim();
    if (string.IsNullOrWhiteSpace(name))
    {
        return (false, null, "孩子姓名不能为空");
    }
    var userId = body.String("user_id");
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = body.String("userId", DefaultUserId);
    }
    var profileKey = body.String("profile_key");
    if (string.IsNullOrWhiteSpace(profileKey))
    {
        profileKey = body.String("profileKey");
    }
    if (string.IsNullOrWhiteSpace(profileKey))
    {
        profileKey = MakeChildProfileKey(userId, name);
    }

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        await using (var profileCmd = new NpgsqlCommand("""
            INSERT INTO child_profiles (profile_key, name, status, note)
            VALUES (@profile_key, @name, @status, @note)
            ON CONFLICT (profile_key) DO NOTHING
            """, conn, tx))
        {
            profileCmd.Parameters.AddWithValue("profile_key", profileKey);
            profileCmd.Parameters.AddWithValue("name", name);
            profileCmd.Parameters.AddWithValue("status", body.String("status", "active"));
            profileCmd.Parameters.AddWithValue("note", body.String("note"));
            await profileCmd.ExecuteNonQueryAsync();
        }

        await using var cmd = new NpgsqlCommand("""
            INSERT INTO children (family_group_id, profile_key, name, status, note)
            SELECT @family_group_id, cp.profile_key, cp.name, cp.status, cp.note
            FROM child_profiles cp
            WHERE cp.profile_key = @profile_key
            RETURNING id, name, status, note, profile_key, created_at, updated_at
            """, conn, tx);
        cmd.Parameters.AddWithValue("family_group_id", familyGroupId is null ? DBNull.Value : familyGroupId.Value);
        cmd.Parameters.AddWithValue("profile_key", profileKey);
        cmd.Parameters.AddWithValue("name", name);
        cmd.Parameters.AddWithValue("status", body.String("status", "active"));
        cmd.Parameters.AddWithValue("note", body.String("note"));
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        var child = ReadChild(reader);
        await reader.CloseAsync();

        await using (var membershipsCmd = new NpgsqlCommand("""
            INSERT INTO children (family_group_id, profile_key, name, status, note)
            SELECT fg.id, cp.profile_key, cp.name, cp.status, cp.note
            FROM family_groups fg
            JOIN child_profiles cp ON cp.profile_key = @profile_key
            LEFT JOIN family_group_users fgu
              ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
            WHERE fg.created_by = @user_id OR fgu.user_id = @user_id
            ON CONFLICT (family_group_id, profile_key) WHERE profile_key IS NOT NULL DO NOTHING
            """, conn, tx))
        {
            membershipsCmd.Parameters.AddWithValue("profile_key", profileKey);
            membershipsCmd.Parameters.AddWithValue("user_id", userId);
            await membershipsCmd.ExecuteNonQueryAsync();
        }

        await using var accountCmd = new NpgsqlCommand("""
            INSERT INTO accounts (child_id, profile_key, points, cash_cny, items_count)
            VALUES (@child_id, @profile_key, @points, @cash_cny, @items_count)
            ON CONFLICT (profile_key) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            """, conn, tx);
        accountCmd.Parameters.AddWithValue("child_id", GetInt(child, "id"));
        accountCmd.Parameters.AddWithValue("profile_key", profileKey);
        accountCmd.Parameters.AddWithValue("points", body.Decimal("score") ?? body.Decimal("points") ?? 0);
        accountCmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash") ?? body.Decimal("cash_cny") ?? 0);
        accountCmd.Parameters.AddWithValue("items_count", body.Int("items") ?? 0);
        await accountCmd.ExecuteNonQueryAsync();

        var parentAppUserId = body.String("parent_app_user_id");
        if (string.IsNullOrWhiteSpace(parentAppUserId))
        {
            parentAppUserId = body.String("parentAppUserId");
        }
        if (!string.IsNullOrWhiteSpace(parentAppUserId))
        {
            await using var bindingCmd = new NpgsqlCommand("""
                INSERT INTO child_user_bindings (parent_app_user_id, child_profile_key, child_id)
                VALUES (@parent_app_user_id, @child_profile_key, @child_id)
                ON CONFLICT (parent_app_user_id, child_profile_key) DO UPDATE SET
                    child_id = @child_id,
                    updated_at = CURRENT_TIMESTAMP
                """, conn, tx);
            bindingCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            bindingCmd.Parameters.AddWithValue("child_profile_key", profileKey);
            bindingCmd.Parameters.AddWithValue("child_id", GetInt(child, "id"));
            await bindingCmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        var created = (await GetChildren(connectionString, familyGroupId)).First(c => GetInt(c, "id") == GetInt(child, "id"));
        return (true, created, null);
    }
    catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
    {
        await tx.RollbackAsync();
        return (false, null, "该孩子已存在");
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return (false, null, ex.Message);
    }
}

static string BuildConnectionString(IConfiguration configuration)
{
    var configured = configuration.GetConnectionString("Default");
    if (!string.IsNullOrWhiteSpace(configured))
    {
        return configured;
    }

    var builder = new NpgsqlConnectionStringBuilder
    {
        Host = Environment.GetEnvironmentVariable("PGHOST") ?? "localhost",
        Port = int.TryParse(Environment.GetEnvironmentVariable("PGPORT"), out var port) ? port : 5432,
        Database = Environment.GetEnvironmentVariable("PGDATABASE") ?? "family_rewards",
        Username = Environment.GetEnvironmentVariable("PGUSER") ?? Environment.UserName,
        Password = Environment.GetEnvironmentVariable("PGPASSWORD") ?? Environment.GetEnvironmentVariable("PG_PASSWORD") ?? "",
        IncludeErrorDetail = true
    };
    return builder.ConnectionString;
}

static async Task<NpgsqlConnection> OpenConnection(string connectionString)
{
    var conn = new NpgsqlConnection(connectionString);
    await conn.OpenAsync();
    await EnsureUtf8DatabaseEncoding(conn);
    return conn;
}

static async Task EnsureUtf8DatabaseEncoding(NpgsqlConnection conn)
{
    await using (var cmd = new NpgsqlCommand("SET client_encoding = 'UTF8'", conn))
    {
        await cmd.ExecuteNonQueryAsync();
    }

    await using var checkCmd = new NpgsqlCommand("SHOW server_encoding", conn);
    var serverEncoding = Convert.ToString(await checkCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
    if (!string.Equals(serverEncoding, "UTF8", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException($"PostgreSQL 数据库编码必须是 UTF8，当前是 {serverEncoding}");
    }
}

static async Task InitDatabase(string connectionString)
{
    await using var conn = await OpenConnection(connectionString);
    var statements = new[]
    {
        """
        CREATE TABLE IF NOT EXISTS family_groups (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL UNIQUE,
            description TEXT,
            created_by VARCHAR(100) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS family_group_users (
            id SERIAL PRIMARY KEY,
            family_group_id INTEGER NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
            user_id VARCHAR(100) NOT NULL,
            role VARCHAR(30) DEFAULT 'member',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(family_group_id, user_id)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS family_group_invites (
            id SERIAL PRIMARY KEY,
            family_group_id INTEGER NOT NULL UNIQUE REFERENCES family_groups(id) ON DELETE CASCADE,
            invite_code VARCHAR(8) NOT NULL UNIQUE,
            created_by VARCHAR(180) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            revoked_at TIMESTAMP NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS app_user_profiles (
            id SERIAL PRIMARY KEY,
            unified_user_id VARCHAR(160) NOT NULL,
            username VARCHAR(160) NOT NULL,
            channel VARCHAR(20) NOT NULL DEFAULT 'pc',
            role VARCHAR(20) NOT NULL,
            app_user_id VARCHAR(180) NOT NULL,
            child_profile_key VARCHAR(180),
            child_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(unified_user_id, channel)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS child_user_bindings (
            id SERIAL PRIMARY KEY,
            parent_app_user_id VARCHAR(180) NOT NULL,
            child_profile_key VARCHAR(180) NOT NULL,
            child_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(parent_app_user_id, child_profile_key)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS child_profiles (
            profile_key VARCHAR(180) PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            note TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS child_auth_codes (
            id SERIAL PRIMARY KEY,
            child_id INTEGER NOT NULL,
            family_group_id INTEGER NOT NULL,
            child_profile_key VARCHAR(180) NOT NULL,
            parent_app_user_id VARCHAR(180) NOT NULL,
            code_hash VARCHAR(128) NOT NULL UNIQUE,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS watch_device_bindings (
            id SERIAL PRIMARY KEY,
            child_id INTEGER NOT NULL,
            family_group_id INTEGER NOT NULL,
            child_profile_key VARCHAR(180) NOT NULL,
            parent_app_user_id VARCHAR(180) NOT NULL,
            device_token_hash VARCHAR(128) NOT NULL UNIQUE,
            device_name VARCHAR(240) NOT NULL DEFAULT '',
            platform VARCHAR(80) NOT NULL DEFAULT '',
            user_agent TEXT NOT NULL DEFAULT '',
            bound_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_seen_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            revoked_at TIMESTAMP NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS watch_device_unbind_codes (
            id SERIAL PRIMARY KEY,
            device_binding_id INTEGER NOT NULL REFERENCES watch_device_bindings(id) ON DELETE CASCADE,
            child_id INTEGER NOT NULL,
            family_group_id INTEGER NOT NULL,
            parent_app_user_id VARCHAR(180) NOT NULL,
            code_hash VARCHAR(128) NOT NULL UNIQUE,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS children (
            id SERIAL PRIMARY KEY,
            family_group_id INTEGER REFERENCES family_groups(id) ON DELETE RESTRICT,
            name VARCHAR(50) NOT NULL,
            status VARCHAR(20) DEFAULT 'active',
            note TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(family_group_id, name)
        )
        """,
        "ALTER TABLE children ADD COLUMN IF NOT EXISTS family_group_id INTEGER",
        "ALTER TABLE children ADD COLUMN IF NOT EXISTS profile_key VARCHAR(160)",
        """
        DO $$
        BEGIN
            ALTER TABLE children
            ADD CONSTRAINT fk_children_family_group
            FOREIGN KEY (family_group_id) REFERENCES family_groups(id) ON DELETE RESTRICT;
        EXCEPTION
            WHEN duplicate_object THEN NULL;
        END $$;
        """,
        "ALTER TABLE children DROP CONSTRAINT IF EXISTS children_name_key",
        "ALTER TABLE children DROP CONSTRAINT IF EXISTS children_family_group_id_name_key",
        "DROP INDEX IF EXISTS ux_children_family_group_name",
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_children_family_group_profile ON children(family_group_id, profile_key) WHERE profile_key IS NOT NULL",
        """
        CREATE TABLE IF NOT EXISTS accounts (
            id SERIAL PRIMARY KEY,
            child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
            points NUMERIC(10,2) DEFAULT 0,
            cash_cny NUMERIC(10,2) DEFAULT 0,
            items_count INTEGER DEFAULT 0,
            items_detail TEXT,
            points_earned NUMERIC(10,2) DEFAULT 0,
            points_spent NUMERIC(10,2) DEFAULT 0,
            cash_earned NUMERIC(10,2) DEFAULT 0,
            cash_spent NUMERIC(10,2) DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(child_id)
        )
        """,
        "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS profile_key VARCHAR(160)",
        "ALTER TABLE accounts ALTER COLUMN points TYPE NUMERIC(10,2) USING points::numeric",
        "ALTER TABLE accounts ALTER COLUMN points_earned TYPE NUMERIC(10,2) USING points_earned::numeric",
        "ALTER TABLE accounts ALTER COLUMN points_spent TYPE NUMERIC(10,2) USING points_spent::numeric",
        "UPDATE children SET profile_key = CONCAT('child-', id) WHERE profile_key IS NULL OR profile_key = ''",
        """
        INSERT INTO child_profiles (profile_key, name, status, note, created_at, updated_at)
        SELECT DISTINCT ON (profile_key)
               profile_key, name, status, note, created_at, updated_at
        FROM children
        WHERE profile_key IS NOT NULL AND profile_key <> ''
        ORDER BY profile_key, updated_at DESC, id DESC
        ON CONFLICT (profile_key) DO NOTHING
        """,
        """
        UPDATE children c
        SET name = cp.name,
            status = cp.status,
            note = cp.note,
            updated_at = GREATEST(c.updated_at, cp.updated_at)
        FROM child_profiles cp
        WHERE cp.profile_key = c.profile_key
          AND (c.name IS DISTINCT FROM cp.name
            OR c.status IS DISTINCT FROM cp.status
            OR c.note IS DISTINCT FROM cp.note)
        """,
        """
        UPDATE accounts a
        SET profile_key = c.profile_key
        FROM children c
        WHERE a.child_id = c.id AND (a.profile_key IS NULL OR a.profile_key = '')
        """,
        "DROP INDEX IF EXISTS ux_accounts_profile_key",
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_accounts_profile_key ON accounts(profile_key)",
        """
        CREATE TABLE IF NOT EXISTS transactions (
            id SERIAL PRIMARY KEY,
            date DATE NOT NULL,
            child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
            type VARCHAR(20) NOT NULL,
            direction VARCHAR(10) NOT NULL,
            category VARCHAR(50),
            description TEXT,
            points NUMERIC(10,2) DEFAULT 0,
            cash_cny NUMERIC(10,2) DEFAULT 0,
            items TEXT,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CHECK (direction IN ('+', '-'))
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS rules (
            id SERIAL PRIMARY KEY,
            name VARCHAR(200) NOT NULL,
            category VARCHAR(50),
            points NUMERIC(10,2) DEFAULT 0,
            cash_cny NUMERIC(10,2) DEFAULT 0,
            description TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS watch_reward_requests (
            id SERIAL PRIMARY KEY,
            family_group_id INTEGER NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
            child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
            rule_id INTEGER REFERENCES rules(id) ON DELETE SET NULL,
            title VARCHAR(120) NOT NULL,
            category VARCHAR(50),
            points NUMERIC(10,2) NOT NULL DEFAULT 0,
            note TEXT,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            requested_by VARCHAR(100),
            requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            reviewed_at TIMESTAMP NULL,
            completed_at TIMESTAMP NULL,
            review_note TEXT,
            transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS redlines (
            id SERIAL PRIMARY KEY,
            order_num INTEGER,
            rule VARCHAR(200),
            proposer VARCHAR(50),
            description TEXT,
            penalty_points INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_tx_child ON transactions(child_id)",
        "CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date)",
        "CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type)",
        "CREATE INDEX IF NOT EXISTS idx_children_family_group ON children(family_group_id)",
        "CREATE INDEX IF NOT EXISTS idx_family_group_users_user ON family_group_users(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_family_group_invites_code ON family_group_invites(invite_code) WHERE revoked_at IS NULL",
        "CREATE INDEX IF NOT EXISTS idx_app_user_profiles_unified ON app_user_profiles(unified_user_id)",
        "CREATE INDEX IF NOT EXISTS idx_child_user_bindings_parent ON child_user_bindings(parent_app_user_id)",
        "CREATE INDEX IF NOT EXISTS idx_child_user_bindings_child ON child_user_bindings(child_profile_key)",
        "CREATE INDEX IF NOT EXISTS idx_child_auth_codes_child ON child_auth_codes(child_id, expires_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_watch_device_bindings_child ON watch_device_bindings(child_id, revoked_at)",
        "CREATE INDEX IF NOT EXISTS idx_watch_device_bindings_parent ON watch_device_bindings(parent_app_user_id)",
        """
        UPDATE watch_device_bindings newer
        SET revoked_at = CURRENT_TIMESTAMP
        WHERE newer.revoked_at IS NULL
          AND EXISTS (
              SELECT 1
              FROM watch_device_bindings keeper
              WHERE keeper.child_profile_key = newer.child_profile_key
                AND keeper.revoked_at IS NULL
                AND keeper.id < newer.id
          )
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_watch_device_bindings_active_child ON watch_device_bindings(child_profile_key) WHERE revoked_at IS NULL",
        "CREATE INDEX IF NOT EXISTS idx_watch_device_unbind_codes_device ON watch_device_unbind_codes(device_binding_id, expires_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_watch_reward_requests_family_child ON watch_reward_requests(family_group_id, child_id, requested_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_watch_reward_requests_status ON watch_reward_requests(status)"
    };

    foreach (var sql in statements)
    {
        await using var cmd = new NpgsqlCommand(sql, conn);
        await cmd.ExecuteNonQueryAsync();
    }

    var defaultFamilyGroupId = await EnsureFamilyGroup(conn, DefaultFamilyGroupName, DefaultUserId);
    await using (var migrateCmd = new NpgsqlCommand("""
        UPDATE children
        SET family_group_id = @family_group_id
        WHERE family_group_id IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM children existing
              WHERE existing.family_group_id = @family_group_id
                AND existing.name = children.name
          )
        """, conn))
    {
        migrateCmd.Parameters.AddWithValue("family_group_id", defaultFamilyGroupId);
        await migrateCmd.ExecuteNonQueryAsync();
    }

    await SeedRules(conn);
}

static async Task SeedRules(NpgsqlConnection conn)
{
    await using (var countCmd = new NpgsqlCommand("SELECT COUNT(*) FROM rules", conn))
    {
        if (Convert.ToInt32(await countCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
        {
            var rules = new (string Name, string Category, decimal Points, string Description)[]
            {
                ("按时/及时完成作业", "学习", 5, "规定时间内完成"),
                ("主动完成作业", "学习", 3, "不用催促"),
                ("作业优秀/全对", "学习", 2, "额外奖励"),
                ("主动刷牙", "规矩", 2, "早晚各一次"),
                ("好好吃饭", "规矩", 2, "不挑食、按时吃"),
                ("自己收拾玩具", "规矩", 2, "玩完归位"),
                ("按时睡觉", "规矩", 2, "不拖延"),
                ("主动看书", "学习", 3, "自己拿起书看"),
                ("帮忙做家务", "帮忙", 3, "倒垃圾、擦桌子等"),
                ("分享玩具", "规矩", 2, "不抢不争")
            };

            foreach (var rule in rules)
            {
                await using var cmd = new NpgsqlCommand("""
                    INSERT INTO rules (name, category, points, cash_cny, description)
                    VALUES (@name, @category, @points, 0, @description)
                    """, conn);
                cmd.Parameters.AddWithValue("name", rule.Name);
                cmd.Parameters.AddWithValue("category", rule.Category);
                cmd.Parameters.AddWithValue("points", rule.Points);
                cmd.Parameters.AddWithValue("description", rule.Description);
                await cmd.ExecuteNonQueryAsync();
            }
        }
    }

    await using (var countCmd = new NpgsqlCommand("SELECT COUNT(*) FROM redlines", conn))
    {
        if (Convert.ToInt32(await countCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
        {
            var redlines = new (int Order, string Rule, string Proposer, string Description, int Penalty)[]
            {
                (1, "不大喊大叫", "彦谦", "无论什么原因都不允许大喊大叫、乱发脾气", 10),
                (2, "不跟紧大人", "", "外出时必须紧跟父母，不得独自跑开、躲藏", 15),
                (3, "不碰危险物品", "", "不碰剪刀、刀具、火源、药品、电源插座", 20),
                (4, "不私自下水", "", "靠近水边必须有大人陪同，不得独自下水", 20),
                (5, "不跟陌生人走", "", "无论什么理由，不得跟随陌生人离开", 20)
            };

            foreach (var redline in redlines)
            {
                await using var cmd = new NpgsqlCommand("""
                    INSERT INTO redlines (order_num, rule, proposer, description, penalty_points)
                    VALUES (@order_num, @rule, @proposer, @description, @penalty)
                    """, conn);
                cmd.Parameters.AddWithValue("order_num", redline.Order);
                cmd.Parameters.AddWithValue("rule", redline.Rule);
                cmd.Parameters.AddWithValue("proposer", redline.Proposer);
                cmd.Parameters.AddWithValue("description", redline.Description);
                cmd.Parameters.AddWithValue("penalty", redline.Penalty);
                await cmd.ExecuteNonQueryAsync();
            }
        }
    }
}

static async Task<int> EnsureFamilyGroup(NpgsqlConnection conn, string name, string userId, string description = "")
{
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO family_groups (name, description, created_by)
        VALUES (@name, @description, @created_by)
        ON CONFLICT (name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
        RETURNING id
        """, conn);
    cmd.Parameters.AddWithValue("name", name.Trim());
    cmd.Parameters.AddWithValue("description", description);
    cmd.Parameters.AddWithValue("created_by", string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId.Trim());
    var id = Convert.ToInt32(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);

    await using var userCmd = new NpgsqlCommand("""
        INSERT INTO family_group_users (family_group_id, user_id, role)
        VALUES (@family_group_id, @user_id, 'owner')
        ON CONFLICT (family_group_id, user_id) DO UPDATE SET role = family_group_users.role, updated_at = CURRENT_TIMESTAMP
        """, conn);
    userCmd.Parameters.AddWithValue("family_group_id", id);
    userCmd.Parameters.AddWithValue("user_id", string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId.Trim());
    await userCmd.ExecuteNonQueryAsync();

    return id;
}

static async Task<List<Dictionary<string, object?>>> GetFamilyGroups(string connectionString, string userId)
{
    await using var conn = await OpenConnection(connectionString);
    await EnsureFamilyGroup(conn, DefaultFamilyGroupName, string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId);

    await using var cmd = new NpgsqlCommand("""
        SELECT fg.id, fg.name, fg.description, fg.created_by, fgu.role, fg.created_at, fg.updated_at
        FROM family_groups fg
        LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.created_by = @user_id OR fgu.user_id = @user_id OR @user_id = @default_user_id
        ORDER BY fg.id
        """, conn);
    cmd.Parameters.AddWithValue("user_id", string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId);
    cmd.Parameters.AddWithValue("default_user_id", DefaultUserId);

    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(ReadFamilyGroup(reader));
    }
    return rows;
}

static async Task<(bool Success, Dictionary<string, object?>? Group, string? Error)> CreateFamilyGroup(string connectionString, string name, string userId, string description)
{
    name = name.Trim();
    if (string.IsNullOrWhiteSpace(name))
    {
        return (false, null, "家庭组名称不能为空");
    }

    await using var conn = await OpenConnection(connectionString);
    try
    {
        var normalizedUserId = string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId;
        var id = await EnsureFamilyGroup(conn, name, normalizedUserId, description);
        await SyncOwnedChildrenToFamilyGroup(conn, id, normalizedUserId, "由所属账号自动加入");
        await using var cmd = new NpgsqlCommand("""
            SELECT fg.id, fg.name, fg.description, fg.created_by, fgu.role, fg.created_at, fg.updated_at
            FROM family_groups fg
            LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
            WHERE fg.id = @id
            """, conn);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("user_id", normalizedUserId);
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return (true, ReadFamilyGroup(reader), null);
    }
    catch (Exception ex)
    {
        return (false, null, ex.Message);
    }
}

static async Task<bool> UpsertFamilyGroupUser(string connectionString, int familyGroupId, string userId, string role)
{
    await using var conn = await OpenConnection(connectionString);
    await using (var existsCmd = new NpgsqlCommand("SELECT COUNT(*) FROM family_groups WHERE id = @id", conn))
    {
        existsCmd.Parameters.AddWithValue("id", familyGroupId);
        if (Convert.ToInt32(await existsCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
        {
            return false;
        }
    }

    await using var cmd = new NpgsqlCommand("""
        INSERT INTO family_group_users (family_group_id, user_id, role)
        VALUES (@family_group_id, @user_id, @role)
        ON CONFLICT (family_group_id, user_id) DO UPDATE SET role = @role, updated_at = CURRENT_TIMESTAMP
        """, conn);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.AddWithValue("user_id", userId.Trim());
    cmd.Parameters.AddWithValue("role", string.IsNullOrWhiteSpace(role) ? "member" : role.Trim());
    await cmd.ExecuteNonQueryAsync();
    return true;
}

static async Task<(bool Success, bool Forbidden, string FamilyGroupName, string InviteCode, string Error)> GetOrCreateFamilyGroupInvite(
    string connectionString,
    int familyGroupId,
    string appUserId)
{
    await using var conn = await OpenConnection(connectionString);
    string familyGroupName;
    await using (var groupCmd = new NpgsqlCommand("""
        SELECT fg.name
        FROM family_groups fg
        LEFT JOIN family_group_users fgu
          ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.id = @family_group_id
          AND (fg.created_by = @user_id OR fgu.role = 'owner' OR @user_id = @default_user_id)
        LIMIT 1
        """, conn))
    {
        groupCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        groupCmd.Parameters.AddWithValue("user_id", appUserId);
        groupCmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
        var result = await groupCmd.ExecuteScalarAsync();
        if (result is null || result is DBNull)
        {
            await using var existsCmd = new NpgsqlCommand("SELECT COUNT(*) FROM family_groups WHERE id = @id", conn);
            existsCmd.Parameters.AddWithValue("id", familyGroupId);
            var exists = Convert.ToInt32(await existsCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0;
            return (false, exists, "", "", exists ? "只有家庭组管理员可以生成邀请码" : "家庭组不存在");
        }
        familyGroupName = Convert.ToString(result, CultureInfo.InvariantCulture) ?? "";
    }

    await using (var existingCmd = new NpgsqlCommand("""
        SELECT invite_code
        FROM family_group_invites
        WHERE family_group_id = @family_group_id AND revoked_at IS NULL
        LIMIT 1
        """, conn))
    {
        existingCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        var existing = await existingCmd.ExecuteScalarAsync();
        if (existing is not null && existing is not DBNull)
        {
            return (true, false, familyGroupName, Convert.ToString(existing, CultureInfo.InvariantCulture) ?? "", "");
        }
    }

    for (var attempt = 0; attempt < 10; attempt++)
    {
        var inviteCode = RandomNumberGenerator.GetInt32(0, 100_000_000).ToString("D8", CultureInfo.InvariantCulture);
        try
        {
            await using var insertCmd = new NpgsqlCommand("""
                INSERT INTO family_group_invites (family_group_id, invite_code, created_by)
                VALUES (@family_group_id, @invite_code, @created_by)
                RETURNING invite_code
                """, conn);
            insertCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            insertCmd.Parameters.AddWithValue("invite_code", inviteCode);
            insertCmd.Parameters.AddWithValue("created_by", appUserId);
            var created = Convert.ToString(await insertCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) ?? "";
            return (true, false, familyGroupName, created, "");
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            await using var retryCmd = new NpgsqlCommand("""
                SELECT invite_code
                FROM family_group_invites
                WHERE family_group_id = @family_group_id AND revoked_at IS NULL
                LIMIT 1
                """, conn);
            retryCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            var existing = await retryCmd.ExecuteScalarAsync();
            if (existing is not null && existing is not DBNull)
            {
                return (true, false, familyGroupName, Convert.ToString(existing, CultureInfo.InvariantCulture) ?? "", "");
            }
        }
    }

    return (false, false, familyGroupName, "", "邀请码生成失败，请重试");
}

static string NormalizeFamilyGroupInviteCode(string value) => value.Trim();

static async Task<(bool Success, int FamilyGroupId, string FamilyGroupName, int LinkedChildCount, string Error)> JoinFamilyGroupByInviteCode(
    string connectionString,
    string inviteCode,
    string appUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var transaction = await conn.BeginTransactionAsync();
    int familyGroupId;
    string familyGroupName;
    await using (var inviteCmd = new NpgsqlCommand("""
        SELECT fg.id, fg.name
        FROM family_group_invites fgi
        JOIN family_groups fg ON fg.id = fgi.family_group_id
        WHERE fgi.invite_code = @invite_code AND fgi.revoked_at IS NULL
        LIMIT 1
        """, conn, transaction))
    {
        inviteCmd.Parameters.AddWithValue("invite_code", inviteCode);
        await using var reader = await inviteCmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            return (false, 0, "", 0, "邀请码不存在或已失效");
        }
        familyGroupId = reader.Int("id");
        familyGroupName = reader.String("name");
    }

    await using (var memberCmd = new NpgsqlCommand("""
        INSERT INTO family_group_users (family_group_id, user_id, role)
        VALUES (@family_group_id, @user_id, 'member')
        ON CONFLICT (family_group_id, user_id) DO UPDATE SET
            updated_at = CURRENT_TIMESTAMP
        """, conn, transaction))
    {
        memberCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        memberCmd.Parameters.AddWithValue("user_id", appUserId);
        await memberCmd.ExecuteNonQueryAsync();
    }

    var linkedChildCount = await SyncOwnedChildrenToFamilyGroup(conn, familyGroupId, appUserId, $"由 {appUserId} 通过邀请码加入", transaction);

    await transaction.CommitAsync();
    return (true, familyGroupId, familyGroupName, linkedChildCount, "");
}

static async Task<int> SyncOwnedChildrenToFamilyGroup(NpgsqlConnection conn, int familyGroupId, string parentAppUserId, string note, NpgsqlTransaction? tx = null)
{
    var ownedChildren = new List<(string ProfileKey, string Name)>();
    await using (var childrenCmd = new NpgsqlCommand("""
        SELECT DISTINCT cp.profile_key, cp.name
        FROM child_user_bindings cub
        JOIN child_profiles cp ON cp.profile_key = cub.child_profile_key
        WHERE cub.parent_app_user_id = @parent_app_user_id
          AND cp.status = 'active'
        ORDER BY cp.name
        """, conn, tx))
    {
        childrenCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
        await using var reader = await childrenCmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            ownedChildren.Add((reader.String("profile_key"), reader.String("name")));
        }
    }

    foreach (var child in ownedChildren)
    {
        await EnsureChildInFamilyGroup(conn, familyGroupId, child.ProfileKey, child.Name, note, tx);
    }
    return ownedChildren.Count;
}

static async Task<(AppUserProfile? Profile, IResult? Error)> RequireParentProfile(string connectionString, HttpRequest request)
{
    var headerRole = request.Headers.TryGetValue("X-App-User-Role", out var roleHeader) ? NormalizeAppRole(roleHeader.ToString()) : "";
    if (headerRole == "child")
    {
        return (null, Results.Json(new { error = "孩子账号只能使用手表端积分查询和积分申请功能", code = "child_forbidden" }, statusCode: StatusCodes.Status403Forbidden));
    }
    if (headerRole == "parent" && request.Headers.TryGetValue("X-App-User-Id", out var appUserId) && !string.IsNullOrWhiteSpace(appUserId.ToString()))
    {
        return (new AppUserProfile(GetUnifiedUserId(request), GetUnifiedUsername(request), "pc", "parent", appUserId.ToString().Trim(), null, null, false), null);
    }

    var profile = await GetOrCreateAppUserProfile(connectionString, request, NormalizeIdentityChannel(request.Query.String("channel"), "pc"), null, autoCreate: false);
    if (profile.NeedsRole)
    {
        return (null, Results.Json(new { error = "请选择家长 / 孩子身份", code = "needs_role" }, statusCode: StatusCodes.Status428PreconditionRequired));
    }
    if (!string.Equals(profile.Role, "parent", StringComparison.Ordinal))
    {
        return (null, Results.Json(new { error = "孩子账号只能使用手表端积分查询和积分申请功能", code = "child_forbidden" }, statusCode: StatusCodes.Status403Forbidden));
    }
    return (profile, null);
}

static async Task<AppUserProfile> GetOrCreateAppUserProfile(
    string connectionString,
    HttpRequest request,
    string channel,
    string? role,
    bool autoCreate,
    JsonObject? body = null)
{
    channel = NormalizeIdentityChannel(channel, "pc");
    role = NormalizeAppRole(role);
    var unifiedUserId = GetUnifiedUserId(request);
    var username = GetUnifiedUsername(request);
    await using var conn = await OpenConnection(connectionString);

    if (string.IsNullOrWhiteSpace(role))
    {
        await using var existingCmd = new NpgsqlCommand("""
            SELECT *
            FROM app_user_profiles
            WHERE unified_user_id = @unified_user_id AND channel = @channel
            LIMIT 1
            """, conn);
        existingCmd.Parameters.AddWithValue("unified_user_id", unifiedUserId);
        existingCmd.Parameters.AddWithValue("channel", channel);
        await using var existingReader = await existingCmd.ExecuteReaderAsync();
        if (await existingReader.ReadAsync())
        {
            return ReadAppUserProfile(existingReader, needsRole: false);
        }
        await existingReader.CloseAsync();

        if (!autoCreate)
        {
            return new AppUserProfile(unifiedUserId, username, channel, "", "", null, null, true);
        }
        role = channel == "watch" ? "child" : "parent";
    }

    var profile = string.Equals(role, "child", StringComparison.Ordinal)
        ? await EnsureChildAppUserProfile(conn, unifiedUserId, username, channel, body)
        : await EnsureParentAppUserProfile(conn, unifiedUserId, username, channel);
    return profile;
}

static async Task<AppUserProfile> EnsureParentAppUserProfile(NpgsqlConnection conn, string unifiedUserId, string username, string channel)
{
    var appUserId = MakeParentAppUserId(username);
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO app_user_profiles (unified_user_id, username, channel, role, app_user_id)
        VALUES (@unified_user_id, @username, @channel, 'parent', @app_user_id)
        ON CONFLICT (unified_user_id, channel) DO UPDATE SET
            username = @username,
            role = 'parent',
            app_user_id = @app_user_id,
            child_profile_key = NULL,
            child_id = NULL,
            updated_at = CURRENT_TIMESTAMP
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("unified_user_id", unifiedUserId);
    cmd.Parameters.AddWithValue("username", username);
    cmd.Parameters.AddWithValue("channel", channel);
    cmd.Parameters.AddWithValue("app_user_id", appUserId);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return ReadAppUserProfile(reader, needsRole: false);
}

static async Task<AppUserProfile> EnsureChildAppUserProfile(NpgsqlConnection conn, string unifiedUserId, string username, string channel, JsonObject? body)
{
    var requestedChildId = body?.Int("child_id") ?? body?.Int("childId");
    string? childProfileKey = null;
    string childName = body?.String("child_name") ?? body?.String("childName") ?? "";
    int? existingChildId = null;

    if (requestedChildId is not null)
    {
        await using var childCmd = new NpgsqlCommand("SELECT id, name, profile_key FROM children WHERE id = @id", conn);
        childCmd.Parameters.AddWithValue("id", requestedChildId.Value);
        await using var childReader = await childCmd.ExecuteReaderAsync();
        if (await childReader.ReadAsync())
        {
            existingChildId = childReader.Int("id");
            childName = childReader.String("name");
            childProfileKey = childReader.String("profile_key");
        }
    }

    if (string.IsNullOrWhiteSpace(childProfileKey))
    {
        await using var profileCmd = new NpgsqlCommand("""
            SELECT child_profile_key, child_id
            FROM app_user_profiles
            WHERE unified_user_id = @unified_user_id AND role = 'child' AND child_profile_key IS NOT NULL
            ORDER BY id
            LIMIT 1
            """, conn);
        profileCmd.Parameters.AddWithValue("unified_user_id", unifiedUserId);
        await using var profileReader = await profileCmd.ExecuteReaderAsync();
        if (await profileReader.ReadAsync())
        {
            childProfileKey = profileReader.String("child_profile_key");
            existingChildId = NullableInt(profileReader, "child_id");
        }
    }

    if (string.IsNullOrWhiteSpace(childProfileKey))
    {
        var nextNumber = await NextBabyNumber(conn, username);
        childProfileKey = $"{unifiedUserId}:baby{nextNumber}";
        if (string.IsNullOrWhiteSpace(childName))
        {
            childName = $"宝宝{nextNumber}";
        }
    }

    var babyNumber = ExtractBabyNumber(childProfileKey) ?? await NextBabyNumber(conn, username);
    var appUserId = MakeChildAppUserId(username, babyNumber);
    var parentAppUserId = MakeParentAppUserId(username);
    var familyGroupId = await EnsureFamilyGroup(conn, $"{username}的家庭", parentAppUserId);
    var childId = existingChildId ?? await EnsureChildInFamilyGroup(conn, familyGroupId, childProfileKey, childName, "");

    await UpsertChildBinding(conn, parentAppUserId, childProfileKey, childId);

    await using var cmd = new NpgsqlCommand("""
        INSERT INTO app_user_profiles (unified_user_id, username, channel, role, app_user_id, child_profile_key, child_id)
        VALUES (@unified_user_id, @username, @channel, 'child', @app_user_id, @child_profile_key, @child_id)
        ON CONFLICT (unified_user_id, channel) DO UPDATE SET
            username = @username,
            role = 'child',
            app_user_id = @app_user_id,
            child_profile_key = @child_profile_key,
            child_id = @child_id,
            updated_at = CURRENT_TIMESTAMP
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("unified_user_id", unifiedUserId);
    cmd.Parameters.AddWithValue("username", username);
    cmd.Parameters.AddWithValue("channel", channel);
    cmd.Parameters.AddWithValue("app_user_id", appUserId);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);
    cmd.Parameters.AddWithValue("child_id", childId);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return ReadAppUserProfile(reader, needsRole: false);
}

static async Task<int> NextBabyNumber(NpgsqlConnection conn, string username)
{
    await using var cmd = new NpgsqlCommand("SELECT COUNT(*) FROM app_user_profiles WHERE app_user_id LIKE @prefix", conn);
    cmd.Parameters.AddWithValue("prefix", $"{username}baby%");
    return Convert.ToInt32(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) + 1;
}

static async Task UpsertChildBinding(NpgsqlConnection conn, string parentAppUserId, string childProfileKey, int childId)
{
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO child_user_bindings (parent_app_user_id, child_profile_key, child_id)
        VALUES (@parent_app_user_id, @child_profile_key, @child_id)
        ON CONFLICT (parent_app_user_id, child_profile_key) DO UPDATE SET
            child_id = @child_id,
            updated_at = CURRENT_TIMESTAMP
        """, conn);
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);
    cmd.Parameters.AddWithValue("child_id", childId);
    await cmd.ExecuteNonQueryAsync();
}

static async Task<int> EnsureChildInFamilyGroup(NpgsqlConnection conn, int familyGroupId, string profileKey, string name, string note, NpgsqlTransaction? tx = null)
{
    await using (var profileCmd = new NpgsqlCommand("""
        INSERT INTO child_profiles (profile_key, name, status, note)
        VALUES (@profile_key, @name, 'active', @note)
        ON CONFLICT (profile_key) DO NOTHING
        """, conn, tx))
    {
        profileCmd.Parameters.AddWithValue("profile_key", profileKey);
        profileCmd.Parameters.AddWithValue("name", string.IsNullOrWhiteSpace(name) ? "宝宝1" : name.Trim());
        profileCmd.Parameters.AddWithValue("note", note);
        await profileCmd.ExecuteNonQueryAsync();
    }

    await using (var existingCmd = new NpgsqlCommand("SELECT id FROM children WHERE family_group_id = @family_group_id AND profile_key = @profile_key LIMIT 1", conn, tx))
    {
        existingCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        existingCmd.Parameters.AddWithValue("profile_key", profileKey);
        var existing = await existingCmd.ExecuteScalarAsync();
        if (existing is not null && existing is not DBNull)
        {
            return Convert.ToInt32(existing, CultureInfo.InvariantCulture);
        }
    }

    await using var cmd = new NpgsqlCommand("""
        INSERT INTO children (family_group_id, profile_key, name, status, note)
        SELECT @family_group_id, cp.profile_key, cp.name, cp.status, cp.note
        FROM child_profiles cp
        WHERE cp.profile_key = @profile_key
        ON CONFLICT (family_group_id, profile_key) WHERE profile_key IS NOT NULL DO UPDATE SET
            name = EXCLUDED.name,
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            updated_at = CURRENT_TIMESTAMP
        RETURNING id
        """, conn, tx);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.AddWithValue("profile_key", profileKey);
    cmd.Parameters.AddWithValue("name", string.IsNullOrWhiteSpace(name) ? "宝宝1" : name.Trim());
    cmd.Parameters.AddWithValue("note", note);
    var childId = Convert.ToInt32(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);

    await using var accountCmd = new NpgsqlCommand("""
        INSERT INTO accounts (child_id, profile_key, points, cash_cny, items_count)
        VALUES (@child_id, @profile_key, 0, 0, 0)
        ON CONFLICT (profile_key) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
        """, conn);
    accountCmd.Parameters.AddWithValue("child_id", childId);
    accountCmd.Parameters.AddWithValue("profile_key", profileKey);
    await accountCmd.ExecuteNonQueryAsync();
    return childId;
}

static async Task<int> ResolveFamilyGroupId(string connectionString, HttpRequest request, JsonObject? body = null)
{
    var requestedId = body?.Int("family_group_id") ?? body?.Int("familyGroupId") ?? request.Query.Int("familyGroupId") ?? request.Query.Int("family_group_id");
    if (requestedId is not null)
    {
        return requestedId.Value;
    }

    var requestedName = body?.String("family_group_name") ?? "";
    if (string.IsNullOrWhiteSpace(requestedName))
    {
        requestedName = body?.String("familyGroupName") ?? "";
    }
    if (string.IsNullOrWhiteSpace(requestedName))
    {
        requestedName = request.Query.String("familyGroupName");
    }
    if (string.IsNullOrWhiteSpace(requestedName))
    {
        requestedName = request.Query.String("family_group_name");
    }

    var userId = GetRequestUserId(request);
    await using var conn = await OpenConnection(connectionString);
    if (!string.IsNullOrWhiteSpace(requestedName))
    {
        return await EnsureFamilyGroup(conn, requestedName, userId);
    }

    await using var cmd = new NpgsqlCommand("""
        SELECT fg.id
        FROM family_groups fg
        LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.created_by = @user_id OR fgu.user_id = @user_id
        ORDER BY fg.id
        LIMIT 1
        """, conn);
    cmd.Parameters.AddWithValue("user_id", userId);
    var result = await cmd.ExecuteScalarAsync();
    if (result is not null && result is not DBNull)
    {
        return Convert.ToInt32(result, CultureInfo.InvariantCulture);
    }

    return await EnsureFamilyGroup(conn, DefaultFamilyGroupName, userId);
}

static string GetRequestUserId(HttpRequest request)
{
    var userId = request.Headers.TryGetValue("X-App-User-Id", out var appUserId) ? appUserId.ToString() : "";
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = request.Query.String("appUserId");
    }
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = request.Headers.TryGetValue("X-User-Id", out var headerUserId) ? headerUserId.ToString() : "";
    }
    if (string.IsNullOrWhiteSpace(userId) && request.Headers.TryGetValue("X-Gateway-User-Id", out var gatewayUserId))
    {
        userId = gatewayUserId.ToString();
    }
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = request.Query.String("userId");
    }
    return string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId.Trim();
}

static string GetUnifiedUserId(HttpRequest request)
{
    var userId = request.Headers.TryGetValue("X-User-Id", out var headerUserId) ? headerUserId.ToString() : "";
    if (string.IsNullOrWhiteSpace(userId) && request.Headers.TryGetValue("X-Gateway-User-Id", out var gatewayUserId))
    {
        userId = gatewayUserId.ToString();
    }
    userId = FirstClaim(request, ClaimTypes.NameIdentifier, "sub", "user_id", "uid") ?? userId;
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = request.Query.String("userId");
    }
    return string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId.Trim();
}

static bool HasUnifiedIdentity(HttpRequest request)
{
    if (request.Headers.TryGetValue("X-User-Id", out var headerUserId) && !string.IsNullOrWhiteSpace(headerUserId.ToString()))
    {
        return true;
    }
    if (request.Headers.TryGetValue("X-Gateway-User-Id", out var gatewayUserId) && !string.IsNullOrWhiteSpace(gatewayUserId.ToString()))
    {
        return true;
    }
    if (!string.IsNullOrWhiteSpace(request.Query.String("userId")))
    {
        return true;
    }
    return request.HttpContext.User.Identity?.IsAuthenticated == true
        || request.HttpContext.User.Claims.Any(claim => !string.IsNullOrWhiteSpace(claim.Value));
}

static string GetUnifiedUsername(HttpRequest request)
{
    var name = FirstClaim(request, "preferred_username", ClaimTypes.Name, "name")
        ?? (request.Headers.TryGetValue("X-User-Name", out var headerName) ? headerName.ToString() : "")
        ?? "";
    if (string.IsNullOrWhiteSpace(name))
    {
        name = GetUnifiedUserId(request);
    }
    return NormalizeBusinessUserName(name);
}

static string? FirstClaim(HttpRequest request, params string[] types)
{
    foreach (var type in types)
    {
        var value = request.HttpContext.User.FindFirstValue(type);
        if (!string.IsNullOrWhiteSpace(value)) return value.Trim();
    }
    return null;
}

static bool IsWatchRequest(HttpRequest request) =>
    request.Path.StartsWithSegments("/watch", StringComparison.OrdinalIgnoreCase)
    || request.Path.StartsWithSegments("/api/watch", StringComparison.OrdinalIgnoreCase);

static string NormalizeIdentityChannel(string? value, string fallback)
{
    var channel = (value ?? fallback).Trim().ToLowerInvariant();
    return channel == "watch" ? "watch" : "pc";
}

static string NormalizeAppRole(string? value)
{
    var role = (value ?? "").Trim().ToLowerInvariant();
    return role is "parent" or "child" ? role : "";
}

static string NormalizeBusinessUserName(string value)
{
    var normalized = new string(value.Trim().Where(ch => !char.IsWhiteSpace(ch)).ToArray());
    return string.IsNullOrWhiteSpace(normalized) ? DefaultUserId : normalized;
}

static string MakeParentAppUserId(string username) => $"{NormalizeBusinessUserName(username)}parent";

static string MakeChildAppUserId(string username, int number) => $"{NormalizeBusinessUserName(username)}baby{Math.Max(1, number)}";

static int? ExtractBabyNumber(string profileKey)
{
    var marker = "baby";
    var index = profileKey.LastIndexOf(marker, StringComparison.OrdinalIgnoreCase);
    if (index < 0) return null;
    return int.TryParse(profileKey[(index + marker.Length)..], NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
        ? parsed
        : null;
}

static Dictionary<string, object?> ReadAppUserProfilePayload(IDataRecord reader, bool needsRole) => new()
{
    ["needsRole"] = needsRole,
    ["unifiedUserId"] = reader.String("unified_user_id"),
    ["username"] = reader.String("username"),
    ["channel"] = reader.String("channel"),
    ["role"] = reader.String("role"),
    ["appUserId"] = reader.String("app_user_id"),
    ["childProfileKey"] = reader.HasColumn("child_profile_key") ? NullableString(reader, "child_profile_key") : null,
    ["childId"] = reader.HasColumn("child_id") ? NullableInt(reader, "child_id") : null
};

static AppUserProfile ReadAppUserProfile(IDataRecord reader, bool needsRole = false)
{
    var payload = ReadAppUserProfilePayload(reader, needsRole);
    return new AppUserProfile(
        Convert.ToString(payload["unifiedUserId"], CultureInfo.InvariantCulture) ?? "",
        Convert.ToString(payload["username"], CultureInfo.InvariantCulture) ?? "",
        Convert.ToString(payload["channel"], CultureInfo.InvariantCulture) ?? "",
        Convert.ToString(payload["role"], CultureInfo.InvariantCulture) ?? "",
        Convert.ToString(payload["appUserId"], CultureInfo.InvariantCulture) ?? "",
        Convert.ToString(payload["childProfileKey"], CultureInfo.InvariantCulture),
        payload["childId"] is int childId ? childId : null,
        needsRole);
}

static Dictionary<string, object?> ReadFamilyGroup(IDataRecord reader) => new()
{
    ["id"] = reader.Int("id"),
    ["name"] = reader.String("name"),
    ["description"] = reader.String("description"),
    ["createdBy"] = reader.String("created_by"),
    ["role"] = reader.HasColumn("role") ? reader.String("role") : "",
    ["createdAt"] = reader.DateTime("created_at").ToString("O"),
    ["updatedAt"] = reader.DateTime("updated_at").ToString("O")
};

static async Task<List<Dictionary<string, object?>>> GetChildren(string connectionString, int? familyGroupId = null, string? childProfileKey = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT c.id, c.family_group_id, fg.name AS family_group_name,
               c.profile_key, COALESCE(cp.name, c.name) AS name,
               COALESCE(cp.status, c.status) AS status,
               COALESCE(cp.note, c.note) AS note,
               COALESCE(cp.created_at, c.created_at) AS created_at,
               COALESCE(cp.updated_at, c.updated_at) AS updated_at,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items
        FROM children c
        LEFT JOIN child_profiles cp ON cp.profile_key = c.profile_key
        LEFT JOIN family_groups fg ON fg.id = c.family_group_id
        LEFT JOIN accounts a ON a.profile_key = c.profile_key
        WHERE COALESCE(cp.status, c.status) = 'active'
          AND (@family_group_id IS NULL OR c.family_group_id = @family_group_id)
          AND (@child_profile_key IS NULL OR c.profile_key = @child_profile_key)
        ORDER BY c.id
        """, conn);
    cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
    {
        Value = familyGroupId is null ? DBNull.Value : familyGroupId.Value
    });
    cmd.Parameters.Add(new NpgsqlParameter("child_profile_key", NpgsqlDbType.Varchar)
    {
        Value = string.IsNullOrWhiteSpace(childProfileKey) ? DBNull.Value : childProfileKey
    });
    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new Dictionary<string, object?>
        {
            ["id"] = reader.Int("id"),
            ["familyGroupId"] = reader.Int("family_group_id"),
            ["family_group_id"] = reader.Int("family_group_id"),
            ["familyGroupName"] = reader.String("family_group_name"),
            ["family_group_name"] = reader.String("family_group_name"),
            ["profileKey"] = reader.String("profile_key"),
            ["profile_key"] = reader.String("profile_key"),
            ["name"] = reader.String("name"),
            ["status"] = reader.String("status"),
            ["note"] = reader.String("note"),
            ["createdAt"] = reader.DateTime("created_at").ToString("O"),
            ["updatedAt"] = reader.DateTime("updated_at").ToString("O"),
            ["score"] = reader.Decimal("score"),
            ["cash"] = reader.Decimal("cash"),
            ["items"] = reader.Int("items")
        });
    }
    return rows;
}

static async Task<Dictionary<string, object>> GetRules(string connectionString)
{
    await using var conn = await OpenConnection(connectionString);
    var rules = new List<Dictionary<string, object?>>();
    await using (var cmd = new NpgsqlCommand("SELECT * FROM rules ORDER BY id", conn))
    await using (var reader = await cmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            rules.Add(ReadRule(reader));
        }
    }

    var redlines = new List<Dictionary<string, object?>>();
    await using (var cmd = new NpgsqlCommand("SELECT * FROM redlines ORDER BY order_num", conn))
    await using (var reader = await cmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            redlines.Add(new Dictionary<string, object?>
            {
                ["id"] = reader.Int("id"),
                ["order_num"] = reader.Int("order_num"),
                ["rule"] = reader.String("rule"),
                ["proposer"] = reader.String("proposer"),
                ["description"] = reader.String("description"),
                ["penalty_points"] = reader.Int("penalty_points"),
                ["created_at"] = reader.DateTime("created_at").ToString("O")
            });
        }
    }

    return new Dictionary<string, object> { ["rules"] = rules, ["redlines"] = redlines };
}

static async Task<List<Dictionary<string, object?>>> GetRecentTransactions(string connectionString, int limit, int? familyGroupId = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE (@family_group_id IS NULL OR c.family_group_id = @family_group_id)
        ORDER BY t.date DESC, t.id DESC
        LIMIT @limit
        """, conn);
    cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
    {
        Value = familyGroupId is null ? DBNull.Value : familyGroupId.Value
    });
    cmd.Parameters.AddWithValue("limit", limit);
    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(ReadTransaction(reader));
    }
    return rows;
}

static async Task<Dictionary<string, object?>> CreateTransaction(string connectionString, JsonObject body, int? familyGroupId = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var childId = body.Int("child_id") ?? body.Int("childId") ?? 0;
        var type = NormalizeTransactionType(body.String("type"));
        var direction = body.String("direction", "+");
        var points = body.Decimal("points") ?? body.Decimal("amount") ?? 0;
        var cash = body.Decimal("cash_cny") ?? (type == "cash" ? body.Decimal("amount") : null) ?? 0;
        var itemText = body.String("items");

        if (familyGroupId is not null)
        {
            await using var childCmd = new NpgsqlCommand("SELECT COUNT(*) FROM children WHERE id = @child_id AND family_group_id = @family_group_id", conn, tx);
            childCmd.Parameters.AddWithValue("child_id", childId);
            childCmd.Parameters.AddWithValue("family_group_id", familyGroupId.Value);
            if (Convert.ToInt32(await childCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "孩子不属于当前家庭组" };
            }
        }

        await using var cmd = new NpgsqlCommand("""
            INSERT INTO transactions (date, child_id, type, direction, category, description, points, cash_cny, items, notes)
            VALUES (@date, @child_id, @type, @direction, @category, @description, @points, @cash_cny, @items, @notes)
            RETURNING *
            """, conn, tx);
        cmd.Parameters.AddWithValue("date", DateOnly.Parse(body.String("date", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)), CultureInfo.InvariantCulture));
        cmd.Parameters.AddWithValue("child_id", childId);
        cmd.Parameters.AddWithValue("type", type);
        cmd.Parameters.AddWithValue("direction", direction);
        cmd.Parameters.AddWithValue("category", body.String("category"));
        cmd.Parameters.AddWithValue("description", body.String("description"));
        cmd.Parameters.AddWithValue("points", type == "points" ? points : 0);
        cmd.Parameters.AddWithValue("cash_cny", cash);
        cmd.Parameters.AddWithValue("items", itemText);
        cmd.Parameters.AddWithValue("notes", body.String("notes"));

        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        var transaction = ReadTransaction(reader);
        await reader.CloseAsync();

        await UpdateAccount(conn, tx, childId, type, direction, points, cash, itemText);
        await tx.CommitAsync();

        return new Dictionary<string, object?> { ["transaction"] = transaction, ["status"] = "ok" };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> DeleteChildMembership(string connectionString, int id, int familyGroupId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        string profileKey;
        await using (var lookup = new NpgsqlCommand("""
            SELECT profile_key
            FROM children
            WHERE id = @id AND family_group_id = @family_group_id
            FOR UPDATE
            """, conn, tx))
        {
            lookup.Parameters.AddWithValue("id", id);
            lookup.Parameters.AddWithValue("family_group_id", familyGroupId);
            var value = await lookup.ExecuteScalarAsync();
            if (value is null || value is DBNull)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "孩子不存在" };
            }
            profileKey = Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
        }

        await using (var replacement = new NpgsqlCommand("""
            SELECT id
            FROM children
            WHERE profile_key = @profile_key AND id <> @id
            ORDER BY id
            LIMIT 1
            """, conn, tx))
        {
            replacement.Parameters.AddWithValue("profile_key", profileKey);
            replacement.Parameters.AddWithValue("id", id);
            var replacementId = await replacement.ExecuteScalarAsync();
            if (replacementId is not null && replacementId is not DBNull)
            {
                await using var reassign = new NpgsqlCommand("""
                    UPDATE accounts
                    SET child_id = @replacement_id
                    WHERE child_id = @id AND profile_key = @profile_key
                    """, conn, tx);
                reassign.Parameters.AddWithValue("replacement_id", Convert.ToInt32(replacementId, CultureInfo.InvariantCulture));
                reassign.Parameters.AddWithValue("id", id);
                reassign.Parameters.AddWithValue("profile_key", profileKey);
                await reassign.ExecuteNonQueryAsync();
            }
        }

        await using (var cmd = new NpgsqlCommand("DELETE FROM children WHERE id = @id AND family_group_id = @family_group_id", conn, tx))
        {
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            await cmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?> { ["status"] = "ok" };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> CreateChildAuthCode(string connectionString, int childId, int familyGroupId, string parentAppUserId, int expiresInMinutes)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var child = await GetChildForFamily(conn, tx, childId, familyGroupId);
        if (child is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "孩子不属于当前家庭组" };
        }

        await using (var expireCmd = new NpgsqlCommand("""
            UPDATE child_auth_codes
            SET used_at = CURRENT_TIMESTAMP
            WHERE child_id = @child_id
              AND family_group_id = @family_group_id
              AND used_at IS NULL
              AND expires_at > CURRENT_TIMESTAMP
            """, conn, tx))
        {
            expireCmd.Parameters.AddWithValue("child_id", childId);
            expireCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            await expireCmd.ExecuteNonQueryAsync();
        }

        var code = GenerateAuthCode();
        var codeHash = HashSecret(code);
        var expiresAt = DateTime.UtcNow.AddMinutes(expiresInMinutes);
        await using (var cmd = new NpgsqlCommand("""
            INSERT INTO child_auth_codes (child_id, family_group_id, child_profile_key, parent_app_user_id, code_hash, expires_at)
            VALUES (@child_id, @family_group_id, @child_profile_key, @parent_app_user_id, @code_hash, @expires_at)
            """, conn, tx))
        {
            cmd.Parameters.AddWithValue("child_id", childId);
            cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            cmd.Parameters.AddWithValue("child_profile_key", Convert.ToString(child["profileKey"], CultureInfo.InvariantCulture) ?? "");
            cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            cmd.Parameters.AddWithValue("code_hash", codeHash);
            cmd.Parameters.AddWithValue("expires_at", expiresAt);
            await cmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["code"] = code,
            ["expiresAt"] = expiresAt.ToString("O", CultureInfo.InvariantCulture),
            ["expiresInMinutes"] = expiresInMinutes,
            ["child"] = child
        };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> GetChildWatchDevices(string connectionString, int childId, int familyGroupId, string parentAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    var child = await GetChildForFamily(conn, null, childId, familyGroupId);
    if (child is null)
    {
        return new Dictionary<string, object?> { ["error"] = "孩子不属于当前家庭组" };
    }

    var devices = new List<Dictionary<string, object?>>();
    await using var cmd = new NpgsqlCommand("""
        SELECT id, child_id, family_group_id, child_profile_key, parent_app_user_id, device_name, platform, user_agent, bound_at, last_seen_at, revoked_at
        FROM watch_device_bindings
        WHERE child_profile_key = @child_profile_key
          AND parent_app_user_id = @parent_app_user_id
        ORDER BY revoked_at NULLS FIRST, last_seen_at DESC, id DESC
        """, conn);
    cmd.Parameters.AddWithValue("child_profile_key", Convert.ToString(child["profileKey"], CultureInfo.InvariantCulture) ?? "");
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        devices.Add(ReadWatchDevice(reader));
    }

    return new Dictionary<string, object?> { ["child"] = child, ["devices"] = devices };
}

static async Task<Dictionary<string, object?>> RevokeChildWatchDevice(string connectionString, int childId, int deviceId, int familyGroupId, string parentAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    var child = await GetChildForFamily(conn, null, childId, familyGroupId);
    if (child is null)
    {
        return new Dictionary<string, object?> { ["error"] = "孩子不属于当前家庭组" };
    }
    await using var cmd = new NpgsqlCommand("""
        UPDATE watch_device_bindings
        SET revoked_at = CURRENT_TIMESTAMP
        WHERE id = @id
          AND child_profile_key = @child_profile_key
          AND parent_app_user_id = @parent_app_user_id
          AND revoked_at IS NULL
        """, conn);
    cmd.Parameters.AddWithValue("id", deviceId);
    cmd.Parameters.AddWithValue("child_profile_key", Convert.ToString(child["profileKey"], CultureInfo.InvariantCulture) ?? "");
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    var affected = await cmd.ExecuteNonQueryAsync();
    return affected == 0
        ? new Dictionary<string, object?> { ["error"] = "设备不存在或已解绑" }
        : new Dictionary<string, object?> { ["status"] = "ok" };
}

static async Task<Dictionary<string, object?>> CreateWatchDeviceUnbindCode(
    string connectionString,
    int childId,
    int deviceId,
    int familyGroupId,
    string parentAppUserId,
    int expiresInMinutes)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var child = await GetChildForFamily(conn, tx, childId, familyGroupId);
        if (child is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "孩子不属于当前家庭组" };
        }

        var bindingChildId = 0;
        var bindingFamilyGroupId = 0;
        await using (var deviceCmd = new NpgsqlCommand("""
            SELECT child_id, family_group_id
            FROM watch_device_bindings
            WHERE id = @id
              AND child_profile_key = @child_profile_key
              AND parent_app_user_id = @parent_app_user_id
              AND revoked_at IS NULL
            """, conn, tx))
        {
            deviceCmd.Parameters.AddWithValue("id", deviceId);
            deviceCmd.Parameters.AddWithValue("child_profile_key", Convert.ToString(child["profileKey"], CultureInfo.InvariantCulture) ?? "");
            deviceCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await using var reader = await deviceCmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "设备不存在或已解绑" };
            }
            bindingChildId = reader.Int("child_id");
            bindingFamilyGroupId = reader.Int("family_group_id");
        }

        await using (var expireCmd = new NpgsqlCommand("""
            UPDATE watch_device_unbind_codes
            SET used_at = CURRENT_TIMESTAMP
            WHERE device_binding_id = @device_binding_id
              AND used_at IS NULL
              AND expires_at > CURRENT_TIMESTAMP
            """, conn, tx))
        {
            expireCmd.Parameters.AddWithValue("device_binding_id", deviceId);
            await expireCmd.ExecuteNonQueryAsync();
        }

        var code = GenerateAuthCode();
        var expiresAt = DateTime.UtcNow.AddMinutes(expiresInMinutes);
        await using (var insertCmd = new NpgsqlCommand("""
            INSERT INTO watch_device_unbind_codes
                (device_binding_id, child_id, family_group_id, parent_app_user_id, code_hash, expires_at)
            VALUES
                (@device_binding_id, @child_id, @family_group_id, @parent_app_user_id, @code_hash, @expires_at)
            """, conn, tx))
        {
            insertCmd.Parameters.AddWithValue("device_binding_id", deviceId);
            insertCmd.Parameters.AddWithValue("child_id", bindingChildId);
            insertCmd.Parameters.AddWithValue("family_group_id", bindingFamilyGroupId);
            insertCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            insertCmd.Parameters.AddWithValue("code_hash", HashSecret(code));
            insertCmd.Parameters.AddWithValue("expires_at", expiresAt);
            await insertCmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["code"] = code,
            ["deviceId"] = deviceId,
            ["expiresAt"] = expiresAt.ToString("O", CultureInfo.InvariantCulture),
            ["expiresInMinutes"] = expiresInMinutes
        };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> BindWatchDevice(string connectionString, JsonObject body, HttpRequest request)
{
    var code = NormalizeAuthCode(body.String("code"));
    if (string.IsNullOrWhiteSpace(code))
    {
        return new Dictionary<string, object?> { ["error"] = "请输入儿童认证码" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        Dictionary<string, object?>? codeRow = null;
        await using (var lookup = new NpgsqlCommand("""
            SELECT cac.id, cac.child_id, cac.family_group_id, cac.child_profile_key, cac.parent_app_user_id, cac.expires_at,
                   c.name AS child_name, fg.name AS family_group_name
            FROM child_auth_codes cac
            JOIN children c ON c.id = cac.child_id AND c.family_group_id = cac.family_group_id AND c.status = 'active'
            LEFT JOIN family_groups fg ON fg.id = cac.family_group_id
            WHERE cac.code_hash = @code_hash
              AND cac.used_at IS NULL
              AND cac.expires_at > CURRENT_TIMESTAMP
            FOR UPDATE OF cac
            """, conn, tx))
        {
            lookup.Parameters.AddWithValue("code_hash", HashSecret(code));
            await using var reader = await lookup.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                codeRow = new Dictionary<string, object?>
                {
                    ["id"] = reader.Int("id"),
                    ["childId"] = reader.Int("child_id"),
                    ["familyGroupId"] = reader.Int("family_group_id"),
                    ["childProfileKey"] = reader.String("child_profile_key"),
                    ["parentAppUserId"] = reader.String("parent_app_user_id"),
                    ["childName"] = reader.String("child_name"),
                    ["familyGroupName"] = reader.String("family_group_name")
                };
            }
        }

        if (codeRow is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "认证码无效或已过期" };
        }

        await using (var activeDeviceCmd = new NpgsqlCommand("""
            SELECT COUNT(*)
            FROM watch_device_bindings
            WHERE child_profile_key = @child_profile_key
              AND revoked_at IS NULL
            """, conn, tx))
        {
            activeDeviceCmd.Parameters.AddWithValue("child_profile_key", Convert.ToString(codeRow["childProfileKey"], CultureInfo.InvariantCulture) ?? "");
            if (Convert.ToInt32(await activeDeviceCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "该孩子已绑定设备，请先由家长解绑现有设备" };
            }
        }

        var token = GenerateDeviceToken();
        var tokenHash = HashSecret(token);
        var deviceName = Truncate(body.String("deviceName", request.Headers.UserAgent.ToString()), 240);
        var platform = Truncate(body.String("platform"), 80);
        var userAgent = request.Headers.UserAgent.ToString();
        int deviceId;
        await using (var insert = new NpgsqlCommand("""
            INSERT INTO watch_device_bindings
                (child_id, family_group_id, child_profile_key, parent_app_user_id, device_token_hash, device_name, platform, user_agent)
            VALUES
                (@child_id, @family_group_id, @child_profile_key, @parent_app_user_id, @device_token_hash, @device_name, @platform, @user_agent)
            RETURNING id
            """, conn, tx))
        {
            insert.Parameters.AddWithValue("child_id", Convert.ToInt32(codeRow["childId"], CultureInfo.InvariantCulture));
            insert.Parameters.AddWithValue("family_group_id", Convert.ToInt32(codeRow["familyGroupId"], CultureInfo.InvariantCulture));
            insert.Parameters.AddWithValue("child_profile_key", Convert.ToString(codeRow["childProfileKey"], CultureInfo.InvariantCulture) ?? "");
            insert.Parameters.AddWithValue("parent_app_user_id", Convert.ToString(codeRow["parentAppUserId"], CultureInfo.InvariantCulture) ?? "");
            insert.Parameters.AddWithValue("device_token_hash", tokenHash);
            insert.Parameters.AddWithValue("device_name", deviceName);
            insert.Parameters.AddWithValue("platform", platform);
            insert.Parameters.AddWithValue("user_agent", userAgent);
            deviceId = Convert.ToInt32(await insert.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
        }

        await using (var useCode = new NpgsqlCommand("UPDATE child_auth_codes SET used_at = CURRENT_TIMESTAMP WHERE id = @id", conn, tx))
        {
            useCode.Parameters.AddWithValue("id", Convert.ToInt32(codeRow["id"], CultureInfo.InvariantCulture));
            await useCode.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["deviceToken"] = token,
            ["deviceId"] = deviceId,
            ["child"] = new Dictionary<string, object?>
            {
                ["id"] = codeRow["childId"],
                ["name"] = codeRow["childName"],
                ["profileKey"] = codeRow["childProfileKey"]
            },
            ["familyGroupId"] = codeRow["familyGroupId"],
            ["familyGroupName"] = codeRow["familyGroupName"]
        };
    }
    catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation && ex.ConstraintName == "ux_watch_device_bindings_active_child")
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = "该孩子已绑定设备，请先由家长解绑现有设备" };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<(WatchDeviceBinding? Binding, IResult? Error)> RequireWatchDeviceBinding(string connectionString, HttpRequest request, bool touch = true)
{
    var token = GetWatchDeviceToken(request);
    if (string.IsNullOrWhiteSpace(token))
    {
        return (null, Results.Json(new { error = "请先输入儿童认证码绑定手表", code = "watch_device_required" }, statusCode: StatusCodes.Status401Unauthorized));
    }

    var tokenHash = HashSecret(token);
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT wdb.id, wdb.child_id, wdb.family_group_id, wdb.child_profile_key, wdb.parent_app_user_id,
               wdb.device_token_hash, wdb.device_name, wdb.platform
        FROM watch_device_bindings wdb
        JOIN children c ON c.id = wdb.child_id AND c.family_group_id = wdb.family_group_id AND c.status = 'active'
        WHERE wdb.device_token_hash = @token_hash
          AND wdb.revoked_at IS NULL
        """, conn);
    cmd.Parameters.AddWithValue("token_hash", tokenHash);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return (null, Results.Json(new { error = "手表绑定已失效，请重新输入认证码", code = "watch_device_invalid" }, statusCode: StatusCodes.Status401Unauthorized));
    }

    var binding = new WatchDeviceBinding(
        reader.Int("id"),
        reader.Int("child_id"),
        reader.Int("family_group_id"),
        reader.String("child_profile_key"),
        reader.String("parent_app_user_id"),
        reader.String("device_token_hash"),
        reader.String("device_name"),
        reader.String("platform"));
    await reader.CloseAsync();

    if (touch)
    {
        await using var touchCmd = new NpgsqlCommand("UPDATE watch_device_bindings SET last_seen_at = CURRENT_TIMESTAMP WHERE id = @id", conn);
        touchCmd.Parameters.AddWithValue("id", binding.Id);
        await touchCmd.ExecuteNonQueryAsync();
    }

    return (binding, null);
}

static async Task<Dictionary<string, object?>> UnbindWatchDeviceWithCode(string connectionString, WatchDeviceBinding binding, string rawCode)
{
    var code = NormalizeAuthCode(rawCode);
    if (string.IsNullOrWhiteSpace(code))
    {
        return new Dictionary<string, object?> { ["error"] = "请输入家长端生成的解绑认证码" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        int? codeId = null;
        await using (var lookupCmd = new NpgsqlCommand("""
            SELECT wduc.id
            FROM watch_device_unbind_codes wduc
            JOIN watch_device_bindings wdb ON wdb.id = wduc.device_binding_id
            WHERE wduc.device_binding_id = @device_binding_id
              AND wduc.child_id = @child_id
              AND wduc.family_group_id = @family_group_id
              AND wduc.parent_app_user_id = @parent_app_user_id
              AND wduc.code_hash = @code_hash
              AND wduc.used_at IS NULL
              AND wduc.expires_at > CURRENT_TIMESTAMP
              AND wdb.device_token_hash = @token_hash
              AND wdb.revoked_at IS NULL
            FOR UPDATE OF wduc, wdb
            """, conn, tx))
        {
            lookupCmd.Parameters.AddWithValue("device_binding_id", binding.Id);
            lookupCmd.Parameters.AddWithValue("child_id", binding.ChildId);
            lookupCmd.Parameters.AddWithValue("family_group_id", binding.FamilyGroupId);
            lookupCmd.Parameters.AddWithValue("parent_app_user_id", binding.ParentAppUserId);
            lookupCmd.Parameters.AddWithValue("code_hash", HashSecret(code));
            lookupCmd.Parameters.AddWithValue("token_hash", binding.TokenHash);
            var value = await lookupCmd.ExecuteScalarAsync();
            if (value is not null)
            {
                codeId = Convert.ToInt32(value, CultureInfo.InvariantCulture);
            }
        }

        if (codeId is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "解绑认证码无效或已过期" };
        }

        await using (var revokeCmd = new NpgsqlCommand("""
            UPDATE watch_device_bindings
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE id = @id AND device_token_hash = @token_hash AND revoked_at IS NULL
            """, conn, tx))
        {
            revokeCmd.Parameters.AddWithValue("id", binding.Id);
            revokeCmd.Parameters.AddWithValue("token_hash", binding.TokenHash);
            if (await revokeCmd.ExecuteNonQueryAsync() != 1)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "设备不存在或已解绑" };
            }
        }

        await using (var useCodeCmd = new NpgsqlCommand("UPDATE watch_device_unbind_codes SET used_at = CURRENT_TIMESTAMP WHERE id = @id", conn, tx))
        {
            useCodeCmd.Parameters.AddWithValue("id", codeId.Value);
            await useCodeCmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?> { ["status"] = "ok" };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>?> GetChildForFamily(NpgsqlConnection conn, NpgsqlTransaction? tx, int childId, int familyGroupId)
{
    await using var cmd = new NpgsqlCommand("""
        SELECT c.id, c.family_group_id, fg.name AS family_group_name,
               c.profile_key, c.name, c.status, c.note, c.created_at, c.updated_at,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items
        FROM children c
        LEFT JOIN family_groups fg ON fg.id = c.family_group_id
        LEFT JOIN accounts a ON a.profile_key = c.profile_key
        WHERE c.id = @child_id AND c.family_group_id = @family_group_id AND c.status = 'active'
        """, conn, tx);
    cmd.Parameters.AddWithValue("child_id", childId);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return null;
    }

    return new Dictionary<string, object?>
    {
        ["id"] = reader.Int("id"),
        ["familyGroupId"] = reader.Int("family_group_id"),
        ["family_group_id"] = reader.Int("family_group_id"),
        ["familyGroupName"] = reader.String("family_group_name"),
        ["family_group_name"] = reader.String("family_group_name"),
        ["profileKey"] = reader.String("profile_key"),
        ["profile_key"] = reader.String("profile_key"),
        ["name"] = reader.String("name"),
        ["status"] = reader.String("status"),
        ["note"] = reader.String("note"),
        ["createdAt"] = reader.DateTime("created_at").ToString("O"),
        ["updatedAt"] = reader.DateTime("updated_at").ToString("O"),
        ["score"] = reader.Decimal("score"),
        ["cash"] = reader.Decimal("cash"),
        ["items"] = reader.Int("items")
    };
}

static async Task<List<Dictionary<string, object?>>> GetWatchRewardRequests(string connectionString, int familyGroupId, int? childId, int limit, string? childProfileKey = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT wrr.*, c.name AS child_name, r.name AS rule_name
        FROM watch_reward_requests wrr
        LEFT JOIN children c ON c.id = wrr.child_id
        LEFT JOIN rules r ON r.id = wrr.rule_id
        WHERE wrr.family_group_id = @family_group_id
          AND (@child_id IS NULL OR wrr.child_id = @child_id)
          AND (@child_profile_key IS NULL OR c.profile_key = @child_profile_key)
        ORDER BY wrr.requested_at DESC, wrr.id DESC
        LIMIT @limit
        """, conn);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.Add(new NpgsqlParameter("child_id", NpgsqlDbType.Integer)
    {
        Value = childId is null ? DBNull.Value : childId.Value
    });
    cmd.Parameters.Add(new NpgsqlParameter("child_profile_key", NpgsqlDbType.Varchar)
    {
        Value = string.IsNullOrWhiteSpace(childProfileKey) ? DBNull.Value : childProfileKey
    });
    cmd.Parameters.AddWithValue("limit", limit);

    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(ReadWatchRewardRequest(reader));
    }
    return rows;
}

static async Task<Dictionary<string, object?>> CreateWatchRewardRequest(string connectionString, JsonObject body, int familyGroupId, string requestedBy, string? childProfileKey = null)
{
    var childId = body.Int("child_id") ?? body.Int("childId") ?? 0;
    if (childId <= 0)
    {
        return new Dictionary<string, object?> { ["error"] = "请选择孩子" };
    }

    await using var conn = await OpenConnection(connectionString);
    if (!await ChildBelongsToFamily(conn, childId, familyGroupId))
    {
        return new Dictionary<string, object?> { ["error"] = "孩子不属于当前家庭组" };
    }
    if (!string.IsNullOrWhiteSpace(childProfileKey))
    {
        await using var ownerCmd = new NpgsqlCommand("SELECT COUNT(*) FROM children WHERE id = @child_id AND family_group_id = @family_group_id AND profile_key = @profile_key", conn);
        ownerCmd.Parameters.AddWithValue("child_id", childId);
        ownerCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        ownerCmd.Parameters.AddWithValue("profile_key", childProfileKey);
        if (Convert.ToInt32(await ownerCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
        {
            return new Dictionary<string, object?> { ["error"] = "孩子账号只能为自己提交积分申请" };
        }
    }

    var ruleId = body.Int("rule_id") ?? body.Int("ruleId");
    string ruleName = "";
    string ruleCategory = "";
    decimal? rulePoints = null;
    if (ruleId is not null)
    {
        await using var ruleCmd = new NpgsqlCommand("SELECT name, category, points FROM rules WHERE id = @id", conn);
        ruleCmd.Parameters.AddWithValue("id", ruleId.Value);
        await using var ruleReader = await ruleCmd.ExecuteReaderAsync();
        if (!await ruleReader.ReadAsync())
        {
            return new Dictionary<string, object?> { ["error"] = "奖励规则不存在" };
        }

        ruleName = ruleReader.String("name");
        ruleCategory = ruleReader.String("category");
        rulePoints = ruleReader.Decimal("points");
    }

    var title = body.String("title").Trim();
    if (string.IsNullOrWhiteSpace(title))
    {
        title = ruleName;
    }
    if (string.IsNullOrWhiteSpace(title))
    {
        return new Dictionary<string, object?> { ["error"] = "请填写申请事项" };
    }

    var points = body.Decimal("points") ?? body.Decimal("score") ?? rulePoints ?? 0;
    if (points <= 0)
    {
        return new Dictionary<string, object?> { ["error"] = "申请积分必须大于 0" };
    }

    var category = body.String("category");
    if (string.IsNullOrWhiteSpace(category))
    {
        category = string.IsNullOrWhiteSpace(ruleCategory) ? "手表申请" : ruleCategory;
    }

    await using var cmd = new NpgsqlCommand("""
        INSERT INTO watch_reward_requests
            (family_group_id, child_id, rule_id, title, category, points, note, status, requested_by)
        VALUES
            (@family_group_id, @child_id, @rule_id, @title, @category, @points, @note, 'pending', @requested_by)
        RETURNING id
        """, conn);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.AddWithValue("child_id", childId);
    cmd.Parameters.Add(new NpgsqlParameter("rule_id", NpgsqlDbType.Integer)
    {
        Value = ruleId is null ? DBNull.Value : ruleId.Value
    });
    cmd.Parameters.AddWithValue("title", title);
    cmd.Parameters.AddWithValue("category", category);
    cmd.Parameters.AddWithValue("points", points);
    cmd.Parameters.AddWithValue("note", body.String("note"));
    cmd.Parameters.AddWithValue("requested_by", requestedBy);

    var id = Convert.ToInt32(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
    return (await GetWatchRewardRequests(connectionString, familyGroupId, childId, 10, childProfileKey))
        .First(row => GetInt(row, "id") == id);
}

static async Task<Dictionary<string, object?>> ApproveWatchRewardRequest(string connectionString, int id, int familyGroupId, string reviewNote)
{
    Dictionary<string, object?> request;
    await using (var conn = await OpenConnection(connectionString))
    await using (var cmd = new NpgsqlCommand("""
        SELECT wrr.*, c.name AS child_name, r.name AS rule_name
        FROM watch_reward_requests wrr
        LEFT JOIN children c ON c.id = wrr.child_id
        LEFT JOIN rules r ON r.id = wrr.rule_id
        WHERE wrr.id = @id AND wrr.family_group_id = @family_group_id
        """, conn))
    {
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            return new Dictionary<string, object?> { ["error"] = "申请不存在" };
        }

        request = ReadWatchRewardRequest(reader);
    }

    if (!string.Equals(Convert.ToString(request["status"], CultureInfo.InvariantCulture), "pending", StringComparison.Ordinal))
    {
        return new Dictionary<string, object?> { ["error"] = "申请已处理" };
    }

    var transactionResult = await CreateTransaction(connectionString, new JsonObject
    {
        ["child_id"] = GetInt(request, "childId"),
        ["type"] = "points",
        ["direction"] = "+",
        ["points"] = GetDecimal(request, "points"),
        ["category"] = Convert.ToString(request["category"], CultureInfo.InvariantCulture) ?? "手表申请",
        ["description"] = Convert.ToString(request["title"], CultureInfo.InvariantCulture) ?? "手表积分申请",
        ["notes"] = $"手表端申请 #{id}"
    }, familyGroupId);

    if (transactionResult.TryGetValue("error", out var error))
    {
        return new Dictionary<string, object?> { ["error"] = error };
    }

    var transaction = (Dictionary<string, object?>)transactionResult["transaction"]!;
    await using (var conn = await OpenConnection(connectionString))
    await using (var cmd = new NpgsqlCommand("""
        UPDATE watch_reward_requests
        SET status = 'approved',
            reviewed_at = CURRENT_TIMESTAMP,
            completed_at = CURRENT_TIMESTAMP,
            review_note = @review_note,
            transaction_id = @transaction_id
        WHERE id = @id AND family_group_id = @family_group_id
        """, conn))
    {
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        cmd.Parameters.AddWithValue("review_note", reviewNote);
        cmd.Parameters.AddWithValue("transaction_id", GetInt(transaction, "id"));
        await cmd.ExecuteNonQueryAsync();
    }

    return new Dictionary<string, object?>
    {
        ["status"] = "approved",
        ["transaction"] = transaction,
        ["request"] = (await GetWatchRewardRequests(connectionString, familyGroupId, GetInt(request, "childId"), 10))
            .First(row => GetInt(row, "id") == id)
    };
}

static async Task<bool> ChildBelongsToFamily(NpgsqlConnection conn, int childId, int familyGroupId)
{
    await using var cmd = new NpgsqlCommand("SELECT COUNT(*) FROM children WHERE id = @child_id AND family_group_id = @family_group_id", conn);
    cmd.Parameters.AddWithValue("child_id", childId);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    return Convert.ToInt32(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0;
}

static async Task UpdateAccount(NpgsqlConnection conn, NpgsqlTransaction tx, int childId, string type, string direction, decimal points, decimal cash, string items)
{
    var sign = direction == "-" ? -1 : 1;
    var sql = type switch
    {
        "points" => sign > 0
            ? "UPDATE accounts SET points = points + @points, points_earned = points_earned + @points, updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)"
            : "UPDATE accounts SET points = points - @points, points_spent = points_spent + @points, updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        "cash" => sign > 0
            ? "UPDATE accounts SET cash_cny = cash_cny + @cash, cash_earned = cash_earned + @cash, updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)"
            : "UPDATE accounts SET cash_cny = cash_cny - @cash, cash_spent = cash_spent + @cash, updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        "items" => sign > 0
            ? "UPDATE accounts SET items_count = items_count + 1, items_detail = CONCAT_WS(', ', NULLIF(items_detail, ''), @items), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)"
            : "UPDATE accounts SET items_count = GREATEST(items_count - 1, 0), updated_at = CURRENT_TIMESTAMP WHERE profile_key = (SELECT profile_key FROM children WHERE id = @child_id)",
        _ => ""
    };
    if (string.IsNullOrWhiteSpace(sql))
    {
        return;
    }

    await using var cmd = new NpgsqlCommand(sql, conn, tx);
    cmd.Parameters.AddWithValue("child_id", childId);
    cmd.Parameters.AddWithValue("points", Math.Abs(points));
    cmd.Parameters.AddWithValue("cash", Math.Abs(cash));
    cmd.Parameters.AddWithValue("items", items);
    await cmd.ExecuteNonQueryAsync();
}

static Dictionary<string, object?> ReadChild(IDataRecord reader) => new()
{
    ["id"] = reader.Int("id"),
    ["name"] = reader.String("name"),
    ["status"] = reader.String("status"),
    ["note"] = reader.String("note"),
    ["profileKey"] = reader.HasColumn("profile_key") ? reader.String("profile_key") : "",
    ["profile_key"] = reader.HasColumn("profile_key") ? reader.String("profile_key") : "",
    ["createdAt"] = reader.DateTime("created_at").ToString("O"),
    ["updatedAt"] = reader.DateTime("updated_at").ToString("O")
};

static Dictionary<string, object?> ReadRule(IDataRecord reader)
{
    var points = reader.Decimal("points");
    return new Dictionary<string, object?>
    {
        ["id"] = reader.Int("id"),
        ["name"] = reader.String("name"),
        ["description"] = reader.String("description"),
        ["category"] = reader.String("category"),
        ["points"] = points,
        ["cash_cny"] = reader.Decimal("cash_cny"),
        ["type"] = points >= 0 ? "positive" : "negative",
        ["isRedLine"] = false,
        ["score"] = points,
        ["enabled"] = true,
        ["createdAt"] = reader.DateTime("created_at").ToString("O"),
        ["updatedAt"] = reader.HasColumn("updated_at") ? reader.DateTime("updated_at").ToString("O") : reader.DateTime("created_at").ToString("O")
    };
}

static Dictionary<string, object?> ReadWatchRewardRequest(IDataRecord reader) => new()
{
    ["id"] = reader.Int("id"),
    ["familyGroupId"] = reader.Int("family_group_id"),
    ["family_group_id"] = reader.Int("family_group_id"),
    ["childId"] = reader.Int("child_id"),
    ["child_id"] = reader.Int("child_id"),
    ["childName"] = reader.HasColumn("child_name") ? reader.String("child_name") : "",
    ["child_name"] = reader.HasColumn("child_name") ? reader.String("child_name") : "",
    ["ruleId"] = NullableInt(reader, "rule_id"),
    ["rule_id"] = NullableInt(reader, "rule_id"),
    ["ruleName"] = reader.HasColumn("rule_name") ? reader.String("rule_name") : "",
    ["rule_name"] = reader.HasColumn("rule_name") ? reader.String("rule_name") : "",
    ["title"] = reader.String("title"),
    ["category"] = reader.String("category"),
    ["points"] = reader.Decimal("points"),
    ["note"] = reader.String("note"),
    ["status"] = reader.String("status"),
    ["statusText"] = WatchRequestStatusText(reader.String("status")),
    ["requestedBy"] = reader.String("requested_by"),
    ["requested_by"] = reader.String("requested_by"),
    ["requestedAt"] = reader.DateTime("requested_at").ToString("O"),
    ["requested_at"] = reader.DateTime("requested_at").ToString("O"),
    ["reviewedAt"] = NullableDateTimeString(reader, "reviewed_at"),
    ["reviewed_at"] = NullableDateTimeString(reader, "reviewed_at"),
    ["completedAt"] = NullableDateTimeString(reader, "completed_at"),
    ["completed_at"] = NullableDateTimeString(reader, "completed_at"),
    ["reviewNote"] = reader.String("review_note"),
    ["review_note"] = reader.String("review_note"),
    ["transactionId"] = NullableInt(reader, "transaction_id"),
    ["transaction_id"] = NullableInt(reader, "transaction_id")
};

static Dictionary<string, object?> ReadWatchDevice(IDataRecord reader) => new()
{
    ["id"] = reader.Int("id"),
    ["childId"] = reader.Int("child_id"),
    ["familyGroupId"] = reader.Int("family_group_id"),
    ["childProfileKey"] = reader.String("child_profile_key"),
    ["parentAppUserId"] = reader.String("parent_app_user_id"),
    ["deviceName"] = reader.String("device_name"),
    ["platform"] = reader.String("platform"),
    ["userAgent"] = reader.String("user_agent"),
    ["boundAt"] = reader.DateTime("bound_at").ToString("O"),
    ["lastSeenAt"] = reader.DateTime("last_seen_at").ToString("O"),
    ["revokedAt"] = NullableDateTimeString(reader, "revoked_at"),
    ["active"] = NullableDateTimeString(reader, "revoked_at") is null
};

static Dictionary<string, object?> ReadTransaction(IDataRecord reader)
{
    var type = reader.String("type");
    var direction = reader.String("direction");
    var childName = reader.HasColumn("child_name") ? reader.String("child_name") : "";
    var amount = type switch
    {
        "cash" => reader.Decimal("cash_cny"),
        "items" => direction == "-" ? -1 : 1,
        _ => reader.Decimal("points")
    };
    if (direction == "-")
    {
        amount = -Math.Abs(amount);
    }

    return new Dictionary<string, object?>
    {
        ["id"] = reader.Int("id"),
        ["date"] = reader.DateOnly("date").ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        ["child_id"] = reader.Int("child_id"),
        ["childId"] = reader.Int("child_id"),
        ["child_name"] = childName,
        ["childName"] = childName,
        ["type"] = type switch { "points" => "score", "items" => "item", _ => type },
        ["rawType"] = type,
        ["direction"] = direction,
        ["category"] = reader.String("category"),
        ["description"] = reader.String("description"),
        ["points"] = reader.Decimal("points"),
        ["cash_cny"] = reader.Decimal("cash_cny"),
        ["items"] = reader.String("items"),
        ["amount"] = amount,
        ["notes"] = reader.String("notes"),
        ["createdAt"] = reader.DateTime("created_at").ToString("O"),
        ["created_at"] = reader.DateTime("created_at").ToString("O")
    };
}

static void AddFilter(List<string> where, List<NpgsqlParameter> parameters, bool skip, string sql, string name, object? value)
{
    if (skip)
    {
        return;
    }
    where.Add(sql);
    parameters.Add(new NpgsqlParameter(name, value ?? DBNull.Value));
}

static NpgsqlParameter CloneParameter(NpgsqlParameter source) => new(source.ParameterName, source.Value);

static string NormalizeTransactionType(string type) => type switch
{
    "score" => "points",
    "item" => "items",
    "" => "",
    _ => type
};

static bool TryParseDateFilter(string value, out DateOnly? date)
{
    date = null;
    if (string.IsNullOrWhiteSpace(value))
    {
        return true;
    }

    if (!System.DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
    {
        return false;
    }

    date = parsed;
    return true;
}

static int GetInt(IReadOnlyDictionary<string, object?> row, string key) =>
    Convert.ToInt32(row[key], CultureInfo.InvariantCulture);

static decimal GetDecimal(IReadOnlyDictionary<string, object?> row, string key) =>
    Convert.ToDecimal(row[key], CultureInfo.InvariantCulture);

static string NormalizeAuthCode(string value) =>
    new(value.Trim().Where(char.IsLetterOrDigit).Select(char.ToUpperInvariant).ToArray());

static string GenerateAuthCode()
{
    const string alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    Span<char> chars = stackalloc char[6];
    for (var i = 0; i < chars.Length; i++)
    {
        chars[i] = alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
    }
    return new string(chars);
}

static string GenerateDeviceToken()
{
    Span<byte> bytes = stackalloc byte[32];
    RandomNumberGenerator.Fill(bytes);
    return Convert.ToBase64String(bytes)
        .TrimEnd('=')
        .Replace('+', '-')
        .Replace('/', '_');
}

static string HashSecret(string value)
{
    var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
    return Convert.ToHexString(bytes).ToLowerInvariant();
}

static string GetWatchDeviceToken(HttpRequest request)
{
    if (request.Headers.TryGetValue("X-Watch-Device-Token", out var headerToken) && !string.IsNullOrWhiteSpace(headerToken.ToString()))
    {
        return headerToken.ToString().Trim();
    }
    if (request.Headers.TryGetValue("Authorization", out var authHeader))
    {
        var value = authHeader.ToString();
        const string bearer = "Bearer ";
        if (value.StartsWith(bearer, StringComparison.OrdinalIgnoreCase))
        {
            return value[bearer.Length..].Trim();
        }
    }
    return request.Query.String("deviceToken").Trim();
}

static string Truncate(string value, int maxLength)
{
    value = value.Trim();
    return value.Length <= maxLength ? value : value[..maxLength];
}

static int? NullableInt(IDataRecord reader, string name)
{
    if (!reader.HasColumn(name))
    {
        return null;
    }

    var value = reader[name];
    return value is DBNull ? null : Convert.ToInt32(value, CultureInfo.InvariantCulture);
}

static string? NullableString(IDataRecord reader, string name)
{
    if (!reader.HasColumn(name))
    {
        return null;
    }

    var value = reader[name];
    return value is DBNull ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
}

static string? NullableDateTimeString(IDataRecord reader, string name)
{
    if (!reader.HasColumn(name))
    {
        return null;
    }

    var value = reader[name];
    return value is DBNull ? null : Convert.ToDateTime(value, CultureInfo.InvariantCulture).ToString("O");
}

static string WatchRequestStatusText(string status) => status switch
{
    "pending" => "待确认",
    "approved" => "已领取",
    "rejected" => "已退回",
    _ => "处理中"
};

static string MakeChildProfileKey(string userId, string name)
{
    var owner = string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId.Trim();
    var normalizedName = name.Trim().ToLowerInvariant();
    return $"{owner}:{normalizedName}";
}

static string ExtractAgentText(JsonNode? providerJson, string fallback)
{
    var content = providerJson?["choices"]?[0]?["message"]?["content"]?.ToString();
    if (!string.IsNullOrWhiteSpace(content)) return content;

    content = providerJson?["choices"]?[0]?["text"]?.ToString();
    if (!string.IsNullOrWhiteSpace(content)) return content;

    content = providerJson?["output_text"]?.ToString();
    if (!string.IsNullOrWhiteSpace(content)) return content;

    content = providerJson?["response"]?.ToString();
    if (!string.IsNullOrWhiteSpace(content)) return content;

    return fallback;
}

static JsonObject? ParseJsonObjectFromText(string text)
{
    var cleaned = text.Trim();
    if (cleaned.StartsWith("```", StringComparison.Ordinal))
    {
        cleaned = cleaned.Replace("```json", "", StringComparison.OrdinalIgnoreCase)
            .Replace("```", "", StringComparison.Ordinal)
            .Trim();
    }

    try
    {
        return JsonNode.Parse(cleaned) as JsonObject;
    }
    catch
    {
        var start = cleaned.IndexOf('{');
        var end = cleaned.LastIndexOf('}');
        if (start >= 0 && end > start)
        {
            try { return JsonNode.Parse(cleaned[start..(end + 1)]) as JsonObject; } catch { }
        }
    }

    return null;
}

static void NormalizeRewardCommand(JsonObject command, List<Dictionary<string, object?>> children, string transcript)
{
    var childId = command.Int("childId");
    var childName = command.String("childName");
    var matchedChild = childId is not null
        ? children.FirstOrDefault(c => GetInt(c, "id") == childId)
        : null;
    matchedChild ??= children.FirstOrDefault(c => string.Equals(Convert.ToString(c["name"], CultureInfo.InvariantCulture), childName, StringComparison.Ordinal));
    matchedChild ??= children.FirstOrDefault(c => transcript.Contains(Convert.ToString(c["name"], CultureInfo.InvariantCulture) ?? "", StringComparison.Ordinal));

    if (matchedChild is not null)
    {
        command["childId"] = GetInt(matchedChild, "id");
        command["childName"] = Convert.ToString(matchedChild["name"], CultureInfo.InvariantCulture);
    }

    var type = command.String("type", "score");
    if (type is not ("score" or "cash" or "item"))
    {
        command["type"] = "score";
    }

    var amount = command.Decimal("amount") ?? 0;
    command["amount"] = amount;
    if (string.IsNullOrWhiteSpace(command.String("category")))
    {
        command["category"] = amount < 0 ? "扣分" : "奖励";
    }
    if (string.IsNullOrWhiteSpace(command.String("description")))
    {
        command["description"] = transcript;
    }
}

sealed class SystemConfigStore
{
    private readonly string _path;

    public SystemConfigStore(string contentRoot)
    {
        _path = Path.Combine(contentRoot, "system_config.json");
    }

    public JsonObject Load()
    {
        if (!File.Exists(_path))
        {
            var defaults = Defaults();
            File.WriteAllText(_path, defaults.ToJsonString(FamilyRewardJson.CreateOptions(writeIndented: true)));
            return defaults;
        }

        try
        {
            return JsonNode.Parse(File.ReadAllText(_path)) as JsonObject ?? Defaults();
        }
        catch
        {
            return Defaults();
        }
    }

    public JsonObject Save(JsonObject body)
    {
        var current = Load();
        Merge(current["voice"]!.AsObject(), body["voice"] as JsonObject);
        Merge(current["agent"]!.AsObject(), body["agent"] as JsonObject);
        File.WriteAllText(_path, current.ToJsonString(FamilyRewardJson.CreateOptions(writeIndented: true)));
        return current;
    }

    private static void Merge(JsonObject target, JsonObject? source)
    {
        if (source is null) return;
        foreach (var item in source)
        {
            target[item.Key] = item.Value?.DeepClone();
        }
    }

    private static JsonObject Defaults() => new()
    {
        ["voice"] = new JsonObject
        {
            ["enabled"] = false,
            ["recognitionLanguage"] = "zh-CN",
            ["transcriptionProvider"] = "browser"
        },
        ["agent"] = new JsonObject
        {
            ["enabled"] = false,
            ["endpoint"] = "",
            ["apiKey"] = "",
            ["model"] = "gpt-4o-mini",
            ["timeout_seconds"] = 20,
            ["systemPrompt"] = "你是家加分智能助手，输出简短可执行建议。"
        }
    };
}

static class ReaderExtensions
{
    public static bool HasColumn(this IDataRecord reader, string name)
    {
        for (var i = 0; i < reader.FieldCount; i++)
        {
            if (string.Equals(reader.GetName(i), name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    public static string String(this IDataRecord reader, string name)
    {
        var value = reader[name];
        return value is DBNull ? "" : Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
    }

    public static int Int(this IDataRecord reader, string name)
    {
        var value = reader[name];
        return value is DBNull ? 0 : Convert.ToInt32(value, CultureInfo.InvariantCulture);
    }

    public static decimal Decimal(this IDataRecord reader, string name)
    {
        var value = reader[name];
        return value is DBNull ? 0 : Convert.ToDecimal(value, CultureInfo.InvariantCulture);
    }

    public static DateTime DateTime(this IDataRecord reader, string name)
    {
        var value = reader[name];
        return value is DBNull ? System.DateTime.MinValue : Convert.ToDateTime(value, CultureInfo.InvariantCulture);
    }

    public static DateOnly DateOnly(this IDataRecord reader, string name)
    {
        var value = reader[name];
        return value switch
        {
            System.DateTime date => System.DateOnly.FromDateTime(date),
            System.DateOnly dateOnly => dateOnly,
            _ => System.DateOnly.Parse(Convert.ToString(value, CultureInfo.InvariantCulture) ?? "", CultureInfo.InvariantCulture)
        };
    }
}

static class JsonExtensions
{
    public static string String(this JsonObject body, string name, string fallback = "")
    {
        var value = body[name];
        return value is null ? fallback : value.GetValueKind() == JsonValueKind.Null ? fallback : value.ToString();
    }

    public static int? Int(this JsonObject body, string name)
    {
        var value = body[name];
        if (value is null) return null;
        return int.TryParse(value.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) ? parsed : null;
    }

    public static bool Bool(this JsonObject body, string name)
    {
        var value = body[name];
        if (value is null) return false;
        return bool.TryParse(value.ToString(), out var parsed)
            ? parsed
            : value.ToString() is "1" or "yes" or "on";
    }

    public static decimal? Decimal(this JsonObject body, string name)
    {
        var value = body[name];
        if (value is null) return null;
        return decimal.TryParse(value.ToString(), NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed) ? parsed : null;
    }
}

static class QueryExtensions
{
    public static string String(this IQueryCollection query, string name) =>
        query.TryGetValue(name, out var value) ? value.ToString() : "";

    public static int? Int(this IQueryCollection query, string name) =>
        int.TryParse(query.String(name), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) ? parsed : null;
}

static class FamilyRewardJson
{
    public static JsonSerializerOptions CreateOptions(bool writeIndented = false) => new(JsonSerializerDefaults.Web)
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = writeIndented
    };
}

public sealed record AppUserProfile(
    string UnifiedUserId,
    string Username,
    string Channel,
    string Role,
    string AppUserId,
    string? ChildProfileKey,
    int? ChildId,
    bool NeedsRole);

public sealed record WatchDeviceBinding(
    int Id,
    int ChildId,
    int FamilyGroupId,
    string ChildProfileKey,
    string ParentAppUserId,
    string TokenHash,
    string DeviceName,
    string Platform);
