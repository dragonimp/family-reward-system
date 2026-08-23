using AgentIdentity.Sdk;
using Goldfish.WebAppSdk;
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
const string FamilyRewardMcpApplyMatchingRuleToolName = "family_reward_apply_matching_rule";
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
const string FamilyRewardMcpUpdateFamilyGroupToolName = "family_reward_update_family_group";
const string FamilyRewardMcpDeleteFamilyGroupToolName = "family_reward_delete_family_group";
const string FamilyRewardMcpGetFamilyGroupInviteToolName = "family_reward_get_family_group_invite";
const string FamilyRewardMcpJoinFamilyGroupToolName = "family_reward_join_family_group";
const string FamilyRewardMcpRemoveFamilyGroupChildToolName = "family_reward_remove_family_group_child";
const string FamilyRewardMcpQueryFamilyMembersToolName = "family_reward_query_family_members";
const string FamilyRewardMcpCreateFamilyMemberToolName = "family_reward_create_family_member";
const string FamilyRewardMcpUpdateFamilyMemberToolName = "family_reward_update_family_member";
const string FamilyRewardMcpDeleteFamilyMemberToolName = "family_reward_delete_family_member";
const string FamilyRewardMcpUpdateRuleTemplateToolName = "family_reward_update_rule_template";
const string FamilyRewardMcpGenerateChildAuthCodeToolName = "family_reward_generate_child_auth_code";
const string FamilyRewardMcpQueryChildDevicesToolName = "family_reward_query_child_devices";
const string FamilyRewardMcpRevokeChildDeviceToolName = "family_reward_revoke_child_device";
const string FamilyRewardMcpGenerateDeviceUnbindCodeToolName = "family_reward_generate_device_unbind_code";
const string FamilyRewardMcpQueryChildFriendsToolName = "family_reward_query_child_friends";
const string FamilyRewardMcpQueryFriendNotificationsToolName = "family_reward_query_friend_notifications";
const string FamilyRewardMcpMarkFriendNotificationReadToolName = "family_reward_mark_friend_notification_read";
const string FamilyRewardMcpQueryRewardRequestsToolName = "family_reward_query_reward_requests";
const string FamilyRewardMcpApproveRewardRequestToolName = "family_reward_approve_reward_request";
const string FamilyRewardMcpQueryCircleDashboardToolName = "family_reward_query_circle_dashboard";
const string FamilyRewardMcpQueryCircleLeaderboardToolName = "family_reward_query_circle_leaderboard";
const string FamilyRewardMcpQueryCircleCategoriesToolName = "family_reward_query_circle_categories";
const string FamilyRewardMcpServiceName = "family-reward-mcp";
const string FamilyRewardMcpGroundingInstructions = "涉及孩子、家庭成员、积分余额或流水、规则、圈子、设备、好友、申请和统计等家加分业务事实时，必须先调用对应工具，并且只能依据工具本次返回的数据回答；不得依赖记忆、会话猜测或编造结果。工具不可用、调用失败或结果不足时，必须明确说明暂时无法核验并建议重试，不得声称查询或操作成功。自然语言行为记分必须优先调用 family_reward_apply_matching_rule，由服务端匹配当前生效规则并落库；不要仅查询规则后口头回复。";
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
builder.Services.AddAgentIdentityFeedbackClient(builder.Configuration);

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
    version = "3.2.0",
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

    var created = await CreateFamilyGroup(connectionString, body.String("name"), access.Profile!.AppUserId, body.String("description"));
    if (!created.Success)
    {
        return Results.BadRequest(new { error = created.Error });
    }

    return Results.Created($"/api/family-groups/{GetInt(created.Group!, "id")}", created.Group);
});

app.MapPut("/api/family-groups/{id:int}", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;

    var updated = await UpdateFamilyGroup(connectionString, id, body.String("name"), access.Profile!.AppUserId, body.String("description"));
    if (updated.Forbidden)
    {
        return Results.Json(new { error = updated.Error }, statusCode: StatusCodes.Status403Forbidden);
    }
    if (!updated.Success)
    {
        return updated.NotFound
            ? Results.NotFound(new { error = updated.Error })
            : Results.BadRequest(new { error = updated.Error });
    }

    return Results.Json(updated.Group);
});

app.MapDelete("/api/family-groups/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;

    var result = await DeleteFamilyGroup(connectionString, id, access.Profile!.AppUserId);
    if (result.Forbidden)
    {
        return Results.Json(new { error = result.Error }, statusCode: StatusCodes.Status403Forbidden);
    }
    return result.Success
        ? Results.Json(new
        {
            status = "ok",
            familyGroupId = id,
            familyGroupName = result.FamilyGroupName,
            removedChildren = result.RemovedChildren
        })
        : Results.NotFound(new { error = result.Error });
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
    var linked = await UpsertFamilyGroupUser(connectionString, id, userId, role, access.Profile!.AppUserId);
    if (linked.Forbidden)
    {
        return Results.Json(new { error = linked.Error }, statusCode: StatusCodes.Status403Forbidden);
    }
    return linked.Success ? Results.Json(new { ok = true }) : Results.NotFound(new { error = linked.Error });
});

app.MapGet("/api/family-groups/{id:int}/children", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var result = await GetFamilyGroupChildren(connectionString, id, access.Profile!.AppUserId);
    if (result.Forbidden)
    {
        return Results.Json(new { error = result.Error }, statusCode: StatusCodes.Status403Forbidden);
    }
    return result.Success ? Results.Json(result.Children) : Results.NotFound(new { error = result.Error });
});

app.MapDelete("/api/family-groups/{id:int}/children/{childId:int}", async (int id, int childId, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var result = await RemoveChildFromFamilyGroup(connectionString, id, childId, access.Profile!.AppUserId);
    if (result.Forbidden)
    {
        return Results.Json(new { error = result.Error }, statusCode: StatusCodes.Status403Forbidden);
    }
    return result.Success ? Results.Json(new { status = "ok" }) : Results.NotFound(new { error = result.Error });
});

app.MapGet("/api/family-members", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;

    await using var conn = await OpenConnection(connectionString);
    await using (var ensureCmd = new NpgsqlCommand("""
        INSERT INTO household_members (owner_parent_app_user_id, display_name, role, is_current_user)
        VALUES (@owner_parent_app_user_id, @display_name, 'guardian', TRUE)
        ON CONFLICT DO NOTHING
        """, conn))
    {
        ensureCmd.Parameters.AddWithValue("owner_parent_app_user_id", access.Profile!.AppUserId);
        ensureCmd.Parameters.AddWithValue("display_name", access.Profile.Username);
        await ensureCmd.ExecuteNonQueryAsync();
    }

    return Results.Json(await GetHouseholdMembers(conn, access.Profile!.AppUserId));
});

app.MapPost("/api/family-members", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var displayName = body.String("displayName").Trim();
    var role = NormalizeHouseholdRole(body.String("role"));
    var note = body.String("note").Trim();
    if (string.IsNullOrWhiteSpace(displayName)) return Results.BadRequest(new { error = "请输入家庭成员姓名" });
    if (displayName.Length > 50) return Results.BadRequest(new { error = "家庭成员姓名不能超过 50 个字符" });
    if (string.IsNullOrWhiteSpace(role)) return Results.BadRequest(new { error = "请选择有效的家庭角色" });

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO household_members (owner_parent_app_user_id, display_name, role, note, is_current_user)
        VALUES (@owner_parent_app_user_id, @display_name, @role, @note, FALSE)
        RETURNING id, display_name, role, note, is_current_user, created_at, updated_at
        """, conn);
    cmd.Parameters.AddWithValue("owner_parent_app_user_id", access.Profile!.AppUserId);
    cmd.Parameters.AddWithValue("display_name", displayName);
    cmd.Parameters.AddWithValue("role", role);
    cmd.Parameters.AddWithValue("note", string.IsNullOrWhiteSpace(note) ? DBNull.Value : note);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return Results.Created($"/api/family-members/{reader.GetInt32(reader.GetOrdinal("id"))}", ReadHouseholdMember(reader));
});

app.MapPut("/api/family-members/{id:int}", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var displayName = body.String("displayName").Trim();
    var role = NormalizeHouseholdRole(body.String("role"));
    var note = body.String("note").Trim();
    if (string.IsNullOrWhiteSpace(displayName)) return Results.BadRequest(new { error = "请输入家庭成员姓名" });
    if (displayName.Length > 50) return Results.BadRequest(new { error = "家庭成员姓名不能超过 50 个字符" });
    if (string.IsNullOrWhiteSpace(role)) return Results.BadRequest(new { error = "请选择有效的家庭角色" });

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE household_members
        SET display_name = @display_name,
            role = @role,
            note = @note,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = @id AND owner_parent_app_user_id = @owner_parent_app_user_id
        RETURNING id, display_name, role, note, is_current_user, created_at, updated_at
        """, conn);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("owner_parent_app_user_id", access.Profile!.AppUserId);
    cmd.Parameters.AddWithValue("display_name", displayName);
    cmd.Parameters.AddWithValue("role", role);
    cmd.Parameters.AddWithValue("note", string.IsNullOrWhiteSpace(note) ? DBNull.Value : note);
    await using var reader = await cmd.ExecuteReaderAsync();
    return await reader.ReadAsync()
        ? Results.Json(ReadHouseholdMember(reader))
        : Results.NotFound(new { error = "家庭成员不存在" });
});

app.MapDelete("/api/family-members/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;

    await using var conn = await OpenConnection(connectionString);
    await using (var cmd = new NpgsqlCommand("""
        DELETE FROM household_members
        WHERE id = @id
          AND owner_parent_app_user_id = @owner_parent_app_user_id
          AND is_current_user = FALSE
        """, conn))
    {
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("owner_parent_app_user_id", access.Profile!.AppUserId);
        if (await cmd.ExecuteNonQueryAsync() > 0) return Results.Json(new { status = "ok" });
    }

    await using var existsCmd = new NpgsqlCommand("""
        SELECT is_current_user
        FROM household_members
        WHERE id = @id AND owner_parent_app_user_id = @owner_parent_app_user_id
        """, conn);
    existsCmd.Parameters.AddWithValue("id", id);
    existsCmd.Parameters.AddWithValue("owner_parent_app_user_id", access.Profile!.AppUserId);
    var isCurrentUser = await existsCmd.ExecuteScalarAsync();
    return isCurrentUser is true
        ? Results.Conflict(new { error = "当前用户不能从家庭成员中删除" })
        : Results.NotFound(new { error = "家庭成员不存在" });
});

app.MapGet("/api/children", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var ownedOnly = request.Query.Bool("ownedOnly") ?? request.Query.Bool("owned_only") ?? false;
    int? familyGroupId = ownedOnly && !HasFamilyGroupSelector(request)
        ? null
        : await ResolveFamilyGroupId(connectionString, request);
    return Results.Json(await GetChildren(connectionString, familyGroupId, ownerAppUserId: ownedOnly ? access.Profile!.AppUserId : null));
});

app.MapGet("/api/children/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var ownedOnly = request.Query.Bool("ownedOnly") ?? request.Query.Bool("owned_only") ?? true;
    int? familyGroupId = HasFamilyGroupSelector(request)
        ? await ResolveFamilyGroupId(connectionString, request)
        : null;
    var child = (await GetChildren(connectionString, familyGroupId, ownerAppUserId: ownedOnly ? access.Profile!.AppUserId : null)).FirstOrDefault(c => GetInt(c, "id") == id);
    return child is null ? Results.NotFound(new { error = "不存在" }) : Results.Json(child);
});

app.MapGet("/api/watch/preview/{childId:int}", async (int childId, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;

    var ownedChildren = await GetChildren(connectionString, ownerAppUserId: access.Profile!.AppUserId);
    var child = ownedChildren.FirstOrDefault(item => GetInt(item, "id") == childId);
    if (child is null)
    {
        return Results.NotFound(new { error = "孩子不存在，或不属于当前家长账号" });
    }

    var familyGroupId = GetInt(child, "familyGroupId");
    var childProfileKey = Convert.ToString(child["profileKey"], CultureInfo.InvariantCulture) ?? "";
    var rulesPayload = await GetRules(connectionString, access.Profile.AppUserId);
    var rules = ((List<Dictionary<string, object?>>)rulesPayload["rules"])
        .Where(rule => GetDecimal(rule, "points") > 0)
        .Take(8)
        .Select(rule => new
        {
            id = GetInt(rule, "id"),
            name = Convert.ToString(rule["name"], CultureInfo.InvariantCulture) ?? "",
            category = Convert.ToString(rule["category"], CultureInfo.InvariantCulture) ?? "",
            points = GetDecimal(rule, "points"),
            description = Convert.ToString(rule["description"], CultureInfo.InvariantCulture) ?? ""
        });
    var requests = familyGroupId > 0
        ? await GetWatchRewardRequests(connectionString, familyGroupId, childId, 6, childProfileKey)
        : [];

    return Results.Json(new
    {
        preview = true,
        score = new
        {
            familyGroupId,
            familyGroupName = Convert.ToString(child["familyGroupName"], CultureInfo.InvariantCulture) ?? "",
            deviceId = "preview",
            updatedAt = DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            children = new[]
            {
                new
                {
                    id = childId,
                    name = Convert.ToString(child["name"], CultureInfo.InvariantCulture) ?? "",
                    points = GetDecimal(child, "score"),
                    cash = GetDecimal(child, "cash"),
                    items = GetInt(child, "items")
                }
            }
        },
        rules = new { rules },
        requests = new { familyGroupId, requests },
        settings = await GetWatchSettings(connectionString, childProfileKey),
        friends = new
        {
            friends = await GetChildFriends(connectionString, childProfileKey),
            leaderboard = await GetChildFriendLeaderboard(connectionString, childProfileKey)
        }
    });
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
    var rulesPayload = await GetRules(connectionString, binding.Binding!.ParentAppUserId);
    var rules = ((List<Dictionary<string, object?>>)rulesPayload["rules"])
        .Where(rule => GetDecimal(rule, "points") > 0)
        .Take(8)
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

app.MapGet("/api/watch/settings", async (HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request, touch: false);
    if (binding.Error is not null) return binding.Error;
    return Results.Json(await GetWatchSettings(connectionString, binding.Binding!.ChildProfileKey));
});

app.MapPut("/api/watch/settings", async (JsonObject body, HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request, touch: false);
    if (binding.Error is not null) return binding.Error;
    var result = await UpdateWatchSettings(connectionString, binding.Binding!.ChildProfileKey, body.String("watchFace"));
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapGet("/api/watch/friends", async (HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request);
    if (binding.Error is not null) return binding.Error;
    return Results.Json(new
    {
        friends = await GetChildFriends(connectionString, binding.Binding!.ChildProfileKey),
        leaderboard = await GetChildFriendLeaderboard(connectionString, binding.Binding!.ChildProfileKey)
    });
});

app.MapPost("/api/watch/friend-code", async (JsonObject body, HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request, touch: false);
    if (binding.Error is not null) return binding.Error;
    var minutes = Math.Clamp(body.Int("expiresInMinutes") ?? 30, 5, 120);
    return Results.Json(await CreateWatchFriendCode(connectionString, binding.Binding!, minutes));
});

app.MapPost("/api/watch/friends", async (JsonObject body, HttpRequest request) =>
{
    var binding = await RequireWatchDeviceBinding(connectionString, request);
    if (binding.Error is not null) return binding.Error;
    var result = await AddWatchFriendByCode(connectionString, binding.Binding!, body.String("code"));
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
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
    var familyGroupId = HasFamilyGroupSelector(request, body)
        ? await ResolveFamilyGroupId(connectionString, request, body)
        : (int?)null;
    var result = await ApproveWatchRewardRequest(connectionString, id, familyGroupId, access.Profile!.AppUserId, body.String("reviewNote"));
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapGet("/api/reward-requests", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = HasFamilyGroupSelector(request)
        ? await ResolveFamilyGroupId(connectionString, request)
        : (int?)null;
    var limit = Math.Clamp(request.Query.Int("limit") ?? 20, 1, 50);
    var status = request.Query.String("status");
    var result = await GetParentWatchRewardRequests(connectionString, familyGroupId, access.Profile!.AppUserId, status, limit);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPost("/api/reward-requests/{id:int}/approve", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = HasFamilyGroupSelector(request, body)
        ? await ResolveFamilyGroupId(connectionString, request, body)
        : (int?)null;
    var result = await ApproveWatchRewardRequest(connectionString, id, familyGroupId, access.Profile!.AppUserId, body.String("reviewNote"));
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPost("/api/feedback", async (JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    if (LegacyFeedbackEndpointsRetired()) return Results.StatusCode(StatusCodes.Status410Gone);

    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;

    var feedbackType = body.String("feedbackType", body.String("feedback_type", "suggestion")).Trim().ToLowerInvariant();
    if (feedbackType is not ("suggestion" or "defect" or "question"))
    {
        return Results.BadRequest(new { error = "请选择有效的反馈类型" });
    }
    var title = body.String("title").Trim();
    var content = body.String("content").Trim();
    var contact = body.String("submitterContact", body.String("submitter_contact")).Trim();
    if (string.IsNullOrWhiteSpace(contact)) contact = GetUnifiedContact(request);
    if (title.Length is < 1 or > 200) return Results.BadRequest(new { error = "标题长度应为 1-200 个字符" });
    if (content.Length is < 1 or > 5000) return Results.BadRequest(new { error = "反馈内容长度应为 1-5000 个字符" });
    if (contact.Length > 160) return Results.BadRequest(new { error = "联系方式不能超过 160 个字符" });

    var source = body["source"] as JsonObject ?? new JsonObject();
    var sourceRecordId = body.String("sourceRecordId", body.String("source_record_id")).Trim();
    if (string.IsNullOrWhiteSpace(sourceRecordId)) sourceRecordId = $"feedback-{Guid.NewGuid():N}";
    if (sourceRecordId.Length is < 8 or > 200) return Results.BadRequest(new { error = "反馈记录编号无效" });
    var sourceUrl = SanitizeFeedbackUrl(source.String("url", body.String("source_url")), request);
    var sourcePath = source.String("path");
    if (string.IsNullOrWhiteSpace(sourcePath) && Uri.TryCreate(sourceUrl, UriKind.Absolute, out var parsedSourceUrl))
    {
        sourcePath = $"{parsedSourceUrl.PathAndQuery}{parsedSourceUrl.Fragment}";
    }
    var pageContext = new JsonObject
    {
        ["pageTitle"] = LimitText(source.String("pageTitle"), 200),
        ["path"] = SanitizeFeedbackPath(sourcePath),
        ["viewport"] = LimitText(source.String("viewport"), 40),
        ["userAgent"] = LimitText(source.String("userAgent"), 500),
        ["capturedAt"] = LimitText(source.String("capturedAt"), 80)
    };
    var atlasPayload = new JsonObject
    {
        ["project_code"] = "family-reward",
        ["app_code"] = "",
        ["feedback_type"] = feedbackType,
        ["title"] = title,
        ["content"] = content,
        ["submitter_name"] = string.IsNullOrWhiteSpace(access.Profile!.Username) ? access.Profile.AppUserId : access.Profile.Username,
        ["submitter_contact"] = contact,
        ["submitter_type"] = "external_user",
        ["source_type"] = "user_report",
        ["source_system"] = "family-reward-web",
        ["source_record_id"] = sourceRecordId,
        ["source_url"] = sourceUrl,
        ["page_context"] = FormatFeedbackPageContext(pageContext),
        ["source_metadata"] = new JsonObject
        {
            ["source"] = new JsonObject
            {
                ["type"] = "user_report",
                ["system"] = "family-reward-web",
                ["recordId"] = sourceRecordId,
                ["url"] = sourceUrl,
                ["pageContext"] = pageContext.DeepClone(),
                ["projectCode"] = "family-reward"
            }
        }.ToJsonString(FamilyRewardJson.CreateOptions())
    };

    return await ProxyAtlasFeedback(httpClientFactory, access.Profile, HttpMethod.Post, "/api/feedback", atlasPayload);
});

app.MapGet("/api/feedback/mine", async (IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    if (LegacyFeedbackEndpointsRetired()) return Results.StatusCode(StatusCodes.Status410Gone);

    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var take = Math.Clamp(request.Query.Int("take") ?? 50, 1, 100);
    var result = await FetchAtlasFeedback(httpClientFactory, access.Profile!, $"/api/feedback/mine?take={take}");
    if (result.Error is not null) return result.Error;
    var items = result.Payload as JsonArray ?? new JsonArray();
    var filtered = new JsonArray(items
        .OfType<JsonObject>()
        .Where(item => string.Equals(item.String("project_code"), "family-reward", StringComparison.OrdinalIgnoreCase))
        .Select(item => item.DeepClone())
        .ToArray());
    return Results.Json(filtered);
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
            *{box-sizing:border-box}
            html,body{width:100%;height:100%;overscroll-behavior:none}
            body{min-height:100vh;height:100vh;height:100dvh;margin:0;overflow:hidden;background:#dce8e2;color:#102019;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
            .wrap{display:grid;place-items:center;width:100%;height:100%;padding:4px;padding:4px max(4px,env(safe-area-inset-right)) 4px max(4px,env(safe-area-inset-left));overflow:hidden}
            .watch-shell{--watch-size:min(calc(100vw - clamp(36px,14vmin,52px)),calc(100vh - 8px),346px);position:relative;width:var(--watch-size);height:var(--watch-size);margin-right:clamp(26px,10vmin,38px)}
            @supports(height:100dvh){.watch-shell{--watch-size:min(calc(100vw - clamp(36px,14vmin,52px)),calc(100dvh - 8px),346px)}}
            .watch-face{position:relative;width:100%;height:100%;overflow:hidden;border-radius:50%;border:clamp(6px,2.8vmin,10px) solid #17231b;background:#f9fbf7;box-shadow:0 12px 30px rgba(16,32,25,.2),inset 0 0 0 1px #cad7ce}
            .watch-face:before{content:"";position:absolute;inset:clamp(8px,4vmin,14px);border:1px solid #d8e2dc;border-radius:50%;pointer-events:none}
            .watch-face.face-world{background:linear-gradient(135deg,#e8f6e9 0 22%,#b9e0b3 22% 39%,#f6f0d3 39% 58%,#96c66d 58% 76%,#e8f6e9 76%);color:#102019}
            .watch-face.face-hellokitty{background:radial-gradient(circle at 68% 23%,#fff 0 10%,transparent 11%),linear-gradient(145deg,#ffeaf3,#fff7fb 48%,#ffd7e8);color:#2d1d24}
            .watch-face.face-starlight{background:radial-gradient(circle at 24% 22%,#ffe27a 0 2.8%,transparent 3.2%),radial-gradient(circle at 72% 34%,#8dd9ff 0 2.5%,transparent 3%),linear-gradient(145deg,#10233b,#284c72 58%,#8bd0d4);color:#f8fbff}
            .watch-face.face-dinosaur{background:radial-gradient(circle at 72% 28%,#f5df77 0 8%,transparent 8.5%),linear-gradient(155deg,#d7f3cb,#76bd6e 58%,#3d8655);color:#153521}
            .watch-face.face-rainbow{background:linear-gradient(145deg,#ff9cab 0 20%,#ffd56a 20% 40%,#8bd48c 40% 60%,#76c8f2 60% 80%,#bca2ee 80%);color:#30243b}
            .watch-face.face-space{background:radial-gradient(circle at 22% 24%,#fff 0 1.2%,transparent 1.8%),radial-gradient(circle at 76% 34%,#ffe16b 0 2%,transparent 2.7%),radial-gradient(circle at 62% 74%,#8cddff 0 1.5%,transparent 2.2%),linear-gradient(145deg,#10142f,#332a68 62%,#145f7a);color:#f8fbff}
            .watch-face.face-starlight .topline,.watch-face.face-starlight .brand{color:#f8fbff}.watch-face.face-starlight .metric,.watch-face.face-starlight .rule-btn,.watch-face.face-starlight input,.watch-face.face-starlight textarea{background:rgba(255,255,255,.94)}
            .watch-face.face-space .topline,.watch-face.face-space .brand{color:#f8fbff}.watch-face.face-space .metric,.watch-face.face-space .rule-btn,.watch-face.face-space input,.watch-face.face-space textarea{background:rgba(255,255,255,.94)}
            .screen{position:absolute;inset:clamp(14px,7vmin,24px);display:flex;align-items:center;justify-content:center;overflow:hidden;text-align:center}
            .topline{position:absolute;top:clamp(7px,3vmin,11px);left:18%;right:18%;display:flex;align-items:center;justify-content:center;gap:4px;overflow:hidden;color:#65736b;font-size:clamp(9px,3.2vmin,11px);white-space:nowrap}
            .brand{font-size:clamp(10px,3.5vmin,12px);font-weight:900;color:#245138}
            .home-child{max-width:min(170px,70vmin);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:clamp(18px,7vmin,24px);font-weight:900}
            .score-ring{display:grid;place-items:center;width:clamp(76px,42vmin,150px);height:clamp(76px,42vmin,150px);margin:clamp(4px,2.8vmin,10px) 0 clamp(3px,1.8vmin,6px);border-radius:50%;border:clamp(4px,2vmin,7px) solid #1f7a48;background:#fff}
            .score{width:100%;padding:0 2px;color:#0c6f3b;font-size:clamp(24px,10vmin,38px);font-variant-numeric:tabular-nums;font-weight:900;letter-spacing:0;line-height:.95;white-space:nowrap}
            .unit{margin-top:clamp(2px,1.4vmin,5px);color:#5c6b62;font-size:clamp(9px,3.5vmin,12px);font-weight:800}
            .metric-row{display:grid;grid-template-columns:1fr 1fr;gap:clamp(3px,1.8vmin,6px);width:min(170px,70vmin)}
            .metric{min-width:0;border:1px solid #d7e1da;border-radius:8px;padding:clamp(3px,1.4vmin,5px) clamp(4px,1.8vmin,6px);background:#eef5f0}
            .metric b{display:block;overflow:hidden;color:#24352b;font-size:clamp(11px,4vmin,14px);text-overflow:ellipsis;white-space:nowrap}.metric span{display:block;margin-top:1px;color:#65736b;font-size:clamp(8px,3vmin,10px)}
            .menu-dock{position:absolute;right:clamp(-4px,-1vmin,-2px);top:50%;z-index:3;transform:translateY(-50%)}
            .menu-toggle{display:grid;place-items:center;width:clamp(34px,13vmin,44px);height:clamp(34px,13vmin,44px);border:2px solid #17231b;border-radius:50%;background:#17231b;color:#fff;font-size:clamp(9px,3.2vmin,11px);font-weight:900;box-shadow:0 4px 10px rgba(16,32,25,.16)}
            .panel{--panel-scale:1;display:none;width:min(205px,100%);max-width:100%;overflow:hidden;text-align:left;transform:scale(var(--panel-scale));transform-origin:center;will-change:transform}.panel.active{display:block}.panel[data-panel=home],#bind-panel .panel{text-align:center}.panel[data-panel=home].active{display:flex;flex-direction:column;align-items:center;justify-content:center}
            .panel:not([data-panel=home]){height:100%;padding:1px 5px 4px 1px;overflow-x:hidden;overflow-y:auto;overscroll-behavior:contain;scrollbar-color:#5d7768 transparent;scrollbar-gutter:stable;scrollbar-width:thin;touch-action:pan-y}.panel:not([data-panel=home])::-webkit-scrollbar{width:4px}.panel:not([data-panel=home])::-webkit-scrollbar-thumb{border-radius:4px;background:#5d7768}.panel:not([data-panel=home])::-webkit-scrollbar-track{background:transparent}
            .panel[data-panel=menu]{height:auto;overflow:hidden;padding:0}
            .panel h1,.panel h2{margin:0 0 8px;text-align:center;font-size:18px;line-height:1.1}.bind-title{font-size:20px;font-weight:900}.bind-sub{margin:5px 0 10px;color:#65736b;font-size:12px}.rules{display:grid;gap:6px}
            .menu-header{display:grid;grid-template-columns:30px 1fr 30px;align-items:center;margin-bottom:7px}.menu-header h2{grid-column:2;margin:0}.home-menu{display:grid;place-items:center;width:28px;height:28px;border:1px solid #c9dbcf;border-radius:8px;background:#fff;color:#17613a;font-size:16px}.menu-groups{display:grid;gap:7px}.menu-group-title{margin:0 0 3px;color:#526258;font-size:10px;font-weight:900}.menu-grid{display:grid;grid-template-columns:1fr 1fr;gap:5px}.menu-card{display:grid;grid-template-columns:26px 1fr;align-items:center;min-height:42px;border:1px solid #d5e0d9;border-radius:8px;background:rgba(255,255,255,.94);padding:5px;color:#17231b;text-align:left}.menu-icon{display:grid;place-items:center;width:24px;height:24px;border-radius:7px;background:#e7f2eb;font-size:15px}.menu-card span:last-child{font-size:10px;font-weight:900;line-height:1.15}.back-menu{display:inline-flex;align-items:center;gap:3px;margin:0 0 6px;border:0;background:transparent;color:#17613a;padding:2px 0;font-size:11px;font-weight:900}.rule-btn{display:grid;grid-template-columns:24px 1fr auto;align-items:center;gap:6px;width:100%;min-height:36px;border:1px solid #d3ded7;border-radius:8px;background:#fff;color:#17231b;padding:5px 7px;font-size:11px;text-align:left}.rule-icon{display:grid;place-items:center;width:22px;height:22px;border-radius:6px;background:#eef5f0}.rule-btn span{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rule-btn b{color:#0c6f3b;white-space:nowrap}.input-action{display:grid;grid-template-columns:1fr auto;gap:5px;align-items:center}.voice-btn{display:grid;place-items:center;width:34px;height:34px;border:1px solid #bfd2c5;border-radius:8px;background:#edf6f0;color:#155c37;font-size:16px}.voice-btn.listening{background:#155c37;color:#fff}.detail-metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;margin-bottom:8px}.detail-metric{border:1px solid #dce6df;border-radius:8px;background:rgba(255,255,255,.92);padding:6px 2px;text-align:center}.detail-metric b{display:block;color:#0c6f3b;font-size:15px}.detail-metric span{font-size:9px;color:#65736b}
            label{display:block;margin:7px 0 3px;color:#44544a;font-size:11px;font-weight:700}input,textarea{width:100%;border:1px solid #cbd8cf;border-radius:8px;background:#fff;color:#17231b;padding:7px;font-size:14px}textarea{min-height:44px;resize:none}.submit,.ghost{width:100%;margin-top:8px;border:0;border-radius:8px;padding:9px;font-size:14px;font-weight:900}.submit{background:#1f7a48;color:#fff}.ghost{background:#e7efe9;color:#17462c}.msg{min-height:16px;margin:6px 0 0;text-align:center;color:#16643a;font-size:11px}
            .requests{list-style:none;margin:0;padding:0;display:grid;gap:5px}.requests li{display:grid;grid-template-columns:1fr auto;gap:6px;border-top:1px solid #e3ebe6;padding-top:5px;color:#25362c;font-size:11px}.requests span{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.requests b{color:#71601b;white-space:nowrap}.empty,.empty-row{color:#64746a;text-align:center;font-size:12px}.code{text-align:center;letter-spacing:3px;font-size:22px;font-weight:900;text-transform:uppercase}.hidden{display:none!important}
            .friend-code{margin:5px 0;border:1px solid #cfe1d4;border-radius:8px;background:#fff;padding:8px;text-align:center}.friend-code b{display:block;color:#102019;font-size:22px;letter-spacing:3px}.friend-code span{display:block;margin-top:2px;color:#637268;font-size:10px}.compact-list{list-style:none;margin:0;padding:0;display:grid;gap:5px}.compact-list li{display:grid;grid-template-columns:auto 1fr auto;gap:5px;align-items:center;border:1px solid #e0e9e3;border-radius:8px;background:rgba(255,255,255,.9);padding:5px 6px;font-size:11px}.compact-list li.empty-row{display:block;text-align:center}.compact-list em{font-style:normal;font-weight:900;color:#5e6a63}.compact-list span{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.compact-list b{color:#0c6f3b;white-space:nowrap}.leaderboard-banner{margin:0 0 6px;border:1px solid #e6c856;border-radius:8px;background:#fff7ca;padding:6px;text-align:center;color:#765817;font-size:11px;font-weight:900}.leaderboard-list li{min-height:34px;border-color:#d8dfc2;background:#fffdf2}.leaderboard-list li:first-child{border-color:#e5b72f;background:#fff2ad}.leaderboard-list li:nth-child(2){border-color:#b9c3c7;background:#f3f6f7}.leaderboard-list li:nth-child(3){border-color:#d29b6c;background:#fff0e2}.rank-icon{display:grid;place-items:center;width:24px;height:24px;font-size:17px}.face-grid{display:grid;gap:6px}.face-option{display:flex;align-items:center;justify-content:space-between;width:100%;border:1px solid #d8e4dc;border-radius:8px;background:#fff;padding:7px;color:#17231b;font-size:12px;font-weight:900}.face-option.active{border-color:#1f7a48;background:#e7f5ec;color:#0c6f3b}.face-swatch{width:22px;height:22px;border-radius:50%;border:1px solid #becdc4}.swatch-world{background:linear-gradient(135deg,#b9e0b3 0 45%,#f6f0d3 45% 65%,#96c66d 65%)}.swatch-hellokitty{background:linear-gradient(145deg,#ffeaf3,#ffd7e8)}.swatch-starlight{background:linear-gradient(145deg,#10233b,#8bd0d4)}.swatch-dinosaur{background:linear-gradient(145deg,#d7f3cb,#3d8655)}.swatch-rainbow{background:linear-gradient(145deg,#ff9cab,#ffd56a,#76c8f2,#bca2ee)}.swatch-space{background:linear-gradient(145deg,#10142f,#145f7a)}
            @media(max-width:260px),(max-height:260px){.panel h1,.panel h2{font-size:16px}.rules{gap:4px}input,textarea{font-size:13px;padding:6px}}
            @media(prefers-reduced-motion:reduce){.panel{will-change:auto}}
          </style>
        </head>
        <body>
          <main class="wrap">
            <div class="watch-shell">
              <div class="watch-face face-world" id="watch-face">
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
                  <div class="panel" data-panel="menu">
                    <div class="menu-header"><button class="home-menu" id="home-menu" type="button" aria-label="返回首页">⌂</button><h2>功能菜单</h2></div>
                    <div class="menu-groups">
                      <div><p class="menu-group-title">积分</p><div class="menu-grid">
                        <button class="menu-card" type="button" data-view="request"><span class="menu-icon">⭐</span><span>积分申请</span></button>
                        <button class="menu-card" type="button" data-view="points-detail"><span class="menu-icon">🏅</span><span>积分详情</span></button>
                      </div></div>
                      <div><p class="menu-group-title">好友</p><div class="menu-grid">
                        <button class="menu-card" type="button" data-view="friend-add"><span class="menu-icon">👥</span><span>添加好友</span></button>
                        <button class="menu-card" type="button" data-view="leaderboard"><span class="menu-icon">🏆</span><span>排行榜</span></button>
                      </div></div>
                      <div><p class="menu-group-title">设置</p><div class="menu-grid">
                        <button class="menu-card" type="button" data-view="settings"><span class="menu-icon">⌚</span><span>表盘设置</span></button>
                        <button class="menu-card" type="button" data-view="device"><span class="menu-icon">🔗</span><span>设备绑定</span></button>
                      </div></div>
                    </div>
                  </div>
                  <div class="panel" data-panel="request">
                    <button class="back-menu" type="button">‹ 返回菜单</button>
                    <h2>申请奖励</h2>
                    <form id="request-form">
                      <input type="hidden" name="rule_id" id="rule-id">
                      <div class="rules" id="rules"></div>
                      <label for="title">申请事项</label>
                      <div class="input-action"><input id="title" name="title" maxlength="80" placeholder="比如 好好吃饭"><button class="voice-btn" type="button" data-speech-target="title" aria-label="语音输入申请事项">🎙</button></div>
                      <input type="hidden" id="points" name="points">
                      <button class="submit" type="submit">提交</button>
                      <p id="msg" class="msg"></p>
                    </form>
                  </div>
                  <div class="panel" data-panel="points-detail">
                    <button class="back-menu" type="button">‹ 返回菜单</button>
                    <h2>积分详情</h2>
                    <div class="detail-metrics">
                      <div class="detail-metric"><b id="detail-score">0</b><span>积分</span></div>
                      <div class="detail-metric"><b id="detail-cash">0</b><span>现金</span></div>
                      <div class="detail-metric"><b id="detail-items">0</b><span>物品</span></div>
                    </div>
                    <label>最近申请</label>
                    <ul class="requests" id="requests"></ul>
                  </div>
                  <div class="panel" data-panel="friend-add">
                    <button class="back-menu" type="button">‹ 返回菜单</button>
                    <h2>添加好友</h2>
                    <button class="submit" id="make-friend-code" type="button">生成好友码</button>
                    <div class="friend-code hidden" id="friend-code-box">
                      <b id="friend-code">--------</b>
                      <span id="friend-code-expire"></span>
                    </div>
                    <label for="friend-code-input">输入好友码</label>
                    <input id="friend-code-input" class="code" maxlength="8" inputmode="numeric" autocomplete="one-time-code" placeholder="8位">
                    <button class="ghost" id="add-friend" type="button">添加好友</button>
                    <p id="friend-msg" class="msg"></p>
                    <label>好友列表</label>
                    <ul class="compact-list" id="friends-list"></ul>
                  </div>
                  <div class="panel" data-panel="leaderboard">
                    <button class="back-menu" type="button">‹ 返回菜单</button>
                    <h2>好友积分榜</h2>
                    <div class="leaderboard-banner">🏆 一起加油，天天进步</div>
                    <ul class="compact-list leaderboard-list" id="friend-leaderboard"></ul>
                  </div>
                  <div class="panel" data-panel="settings">
                    <button class="back-menu" type="button">‹ 返回菜单</button>
                    <h2>表盘设置</h2>
                    <div class="face-grid">
                      <button class="face-option" type="button" data-face="world"><span>我的世界</span><i class="face-swatch swatch-world"></i></button>
                      <button class="face-option" type="button" data-face="hellokitty"><span>HelloKitty</span><i class="face-swatch swatch-hellokitty"></i></button>
                      <button class="face-option" type="button" data-face="starlight"><span>星光梦可</span><i class="face-swatch swatch-starlight"></i></button>
                      <button class="face-option" type="button" data-face="dinosaur"><span>恐龙乐园</span><i class="face-swatch swatch-dinosaur"></i></button>
                      <button class="face-option" type="button" data-face="rainbow"><span>彩虹糖果</span><i class="face-swatch swatch-rainbow"></i></button>
                      <button class="face-option" type="button" data-face="space"><span>宇宙探险</span><i class="face-swatch swatch-space"></i></button>
                    </div>
                    <p id="settings-msg" class="msg"></p>
                  </div>
                  <div class="panel" data-panel="device">
                    <button class="back-menu" type="button">‹ 返回菜单</button>
                    <h2>设备绑定</h2>
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
                <button class="menu-toggle" id="menu-toggle" type="button" aria-label="打开功能菜单">菜单</button>
              </nav>
            </div>
          </main>
          <script>
            const form = document.getElementById('request-form');
            const msg = document.getElementById('msg');
            const bindForm = document.getElementById('bind-form');
            const bindMsg = document.getElementById('bind-msg');
            const tokenKey = 'happylife_watch_device_token';
            const previewChildId = new URLSearchParams(location.search).get('previewChildId') || '';
            const isPreview = /^\d+$/.test(previewChildId);
            const token = () => localStorage.getItem(tokenKey) || '';
            const authHeaders = () => ({ 'X-Watch-Device-Token': token() });
            const blockPreviewWrite = (target) => {
              if (!isPreview) return false;
              target.textContent = '虚拟手表仅供预览';
              return true;
            };
            const escapeText = (value) => String(value || '').replace(/[&<>"']/g, (ch) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
            const formatPoints = (value) => {
              const points = Number(value);
              return Number.isFinite(points)
                ? points.toLocaleString('zh-CN', { useGrouping: false, minimumFractionDigits: 0, maximumFractionDigits: 1 })
                : '0';
            };
            const faceLabels = { world: '我的世界', hellokitty: 'HelloKitty', starlight: '星光梦可', dinosaur: '恐龙乐园', rainbow: '彩虹糖果', space: '宇宙探险' };
            const ruleIcons = ['📚', '✏️', '🪥', '🧹', '🏃', '🤝', '⏰', '🌟'];
            const ruleIcon = (index) => ruleIcons[index % ruleIcons.length];
            const normalizeFace = (value) => ['world', 'hellokitty', 'starlight', 'dinosaur', 'rainbow', 'space'].includes(value) ? value : 'world';
            const applyWatchFace = (value) => {
              const face = normalizeFace(value);
              const watchFace = document.getElementById('watch-face');
              watchFace.classList.remove('face-world', 'face-hellokitty', 'face-starlight', 'face-dinosaur', 'face-rainbow', 'face-space');
              watchFace.classList.add('face-' + face);
              document.querySelectorAll('.face-option').forEach((button) => {
                button.classList.toggle('active', button.dataset.face === face);
              });
              return face;
            };
            const renderFriends = (payload = {}) => {
              const friends = payload.friends || [];
              const leaderboard = payload.leaderboard || [];
              document.getElementById('friends-list').innerHTML = friends.map((friend, index) => `
                <li><em>${index + 1}</em><span>${escapeText(friend.name)}</span><b>${formatPoints(friend.score)}</b></li>
              `).join('') || '<li class="empty-row"><span>暂无好友</span></li>';
              document.getElementById('friend-leaderboard').innerHTML = leaderboard.map((item) => `
                <li><em class="rank-icon">${['🏆', '🥈', '🥉'][Number(item.rank) - 1] || '⭐'}</em><span>${escapeText(item.name)}${item.isSelf ? ' · 我' : ''}</span><b>${formatPoints(item.score)}</b></li>
              `).join('') || '<li class="empty-row"><span>暂无排行</span></li>';
            };
            const calculatePanelScale = (availableWidth, availableHeight, contentWidth, contentHeight) =>
              Math.min(1, availableWidth / Math.max(1, contentWidth), availableHeight / Math.max(1, contentHeight));
            const fitActivePanel = () => requestAnimationFrame(() => {
              document.querySelectorAll('.screen:not(.hidden)').forEach((screen) => {
                const panel = screen.querySelector('.panel.active');
                if (!panel) return;
                panel.style.setProperty('--panel-scale', '1');
                if (!panel.matches('[data-panel="home"],[data-panel="menu"]')) return;
                const scale = calculatePanelScale(
                  Math.max(1, screen.clientWidth - 2),
                  Math.max(1, screen.clientHeight - 2),
                  Math.max(panel.offsetWidth, panel.scrollWidth),
                  Math.max(panel.offsetHeight, panel.scrollHeight)
                );
                panel.style.setProperty('--panel-scale', String(Math.max(.1, scale)));
              });
            });
            const showBound = (bound) => {
              document.getElementById('bind-panel').classList.toggle('hidden', bound);
              document.getElementById('app-panel').classList.toggle('hidden', !bound);
              document.getElementById('menu').classList.toggle('hidden', !bound || currentView !== 'home');
              fitActivePanel();
            };
            let currentView = 'home';
            const setView = (view, push = true) => {
              if (!document.querySelector(`[data-panel="${view}"]`)) view = 'home';
              currentView = view;
              document.querySelectorAll('[data-panel]').forEach((panel) => panel.classList.toggle('active', panel.dataset.panel === view));
              document.getElementById('menu').classList.toggle('hidden', view !== 'home');
              if (push && history.state?.watchView !== view) history.pushState({ watchView: view }, '', location.href);
              fitActivePanel();
            };
            const fetchJson = async (url, options = {}) => {
              const response = await fetch(url, options);
              const payload = await response.json().catch(() => ({}));
              if (!response.ok) throw new Error(payload.error || '请求失败');
              return payload;
            };
            const load = async () => {
              if (!isPreview && !token()) { showBound(false); return; }
              try {
                let score;
                let rulesPayload;
                let requestsPayload;
                let settingsPayload;
                let friendsPayload;
                if (isPreview) {
                  const previewPayload = await fetchJson('/api/watch/preview/' + encodeURIComponent(previewChildId));
                  score = previewPayload.score;
                  rulesPayload = previewPayload.rules;
                  requestsPayload = previewPayload.requests;
                  settingsPayload = previewPayload.settings;
                  friendsPayload = previewPayload.friends;
                } else {
                  [score, rulesPayload, requestsPayload, settingsPayload, friendsPayload] = await Promise.all([
                    fetchJson('/api/watch/score', { headers: authHeaders() }),
                    fetchJson('/api/watch/rules', { headers: authHeaders() }),
                    fetchJson('/api/watch/requests?limit=6', { headers: authHeaders() }),
                    fetchJson('/api/watch/settings', { headers: authHeaders() }),
                    fetchJson('/api/watch/friends', { headers: authHeaders() })
                  ]);
                }
                showBound(true);
                applyWatchFace(settingsPayload.watchFace);
                renderFriends(friendsPayload);
                const child = (score.children || [])[0] || {};
                document.getElementById('updated-at').textContent = new Date(score.updatedAt).toLocaleTimeString('zh-CN', { hour12: false, hour: '2-digit', minute: '2-digit' });
                document.getElementById('child-name').textContent = child.name || '暂无孩子';
                document.getElementById('score').textContent = formatPoints(child.points);
                document.getElementById('cash').textContent = child.cash ?? 0;
                document.getElementById('items').textContent = child.items ?? 0;
                document.getElementById('detail-score').textContent = formatPoints(child.points);
                document.getElementById('detail-cash').textContent = child.cash ?? 0;
                document.getElementById('detail-items').textContent = child.items ?? 0;
                document.getElementById('device-id').textContent = isPreview ? '虚拟预览' : '#' + escapeText(score.deviceId);
                document.getElementById('rules').innerHTML = (rulesPayload.rules || []).map((rule, index) => `
                  <button type="button" class="rule-btn" data-rule-id="${rule.id}" data-points="${rule.points}" data-title="${escapeText(rule.name)}">
                    <i class="rule-icon">${ruleIcon(index)}</i><span>${escapeText(rule.name)}</span><b>+${escapeText(rule.points)}</b>
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
                fitActivePanel();
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
              if (blockPreviewWrite(msg)) return;
              if (!document.getElementById('rule-id').value) {
                msg.textContent = '请先选择一项奖励规则';
                return;
              }
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
                setView('points-detail');
              } catch (error) {
                msg.textContent = error.message || '提交失败';
              }
            });
            document.getElementById('unbind').addEventListener('click', async () => {
              const unbindMsg = document.getElementById('unbind-msg');
              if (blockPreviewWrite(unbindMsg)) return;
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
            document.getElementById('make-friend-code').addEventListener('click', async () => {
              const friendMsg = document.getElementById('friend-msg');
              if (blockPreviewWrite(friendMsg)) return;
              friendMsg.textContent = '正在生成...';
              try {
                const payload = await fetchJson('/api/watch/friend-code', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', ...authHeaders() },
                  body: JSON.stringify({ expiresInMinutes: 30 })
                });
                document.getElementById('friend-code-box').classList.remove('hidden');
                document.getElementById('friend-code').textContent = payload.code;
                document.getElementById('friend-code-expire').textContent = '有效期至 ' + new Date(payload.expiresAt).toLocaleTimeString('zh-CN', { hour12: false, hour: '2-digit', minute: '2-digit' });
                friendMsg.textContent = '让对方手表输入此码';
                fitActivePanel();
              } catch (error) {
                friendMsg.textContent = error.message || '生成失败';
              }
            });
            document.getElementById('add-friend').addEventListener('click', async () => {
              const friendMsg = document.getElementById('friend-msg');
              if (blockPreviewWrite(friendMsg)) return;
              friendMsg.textContent = '正在添加...';
              try {
                const payload = await fetchJson('/api/watch/friends', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', ...authHeaders() },
                  body: JSON.stringify({ code: document.getElementById('friend-code-input').value })
                });
                document.getElementById('friend-code-input').value = '';
                renderFriends(payload);
                friendMsg.textContent = '已添加好友';
                fitActivePanel();
              } catch (error) {
                friendMsg.textContent = error.message || '添加失败';
              }
            });
            document.querySelectorAll('.face-option').forEach((button) => {
              button.addEventListener('click', async () => {
                const settingsMsg = document.getElementById('settings-msg');
                if (blockPreviewWrite(settingsMsg)) return;
                const face = normalizeFace(button.dataset.face || 'world');
                settingsMsg.textContent = '正在保存...';
                try {
                  const payload = await fetchJson('/api/watch/settings', {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json', ...authHeaders() },
                    body: JSON.stringify({ watchFace: face })
                  });
                  applyWatchFace(payload.watchFace);
                  settingsMsg.textContent = '已切换到 ' + faceLabels[normalizeFace(payload.watchFace)];
                } catch (error) {
                  settingsMsg.textContent = error.message || '保存失败';
                }
              });
            });
            document.querySelectorAll('.menu-card').forEach((button) => {
              button.addEventListener('click', () => setView(button.dataset.view || 'home'));
            });
            document.querySelectorAll('.back-menu').forEach((button) => {
              button.addEventListener('click', () => setView('menu'));
            });
            document.getElementById('home-menu').addEventListener('click', () => setView('home'));
            document.getElementById('menu-toggle').addEventListener('click', () => {
              setView('menu');
            });
            document.querySelectorAll('[data-speech-target]').forEach((button) => {
              button.addEventListener('click', () => {
                const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
                const target = document.getElementById(button.dataset.speechTarget || '');
                if (!SpeechRecognition || !target) {
                  msg.textContent = '当前手表不支持语音识别，请使用键盘输入';
                  return;
                }
                try {
                  const recognition = new SpeechRecognition();
                  recognition.lang = 'zh-CN';
                  recognition.interimResults = false;
                  recognition.maxAlternatives = 1;
                  recognition.onstart = () => {
                    button.classList.add('listening');
                    msg.textContent = '正在听，请说话...';
                  };
                  recognition.onresult = (event) => {
                    const text = event.results?.[0]?.[0]?.transcript || '';
                    target.value = target.value ? `${target.value}${text}` : text;
                    msg.textContent = text ? '语音已转成文字，请确认后提交' : '没有识别到内容';
                  };
                  recognition.onerror = () => { msg.textContent = '语音识别失败，请使用键盘输入'; };
                  recognition.onend = () => { button.classList.remove('listening'); };
                  recognition.start();
                } catch {
                  button.classList.remove('listening');
                  msg.textContent = '无法启动语音识别，请使用键盘输入';
                }
              });
            });
            history.replaceState({ watchView: 'home' }, '', location.href);
            window.addEventListener('popstate', (event) => {
              const next = event.state?.watchView || (currentView === 'home' ? 'home' : 'menu');
              setView(next, false);
            });
            window.addEventListener('resize', fitActivePanel);
            window.addEventListener('orientationchange', fitActivePanel);
            if (window.visualViewport) window.visualViewport.addEventListener('resize', fitActivePanel);
            if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitActivePanel);
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
    var familyGroupId = await ResolveInitialFamilyGroupIdForChild(connectionString, request, body, access.Profile!.AppUserId);
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
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    await using var cmd = new NpgsqlCommand("""
        SELECT c.profile_key
        FROM children c
        JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
        WHERE c.id = @id
          AND cub.parent_app_user_id = @parent_app_user_id
        LIMIT 1
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
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

    var updated = (await GetChildren(connectionString, ownerAppUserId: access.Profile!.AppUserId))
        .First(c => string.Equals(Convert.ToString(c["profileKey"], CultureInfo.InvariantCulture), profileKey, StringComparison.Ordinal));
    return Results.Json(updated);
});

app.MapDelete("/api/children/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var result = await DeleteChildMembership(connectionString, id, access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapPost("/api/children/{id:int}/auth-code", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveChildFamilyGroupId(connectionString, request, body, id, access.Profile!.AppUserId);
    var minutes = Math.Clamp(body.Int("expiresInMinutes") ?? 24 * 60, 10, 24 * 60);
    var result = await CreateChildAuthCode(connectionString, id, familyGroupId, access.Profile!.AppUserId, minutes);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapGet("/api/children/{id:int}/devices", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveChildFamilyGroupId(connectionString, request, null, id, access.Profile!.AppUserId);
    var result = await GetChildWatchDevices(connectionString, id, familyGroupId, access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapGet("/api/children/{id:int}/friends", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveChildFamilyGroupId(connectionString, request, null, id, access.Profile!.AppUserId);
    var child = await GetParentOwnedChild(connectionString, id, familyGroupId, access.Profile!.AppUserId);
    if (child is null) return Results.Json(new { error = "孩子不属于当前家长账号" }, statusCode: StatusCodes.Status403Forbidden);
    var profileKey = Convert.ToString(child["profileKey"], CultureInfo.InvariantCulture) ?? "";
    return Results.Json(new
    {
        child,
        friends = await GetChildFriends(connectionString, profileKey),
        leaderboard = await GetChildFriendLeaderboard(connectionString, profileKey)
    });
});

app.MapGet("/api/children/friend-notifications", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var unreadOnly = request.Query.Bool("unreadOnly") ?? request.Query.Bool("unread_only") ?? false;
    return Results.Json(new { notifications = await GetChildFriendNotifications(connectionString, access.Profile!.AppUserId, unreadOnly) });
});

app.MapPost("/api/children/friend-notifications/{id:int}/read", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var result = await MarkChildFriendNotificationRead(connectionString, id, access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapDelete("/api/children/{id:int}/devices/{deviceId:int}", async (int id, int deviceId, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveChildFamilyGroupId(connectionString, request, null, id, access.Profile!.AppUserId);
    var result = await RevokeChildWatchDevice(connectionString, id, deviceId, familyGroupId, access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapPost("/api/children/{id:int}/devices/{deviceId:int}/unbind-code", async (int id, int deviceId, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var familyGroupId = await ResolveChildFamilyGroupId(connectionString, request, body, id, access.Profile!.AppUserId);
    var minutes = Math.Clamp(body.Int("expiresInMinutes") ?? 10, 5, 30);
    var result = await CreateWatchDeviceUnbindCode(connectionString, id, deviceId, familyGroupId, access.Profile!.AppUserId, minutes);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapGet("/api/transactions", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var query = request.Query;
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

    var where = new List<string>
    {
        "cub.parent_app_user_id = @parent_app_user_id"
    };
    var parameters = new List<NpgsqlParameter>
    {
        new("parent_app_user_id", access.Profile!.AppUserId)
    };
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
        JOIN children c ON c.id = t.child_id
        JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
        WHERE {whereSql}
        """, conn);
    countCmd.Parameters.AddRange(parameters.Select(CloneParameter).ToArray());
    var total = Convert.ToInt32(await countCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);

    await using var cmd = new NpgsqlCommand($"""
        SELECT t.*, COALESCE(cp.name, c.name) AS child_name
        FROM transactions t
        JOIN children c ON c.id = t.child_id
        JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
        LEFT JOIN child_profiles cp ON cp.profile_key = c.profile_key
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
    var result = await CreateTransaction(connectionString, body, familyGroupId, access.Profile!.AppUserId);
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
        var result = await CreateTransaction(connectionString, node, familyGroupId, access.Profile!.AppUserId);
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
    var result = await DeleteTransaction(connectionString, id, parentAppUserId: access.Profile!.AppUserId);
    return result.ContainsKey("error") ? Results.NotFound(result) : Results.Json(result);
});

app.MapGet("/api/rules", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    return Results.Json(await GetRules(connectionString, access.Profile!.AppUserId));
});

app.MapPost("/api/rules", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var created = await CreatePersonalRule(connectionString, access.Profile!.AppUserId, body);
    return created.ContainsKey("error")
        ? Results.BadRequest(created)
        : Results.Created("/api/rules", created["rule"]);
});

app.MapPut("/api/rule-template", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var ruleIds = body["ruleIds"] is JsonArray array
        ? array.Select(node => node?.GetValue<int?>()).Where(id => id.HasValue).Select(id => id!.Value).Distinct().ToList()
        : new List<int>();
    var result = await SaveRuleTemplate(connectionString, access.Profile!.AppUserId, ruleIds);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPut("/api/rules/{id:int}", async (int id, JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE rules
        SET name = @name, category = @category, points = @points, cash_cny = @cash_cny, description = @description
        WHERE id = @id AND owner_app_user_id = @owner_app_user_id
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("owner_app_user_id", access.Profile!.AppUserId);
    cmd.Parameters.AddWithValue("name", body.String("name"));
    cmd.Parameters.AddWithValue("category", body.String("category"));
    cmd.Parameters.AddWithValue("points", NormalizeRulePoints(body));
    cmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash_cny") ?? 0);
    cmd.Parameters.AddWithValue("description", body.String("description"));
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return Results.NotFound(new { error = "规则不存在或无权修改公共规则" });
    }

    return Results.Json(ReadRule(reader));
});

app.MapDelete("/api/rules/{id:int}", async (int id, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM rules WHERE id = @id AND owner_app_user_id = @owner_app_user_id", conn);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("owner_app_user_id", access.Profile!.AppUserId);
    if (await cmd.ExecuteNonQueryAsync() == 0)
    {
        return Results.NotFound(new { error = "规则不存在或无权删除公共规则" });
    }
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

var configStore = new SystemConfigStore(connectionString, app.Environment.ContentRootPath);
await configStore.LoadAsync();

app.MapGet("/api/system/config", async (HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    return Results.Json(await configStore.LoadAsync());
});

app.MapPut("/api/system/config", async (JsonObject body, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    var saved = await configStore.SaveAsync(body);
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

    var config = await configStore.LoadAsync();
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

    var children = await GetChildren(connectionString, ownerAppUserId: access.Profile!.AppUserId);
    var rules = await GetRules(connectionString, access.Profile!.AppUserId);
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
    var config = await configStore.LoadAsync();
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
    if (string.IsNullOrWhiteSpace(prompt))
    {
        return Results.BadRequest(new { ok = false, error = "请输入对话内容" });
    }
    if (endpoint.EndsWith("/acp", StringComparison.OrdinalIgnoreCase))
    {
        var acpResult = await InvokeGoldfishAcp(
            httpClientFactory.CreateClient(),
            endpoint,
            agent.String("apiKey"),
            agent.String("profile", "happylife"),
            agent.String("workingDirectory", "/Users/wengzhishan/Projects/family-reward-system"),
            GetUnifiedUsername(request),
            prompt,
            agent.Int("timeout_seconds") ?? 90);
        return acpResult.Ok
            ? Results.Json(new { ok = true, response = new { output_text = acpResult.Text } })
            : Results.Json(new { ok = false, error = acpResult.Error }, statusCode: 502);
    }

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

app.MapGet("/api/agentfree/agents", async (IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        return Results.Json(await GetFamilyRewardAgentFreeAgents(httpClientFactory, GetUnifiedUsername(request), webAppBotId, request.HttpContext.RequestAborted));
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"获取家庭积分应用智能体失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapGet("/api/agentfree/sessions", async (IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        var agents = await GetFamilyRewardAgentFreeAgents(httpClientFactory, userName, webAppBotId, request.HttpContext.RequestAborted);
        var authorizedAgentIds = agents
            .OfType<JsonObject>()
            .Select(item => item.Int("id"))
            .Where(id => id.HasValue)
            .Select(id => id!.Value)
            .ToHashSet();
        var requestedAgentId = request.Query.Int("agentId");
        if (requestedAgentId.HasValue && !authorizedAgentIds.Contains(requestedAgentId.Value))
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        if (authorizedAgentIds.Count == 0) return Results.Json(new JsonArray());
        var sessions = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId).GetSessionsAsync(
            userName,
            gatewayType: "WebApp",
            agentId: requestedAgentId,
            limit: request.Query.Int("limit") is int requestedLimit ? Math.Clamp(requestedLimit, 1, 500) : null,
            cancellationToken: request.HttpContext.RequestAborted);
        var familySessions = FilterFamilyRewardAgentFreeSessions(sessions, authorizedAgentIds);
        return Results.Json(await FilterReadableFamilyRewardAgentFreeSessions(
            httpClientFactory,
            familySessions,
            userName,
            request.HttpContext.RequestAborted));
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"获取智能体会话失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapGet("/api/agentfree/sessions/{id}", async (string id, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        var agentId = await ResolveFamilyRewardAgentFreeAgentIdForBot(httpClientFactory, userName, webAppBotId, request.HttpContext.RequestAborted);
        var session = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId)
            .GetSessionAsync(id, userName, request.HttpContext.RequestAborted);
        if (agentId is null || session?.AgentId != agentId)
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        return Results.Json(session);
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"获取智能体会话失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapGet("/api/agentfree/sessions/{id}/messages", async (string id, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        if (await GetFamilyRewardAgentFreeSessionForBot(httpClientFactory, id, userName, webAppBotId, request.HttpContext.RequestAborted) is null)
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        var messages = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId).GetSessionMessagesAsync(
            id,
            userName,
            new OrbitWebAppMessageQuery
            {
                Take = request.Query.Int("take"),
                BeforeId = long.TryParse(request.Query.String("beforeId"), out var beforeId) ? beforeId : null,
                Ids = request.Query.String("ids")
            },
            request.HttpContext.RequestAborted);
        return Results.Json(messages);
    }
    catch (Exception ex)
    {
        if (IsAgentFreeAccessDenied(ex)) return Results.Json(new JsonArray());
        return Results.Json(new { error = $"获取智能体消息失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapGet("/api/agentfree/sessions/{id}/timeline", async (string id, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        if (await GetFamilyRewardAgentFreeSessionForBot(httpClientFactory, id, userName, webAppBotId, request.HttpContext.RequestAborted) is null)
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        var timeline = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId).GetSessionTimelineAsync(
            id, userName, request.QueryString.Value, request.HttpContext.RequestAborted);
        return Results.Json(timeline ?? new JsonArray());
    }
    catch (Exception ex)
    {
        if (IsAgentFreeAccessDenied(ex)) return Results.Json(new JsonArray());
        return Results.Json(new { error = $"获取智能体会话过程失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapGet("/api/agentfree/sessions/{id}/queue", async (string id, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        if (await GetFamilyRewardAgentFreeSessionForBot(httpClientFactory, id, userName, webAppBotId, request.HttpContext.RequestAborted) is null)
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        var queue = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId)
            .GetSessionQueueAsync(id, userName, request.HttpContext.RequestAborted);
        return Results.Json(queue ?? new JsonObject { ["items"] = new JsonArray(), ["waitingCount"] = 0 });
    }
    catch (Exception ex)
    {
        if (IsAgentFreeAccessDenied(ex)) return Results.Json(new JsonObject { ["items"] = new JsonArray(), ["waitingCount"] = 0 });
        return Results.Json(new { error = $"获取智能体会话队列失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapPost("/api/agentfree/sessions", async (JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, body.String("webAppBotId"));
        var agentId = await ResolveFamilyRewardAgentFreeAgentIdForBot(httpClientFactory, userName, webAppBotId, request.HttpContext.RequestAborted);
        if (agentId is null)
        {
            return Results.Json(new { error = "未找到家庭积分应用智能体" }, statusCode: StatusCodes.Status502BadGateway);
        }
        var session = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId).CreateSessionAsync(
            new CreateOrbitWebAppSessionRequest
            {
                AgentId = agentId.Value,
                Name = string.IsNullOrWhiteSpace(body.String("name")) ? "家庭积分会话" : body.String("name").Trim(),
                WebAppBotId = webAppBotId
            },
            userName,
            request.HttpContext.RequestAborted);
        return Results.Json(session);
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"创建智能体会话失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapPut("/api/agentfree/sessions/{id}", async (string id, JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        if (await GetFamilyRewardAgentFreeSessionForBot(httpClientFactory, id, userName, webAppBotId, request.HttpContext.RequestAborted) is null)
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        await CreateOrbitWebAppClient(httpClientFactory, webAppBotId).UpdateSessionAsync(
            id,
            new UpdateOrbitWebAppSessionRequest
            {
                Name = body.String("name"),
                IsArchived = body["isArchived"]?.GetValue<bool?>()
            },
            userName,
            request.HttpContext.RequestAborted);
        return Results.Json(new { id });
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"更新智能体会话失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapPost("/api/agentfree/chat/sessions/{id}/reset", async (string id, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var userName = GetUnifiedUsername(request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, request.Query.String("webAppBotId"));
        if (await GetFamilyRewardAgentFreeSessionForBot(httpClientFactory, id, userName, webAppBotId, request.HttpContext.RequestAborted) is null)
        {
            return Results.Json(new { error = "无权访问该智能体会话" }, statusCode: StatusCodes.Status403Forbidden);
        }
        var result = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId)
            .ResetSessionContextAsync(id, userName, request.HttpContext.RequestAborted);
        return Results.Json(result ?? new JsonObject { ["id"] = id });
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"重置智能体会话失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapPost("/api/agentfree/interactions/{interactionId}/respond", async (string interactionId, JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
    var access = await RequireParentProfile(connectionString, request);
    if (access.Error is not null) return access.Error;
    try
    {
        var result = await CreateOrbitWebAppClient(httpClientFactory)
            .RespondInteractionAsync(interactionId, body, GetUnifiedUsername(request), request.HttpContext.RequestAborted);
        return Results.Json(result ?? new JsonObject { ["interactionId"] = interactionId });
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = $"提交智能体交互结果失败: {ex.Message}" }, statusCode: StatusCodes.Status502BadGateway);
    }
});

app.MapPost("/api/agentfree/chat/stream", async (JsonObject body, IHttpClientFactory httpClientFactory, HttpContext context) =>
{
    var access = await RequireParentProfile(connectionString, context.Request);
    if (access.Error is not null)
    {
        await access.Error.ExecuteAsync(context);
        return;
    }
    var message = body.String("message").Trim();
    if (string.IsNullOrWhiteSpace(message))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsJsonAsync(new { error = "消息不能为空" }, context.RequestAborted);
        return;
    }

    try
    {
        var userName = GetUnifiedUsername(context.Request);
        var config = await configStore.LoadAsync();
        var webAppBotId = ResolveFamilyRewardWebAppBotId(config, body.String("webAppBotId"));
        var agentId = await ResolveFamilyRewardAgentFreeAgentIdForBot(httpClientFactory, userName, webAppBotId, context.RequestAborted);
        if (agentId is null)
        {
            context.Response.StatusCode = StatusCodes.Status502BadGateway;
            await context.Response.WriteAsJsonAsync(new { error = "未找到家庭积分应用智能体" }, context.RequestAborted);
            return;
        }
        var sessionId = body.String("sessionId").Trim();
        if (string.IsNullOrWhiteSpace(sessionId)
                || await GetFamilyRewardAgentFreeSessionForBot(httpClientFactory, sessionId, userName, webAppBotId, context.RequestAborted) is null)
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsJsonAsync(new { error = "无权访问该智能体会话" }, context.RequestAborted);
            return;
        }
        var displayName = FirstClaim(context.Request, "name", ClaimTypes.Name) ?? userName;
        var payload = new JsonObject
        {
            ["sessionId"] = sessionId,
            ["agentId"] = agentId.Value,
            ["AgentId"] = agentId.Value,
            ["name"] = message.Length > 24 ? message[..24] : message,
            ["content"] = message,
            ["attachments"] = body["attachments"]?.DeepClone() ?? new JsonArray(),
            ["user"] = new JsonObject
            {
                ["username"] = userName,
                ["displayName"] = displayName,
                ["role"] = "parent"
            },
            ["metadata"] = new JsonObject
            {
                ["source"] = "family-reward-web",
                ["gatewayType"] = "WebApp",
                ["channelType"] = "WebApp",
                ["webAppBotId"] = webAppBotId,
                ["agentId"] = agentId.Value,
                ["username"] = userName
            },
            ["gatewayContext"] = new JsonObject
            {
                ["GatewayType"] = "WebApp",
                ["GatewayBotId"] = webAppBotId,
                ["GatewayMetadata_transport"] = webAppBotId,
                ["GatewayMetadata_source"] = "family-reward-web",
                ["GatewayMetadata_webAppBotId"] = webAppBotId,
                ["GatewayMetadata_username"] = userName
            }
        };
        if (body["enableThinking"] is not null) payload["enableThinking"] = body["enableThinking"]!.DeepClone();
        if (body["messageMode"] is not null) payload["messageMode"] = body["messageMode"]!.DeepClone();
        using var upstreamResult = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId)
            .OpenChatStreamAsync(payload, userName, context.RequestAborted);
        var upstream = upstreamResult.Response;
        if (!upstream.IsSuccessStatusCode)
        {
            var error = await upstream.Content.ReadAsStringAsync(context.RequestAborted);
            context.Response.StatusCode = (int)upstream.StatusCode;
            context.Response.ContentType = upstream.Content.Headers.ContentType?.ToString() ?? "application/json; charset=utf-8";
            await context.Response.WriteAsync(error, context.RequestAborted);
            return;
        }

        context.Response.ContentType = upstream.Content.Headers.ContentType?.ToString() ?? "text/event-stream; charset=utf-8";
        context.Response.Headers.CacheControl = "no-cache";
        context.Response.Headers.Connection = "keep-alive";
        context.Response.Headers["X-Accel-Buffering"] = "no";
        await using var stream = await upstream.Content.ReadAsStreamAsync(context.RequestAborted);
        await stream.CopyToAsync(context.Response.Body, context.RequestAborted);
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
    {
    }
    catch (Exception ex)
    {
        if (!context.Response.HasStarted)
        {
            context.Response.StatusCode = StatusCodes.Status502BadGateway;
            await context.Response.WriteAsJsonAsync(new { error = $"智能体服务响应失败: {ex.Message}" }, context.RequestAborted);
        }
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
                    version = "3.2.0"
                },
                instructions = $"Use tools/list and tools/call with separated tools for children, score/accounts, records/transactions, rules, and family groups. {FamilyRewardMcpGroundingInstructions}"
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

static string ResolveFamilyRewardWebAppBotId(JsonObject config, string? requestedBotId)
{
    if (!string.IsNullOrWhiteSpace(requestedBotId)) return requestedBotId.Trim();
    var configured = config["agent"]?.AsObject().String("webAppBotId");
    if (string.IsNullOrWhiteSpace(configured)) throw new InvalidOperationException("未配置家庭积分 WEBAP 通道入口标识");
    return configured.Trim();
}

static OrbitWebAppClient CreateOrbitWebAppClient(IHttpClientFactory httpClientFactory, string webAppBotId = "")
{
    var client = httpClientFactory.CreateClient();
    client.Timeout = TimeSpan.FromMinutes(10);
    return new OrbitWebAppClient(client, new OrbitWebAppOptions
    {
        ApplicationId = "family-reward",
        WebAppBotId = webAppBotId,
        BaseAddress = new Uri(AgentFreeGatewayConfiguration.BaseUrl.TrimEnd('/'))
    });
}

static async Task<JsonArray> GetFamilyRewardAgentFreeAgents(
    IHttpClientFactory httpClientFactory,
    string userName,
    string webAppBotId,
    CancellationToken cancellationToken)
{
    var agents = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId)
        .GetAuthorizedAgentsAsync(userName, cancellationToken);
    var result = new JsonArray();
    if (agents is null) return result;
    foreach (var item in agents.OfType<JsonObject>())
    {
        var active = string.Equals(item.String("status"), "Active", StringComparison.OrdinalIgnoreCase);
        // AgentFree 已经通过 authorizedOnly、gatewayType 和 webAppBotId
        // 按当前用户的实际授权及 WEBAP 路由完成筛选。这里不能再按名称或
        // agentCode 限制，否则像“WEBAP家加分”这样的合法实例会被误过滤。
        if (active) result.Add(item.DeepClone());
    }
    return result;
}

static async Task<int?> ResolveFamilyRewardAgentFreeAgentIdForBot(
    IHttpClientFactory httpClientFactory,
    string userName,
    string webAppBotId,
    CancellationToken cancellationToken)
{
    var agents = await GetFamilyRewardAgentFreeAgents(httpClientFactory, userName, webAppBotId, cancellationToken);
    return agents.OfType<JsonObject>().Select(item => item.Int("id")).FirstOrDefault(id => id.HasValue);
}

static async Task<OrbitWebAppSession?> GetFamilyRewardAgentFreeSessionForBot(
    IHttpClientFactory httpClientFactory,
    string sessionId,
    string userName,
    string webAppBotId,
    CancellationToken cancellationToken)
{
    var agents = await GetFamilyRewardAgentFreeAgents(httpClientFactory, userName, webAppBotId, cancellationToken);
    var authorizedAgentIds = agents
        .OfType<JsonObject>()
        .Select(item => item.Int("id"))
        .Where(id => id.HasValue)
        .Select(id => id!.Value)
        .ToHashSet();
    if (authorizedAgentIds.Count == 0) return null;
    var session = await CreateOrbitWebAppClient(httpClientFactory, webAppBotId)
        .GetSessionAsync(sessionId, userName, cancellationToken);
    return session is not null && authorizedAgentIds.Contains(session.AgentId) ? session : null;
}

static List<OrbitWebAppSession> FilterFamilyRewardAgentFreeSessions(
    IEnumerable<OrbitWebAppSession> sessions,
    IReadOnlySet<int> authorizedAgentIds)
{
    return sessions
        .Where(session => authorizedAgentIds.Contains(session.AgentId) && !session.IsArchived)
        .ToList();
}

static async Task<List<OrbitWebAppSession>> FilterReadableFamilyRewardAgentFreeSessions(
    IHttpClientFactory httpClientFactory,
    IEnumerable<OrbitWebAppSession> sessions,
    string userName,
    CancellationToken cancellationToken)
{
    var result = new List<OrbitWebAppSession>();
    foreach (var item in sessions)
    {
        var sessionId = item.Id;
        if (string.IsNullOrWhiteSpace(sessionId)) continue;
        try
        {
            var session = await CreateOrbitWebAppClient(httpClientFactory)
                .GetSessionAsync(sessionId, userName, cancellationToken);
            if (session?.AgentId == item.AgentId && !session.IsArchived) result.Add(item);
        }
        catch (Exception ex) when (IsAgentFreeAccessDenied(ex))
        {
        }
    }
    return result;
}

static bool IsAgentFreeAccessDenied(Exception ex) =>
    ex.Message.Contains("无权限", StringComparison.OrdinalIgnoreCase)
    || ex.Message.Contains("Forbidden", StringComparison.OrdinalIgnoreCase)
    || ex.Message.Contains("403", StringComparison.OrdinalIgnoreCase);

static async Task<(bool Ok, string Text, string Error)> InvokeGoldfishAcp(
    HttpClient client,
    string endpoint,
    string apiKey,
    string profile,
    string workingDirectory,
    string username,
    string prompt,
    int timeoutSeconds,
    Func<string, CancellationToken, Task>? onDelta = null,
    CancellationToken cancellationToken = default)
{
    client.Timeout = Timeout.InfiniteTimeSpan;
    using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
    timeoutCts.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(timeoutSeconds, 20, 180)));
    var operationToken = timeoutCts.Token;
    var sessionId = $"happylife-web-{Guid.NewGuid():N}";
    var createPayload = new JsonObject
    {
        ["jsonrpc"] = "2.0",
        ["id"] = 1,
        ["method"] = "session/new",
        ["params"] = new JsonObject
        {
            ["cwd"] = workingDirectory,
            ["mcpServers"] = new JsonArray(),
            ["_meta"] = new JsonObject
            {
                ["agentfree"] = new JsonObject { ["requestedSessionId"] = sessionId }
            }
        }
    };

    try
    {
        using (var createRequest = CreateAgentRequest(endpoint, apiKey, createPayload))
        using (var createResponse = await client.SendAsync(createRequest, operationToken))
        {
            var createText = await createResponse.Content.ReadAsStringAsync(operationToken);
            if (!createResponse.IsSuccessStatusCode)
            {
                return (false, "", $"智能体会话创建失败（{(int)createResponse.StatusCode}）");
            }
            var createJson = JsonNode.Parse(createText) as JsonObject;
            var createdSessionId = createJson?["result"]?["sessionId"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(createdSessionId)) return (false, "", "智能体未返回有效会话");
            sessionId = createdSessionId;
        }

        var contextualPrompt = $"当前登录用户的用户中心用户名：{username}。调用 MCP 工具时必须传 username，不能传或推断内部用户编号。\n\n{prompt}";
        var promptPayload = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 2,
            ["method"] = "session/prompt",
            ["params"] = new JsonObject
            {
                ["sessionId"] = sessionId,
                ["prompt"] = new JsonArray
                {
                    new JsonObject { ["type"] = "text", ["text"] = contextualPrompt }
                },
                ["_meta"] = new JsonObject
                {
                    ["agentfree"] = new JsonObject
                    {
                        ["agent_type"] = "Goldfish",
                        ["Profile"] = profile,
                        ["username"] = username
                    }
                }
            }
        };
        using var promptRequest = CreateAgentRequest(endpoint, apiKey, promptPayload);
        using var promptResponse = await client.SendAsync(promptRequest, HttpCompletionOption.ResponseHeadersRead, operationToken);
        if (!promptResponse.IsSuccessStatusCode)
        {
            return (false, "", $"智能体调用失败（{(int)promptResponse.StatusCode}）");
        }

        var answer = new StringBuilder();
        var stopReason = "";
        await using var stream = await promptResponse.Content.ReadAsStreamAsync(operationToken);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        while (await reader.ReadLineAsync(operationToken) is { } line)
        {
            if (!line.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) continue;
            JsonObject? frame = null;
            try { frame = JsonNode.Parse(line[5..].Trim()) as JsonObject; } catch { }
            if (frame is null) continue;
            var update = frame["params"]?["update"] as JsonObject;
            if (string.Equals(update?.String("sessionUpdate"), "agent_message_chunk", StringComparison.OrdinalIgnoreCase))
            {
                var delta = update?["content"]?["text"]?.GetValue<string>() ?? "";
                answer.Append(delta);
                if (!string.IsNullOrEmpty(delta) && onDelta is not null)
                {
                    await onDelta(delta, operationToken);
                }
            }
            stopReason = frame["result"]?["stopReason"]?.GetValue<string>() ?? stopReason;
        }

        var text = answer.ToString().Trim();
        if (!string.Equals(stopReason, "end_turn", StringComparison.OrdinalIgnoreCase))
        {
            return (false, "", string.IsNullOrWhiteSpace(text) ? "智能体未正常完成本次对话" : text);
        }
        return string.IsNullOrWhiteSpace(text)
            ? (false, "", "智能体没有返回内容")
            : (true, text, "");
    }
    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
    {
        return (false, "", "智能体响应超时，请稍后重试");
    }
    catch (OperationCanceledException)
    {
        return (false, "", "智能体对话已取消");
    }
    catch (Exception ex)
    {
        return (false, "", $"智能体服务异常：{ex.Message}");
    }
}

static HttpRequestMessage CreateAgentRequest(string endpoint, string apiKey, JsonObject payload)
{
    var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
    {
        Content = new StringContent(payload.ToJsonString(FamilyRewardJson.CreateOptions()), Encoding.UTF8, "application/json")
    };
    if (!string.IsNullOrWhiteSpace(apiKey))
    {
        request.Headers.Authorization = AuthenticationHeaderValue.Parse(
            apiKey.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? apiKey : $"Bearer {apiKey}");
    }
    return request;
}

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
        ["requiredPermissions"] = new JsonArray { "INTERNET", "ACCESS_NETWORK_STATE", "RECORD_AUDIO" },
        ["privacyPolicyUrl"] = $"{baseUrl}/legal/privacy.html",
        ["termsUrl"] = $"{baseUrl}/legal/terms.html",
        ["privacy"] = new JsonObject
        {
            ["collectsPreciseLocation"] = false,
            ["collectsContacts"] = false,
            ["usesMicrophoneOnDemand"] = true,
            ["storesRawAudio"] = false,
            ["microphonePurpose"] = "仅在用户主动点击语音输入时将申请事项转换为文字，可拒绝并改用键盘输入",
            ["collectsCamera"] = false,
            ["childAccountOnly"] = true
        },
        ["releaseReadiness"] = new JsonObject
        {
            ["webEntry"] = "ready",
            ["androidWrapper"] = "ready_for_sdk_build",
            ["storeListingAssets"] = "prepared",
            ["blockedBy"] = "小天才准入、软著、APP备案、法人证件、公司签章和物理真机验收"
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
            version = "3.2.0",
            title = "家加分 MCP 业务工具服务",
            description = "提供家庭成员、孩子、圈子、积分记录、规则、设备、好友、申请审批和圈子统计工具；家庭是当前家长自己的成员清单，圈子是多个家庭协作共享孩子积分的空间。"
        },
        endpoint = "/api/mcp",
        protocols = new[] { "initialize", "initialized", "notifications/initialized", "ping", "tools/list", "tools/call" },
        tools = BuildMcpToolCatalog()
    };
}

static object BuildMcpToolCatalog()
{
    var tools = new object[]
    {
            new
            {
                name = FamilyRewardMcpAddChildToolName,
                description = "家庭管理/新增孩子：为当前家长创建全局孩子档案并建立所属关系，可设置初始积分、现金和物品。新孩子会同步进入该家长已创建或加入的圈子；family_group_id 只用于指定初始圈子且必须是当前家长可访问的圈子。",
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
                        family_group_id = new { type = "integer", description = "圈子ID；不传则使用默认圈子" },
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
                description = "家庭管理/修改孩子：仅允许修改当前家长名下孩子的姓名、备注、状态和账户余额；加入同一圈子的其他家庭只能查看，不能修改。按 child_id 或 child_name 定位，至少更新一个字段。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
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
                description = "查询孩子：不传 family_group_id 时只返回当前家长名下孩子；传 family_group_id 时先校验当前家长已创建或加入该圈子，再返回圈子内全部孩子（包括其他家庭的孩子，只读）。可用 child_id 或 child_name 定位单个孩子。未命中时必须调用 family_reward_list_children 在相同范围内复核完整清单。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；可选。只传此字段时返回该圈子全部孩子" },
                        child_id = new { type = "integer", description = "孩子ID（可选）。未找到时不要直接结束，应再查完整孩子清单进行对比" },
                        child_name = new { type = "string", description = "孩子姓名（可选）。未找到时不要直接结束，应再查完整孩子清单进行对比" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpListChildrenToolName,
                description = "列出孩子清单：不传 family_group_id 时只列出当前家长名下有效孩子；传入时仅在当前家长可访问的指定圈子中列出全部有效孩子。该工具是清单查询，不接受 child_id 或 child_name。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；可选。只传此字段时返回该圈子全部孩子" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteChildToolName,
                description = "家庭管理/删除孩子所属关系：仅允许当前家长删除自己名下的孩子；不会因为圈子成员身份获得删除权。删除最后一个所属关系时才清理该孩子全局档案及相关数据。按 child_id 或 child_name 定位。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（用于定位）" },
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpAdjustScoreToolName,
                description = "调整积分：仅允许给当前家长名下孩子加分或减分；即使可以在圈子中查看其他家庭孩子积分，也不能修改。delta 正数加分、负数减分。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
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
                name = FamilyRewardMcpApplyMatchingRuleToolName,
                description = "按当前生效规则自动加减积分：处理“玥玥今天帮助妹妹，请加分”这类自然语言记分请求。服务端会校验孩子属于当前家长，匹配该家长当前生效规则模板，并在一次事务中写入积分明细和更新余额。不得只查询规则、猜测分值或仅回复说明；无法唯一匹配时不会写入。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；仅用于缩小孩子姓名定位范围" },
                        child_id = new { type = "integer", description = "孩子ID（与 child_name 二选一）" },
                        child_name = new { type = "string", description = "孩子姓名（与 child_id 二选一）" },
                        behavior = new { type = "string", description = "孩子完成的自然语言行为，例如：今天帮助妹妹" },
                        date = new { type = "string", description = "交易日期，格式 YYYY-MM-DD（默认今天）" },
                        request_id = new { type = "string", description = "本次用户消息的稳定请求号；流式重试时复用同一值，避免重复入账" },
                        notes = new { type = "string", description = "可选备注" }
                    },
                    required = new[] { "behavior" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryScoreToolName,
                description = "查询积分余额：不传 family_group_id 时仅查询当前家长名下孩子；传 family_group_id 时先校验圈子成员身份，再查询该圈子全部孩子余额。圈子成员可以看余额，但只有孩子所属家长可以通过 include_transactions 查看该孩子明细。未命中时必须在相同范围调用 family_reward_list_children 复核。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；可选。只传此字段时返回该圈子全部孩子的积分清单" },
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
                description = "写入积分明细并同步余额：仅允许操作当前家长名下孩子；圈子可见但不属于当前家长的孩子不可写。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
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
                description = "新增账户记录：仅允许为当前家长名下孩子新增积分、现金或物品记录，并同步更新全局孩子账户。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
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
                description = "修改账户记录：仅允许修改当前家长名下孩子的记录；按记录ID回滚旧影响后应用新记录，圈子成员身份不授予修改权。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        transaction_id = new { type = "integer", description = "记录ID" },
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
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
                description = "删除账户记录：仅允许删除当前家长名下孩子的记录，并自动回滚该记录对账户的影响。",
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
                description = "查询积分明细：仅查询当前家长名下孩子的积分交易，不因加入圈子而开放其他家庭孩子的行为明细。支持按孩子、日期、分类和分页筛选；未命中时在当前家长名下孩子范围复核。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID；用于缩小孩子姓名定位范围" },
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
                description = "查询规则：返回公共规则、当前家长自己的个人规则和当前生效模板。其他家长的个人规则不可见。",
                inputSchema = new
                {
                    type = "object",
                    properties = new { }
                }
            },
            new
            {
                name = FamilyRewardMcpCreateRuleToolName,
                description = "为指定家长新增个人积分规则，并自动加入该家长的个人规则模板。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        name = new { type = "string", description = "规则名称" },
                        category = new { type = "string", description = "分类" },
                        points = new { type = "number", description = "积分绝对值；reward为加分，redline为减分" },
                        rule_type = new { type = "string", @enum = new[] { "reward", "redline" }, description = "规则类型：奖励或红线" },
                        cash_cny = new { type = "number", description = "现金" },
                        description = new { type = "string", description = "描述" }
                    },
                    required = new[] { "name" }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateRuleToolName,
                description = "修改指定家长自己的个人积分规则；公共规则不可修改。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        rule_id = new { type = "integer", description = "规则ID" },
                        name = new { type = "string", description = "规则名称" },
                        category = new { type = "string", description = "分类" },
                        points = new { type = "number", description = "积分绝对值；reward为加分，redline为减分" },
                        rule_type = new { type = "string", @enum = new[] { "reward", "redline" }, description = "规则类型：奖励或红线" },
                        cash_cny = new { type = "number", description = "现金" },
                        description = new { type = "string", description = "描述" }
                    },
                    required = new[] { "rule_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteRuleToolName,
                description = "删除指定家长自己的个人积分规则；公共规则不可删除。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        rule_id = new { type = "integer", description = "规则ID" }
                    },
                    required = new[] { "rule_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryFamilyGroupsToolName,
                description = "圈子管理/查询圈子：只返回当前家长创建或已经加入的圈子，并标明 owner/member 角色。圈子是多个家庭协作查看孩子积分的空间，不等同于当前家长自己的家庭成员清单。",
                inputSchema = new
                {
                    type = "object",
                    properties = new { }
                }
            },
            new
            {
                name = FamilyRewardMcpCreateFamilyGroupToolName,
                description = "圈子管理/新增圈子：当前家长成为圈子管理员，并自动把自己名下有效孩子同步到新圈子。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        name = new { type = "string", description = "圈子名称" },
                        description = new { type = "string", description = "描述" }
                    },
                    required = new[] { "name" }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateFamilyGroupToolName,
                description = "圈子管理/修改圈子：仅圈子创建者或 owner 管理员可修改圈子名称和说明；普通圈子成员只能查看。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID" },
                        name = new { type = "string", description = "新的圈子名称" },
                        description = new { type = "string", description = "新的圈子说明" }
                    },
                    required = new[] { "family_group_id", "name" }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteFamilyGroupToolName,
                description = "圈子管理/删除圈子：仅圈子创建者或 owner 管理员可删除。删除圈子不会删除孩子全局档案和所属家庭关系。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID" }
                    },
                    required = new[] { "family_group_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpGetFamilyGroupInviteToolName,
                description = "圈子管理/获取邀请码：仅圈子创建者或 owner 管理员可生成或查看 8 位圈子邀请码。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID" }
                    },
                    required = new[] { "family_group_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpJoinFamilyGroupToolName,
                description = "圈子管理/加入圈子：当前家长使用 8 位邀请码加入圈子，并自动把自己名下有效孩子同步到该圈子。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        invite_code = new { type = "string", description = "8 位数字圈子邀请码" }
                    },
                    required = new[] { "invite_code" }
                }
            },
            new
            {
                name = FamilyRewardMcpRemoveFamilyGroupChildToolName,
                description = "圈子管理/移除孩子：仅圈子创建者或 owner 管理员可把孩子从该圈子移除；不会删除孩子的家庭所属关系或全局积分账户。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID" },
                        child_id = new { type = "integer", description = "该圈子中的孩子ID" }
                    },
                    required = new[] { "family_group_id", "child_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryFamilyMembersToolName,
                description = "家庭管理/查询家庭成员：只返回当前家长自己的家庭成员清单，包括当前用户以及爸爸、妈妈、爷爷、奶奶等成员；家庭成员不随圈子切换而改变。",
                inputSchema = new { type = "object", properties = new { } }
            },
            new
            {
                name = FamilyRewardMcpCreateFamilyMemberToolName,
                description = "家庭管理/新增家庭成员：只在当前家长自己的家庭清单中新增成员，不会把该成员加入任何圈子。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        display_name = new { type = "string", description = "家庭成员姓名，最多 50 个字符" },
                        role = new { type = "string", @enum = new[] { "father", "mother", "grandfather", "grandmother", "maternal_grandfather", "maternal_grandmother", "guardian", "other" }, description = "家庭角色" },
                        note = new { type = "string", description = "备注" }
                    },
                    required = new[] { "display_name", "role" }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateFamilyMemberToolName,
                description = "家庭管理/修改家庭成员：仅允许修改当前家长自己的家庭成员；可修改当前用户角色，但不能改变成员所属家庭。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        member_id = new { type = "integer", description = "家庭成员ID" },
                        display_name = new { type = "string", description = "家庭成员姓名，最多 50 个字符" },
                        role = new { type = "string", @enum = new[] { "father", "mother", "grandfather", "grandmother", "maternal_grandfather", "maternal_grandmother", "guardian", "other" }, description = "家庭角色" },
                        note = new { type = "string", description = "备注" }
                    },
                    required = new[] { "member_id", "display_name", "role" }
                }
            },
            new
            {
                name = FamilyRewardMcpDeleteFamilyMemberToolName,
                description = "家庭管理/删除家庭成员：仅允许删除当前家长自己的非当前用户成员；当前用户不能从自己的家庭清单删除。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        member_id = new { type = "integer", description = "家庭成员ID" }
                    },
                    required = new[] { "member_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpUpdateRuleTemplateToolName,
                description = "规则管理/更新规则模板：为当前家长保存有序规则ID清单；只能选择公共规则或当前家长自己的个人规则，顺序用于手表端展示。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        rule_ids = new { type = "array", items = new { type = "integer" }, description = "按展示顺序排列的规则ID数组，可为空数组" }
                    },
                    required = new[] { "rule_ids" }
                }
            },
            new
            {
                name = FamilyRewardMcpGenerateChildAuthCodeToolName,
                description = "家庭管理/生成儿童认证码：仅孩子所属家长可为自己名下孩子生成手表绑定认证码。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（与 child_id 二选一）" },
                        family_group_id = new { type = "integer", description = "孩子所在圈子ID，可选" },
                        expires_in_minutes = new { type = "integer", description = "有效分钟数，10 到 1440，默认 1440" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryChildDevicesToolName,
                description = "家庭管理/查询孩子手表设备：仅孩子所属家长可查看自己名下孩子的设备绑定。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（与 child_id 二选一）" },
                        family_group_id = new { type = "integer", description = "孩子所在圈子ID，可选" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpRevokeChildDeviceToolName,
                description = "家庭管理/解绑孩子手表：仅孩子所属家长可撤销自己名下孩子的指定设备绑定。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（与 child_id 二选一）" },
                        family_group_id = new { type = "integer", description = "孩子所在圈子ID，可选" },
                        device_id = new { type = "integer", description = "设备绑定ID" }
                    },
                    required = new[] { "device_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpGenerateDeviceUnbindCodeToolName,
                description = "家庭管理/生成设备解绑码：仅孩子所属家长可为自己名下孩子的指定设备生成短期解绑码。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（与 child_id 二选一）" },
                        family_group_id = new { type = "integer", description = "孩子所在圈子ID，可选" },
                        device_id = new { type = "integer", description = "设备绑定ID" },
                        expires_in_minutes = new { type = "integer", description = "有效分钟数，5 到 30，默认 10" }
                    },
                    required = new[] { "device_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryChildFriendsToolName,
                description = "家庭管理/查询孩子好友：仅孩子所属家长可查看自己名下孩子的好友列表和好友积分榜。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        child_id = new { type = "integer", description = "孩子ID" },
                        child_name = new { type = "string", description = "孩子姓名（与 child_id 二选一）" },
                        family_group_id = new { type = "integer", description = "孩子所在圈子ID，可选" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryFriendNotificationsToolName,
                description = "家庭管理/查询好友通知：只返回当前家长名下孩子收到的好友关系通知。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        unread_only = new { type = "boolean", description = "是否只返回未读通知，默认 false" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpMarkFriendNotificationReadToolName,
                description = "家庭管理/标记好友通知已读：仅允许处理当前家长名下孩子的通知。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        notification_id = new { type = "integer", description = "好友通知ID" }
                    },
                    required = new[] { "notification_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryRewardRequestsToolName,
                description = "积分申请/查询待确认申请：只返回当前家长名下孩子在当前家长可访问圈子中提交的申请；可按圈子和状态筛选。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        family_group_id = new { type = "integer", description = "圈子ID，可选；传入时必须是当前家长可访问圈子" },
                        status = new { type = "string", description = "申请状态，可选，例如 pending、completed" },
                        limit = new { type = "integer", description = "返回数量，默认 100，最大 200" }
                    }
                }
            },
            new
            {
                name = FamilyRewardMcpApproveRewardRequestToolName,
                description = "积分申请/确认领取：仅孩子所属家长可确认自己名下孩子的待处理申请，并生成积分流水。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        request_id = new { type = "integer", description = "积分申请ID" },
                        family_group_id = new { type = "integer", description = "申请所在圈子ID，可选" },
                        review_note = new { type = "string", description = "家长确认备注" }
                    },
                    required = new[] { "request_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryCircleDashboardToolName,
                description = "圈子统计/查询总览：仅圈子成员可查看指定圈子的孩子余额和最近记录汇总。",
                inputSchema = new
                {
                    type = "object",
                    properties = new { family_group_id = new { type = "integer", description = "圈子ID" } },
                    required = new[] { "family_group_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryCircleLeaderboardToolName,
                description = "圈子统计/查询积分榜：仅圈子成员可查看指定圈子孩子的积分排名。",
                inputSchema = new
                {
                    type = "object",
                    properties = new { family_group_id = new { type = "integer", description = "圈子ID" } },
                    required = new[] { "family_group_id" }
                }
            },
            new
            {
                name = FamilyRewardMcpQueryCircleCategoriesToolName,
                description = "圈子统计/查询分类汇总：仅圈子成员可查看指定圈子的积分记录分类汇总。",
                inputSchema = new
                {
                    type = "object",
                    properties = new { family_group_id = new { type = "integer", description = "圈子ID" } },
                    required = new[] { "family_group_id" }
                }
            }
    };

    var toolNodes = JsonSerializer.SerializeToNode(tools, FamilyRewardJson.CreateOptions()) as JsonArray ?? [];
    foreach (var tool in toolNodes.OfType<JsonObject>())
    {
        var schema = tool["inputSchema"] as JsonObject;
        var properties = schema?["properties"] as JsonObject;
        if (schema is null || properties is null)
        {
            continue;
        }

        properties["username"] = new JsonObject
        {
            ["type"] = "string",
            ["description"] = "当前登录用户的用户中心用户名（必填）。由 Goldfish 网关注入；服务端据此解析当前家长的内部权限范围。"
        };
        var required = schema["required"] as JsonArray ?? [];
        if (!required.Any(item => string.Equals(item?.GetValue<string>(), "username", StringComparison.Ordinal)))
        {
            required.Insert(0, "username");
        }
        schema["required"] = required;
        tool["description"] = $"{tool.String("description")} 所有调用必须传用户中心用户名 username；服务端会解析内部权限并拒绝越权访问。";
    }

    return new { tools = toolNodes };
}

static bool IsKnownMcpTool(string toolName) => toolName is
    FamilyRewardMcpQueryChildrenToolName or
    FamilyRewardMcpListChildrenToolName or
    FamilyRewardMcpAddChildToolName or
    FamilyRewardMcpUpdateChildToolName or
    FamilyRewardMcpDeleteChildToolName or
    FamilyRewardMcpAdjustScoreToolName or
    FamilyRewardMcpApplyMatchingRuleToolName or
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
    FamilyRewardMcpUpdateRuleTemplateToolName or
    FamilyRewardMcpQueryFamilyGroupsToolName or
    FamilyRewardMcpCreateFamilyGroupToolName or
    FamilyRewardMcpUpdateFamilyGroupToolName or
    FamilyRewardMcpDeleteFamilyGroupToolName or
    FamilyRewardMcpGetFamilyGroupInviteToolName or
    FamilyRewardMcpJoinFamilyGroupToolName or
    FamilyRewardMcpRemoveFamilyGroupChildToolName or
    FamilyRewardMcpQueryFamilyMembersToolName or
    FamilyRewardMcpCreateFamilyMemberToolName or
    FamilyRewardMcpUpdateFamilyMemberToolName or
    FamilyRewardMcpDeleteFamilyMemberToolName or
    FamilyRewardMcpGenerateChildAuthCodeToolName or
    FamilyRewardMcpQueryChildDevicesToolName or
    FamilyRewardMcpRevokeChildDeviceToolName or
    FamilyRewardMcpGenerateDeviceUnbindCodeToolName or
    FamilyRewardMcpQueryChildFriendsToolName or
    FamilyRewardMcpQueryFriendNotificationsToolName or
    FamilyRewardMcpMarkFriendNotificationReadToolName or
    FamilyRewardMcpQueryRewardRequestsToolName or
    FamilyRewardMcpApproveRewardRequestToolName or
    FamilyRewardMcpQueryCircleDashboardToolName or
    FamilyRewardMcpQueryCircleLeaderboardToolName or
    FamilyRewardMcpQueryCircleCategoriesToolName;

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

    if (parts.Count == 1)
    {
        parts.Add($"结果 {node.ToJsonString(FamilyRewardJson.CreateOptions())}");
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

    if (ResolveMcpParentAppUserId(arguments) is null)
    {
        return new
        {
            ok = false,
            action = "validate_parent",
            error = "缺少必填参数 username。请传当前登录用户的用户中心用户名。"
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
    allowed.Add("username");
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
    FamilyRewardMcpApplyMatchingRuleToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "behavior", "date", "request_id", "notes"
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
        "name", "category", "points", "rule_type", "cash_cny", "description"
    },
    FamilyRewardMcpUpdateRuleToolName => new(StringComparer.Ordinal)
    {
        "rule_id", "name", "category", "points", "rule_type", "cash_cny", "description"
    },
    FamilyRewardMcpDeleteRuleToolName => new(StringComparer.Ordinal)
    {
        "rule_id"
    },
    FamilyRewardMcpUpdateRuleTemplateToolName => new(StringComparer.Ordinal)
    {
        "rule_ids"
    },
    FamilyRewardMcpQueryFamilyGroupsToolName => new(StringComparer.Ordinal)
    {
    },
    FamilyRewardMcpCreateFamilyGroupToolName => new(StringComparer.Ordinal)
    {
        "name", "description"
    },
    FamilyRewardMcpUpdateFamilyGroupToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "name", "description"
    },
    FamilyRewardMcpDeleteFamilyGroupToolName or
    FamilyRewardMcpGetFamilyGroupInviteToolName or
    FamilyRewardMcpQueryCircleDashboardToolName or
    FamilyRewardMcpQueryCircleLeaderboardToolName or
    FamilyRewardMcpQueryCircleCategoriesToolName => new(StringComparer.Ordinal)
    {
        "family_group_id"
    },
    FamilyRewardMcpJoinFamilyGroupToolName => new(StringComparer.Ordinal)
    {
        "invite_code"
    },
    FamilyRewardMcpRemoveFamilyGroupChildToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id"
    },
    FamilyRewardMcpQueryFamilyMembersToolName => new(StringComparer.Ordinal),
    FamilyRewardMcpCreateFamilyMemberToolName => new(StringComparer.Ordinal)
    {
        "display_name", "role", "note"
    },
    FamilyRewardMcpUpdateFamilyMemberToolName => new(StringComparer.Ordinal)
    {
        "member_id", "display_name", "role", "note"
    },
    FamilyRewardMcpDeleteFamilyMemberToolName => new(StringComparer.Ordinal)
    {
        "member_id"
    },
    FamilyRewardMcpGenerateChildAuthCodeToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "expires_in_minutes"
    },
    FamilyRewardMcpQueryChildDevicesToolName or
    FamilyRewardMcpQueryChildFriendsToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name"
    },
    FamilyRewardMcpRevokeChildDeviceToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "device_id"
    },
    FamilyRewardMcpGenerateDeviceUnbindCodeToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "child_id", "child_name", "device_id", "expires_in_minutes"
    },
    FamilyRewardMcpQueryFriendNotificationsToolName => new(StringComparer.Ordinal)
    {
        "unread_only"
    },
    FamilyRewardMcpMarkFriendNotificationReadToolName => new(StringComparer.Ordinal)
    {
        "notification_id"
    },
    FamilyRewardMcpQueryRewardRequestsToolName => new(StringComparer.Ordinal)
    {
        "family_group_id", "status", "limit"
    },
    FamilyRewardMcpApproveRewardRequestToolName => new(StringComparer.Ordinal)
    {
        "request_id", "family_group_id", "review_note"
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
        FamilyRewardMcpApplyMatchingRuleToolName => await McpApplyMatchingRule(connectionString, arguments),
        FamilyRewardMcpQueryScoreToolName => await McpQueryScore(connectionString, arguments),
        FamilyRewardMcpCreateRecordToolName => await McpCreateRecord(connectionString, arguments),
        FamilyRewardMcpUpdateRecordToolName => await McpUpdateRecord(connectionString, arguments),
        FamilyRewardMcpDeleteRecordToolName => await McpDeleteRecord(connectionString, arguments),
        FamilyRewardMcpLogScoreOperationToolName => await McpLogScoreOperation(connectionString, arguments),
        FamilyRewardMcpQueryScoreOperationToolName => await McpQueryScoreOperations(connectionString, arguments),
        FamilyRewardMcpQueryRulesToolName => await McpQueryRules(connectionString, arguments),
        FamilyRewardMcpCreateRuleToolName => await McpCreateRule(connectionString, arguments),
        FamilyRewardMcpUpdateRuleToolName => await McpUpdateRule(connectionString, arguments),
        FamilyRewardMcpDeleteRuleToolName => await McpDeleteRule(connectionString, arguments),
        FamilyRewardMcpUpdateRuleTemplateToolName => await McpUpdateRuleTemplate(connectionString, arguments),
        FamilyRewardMcpQueryFamilyGroupsToolName => await McpQueryFamilyGroups(connectionString, arguments),
        FamilyRewardMcpCreateFamilyGroupToolName => await McpCreateFamilyGroup(connectionString, arguments),
        FamilyRewardMcpUpdateFamilyGroupToolName => await McpUpdateFamilyGroup(connectionString, arguments),
        FamilyRewardMcpDeleteFamilyGroupToolName => await McpDeleteFamilyGroup(connectionString, arguments),
        FamilyRewardMcpGetFamilyGroupInviteToolName => await McpGetFamilyGroupInvite(connectionString, arguments),
        FamilyRewardMcpJoinFamilyGroupToolName => await McpJoinFamilyGroup(connectionString, arguments),
        FamilyRewardMcpRemoveFamilyGroupChildToolName => await McpRemoveFamilyGroupChild(connectionString, arguments),
        FamilyRewardMcpQueryFamilyMembersToolName => await McpQueryFamilyMembers(connectionString, arguments),
        FamilyRewardMcpCreateFamilyMemberToolName => await McpCreateFamilyMember(connectionString, arguments),
        FamilyRewardMcpUpdateFamilyMemberToolName => await McpUpdateFamilyMember(connectionString, arguments),
        FamilyRewardMcpDeleteFamilyMemberToolName => await McpDeleteFamilyMember(connectionString, arguments),
        FamilyRewardMcpGenerateChildAuthCodeToolName => await McpGenerateChildAuthCode(connectionString, arguments),
        FamilyRewardMcpQueryChildDevicesToolName => await McpQueryChildDevices(connectionString, arguments),
        FamilyRewardMcpRevokeChildDeviceToolName => await McpRevokeChildDevice(connectionString, arguments),
        FamilyRewardMcpGenerateDeviceUnbindCodeToolName => await McpGenerateDeviceUnbindCode(connectionString, arguments),
        FamilyRewardMcpQueryChildFriendsToolName => await McpQueryChildFriends(connectionString, arguments),
        FamilyRewardMcpQueryFriendNotificationsToolName => await McpQueryFriendNotifications(connectionString, arguments),
        FamilyRewardMcpMarkFriendNotificationReadToolName => await McpMarkFriendNotificationRead(connectionString, arguments),
        FamilyRewardMcpQueryRewardRequestsToolName => await McpQueryRewardRequests(connectionString, arguments),
        FamilyRewardMcpApproveRewardRequestToolName => await McpApproveRewardRequest(connectionString, arguments),
        FamilyRewardMcpQueryCircleDashboardToolName => await McpQueryCircleDashboard(connectionString, arguments),
        FamilyRewardMcpQueryCircleLeaderboardToolName => await McpQueryCircleLeaderboard(connectionString, arguments),
        FamilyRewardMcpQueryCircleCategoriesToolName => await McpQueryCircleCategories(connectionString, arguments),
        _ => new { ok = false, error = $"Tool '{toolName}' 不存在" }
    };
}

static async Task<object> McpAddChild(string connectionString, JsonObject arguments)
{
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is not null && !await IsMcpFamilyAccessible(connectionString, familyGroupId.Value, parentAppUserId))
    {
        return new { ok = false, error = "圈子不存在或当前家长无权访问" };
    }

    var body = arguments.DeepClone().AsObject();
    body["user_id"] = parentAppUserId;
    body["parent_app_user_id"] = parentAppUserId;
    var result = await CreateChildCore(connectionString, body, familyGroupId);
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
        return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
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
    var tx = await CreateTransaction(connectionString, txBody, parentAppUserId: ResolveMcpParentAppUserId(arguments));
    if (tx.ContainsKey("error"))
    {
        return new { ok = false, error = tx["error"] };
    }

    var updated = (await GetMcpChildren(connectionString, arguments)).FirstOrDefault(c => GetInt(c, "id") == GetInt(target, "id"));
    return new { ok = true, action = "adjust_score", child = updated, transaction = tx["transaction"] };
}

static async Task<object> McpApplyMatchingRule(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, action = "apply_matching_rule", error = "未找到目标孩子，或当前家长权限不足" };
    }

    var behavior = arguments.String("behavior").Trim();
    if (string.IsNullOrWhiteSpace(behavior))
    {
        return new { ok = false, action = "apply_matching_rule", error = "behavior 行为描述不能为空" };
    }
    if (!TryParseDateFilter(arguments.String("date"), out _))
    {
        return new { ok = false, action = "apply_matching_rule", error = "date 日期格式无效，请使用 yyyy-MM-dd" };
    }

    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    var ruleData = await GetRules(connectionString, parentAppUserId);
    var effectiveRules = (List<Dictionary<string, object?>>)ruleData["rules"];
    var childName = Convert.ToString(target["name"], CultureInfo.InvariantCulture) ?? string.Empty;
    var matches = effectiveRules
        .Select(rule => new
        {
            Rule = rule,
            Score = ScoreRuleMatch(behavior, childName, rule),
            IsPersonal = !string.IsNullOrWhiteSpace(Convert.ToString(rule["ownerAppUserId"], CultureInfo.InvariantCulture))
        })
        .Where(candidate => candidate.Score >= 70)
        .OrderByDescending(candidate => candidate.Score)
        .ThenByDescending(candidate => candidate.IsPersonal)
        .ThenByDescending(candidate => NormalizeRuleMatchText(Convert.ToString(candidate.Rule["name"], CultureInfo.InvariantCulture) ?? string.Empty, string.Empty).Length)
        .ThenBy(candidate => GetInt(candidate.Rule, "id"))
        .ToList();

    if (matches.Count == 0)
    {
        return new
        {
            ok = false,
            action = "apply_matching_rule",
            error = "当前生效规则中没有匹配该行为的规则，未写入积分",
            behavior,
            effective_rule_count = effectiveRules.Count
        };
    }

    var best = matches[0];
    var sameRank = matches
        .Where(candidate => candidate.Score == best.Score && candidate.IsPersonal == best.IsPersonal)
        .ToList();
    if (sameRank.Count > 1)
    {
        return new
        {
            ok = false,
            action = "apply_matching_rule",
            error = "匹配到多个同等规则，未写入积分；请补充更具体的行为描述",
            candidates = sameRank.Select(candidate => new
            {
                id = GetInt(candidate.Rule, "id"),
                name = Convert.ToString(candidate.Rule["name"], CultureInfo.InvariantCulture),
                points = GetDecimal(candidate.Rule, "points")
            })
        };
    }

    var points = GetDecimal(best.Rule, "points");
    if (points == 0)
    {
        return new { ok = false, action = "apply_matching_rule", error = "匹配规则的积分为 0，未写入积分" };
    }

    var requestId = arguments.String("request_id").Trim();
    var idempotencyKey = string.IsNullOrWhiteSpace(requestId)
        ? string.Empty
        : Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{parentAppUserId}:{requestId}"))).ToLowerInvariant();
    var beforeScore = GetDecimal(target, "score");
    var txBody = new JsonObject
    {
        ["child_id"] = GetInt(target, "id"),
        ["type"] = "points",
        ["direction"] = points > 0 ? "+" : "-",
        ["points"] = Math.Abs(points),
        ["category"] = Convert.ToString(best.Rule["category"], CultureInfo.InvariantCulture) ?? "规则记分",
        ["description"] = $"{Convert.ToString(best.Rule["name"], CultureInfo.InvariantCulture)}：{behavior}",
        ["notes"] = arguments.String("notes"),
        ["date"] = arguments.String("date", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)),
        ["idempotency_key"] = idempotencyKey
    };
    var tx = await CreateTransaction(connectionString, txBody, parentAppUserId: parentAppUserId);
    if (tx.ContainsKey("error"))
    {
        return new { ok = false, action = "apply_matching_rule", error = tx["error"] };
    }

    var updated = (await GetMcpChildren(connectionString, arguments))
        .FirstOrDefault(child => GetInt(child, "id") == GetInt(target, "id"));
    return new
    {
        ok = true,
        action = "apply_matching_rule",
        behavior,
        matched_rule = best.Rule,
        points_delta = points,
        before_score = beforeScore,
        after_score = updated is null ? beforeScore : GetDecimal(updated, "score"),
        deduplicated = tx.TryGetValue("deduplicated", out var deduplicated) && Convert.ToBoolean(deduplicated, CultureInfo.InvariantCulture),
        child = updated,
        transaction = tx["transaction"]
    };
}

static int ScoreRuleMatch(string behavior, string childName, Dictionary<string, object?> rule)
{
    var eventText = NormalizeRuleMatchText(behavior, childName);
    var ruleName = NormalizeRuleMatchText(Convert.ToString(rule["name"], CultureInfo.InvariantCulture) ?? string.Empty, string.Empty);
    var ruleDescription = NormalizeRuleMatchText(Convert.ToString(rule["description"], CultureInfo.InvariantCulture) ?? string.Empty, string.Empty);
    if (string.IsNullOrWhiteSpace(eventText) || string.IsNullOrWhiteSpace(ruleName)) return 0;
    if (eventText == ruleName) return 100;
    if (eventText.Contains(ruleName, StringComparison.Ordinal) || ruleName.Contains(eventText, StringComparison.Ordinal)) return 90;
    if (!string.IsNullOrWhiteSpace(ruleDescription)
        && (ruleDescription.Contains(eventText, StringComparison.Ordinal) || eventText.Contains(ruleDescription, StringComparison.Ordinal))) return 80;

    var eventBigrams = BuildTextBigrams(eventText);
    var ruleBigrams = BuildTextBigrams($"{ruleName}{ruleDescription}");
    if (eventBigrams.Count == 0 || ruleBigrams.Count == 0) return 0;
    var overlap = eventBigrams.Intersect(ruleBigrams, StringComparer.Ordinal).Count();
    return (int)Math.Round(69m * overlap / eventBigrams.Count, MidpointRounding.AwayFromZero);
}

static string NormalizeRuleMatchText(string text, string childName)
{
    var normalized = text.Trim().ToLowerInvariant();
    if (!string.IsNullOrWhiteSpace(childName)) normalized = normalized.Replace(childName.Trim().ToLowerInvariant(), string.Empty, StringComparison.Ordinal);
    foreach (var ignored in new[] { "今天", "今日", "昨天", "刚刚", "请", "给", "因为", "需要", "进行", "积分", "加分", "扣分", "记分", "一下", "这次", "孩子" })
    {
        normalized = normalized.Replace(ignored, string.Empty, StringComparison.Ordinal);
    }
    foreach (var synonym in new[] { "照料", "照看", "照顾", "关照", "爱护", "帮忙", "帮了", "协助" })
    {
        normalized = normalized.Replace(synonym, "帮助", StringComparison.Ordinal);
    }
    normalized = normalized.Replace("帮妹妹", "帮助妹妹", StringComparison.Ordinal)
        .Replace("帮弟弟", "帮助弟弟", StringComparison.Ordinal);
    return new string(normalized.Where(char.IsLetterOrDigit).ToArray());
}

static HashSet<string> BuildTextBigrams(string text)
{
    var result = new HashSet<string>(StringComparer.Ordinal);
    for (var index = 0; index + 1 < text.Length; index++) result.Add(text.Substring(index, 2));
    return result;
}

static async Task<object> McpLogScoreOperation(string connectionString, JsonObject arguments)
{
    var children = await GetMcpChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
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
    var tx = await CreateTransaction(connectionString, txBody, parentAppUserId: ResolveMcpParentAppUserId(arguments));
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
        return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
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
        var profileKey = Convert.ToString(target["profileKey"], CultureInfo.InvariantCulture)
            ?? Convert.ToString(target["profile_key"], CultureInfo.InvariantCulture)
            ?? "";
        await using (var profileCmd = new NpgsqlCommand("""
            UPDATE child_profiles
            SET name = COALESCE(@name, name),
                note = COALESCE(@note, note),
                status = COALESCE(@status, status),
                updated_at = CURRENT_TIMESTAMP
            WHERE profile_key = @profile_key
            """, conn, tx))
        {
            profileCmd.Parameters.AddWithValue("profile_key", profileKey);
            profileCmd.Parameters.AddWithValue("name", hasName ? name : DBNull.Value);
            profileCmd.Parameters.AddWithValue("note", hasNote ? arguments["note"]!.ToString() : DBNull.Value);
            profileCmd.Parameters.AddWithValue("status", hasStatus ? arguments.String("status") : DBNull.Value);
            if (await profileCmd.ExecuteNonQueryAsync() == 0)
            {
                await tx.RollbackAsync();
                return new { ok = false, error = "孩子不存在" };
            }
        }

        await using (var cmd = new NpgsqlCommand("""
            UPDATE children
            SET name = COALESCE(@name, name),
                note = COALESCE(@note, note),
                status = COALESCE(@status, status),
                updated_at = CURRENT_TIMESTAMP
            WHERE profile_key = @profile_key
            """, conn, tx))
        {
            cmd.Parameters.AddWithValue("profile_key", profileKey);
            cmd.Parameters.AddWithValue("name", hasName ? name : DBNull.Value);
            cmd.Parameters.AddWithValue("note", hasNote ? arguments["note"]!.ToString() : DBNull.Value);
            cmd.Parameters.AddWithValue("status", hasStatus ? arguments.String("status") : DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
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
        return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    }

    var result = await DeleteChildMembership(connectionString, GetInt(target, "id"), ResolveMcpParentAppUserId(arguments)!);
    return !result.ContainsKey("error")
        ? new { ok = true, action = "delete_child", child = target }
        : new { ok = false, error = result["error"] };
}

static async Task<object> McpQueryScore(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    if (familyGroupId is not null && !await IsMcpFamilyAccessible(connectionString, familyGroupId.Value, parentAppUserId))
    {
        return new { ok = false, error = "圈子不存在或当前家长权限不足" };
    }

    var children = await GetMcpVisibleFamilyChildren(connectionString, arguments);
    var target = ResolveChildByReference(children, arguments);
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

    var profileKey = Convert.ToString(target["profileKey"], CultureInfo.InvariantCulture)
        ?? Convert.ToString(target["profile_key"], CultureInfo.InvariantCulture)
        ?? "";
    if (includeTransactions && !await IsMcpChildOwnedByParent(connectionString, profileKey, parentAppUserId))
    {
        return new { ok = false, error = "圈子成员只能查看其他家庭孩子的积分余额；积分明细仅孩子所属家长可查" };
    }
    var records = includeTransactions
        ? await GetMcpOwnedChildTransactions(connectionString, profileKey, parentAppUserId, Math.Clamp(limit, 1, 200), startDate, endDate)
        : [];
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
    var requestedFamilyGroupId = arguments.Int("family_group_id");
    if (requestedFamilyGroupId is not null &&
        !await IsMcpFamilyAccessible(connectionString, requestedFamilyGroupId.Value, ResolveMcpParentAppUserId(arguments)!))
    {
        return new { ok = false, error = "圈子不存在或当前家长无权访问" };
    }
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
    var where = new List<string>
    {
        "1=1",
        "t.type = 'points'",
        "EXISTS (SELECT 1 FROM child_user_bindings cub WHERE cub.child_profile_key = c.profile_key AND cub.parent_app_user_id = @parent_app_user_id)"
    };
    var parameters = new List<NpgsqlParameter>
    {
        new("parent_app_user_id", ResolveMcpParentAppUserId(arguments)!)
    };
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

    var ownedChildren = await GetMcpChildren(connectionString, arguments);
    if (ResolveChildByReference(ownedChildren, arguments) is null)
    {
        return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    }

    var body = await NormalizeRecordArguments(connectionString, arguments);
    var result = await CreateTransaction(connectionString, body, parentAppUserId: ResolveMcpParentAppUserId(arguments));
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

    if (HasChildReference(arguments))
    {
        var ownedChildren = await GetMcpChildren(connectionString, arguments);
        if (ResolveChildByReference(ownedChildren, arguments) is null)
        {
            return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
        }
    }

    var body = await NormalizeRecordArguments(connectionString, arguments, allowMissingChild: true);
    var result = await UpdateTransaction(connectionString, id.Value, body, ResolveMcpParentAppUserId(arguments));
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

    var result = await DeleteTransaction(connectionString, id.Value, parentAppUserId: ResolveMcpParentAppUserId(arguments));
    if (result.ContainsKey("error"))
    {
        return new { ok = false, error = result["error"] };
    }

    return new { ok = true, action = "delete_record", transaction = result["transaction"] };
}

static async Task<object> McpQueryChildren(string connectionString, JsonObject? arguments = null)
{
    var familyGroupId = arguments?.Int("family_group_id");
    if (arguments is not null && familyGroupId is not null &&
        !await IsMcpFamilyAccessible(connectionString, familyGroupId.Value, ResolveMcpParentAppUserId(arguments)!))
    {
        return new { ok = false, error = "圈子不存在或当前家长无权访问" };
    }
    var children = arguments is null
        ? await GetMcpChildren(connectionString, arguments)
        : await GetMcpVisibleFamilyChildren(connectionString, arguments);
    var target = arguments is null ? null : ResolveChildByReference(children, arguments);
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

static async Task<object> McpQueryRules(string connectionString, JsonObject arguments)
{
    var parentAppUserId = ResolveMcpParentAppUserId(arguments);
    return parentAppUserId is null
        ? new { ok = false, action = "query_rules", error = "缺少用户中心用户名 username" }
        : new { ok = true, action = "query_rules", data = await GetRules(connectionString, parentAppUserId) };
}

static async Task<object> McpCreateRule(string connectionString, JsonObject arguments)
{
    var name = arguments.String("name").Trim();
    if (string.IsNullOrWhiteSpace(name))
    {
        return new { ok = false, error = "规则名称不能为空" };
    }
    var parentAppUserId = ResolveMcpParentAppUserId(arguments);
    if (parentAppUserId is null) return new { ok = false, error = "缺少用户中心用户名 username" };
    var result = await CreatePersonalRule(connectionString, parentAppUserId, arguments);
    return result.ContainsKey("error")
        ? new { ok = false, error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "create_rule", rule = result["rule"] };
}

static async Task<object> McpUpdateRule(string connectionString, JsonObject arguments)
{
    var id = arguments.Int("rule_id");
    if (id is null)
    {
        return new { ok = false, error = "缺少规则ID" };
    }
    var parentAppUserId = ResolveMcpParentAppUserId(arguments);
    if (parentAppUserId is null) return new { ok = false, error = "缺少用户中心用户名 username" };

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE rules
        SET name = COALESCE(@name, name),
            category = COALESCE(@category, category),
            points = COALESCE(@points, points),
            cash_cny = COALESCE(@cash_cny, cash_cny),
            description = COALESCE(@description, description)
        WHERE id = @id AND owner_app_user_id = @owner_app_user_id
        RETURNING *
        """, conn);
    cmd.Parameters.AddWithValue("id", id.Value);
    cmd.Parameters.AddWithValue("owner_app_user_id", parentAppUserId);
    cmd.Parameters.AddWithValue("name", arguments.ContainsKey("name") ? arguments.String("name") : DBNull.Value);
    cmd.Parameters.AddWithValue("category", arguments.ContainsKey("category") ? arguments.String("category") : DBNull.Value);
    cmd.Parameters.AddWithValue("points", arguments.ContainsKey("points")
        ? NormalizeRulePoints(arguments)
        : DBNull.Value);
    cmd.Parameters.AddWithValue("cash_cny", arguments.ContainsKey("cash_cny") ? arguments.Decimal("cash_cny") ?? 0 : DBNull.Value);
    cmd.Parameters.AddWithValue("description", arguments.ContainsKey("description") ? arguments.String("description") : DBNull.Value);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return new { ok = false, error = "规则不存在或无权修改公共规则" };
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
    var parentAppUserId = ResolveMcpParentAppUserId(arguments);
    if (parentAppUserId is null) return new { ok = false, error = "缺少用户中心用户名 username" };

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM rules WHERE id = @id AND owner_app_user_id = @owner_app_user_id RETURNING *", conn);
    cmd.Parameters.AddWithValue("id", id.Value);
    cmd.Parameters.AddWithValue("owner_app_user_id", parentAppUserId);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return new { ok = false, error = "规则不存在或无权删除公共规则" };
    }
    return new { ok = true, action = "delete_rule", rule = ReadRule(reader) };
}

static string? ResolveMcpParentAppUserId(JsonObject arguments)
{
    var username = arguments.String("username").Trim();
    return string.IsNullOrWhiteSpace(username) ? null : MakeParentAppUserId(username);
}

static async Task<object> McpQueryFamilyGroups(string connectionString, JsonObject arguments)
{
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    return new { ok = true, action = "query_family_groups", familyGroups = await GetFamilyGroups(connectionString, parentAppUserId) };
}

static async Task<object> McpCreateFamilyGroup(string connectionString, JsonObject arguments)
{
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    var result = await CreateFamilyGroup(connectionString, arguments.String("name"), parentAppUserId, arguments.String("description"));
    return result.Success
        ? new { ok = true, action = "create_family_group", familyGroup = result.Group }
        : new { ok = false, error = result.Error };
}

static async Task<object> McpUpdateFamilyGroup(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is null) return new { ok = false, error = "缺少圈子ID family_group_id" };

    var result = await UpdateFamilyGroup(
        connectionString,
        familyGroupId.Value,
        arguments.String("name"),
        ResolveMcpParentAppUserId(arguments)!,
        arguments.String("description"));
    return result.Success
        ? new { ok = true, action = "update_family_group", familyGroup = result.Group }
        : new { ok = false, error = result.Error };
}

static async Task<object> McpDeleteFamilyGroup(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is null) return new { ok = false, error = "缺少圈子ID family_group_id" };

    var result = await DeleteFamilyGroup(connectionString, familyGroupId.Value, ResolveMcpParentAppUserId(arguments)!);
    return result.Success
        ? new
        {
            ok = true,
            action = "delete_family_group",
            family_group_id = familyGroupId,
            family_group_name = result.FamilyGroupName,
            removed_children = result.RemovedChildren
        }
        : new { ok = false, error = result.Error };
}

static async Task<object> McpGetFamilyGroupInvite(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is null) return new { ok = false, error = "缺少圈子ID family_group_id" };

    var result = await GetOrCreateFamilyGroupInvite(connectionString, familyGroupId.Value, ResolveMcpParentAppUserId(arguments)!);
    return result.Success
        ? new
        {
            ok = true,
            action = "get_family_group_invite",
            family_group_id = familyGroupId,
            family_group_name = result.FamilyGroupName,
            invite_code = result.InviteCode
        }
        : new { ok = false, error = result.Error };
}

static async Task<object> McpJoinFamilyGroup(string connectionString, JsonObject arguments)
{
    var inviteCode = NormalizeFamilyGroupInviteCode(arguments.String("invite_code"));
    if (inviteCode.Length != 8 || inviteCode.Any(ch => !char.IsAsciiDigit(ch)))
    {
        return new { ok = false, error = "invite_code 必须是 8 位数字圈子邀请码" };
    }

    var result = await JoinFamilyGroupByInviteCode(connectionString, inviteCode, ResolveMcpParentAppUserId(arguments)!);
    return result.Success
        ? new
        {
            ok = true,
            action = "join_family_group",
            family_group_id = result.FamilyGroupId,
            family_group_name = result.FamilyGroupName,
            linked_child_count = result.LinkedChildCount
        }
        : new { ok = false, error = result.Error };
}

static async Task<object> McpRemoveFamilyGroupChild(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    var childId = arguments.Int("child_id");
    if (familyGroupId is null || childId is null)
    {
        return new { ok = false, error = "缺少圈子ID family_group_id 或孩子ID child_id" };
    }

    var result = await RemoveChildFromFamilyGroup(
        connectionString,
        familyGroupId.Value,
        childId.Value,
        ResolveMcpParentAppUserId(arguments)!);
    return result.Success
        ? new { ok = true, action = "remove_family_group_child", family_group_id = familyGroupId, child_id = childId }
        : new { ok = false, error = result.Error };
}

static async Task EnsureMcpCurrentFamilyMember(NpgsqlConnection conn, string parentAppUserId)
{
    var displayName = parentAppUserId;
    await using (var profileCmd = new NpgsqlCommand("SELECT COALESCE(NULLIF(username, ''), app_user_id) FROM app_user_profiles WHERE app_user_id = @app_user_id AND role = 'parent' ORDER BY id LIMIT 1", conn))
    {
        profileCmd.Parameters.AddWithValue("app_user_id", parentAppUserId);
        var value = await profileCmd.ExecuteScalarAsync();
        if (value is not null && value is not DBNull)
        {
            displayName = Convert.ToString(value, CultureInfo.InvariantCulture) ?? parentAppUserId;
        }
    }

    await using var cmd = new NpgsqlCommand("""
        INSERT INTO household_members (owner_parent_app_user_id, display_name, role, is_current_user)
        VALUES (@owner_parent_app_user_id, @display_name, 'guardian', TRUE)
        ON CONFLICT DO NOTHING
        """, conn);
    cmd.Parameters.AddWithValue("owner_parent_app_user_id", parentAppUserId);
    cmd.Parameters.AddWithValue("display_name", displayName);
    await cmd.ExecuteNonQueryAsync();
}

static async Task<object> McpQueryFamilyMembers(string connectionString, JsonObject arguments)
{
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    await using var conn = await OpenConnection(connectionString);
    await EnsureMcpCurrentFamilyMember(conn, parentAppUserId);
    var members = await GetHouseholdMembers(conn, parentAppUserId);
    return new { ok = true, action = "query_family_members", count = members.Count, familyMembers = members };
}

static async Task<object> McpCreateFamilyMember(string connectionString, JsonObject arguments)
{
    var displayName = arguments.String("display_name").Trim();
    var role = NormalizeHouseholdRole(arguments.String("role"));
    if (string.IsNullOrWhiteSpace(displayName)) return new { ok = false, error = "家庭成员姓名不能为空" };
    if (displayName.Length > 50) return new { ok = false, error = "家庭成员姓名不能超过 50 个字符" };
    if (string.IsNullOrWhiteSpace(role)) return new { ok = false, error = "家庭角色无效" };

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO household_members (owner_parent_app_user_id, display_name, role, note, is_current_user)
        VALUES (@owner_parent_app_user_id, @display_name, @role, @note, FALSE)
        RETURNING id, display_name, role, note, is_current_user, created_at, updated_at
        """, conn);
    cmd.Parameters.AddWithValue("owner_parent_app_user_id", ResolveMcpParentAppUserId(arguments)!);
    cmd.Parameters.AddWithValue("display_name", displayName);
    cmd.Parameters.AddWithValue("role", role);
    cmd.Parameters.AddWithValue("note", string.IsNullOrWhiteSpace(arguments.String("note")) ? DBNull.Value : arguments.String("note").Trim());
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return new { ok = true, action = "create_family_member", familyMember = ReadHouseholdMember(reader) };
}

static async Task<object> McpUpdateFamilyMember(string connectionString, JsonObject arguments)
{
    var memberId = arguments.Int("member_id");
    var displayName = arguments.String("display_name").Trim();
    var role = NormalizeHouseholdRole(arguments.String("role"));
    if (memberId is null) return new { ok = false, error = "缺少家庭成员ID member_id" };
    if (string.IsNullOrWhiteSpace(displayName)) return new { ok = false, error = "家庭成员姓名不能为空" };
    if (displayName.Length > 50) return new { ok = false, error = "家庭成员姓名不能超过 50 个字符" };
    if (string.IsNullOrWhiteSpace(role)) return new { ok = false, error = "家庭角色无效" };

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE household_members
        SET display_name = @display_name, role = @role, note = @note, updated_at = CURRENT_TIMESTAMP
        WHERE id = @id AND owner_parent_app_user_id = @owner_parent_app_user_id
        RETURNING id, display_name, role, note, is_current_user, created_at, updated_at
        """, conn);
    cmd.Parameters.AddWithValue("id", memberId.Value);
    cmd.Parameters.AddWithValue("owner_parent_app_user_id", ResolveMcpParentAppUserId(arguments)!);
    cmd.Parameters.AddWithValue("display_name", displayName);
    cmd.Parameters.AddWithValue("role", role);
    cmd.Parameters.AddWithValue("note", string.IsNullOrWhiteSpace(arguments.String("note")) ? DBNull.Value : arguments.String("note").Trim());
    await using var reader = await cmd.ExecuteReaderAsync();
    return await reader.ReadAsync()
        ? new { ok = true, action = "update_family_member", familyMember = ReadHouseholdMember(reader) }
        : new { ok = false, action = "update_family_member", familyMember = (object?)null, error = "家庭成员不存在或当前家长权限不足" };
}

static async Task<object> McpDeleteFamilyMember(string connectionString, JsonObject arguments)
{
    var memberId = arguments.Int("member_id");
    if (memberId is null) return new { ok = false, error = "缺少家庭成员ID member_id" };
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;

    await using var conn = await OpenConnection(connectionString);
    await using (var deleteCmd = new NpgsqlCommand("DELETE FROM household_members WHERE id = @id AND owner_parent_app_user_id = @owner_parent_app_user_id AND is_current_user = FALSE", conn))
    {
        deleteCmd.Parameters.AddWithValue("id", memberId.Value);
        deleteCmd.Parameters.AddWithValue("owner_parent_app_user_id", parentAppUserId);
        if (await deleteCmd.ExecuteNonQueryAsync() > 0)
        {
            return new { ok = true, action = "delete_family_member", member_id = memberId };
        }
    }

    await using var existsCmd = new NpgsqlCommand("SELECT is_current_user FROM household_members WHERE id = @id AND owner_parent_app_user_id = @owner_parent_app_user_id", conn);
    existsCmd.Parameters.AddWithValue("id", memberId.Value);
    existsCmd.Parameters.AddWithValue("owner_parent_app_user_id", parentAppUserId);
    var isCurrentUser = await existsCmd.ExecuteScalarAsync();
    return isCurrentUser is true
        ? new { ok = false, action = "delete_family_member", member_id = memberId, error = "当前用户不能从家庭成员中删除" }
        : new { ok = false, action = "delete_family_member", member_id = memberId, error = "家庭成员不存在或当前家长权限不足" };
}

static async Task<object> McpUpdateRuleTemplate(string connectionString, JsonObject arguments)
{
    if (arguments["rule_ids"] is not JsonArray ruleIdNodes)
    {
        return new { ok = false, error = "rule_ids 必须是规则ID数组" };
    }
    var ruleIds = ruleIdNodes
        .Select(node => node is null ? null : int.TryParse(node.ToString(), out var id) ? id : (int?)null)
        .Where(id => id.HasValue)
        .Select(id => id!.Value)
        .Distinct()
        .ToList();
    if (ruleIds.Count != ruleIdNodes.Count)
    {
        return new { ok = false, error = "rule_ids 包含无效规则ID" };
    }

    var result = await SaveRuleTemplate(connectionString, ResolveMcpParentAppUserId(arguments)!, ruleIds);
    return result.ContainsKey("error")
        ? new { ok = false, action = "update_rule_template", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "update_rule_template", rule_ids = ruleIds };
}

static async Task<(Dictionary<string, object?>? Child, int FamilyGroupId)> ResolveMcpOwnedChildTarget(
    string connectionString,
    JsonObject arguments)
{
    var requestedFamilyGroupId = arguments.Int("family_group_id");
    var parentAppUserId = ResolveMcpParentAppUserId(arguments)!;
    if (requestedFamilyGroupId is not null && !await IsMcpFamilyAccessible(connectionString, requestedFamilyGroupId.Value, parentAppUserId))
    {
        return (null, 0);
    }

    var child = ResolveChildByReference(await GetMcpChildren(connectionString, arguments), arguments);
    return child is null ? (null, 0) : (child, GetInt(child, "familyGroupId"));
}

static async Task<object> McpGenerateChildAuthCode(string connectionString, JsonObject arguments)
{
    var target = await ResolveMcpOwnedChildTarget(connectionString, arguments);
    if (target.Child is null || target.FamilyGroupId <= 0) return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    var result = await CreateChildAuthCode(
        connectionString,
        GetInt(target.Child, "id"),
        target.FamilyGroupId,
        ResolveMcpParentAppUserId(arguments)!,
        Math.Clamp(arguments.Int("expires_in_minutes") ?? 24 * 60, 10, 24 * 60));
    return result.ContainsKey("error")
        ? new { ok = false, action = "generate_child_auth_code", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "generate_child_auth_code", data = result };
}

static async Task<object> McpQueryChildDevices(string connectionString, JsonObject arguments)
{
    var target = await ResolveMcpOwnedChildTarget(connectionString, arguments);
    if (target.Child is null || target.FamilyGroupId <= 0) return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    var result = await GetChildWatchDevices(connectionString, GetInt(target.Child, "id"), target.FamilyGroupId, ResolveMcpParentAppUserId(arguments)!);
    return result.ContainsKey("error")
        ? new { ok = false, action = "query_child_devices", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "query_child_devices", data = result };
}

static async Task<object> McpRevokeChildDevice(string connectionString, JsonObject arguments)
{
    var deviceId = arguments.Int("device_id");
    if (deviceId is null) return new { ok = false, error = "缺少设备ID device_id" };
    var target = await ResolveMcpOwnedChildTarget(connectionString, arguments);
    if (target.Child is null || target.FamilyGroupId <= 0) return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    var result = await RevokeChildWatchDevice(connectionString, GetInt(target.Child, "id"), deviceId.Value, target.FamilyGroupId, ResolveMcpParentAppUserId(arguments)!);
    return result.ContainsKey("error")
        ? new { ok = false, action = "revoke_child_device", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "revoke_child_device", data = result };
}

static async Task<object> McpGenerateDeviceUnbindCode(string connectionString, JsonObject arguments)
{
    var deviceId = arguments.Int("device_id");
    if (deviceId is null) return new { ok = false, error = "缺少设备ID device_id" };
    var target = await ResolveMcpOwnedChildTarget(connectionString, arguments);
    if (target.Child is null || target.FamilyGroupId <= 0) return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    var result = await CreateWatchDeviceUnbindCode(
        connectionString,
        GetInt(target.Child, "id"),
        deviceId.Value,
        target.FamilyGroupId,
        ResolveMcpParentAppUserId(arguments)!,
        Math.Clamp(arguments.Int("expires_in_minutes") ?? 10, 5, 30));
    return result.ContainsKey("error")
        ? new { ok = false, action = "generate_device_unbind_code", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "generate_device_unbind_code", data = result };
}

static async Task<object> McpQueryChildFriends(string connectionString, JsonObject arguments)
{
    var target = await ResolveMcpOwnedChildTarget(connectionString, arguments);
    if (target.Child is null) return new { ok = false, error = "未找到目标孩子，或当前家长权限不足" };
    var profileKey = Convert.ToString(target.Child["profileKey"], CultureInfo.InvariantCulture) ?? "";
    return new
    {
        ok = true,
        action = "query_child_friends",
        child = target.Child,
        friends = await GetChildFriends(connectionString, profileKey),
        leaderboard = await GetChildFriendLeaderboard(connectionString, profileKey)
    };
}

static async Task<object> McpQueryFriendNotifications(string connectionString, JsonObject arguments)
{
    var notifications = await GetChildFriendNotifications(connectionString, ResolveMcpParentAppUserId(arguments)!, arguments.Bool("unread_only"));
    return new { ok = true, action = "query_friend_notifications", count = notifications.Count, notifications };
}

static async Task<object> McpMarkFriendNotificationRead(string connectionString, JsonObject arguments)
{
    var notificationId = arguments.Int("notification_id");
    if (notificationId is null) return new { ok = false, error = "缺少通知ID notification_id" };
    var result = await MarkChildFriendNotificationRead(connectionString, notificationId.Value, ResolveMcpParentAppUserId(arguments)!);
    return result.ContainsKey("error")
        ? new { ok = false, action = "mark_friend_notification_read", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "mark_friend_notification_read", data = result };
}

static async Task<object> McpQueryRewardRequests(string connectionString, JsonObject arguments)
{
    var result = await GetParentWatchRewardRequests(
        connectionString,
        arguments.Int("family_group_id"),
        ResolveMcpParentAppUserId(arguments)!,
        arguments.String("status"),
        Math.Clamp(arguments.Int("limit") ?? 100, 1, 200));
    return result.ContainsKey("error")
        ? new { ok = false, action = "query_reward_requests", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "query_reward_requests", data = result };
}

static async Task<object> McpApproveRewardRequest(string connectionString, JsonObject arguments)
{
    var requestId = arguments.Int("request_id");
    if (requestId is null) return new { ok = false, error = "缺少申请ID request_id" };
    var result = await ApproveWatchRewardRequest(
        connectionString,
        requestId.Value,
        arguments.Int("family_group_id"),
        ResolveMcpParentAppUserId(arguments)!,
        arguments.String("review_note"));
    return result.ContainsKey("error")
        ? new { ok = false, action = "approve_reward_request", error = Convert.ToString(result["error"], CultureInfo.InvariantCulture) }
        : new { ok = true, action = "approve_reward_request", data = result };
}

static async Task<object> McpQueryCircleDashboard(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is null || !await IsMcpFamilyAccessible(connectionString, familyGroupId.Value, ResolveMcpParentAppUserId(arguments)!))
    {
        return new { ok = false, error = "圈子不存在或当前家长无权访问" };
    }
    var children = await GetChildren(connectionString, familyGroupId.Value);
    var recent = await GetRecentTransactions(connectionString, 20, familyGroupId.Value);
    return new { ok = true, action = "query_circle_dashboard", family_group_id = familyGroupId, children, recent };
}

static async Task<object> McpQueryCircleLeaderboard(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is null || !await IsMcpFamilyAccessible(connectionString, familyGroupId.Value, ResolveMcpParentAppUserId(arguments)!))
    {
        return new { ok = false, error = "圈子不存在或当前家长无权访问" };
    }
    var leaderboard = (await GetChildren(connectionString, familyGroupId.Value))
        .Select(child => new { id = GetInt(child, "id"), name = child["name"], points = GetDecimal(child, "score") })
        .OrderByDescending(child => child.points)
        .ToList();
    return new { ok = true, action = "query_circle_leaderboard", family_group_id = familyGroupId, leaderboard };
}

static async Task<object> McpQueryCircleCategories(string connectionString, JsonObject arguments)
{
    var familyGroupId = arguments.Int("family_group_id");
    if (familyGroupId is null || !await IsMcpFamilyAccessible(connectionString, familyGroupId.Value, ResolveMcpParentAppUserId(arguments)!))
    {
        return new { ok = false, error = "圈子不存在或当前家长无权访问" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT category, COALESCE(SUM(CASE WHEN direction = '-' THEN -points ELSE points END), 0) AS total
        FROM transactions t
        JOIN children c ON c.id = t.child_id
        WHERE c.family_group_id = @family_group_id AND t.type = 'points'
        GROUP BY category
        ORDER BY category
        """, conn);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId.Value);
    var categories = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        categories.Add(new { category = reader.String("category"), total = reader.Decimal("total") });
    }
    return new { ok = true, action = "query_circle_categories", family_group_id = familyGroupId, categories };
}

static async Task<List<Dictionary<string, object?>>> GetMcpChildren(string connectionString, JsonObject? arguments)
{
    var ownerAppUserId = arguments is null ? null : ResolveMcpParentAppUserId(arguments);
    return await GetChildren(
        connectionString,
        arguments?.Int("family_group_id"),
        ownerAppUserId: string.IsNullOrWhiteSpace(ownerAppUserId) ? null : ownerAppUserId);
}

static async Task<bool> IsMcpFamilyAccessible(string connectionString, int familyGroupId, string parentAppUserId)
{
    var groups = await GetFamilyGroups(connectionString, parentAppUserId);
    return groups.Any(group => GetInt(group, "id") == familyGroupId);
}

static async Task<List<Dictionary<string, object?>>> GetMcpVisibleFamilyChildren(
    string connectionString,
    JsonObject arguments)
{
    var requestedFamilyGroupId = arguments.Int("family_group_id");
    if (requestedFamilyGroupId is null)
    {
        return await GetMcpChildren(connectionString, arguments);
    }

    var result = await GetFamilyGroupChildren(
        connectionString,
        requestedFamilyGroupId.Value,
        ResolveMcpParentAppUserId(arguments)!);
    return result.Success ? result.Children : [];
}

static async Task<bool> IsMcpChildOwnedByParent(
    string connectionString,
    string profileKey,
    string parentAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT EXISTS (
            SELECT 1
            FROM child_user_bindings
            WHERE child_profile_key = @profile_key
              AND parent_app_user_id = @parent_app_user_id
        )
        """, conn);
    cmd.Parameters.AddWithValue("profile_key", profileKey);
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    return Convert.ToBoolean(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
}

static async Task<List<Dictionary<string, object?>>> GetMcpOwnedChildTransactions(
    string connectionString,
    string profileKey,
    string parentAppUserId,
    int limit,
    string startDate,
    string endDate)
{
    TryParseDateFilter(startDate, out var startDateValue);
    TryParseDateFilter(endDate, out var endDateValue);
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT t.*, COALESCE(cp.name, c.name) AS child_name
        FROM transactions t
        JOIN children c ON c.id = t.child_id
        LEFT JOIN child_profiles cp ON cp.profile_key = c.profile_key
        WHERE c.profile_key = @profile_key
          AND EXISTS (
              SELECT 1
              FROM child_user_bindings cub
              WHERE cub.child_profile_key = c.profile_key
                AND cub.parent_app_user_id = @parent_app_user_id
          )
          AND (@start_date IS NULL OR t.date >= @start_date)
          AND (@end_date IS NULL OR t.date <= @end_date)
        ORDER BY t.date DESC, t.id DESC
        LIMIT @limit
        """, conn);
    cmd.Parameters.AddWithValue("profile_key", profileKey);
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    cmd.Parameters.Add(new NpgsqlParameter("start_date", NpgsqlDbType.Date)
    {
        Value = startDateValue is null ? DBNull.Value : startDateValue.Value
    });
    cmd.Parameters.Add(new NpgsqlParameter("end_date", NpgsqlDbType.Date)
    {
        Value = endDateValue is null ? DBNull.Value : endDateValue.Value
    });
    cmd.Parameters.AddWithValue("limit", limit);
    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync()) rows.Add(ReadTransaction(reader));
    return rows;
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

static async Task<Dictionary<string, object?>> UpdateTransaction(
    string connectionString,
    int id,
    JsonObject body,
    string? parentAppUserId = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var existing = await ReadTransactionForUpdate(conn, tx, id, parentAppUserId: parentAppUserId);
        if (existing is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?>
            {
                ["error"] = string.IsNullOrWhiteSpace(parentAppUserId)
                    ? "记录不存在"
                    : "记录不存在或当前家长权限不足"
            };
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

static async Task<Dictionary<string, object?>> DeleteTransaction(
    string connectionString,
    int id,
    int? familyGroupId = null,
    string? parentAppUserId = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var existing = await ReadTransactionForUpdate(conn, tx, id, familyGroupId, parentAppUserId);
        if (existing is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?>
            {
                ["error"] = string.IsNullOrWhiteSpace(parentAppUserId)
                    ? "记录不存在"
                    : "记录不存在或当前家长权限不足"
            };
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

static async Task<Dictionary<string, object?>?> ReadTransactionForUpdate(
    NpgsqlConnection conn,
    NpgsqlTransaction tx,
    int id,
    int? familyGroupId = null,
    string? parentAppUserId = null)
{
    await using var cmd = new NpgsqlCommand("""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE t.id = @id
          AND (@family_group_id IS NULL OR c.family_group_id = @family_group_id)
          AND (
              @parent_app_user_id IS NULL OR EXISTS (
                  SELECT 1
                  FROM child_user_bindings cub
                  WHERE cub.child_profile_key = c.profile_key
                    AND cub.parent_app_user_id = @parent_app_user_id
              )
          )
        FOR UPDATE OF t
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
    {
        Value = familyGroupId is null ? DBNull.Value : familyGroupId.Value
    });
    cmd.Parameters.Add(new NpgsqlParameter("parent_app_user_id", NpgsqlDbType.Varchar)
    {
        Value = string.IsNullOrWhiteSpace(parentAppUserId) ? DBNull.Value : parentAppUserId
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
        CREATE TABLE IF NOT EXISTS system_config (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            config_json JSONB NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS family_groups (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
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
        CREATE TABLE IF NOT EXISTS household_members (
            id SERIAL PRIMARY KEY,
            owner_parent_app_user_id VARCHAR(180) NOT NULL,
            display_name VARCHAR(50) NOT NULL,
            role VARCHAR(30) NOT NULL DEFAULT 'guardian',
            note TEXT,
            is_current_user BOOLEAN NOT NULL DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
        CREATE TABLE IF NOT EXISTS watch_face_preferences (
            child_profile_key VARCHAR(180) PRIMARY KEY,
            watch_face VARCHAR(40) NOT NULL DEFAULT 'world',
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS child_friend_codes (
            id SERIAL PRIMARY KEY,
            child_profile_key VARCHAR(180) NOT NULL,
            parent_app_user_id VARCHAR(180) NOT NULL,
            code_hash VARCHAR(128) NOT NULL UNIQUE,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS child_friendships (
            id SERIAL PRIMARY KEY,
            child_profile_key_a VARCHAR(180) NOT NULL,
            child_profile_key_b VARCHAR(180) NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            created_by_child_profile_key VARCHAR(180) NOT NULL,
            created_by_code_id INTEGER REFERENCES child_friend_codes(id) ON DELETE SET NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CHECK (child_profile_key_a < child_profile_key_b),
            UNIQUE(child_profile_key_a, child_profile_key_b)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS child_friend_notifications (
            id SERIAL PRIMARY KEY,
            parent_app_user_id VARCHAR(180) NOT NULL,
            child_profile_key VARCHAR(180) NOT NULL,
            friend_profile_key VARCHAR(180) NOT NULL,
            friendship_id INTEGER REFERENCES child_friendships(id) ON DELETE CASCADE,
            message TEXT NOT NULL,
            read_at TIMESTAMP NULL,
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
        "ALTER TABLE family_groups DROP CONSTRAINT IF EXISTS family_groups_name_key",
        """
        DELETE FROM family_group_users old_user
        USING app_user_profiles aup
        WHERE old_user.user_id = aup.unified_user_id
          AND aup.role = 'parent'
          AND aup.app_user_id <> aup.unified_user_id
          AND EXISTS (
              SELECT 1
              FROM family_group_users new_user
              WHERE new_user.family_group_id = old_user.family_group_id
                AND new_user.user_id = aup.app_user_id
          )
        """,
        """
        UPDATE family_group_users fgu
        SET user_id = aup.app_user_id,
            updated_at = CURRENT_TIMESTAMP
        FROM app_user_profiles aup
        WHERE fgu.user_id = aup.unified_user_id
          AND aup.role = 'parent'
          AND aup.app_user_id <> aup.unified_user_id
        """,
        """
        UPDATE family_groups fg
        SET created_by = aup.app_user_id,
            updated_at = CURRENT_TIMESTAMP
        FROM app_user_profiles aup
        WHERE fg.created_by = aup.unified_user_id
          AND aup.role = 'parent'
          AND aup.app_user_id <> aup.unified_user_id
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_family_groups_created_by_name ON family_groups(created_by, name)",
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
        "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(64)",
        """
        CREATE TABLE IF NOT EXISTS rules (
            id SERIAL PRIMARY KEY,
            name VARCHAR(200) NOT NULL,
            category VARCHAR(50),
            points NUMERIC(10,2) DEFAULT 0,
            cash_cny NUMERIC(10,2) DEFAULT 0,
            description TEXT,
            owner_app_user_id VARCHAR(100),
            source_redline_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        "ALTER TABLE rules ADD COLUMN IF NOT EXISTS owner_app_user_id VARCHAR(100)",
        "ALTER TABLE rules ADD COLUMN IF NOT EXISTS source_redline_id INTEGER",
        """
        CREATE TABLE IF NOT EXISTS user_rule_templates (
            parent_app_user_id VARCHAR(100) PRIMARY KEY,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS user_rule_template_items (
            parent_app_user_id VARCHAR(100) NOT NULL REFERENCES user_rule_templates(parent_app_user_id) ON DELETE CASCADE,
            rule_id INTEGER NOT NULL REFERENCES rules(id) ON DELETE CASCADE,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (parent_app_user_id, rule_id)
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
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_tx_idempotency_key ON transactions(idempotency_key) WHERE idempotency_key IS NOT NULL AND idempotency_key <> ''",
        "CREATE INDEX IF NOT EXISTS idx_rules_owner ON rules(owner_app_user_id)",
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_rules_source_redline ON rules(source_redline_id) WHERE source_redline_id IS NOT NULL",
        "CREATE INDEX IF NOT EXISTS idx_user_rule_template_items_order ON user_rule_template_items(parent_app_user_id, sort_order)",
        "CREATE INDEX IF NOT EXISTS idx_children_family_group ON children(family_group_id)",
        "CREATE INDEX IF NOT EXISTS idx_family_groups_created_by ON family_groups(created_by)",
        "CREATE INDEX IF NOT EXISTS idx_family_group_users_user ON family_group_users(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_family_group_invites_code ON family_group_invites(invite_code) WHERE revoked_at IS NULL",
        "CREATE INDEX IF NOT EXISTS idx_app_user_profiles_unified ON app_user_profiles(unified_user_id)",
        "CREATE INDEX IF NOT EXISTS idx_child_user_bindings_parent ON child_user_bindings(parent_app_user_id)",
        "CREATE INDEX IF NOT EXISTS idx_child_user_bindings_child ON child_user_bindings(child_profile_key)",
        "CREATE INDEX IF NOT EXISTS idx_household_members_owner ON household_members(owner_parent_app_user_id, created_at)",
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_household_members_current_user ON household_members(owner_parent_app_user_id) WHERE is_current_user",
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
        "CREATE INDEX IF NOT EXISTS idx_watch_reward_requests_status ON watch_reward_requests(status)",
        "CREATE INDEX IF NOT EXISTS idx_child_friend_codes_child ON child_friend_codes(child_profile_key, expires_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_child_friendships_a ON child_friendships(child_profile_key_a)",
        "CREATE INDEX IF NOT EXISTS idx_child_friendships_b ON child_friendships(child_profile_key_b)",
        "CREATE INDEX IF NOT EXISTS idx_child_friend_notifications_parent ON child_friend_notifications(parent_app_user_id, read_at, created_at DESC)"
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

    await using var syncCmd = new NpgsqlCommand("""
        INSERT INTO rules (name, category, points, cash_cny, description, source_redline_id)
        SELECT rule, '红线', -ABS(COALESCE(penalty_points, 0)), 0, description, id
        FROM redlines
        WHERE rule IS NOT NULL AND BTRIM(rule) <> ''
        ORDER BY order_num, id
        ON CONFLICT DO NOTHING
        """, conn);
    await syncCmd.ExecuteNonQueryAsync();
}

static async Task<int> EnsureFamilyGroup(NpgsqlConnection conn, string name, string userId, string description = "")
{
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO family_groups (name, description, created_by)
        VALUES (@name, @description, @created_by)
        ON CONFLICT (created_by, name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
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
    var normalizedUserId = string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId;
    var rows = await QueryFamilyGroups(conn, normalizedUserId);
    if (rows.Count > 0)
    {
        return rows;
    }

    await EnsureFamilyGroup(conn, DefaultFamilyGroupName, normalizedUserId);
    return await QueryFamilyGroups(conn, normalizedUserId);
}

static async Task<List<Dictionary<string, object?>>> QueryFamilyGroups(NpgsqlConnection conn, string userId)
{
    await using var cmd = new NpgsqlCommand("""
        SELECT fg.id, fg.name, fg.description, fg.created_by, fgu.role, fg.created_at, fg.updated_at
        FROM family_groups fg
        LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.created_by = @user_id OR fgu.user_id = @user_id OR @user_id = @default_user_id
        ORDER BY fg.id
        """, conn);
    cmd.Parameters.AddWithValue("user_id", userId);
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
        return (false, null, "圈子名称不能为空");
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

static async Task<(bool Success, bool Forbidden, bool NotFound, Dictionary<string, object?>? Group, string Error)> UpdateFamilyGroup(
    string connectionString,
    int familyGroupId,
    string name,
    string operatorAppUserId,
    string description)
{
    name = name.Trim();
    if (string.IsNullOrWhiteSpace(name))
    {
        return (false, false, false, null, "圈子名称不能为空");
    }

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        bool? canManage = null;
        await using (var accessCmd = new NpgsqlCommand("""
            SELECT (fg.created_by = @operator_app_user_id OR EXISTS (
                       SELECT 1
                       FROM family_group_users fgu
                       WHERE fgu.family_group_id = fg.id
                         AND fgu.user_id = @operator_app_user_id
                         AND fgu.role = 'owner'
                   ) OR @operator_app_user_id = @default_user_id) AS can_manage
            FROM family_groups fg
            WHERE fg.id = @family_group_id
            FOR UPDATE
            """, conn, tx))
        {
            accessCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            accessCmd.Parameters.AddWithValue("operator_app_user_id", operatorAppUserId);
            accessCmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
            await using var reader = await accessCmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                canManage = reader.GetBoolean(reader.GetOrdinal("can_manage"));
            }
        }

        if (canManage is null)
        {
            await tx.RollbackAsync();
            return (false, false, true, null, "圈子不存在");
        }
        if (canManage is false)
        {
            await tx.RollbackAsync();
            return (false, true, false, null, "只有圈子创建者或管理员可以修改圈子");
        }

        await using (var updateCmd = new NpgsqlCommand("""
            UPDATE family_groups
            SET name = @name,
                description = @description,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = @family_group_id
            """, conn, tx))
        {
            updateCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            updateCmd.Parameters.AddWithValue("name", name);
            updateCmd.Parameters.AddWithValue("description", description.Trim());
            await updateCmd.ExecuteNonQueryAsync();
        }

        Dictionary<string, object?> group;
        await using (var readCmd = new NpgsqlCommand("""
            SELECT fg.id, fg.name, fg.description, fg.created_by, fgu.role, fg.created_at, fg.updated_at
            FROM family_groups fg
            LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @operator_app_user_id
            WHERE fg.id = @family_group_id
            """, conn, tx))
        {
            readCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            readCmd.Parameters.AddWithValue("operator_app_user_id", operatorAppUserId);
            await using var reader = await readCmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            group = ReadFamilyGroup(reader);
        }

        await tx.CommitAsync();
        return (true, false, false, group, "");
    }
    catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
    {
        await tx.RollbackAsync();
        return (false, false, false, null, "你已经有同名圈子");
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return (false, false, false, null, ex.Message);
    }
}

static async Task<(bool Success, bool Forbidden, string FamilyGroupName, int RemovedChildren, string Error)> DeleteFamilyGroup(
    string connectionString,
    int familyGroupId,
    string operatorAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        string familyGroupName = "";
        bool? canManage = null;
        await using (var groupCmd = new NpgsqlCommand("""
            SELECT fg.name,
                   (fg.created_by = @operator_app_user_id OR EXISTS (
                       SELECT 1
                       FROM family_group_users fgu
                       WHERE fgu.family_group_id = fg.id
                         AND fgu.user_id = @operator_app_user_id
                         AND fgu.role = 'owner'
                   ) OR @operator_app_user_id = @default_user_id) AS can_manage
            FROM family_groups fg
            WHERE fg.id = @family_group_id
            FOR UPDATE
            """, conn, tx))
        {
            groupCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            groupCmd.Parameters.AddWithValue("operator_app_user_id", operatorAppUserId);
            groupCmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
            await using var reader = await groupCmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                familyGroupName = reader.String("name");
                canManage = reader.GetBoolean(reader.GetOrdinal("can_manage"));
            }
        }
        if (canManage is null)
        {
            await tx.RollbackAsync();
            return (false, false, "", 0, "圈子不存在");
        }
        if (canManage is false)
        {
            await tx.RollbackAsync();
            return (false, true, familyGroupName, 0, "只有圈子创建者或管理员可以删除圈子");
        }

        await using (var codeCmd = new NpgsqlCommand("""
            UPDATE child_auth_codes
            SET used_at = CURRENT_TIMESTAMP
            WHERE family_group_id = @family_group_id
              AND used_at IS NULL
            """, conn, tx))
        {
            codeCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            await codeCmd.ExecuteNonQueryAsync();
        }

        await using (var deviceCmd = new NpgsqlCommand("""
            UPDATE watch_device_bindings
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE family_group_id = @family_group_id
              AND revoked_at IS NULL
            """, conn, tx))
        {
            deviceCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            await deviceCmd.ExecuteNonQueryAsync();
        }

        await using (var accountCmd = new NpgsqlCommand("""
            WITH group_children AS (
                SELECT id, profile_key
                FROM children
                WHERE family_group_id = @family_group_id
            ), replacements AS (
                SELECT gc.id AS old_id,
                       (
                           SELECT c2.id
                           FROM children c2
                           WHERE c2.profile_key = gc.profile_key
                             AND c2.id <> gc.id
                             AND c2.family_group_id IS NOT NULL
                           ORDER BY c2.id
                           LIMIT 1
                       ) AS replacement_id
                FROM group_children gc
            )
            UPDATE accounts a
            SET child_id = r.replacement_id,
                updated_at = CURRENT_TIMESTAMP
            FROM replacements r
            WHERE a.child_id = r.old_id
              AND r.replacement_id IS NOT NULL
            """, conn, tx))
        {
            accountCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            await accountCmd.ExecuteNonQueryAsync();
        }

        int removedChildren;
        await using (var childCmd = new NpgsqlCommand("""
            WITH group_children AS (
                SELECT id, profile_key
                FROM children
                WHERE family_group_id = @family_group_id
                FOR UPDATE
            ), replacements AS (
                SELECT gc.id,
                       EXISTS (
                           SELECT 1
                           FROM children c2
                           WHERE c2.profile_key = gc.profile_key
                             AND c2.id <> gc.id
                             AND c2.family_group_id IS NOT NULL
                       ) AS has_replacement
                FROM group_children gc
            ), deleted AS (
                DELETE FROM children c
                USING replacements r
                WHERE c.id = r.id
                  AND r.has_replacement
                RETURNING c.id
            ), detached AS (
                UPDATE children c
                SET family_group_id = NULL,
                    updated_at = CURRENT_TIMESTAMP
                FROM replacements r
                WHERE c.id = r.id
                  AND NOT r.has_replacement
                RETURNING c.id
            )
            SELECT (SELECT COUNT(*) FROM deleted) + (SELECT COUNT(*) FROM detached)
            """, conn, tx))
        {
            childCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            removedChildren = Convert.ToInt32(await childCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
        }

        await using (var deleteCmd = new NpgsqlCommand("DELETE FROM family_groups WHERE id = @family_group_id", conn, tx))
        {
            deleteCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
            await deleteCmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return (true, false, familyGroupName, removedChildren, "");
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return (false, false, "", 0, ex.Message);
    }
}

static async Task<(bool Success, bool Forbidden, string Error)> UpsertFamilyGroupUser(
    string connectionString,
    int familyGroupId,
    string userId,
    string role,
    string operatorAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using (var accessCmd = new NpgsqlCommand("""
        SELECT fg.id,
               (fg.created_by = @operator_app_user_id OR EXISTS (
                   SELECT 1
                   FROM family_group_users fgu
                   WHERE fgu.family_group_id = fg.id
                     AND fgu.user_id = @operator_app_user_id
                     AND fgu.role = 'owner'
               )) AS can_manage
        FROM family_groups fg
        WHERE fg.id = @id
        """, conn))
    {
        accessCmd.Parameters.AddWithValue("id", familyGroupId);
        accessCmd.Parameters.AddWithValue("operator_app_user_id", operatorAppUserId);
        await using var reader = await accessCmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            return (false, false, "圈子不存在");
        }
        if (!reader.GetBoolean(reader.GetOrdinal("can_manage")))
        {
            return (false, true, "只有圈子创建者或管理员可以管理成员");
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
    await SyncOwnedChildrenToFamilyGroup(conn, familyGroupId, userId.Trim(), $"由 {operatorAppUserId} 加入圈子");
    return (true, false, "");
}

static async Task<(bool Success, bool Forbidden, List<Dictionary<string, object?>> Children, string Error)> GetFamilyGroupChildren(
    string connectionString,
    int familyGroupId,
    string appUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using (var accessCmd = new NpgsqlCommand("""
        SELECT COUNT(*)
        FROM family_groups fg
        LEFT JOIN family_group_users fgu
          ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.id = @family_group_id
          AND (fg.created_by = @user_id OR fgu.user_id = @user_id OR @user_id = @default_user_id)
        """, conn))
    {
        accessCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        accessCmd.Parameters.AddWithValue("user_id", appUserId);
        accessCmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
        var canView = Convert.ToInt32(await accessCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0;
        if (!canView)
        {
            await using var existsCmd = new NpgsqlCommand("SELECT COUNT(*) FROM family_groups WHERE id = @id", conn);
            existsCmd.Parameters.AddWithValue("id", familyGroupId);
            var exists = Convert.ToInt32(await existsCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0;
            return (false, exists, [], exists ? "你不是该圈子成员" : "圈子不存在");
        }
    }

    await using var cmd = new NpgsqlCommand("""
        SELECT c.id, c.family_group_id, c.profile_key,
               COALESCE(cp.name, c.name) AS name,
               COALESCE(cp.status, c.status) AS status,
               COALESCE(cp.note, c.note) AS note,
               COALESCE(cp.created_at, c.created_at) AS created_at,
               COALESCE(cp.updated_at, c.updated_at) AS updated_at,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items,
               COALESCE(
                   string_agg(DISTINCT COALESCE(NULLIF(aup.username, ''), cub.parent_app_user_id), '、')
                       FILTER (WHERE cub.parent_app_user_id IS NOT NULL),
                   ''
               ) AS parent_names
        FROM children c
        LEFT JOIN child_profiles cp ON cp.profile_key = c.profile_key
        LEFT JOIN accounts a ON a.profile_key = c.profile_key
        LEFT JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
        LEFT JOIN app_user_profiles aup
          ON aup.app_user_id = cub.parent_app_user_id AND aup.role = 'parent'
        WHERE c.family_group_id = @family_group_id
          AND COALESCE(cp.status, c.status) = 'active'
        GROUP BY c.id, c.family_group_id, c.profile_key, cp.name, c.name, cp.status, c.status,
                 cp.note, c.note, cp.created_at, c.created_at, cp.updated_at, c.updated_at,
                 a.points, a.cash_cny, a.items_count
        ORDER BY COALESCE(cp.name, c.name), c.id
        """, conn);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    var children = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        children.Add(new Dictionary<string, object?>
        {
            ["id"] = reader.Int("id"),
            ["familyGroupId"] = reader.Int("family_group_id"),
            ["family_group_id"] = reader.Int("family_group_id"),
            ["profileKey"] = reader.String("profile_key"),
            ["profile_key"] = reader.String("profile_key"),
            ["name"] = reader.String("name"),
            ["status"] = reader.String("status"),
            ["note"] = reader.String("note"),
            ["createdAt"] = reader.DateTime("created_at").ToString("O"),
            ["updatedAt"] = reader.DateTime("updated_at").ToString("O"),
            ["score"] = reader.Decimal("score"),
            ["cash"] = reader.Decimal("cash"),
            ["items"] = reader.Int("items"),
            ["parentNames"] = reader.String("parent_names"),
            ["parent_names"] = reader.String("parent_names")
        });
    }
    return (true, false, children, "");
}

static async Task<(bool Success, bool Forbidden, string Error)> RemoveChildFromFamilyGroup(
    string connectionString,
    int familyGroupId,
    int childId,
    string appUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    await using (var accessCmd = new NpgsqlCommand("""
        SELECT COUNT(*)
        FROM family_groups fg
        LEFT JOIN family_group_users fgu
          ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.id = @family_group_id
          AND (fg.created_by = @user_id OR fgu.role = 'owner' OR @user_id = @default_user_id)
        """, conn, tx))
    {
        accessCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        accessCmd.Parameters.AddWithValue("user_id", appUserId);
        accessCmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
        var canManage = Convert.ToInt32(await accessCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0;
        if (!canManage)
        {
            await using var existsCmd = new NpgsqlCommand("SELECT COUNT(*) FROM family_groups WHERE id = @id", conn, tx);
            existsCmd.Parameters.AddWithValue("id", familyGroupId);
            var exists = Convert.ToInt32(await existsCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) > 0;
            await tx.RollbackAsync();
            return (false, exists, exists ? "只有圈子管理员可以移除孩子成员" : "圈子不存在");
        }
    }

    string profileKey;
    await using (var childCmd = new NpgsqlCommand("""
        SELECT profile_key
        FROM children
        WHERE id = @child_id AND family_group_id = @family_group_id
        FOR UPDATE
        """, conn, tx))
    {
        childCmd.Parameters.AddWithValue("child_id", childId);
        childCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        var value = await childCmd.ExecuteScalarAsync();
        if (value is null || value is DBNull)
        {
            await tx.RollbackAsync();
            return (false, false, "该孩子不在当前圈子中");
        }
        profileKey = Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
    }

    int? replacementChildId;
    await using (var replacementCmd = new NpgsqlCommand("""
        SELECT id
        FROM children
        WHERE profile_key = @profile_key AND id <> @child_id AND family_group_id IS NOT NULL
        ORDER BY id
        LIMIT 1
        """, conn, tx))
    {
        replacementCmd.Parameters.AddWithValue("profile_key", profileKey);
        replacementCmd.Parameters.AddWithValue("child_id", childId);
        var value = await replacementCmd.ExecuteScalarAsync();
        replacementChildId = value is null || value is DBNull
            ? null
            : Convert.ToInt32(value, CultureInfo.InvariantCulture);
    }

    await using (var codeCmd = new NpgsqlCommand("""
        UPDATE child_auth_codes
        SET used_at = CURRENT_TIMESTAMP
        WHERE child_id = @child_id AND family_group_id = @family_group_id AND used_at IS NULL
        """, conn, tx))
    {
        codeCmd.Parameters.AddWithValue("child_id", childId);
        codeCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        await codeCmd.ExecuteNonQueryAsync();
    }
    await using (var deviceCmd = new NpgsqlCommand("""
        UPDATE watch_device_bindings
        SET revoked_at = CURRENT_TIMESTAMP
        WHERE child_id = @child_id AND family_group_id = @family_group_id AND revoked_at IS NULL
        """, conn, tx))
    {
        deviceCmd.Parameters.AddWithValue("child_id", childId);
        deviceCmd.Parameters.AddWithValue("family_group_id", familyGroupId);
        await deviceCmd.ExecuteNonQueryAsync();
    }

    if (replacementChildId is null)
    {
        await using var detachCmd = new NpgsqlCommand("""
            UPDATE children
            SET family_group_id = NULL, updated_at = CURRENT_TIMESTAMP
            WHERE id = @child_id
            """, conn, tx);
        detachCmd.Parameters.AddWithValue("child_id", childId);
        await detachCmd.ExecuteNonQueryAsync();
    }
    else
    {
        await using (var accountCmd = new NpgsqlCommand("UPDATE accounts SET child_id = @replacement_id WHERE child_id = @child_id", conn, tx))
        {
            accountCmd.Parameters.AddWithValue("replacement_id", replacementChildId.Value);
            accountCmd.Parameters.AddWithValue("child_id", childId);
            await accountCmd.ExecuteNonQueryAsync();
        }
        await using var deleteCmd = new NpgsqlCommand("DELETE FROM children WHERE id = @child_id", conn, tx);
        deleteCmd.Parameters.AddWithValue("child_id", childId);
        await deleteCmd.ExecuteNonQueryAsync();
    }

    await tx.CommitAsync();
    return (true, false, "");
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
            return (false, exists, "", "", exists ? "只有圈子管理员可以生成邀请码" : "圈子不存在");
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

static string NormalizeHouseholdRole(string? role)
{
    var normalized = (role ?? "").Trim().ToLowerInvariant();
    return normalized is "father" or "mother" or "grandfather" or "grandmother"
        or "maternal_grandfather" or "maternal_grandmother" or "guardian" or "other"
        ? normalized
        : "";
}

static async Task<List<Dictionary<string, object?>>> GetHouseholdMembers(NpgsqlConnection conn, string parentAppUserId)
{
    var members = new List<Dictionary<string, object?>>();
    await using var cmd = new NpgsqlCommand("""
        SELECT id, display_name, role, note, is_current_user, created_at, updated_at
        FROM household_members
        WHERE owner_parent_app_user_id = @owner_parent_app_user_id
        ORDER BY is_current_user DESC, created_at, id
        """, conn);
    cmd.Parameters.AddWithValue("owner_parent_app_user_id", parentAppUserId);
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync()) members.Add(ReadHouseholdMember(reader));
    return members;
}

static Dictionary<string, object?> ReadHouseholdMember(NpgsqlDataReader reader) => new()
{
    ["id"] = reader.GetInt32(reader.GetOrdinal("id")),
    ["displayName"] = reader.String("display_name"),
    ["role"] = reader.String("role"),
    ["note"] = reader.IsDBNull(reader.GetOrdinal("note")) ? "" : reader.String("note"),
    ["isCurrentUser"] = reader.GetBoolean(reader.GetOrdinal("is_current_user")),
    ["createdAt"] = reader.GetDateTime(reader.GetOrdinal("created_at")),
    ["updatedAt"] = reader.GetDateTime(reader.GetOrdinal("updated_at"))
};

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
    var familyGroupId = await EnsureFamilyGroup(conn, $"{username}的圈子", parentAppUserId);
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
        """, conn, tx);
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

static bool HasFamilyGroupSelector(HttpRequest request, JsonObject? body = null)
{
    if (body?.Int("family_group_id") is not null || body?.Int("familyGroupId") is not null)
    {
        return true;
    }
    if (!string.IsNullOrWhiteSpace(body?.String("family_group_name")) || !string.IsNullOrWhiteSpace(body?.String("familyGroupName")))
    {
        return true;
    }
    if (request.Query.Int("familyGroupId") is not null || request.Query.Int("family_group_id") is not null)
    {
        return true;
    }
    return !string.IsNullOrWhiteSpace(request.Query.String("familyGroupName")) || !string.IsNullOrWhiteSpace(request.Query.String("family_group_name"));
}

static async Task<int> ResolveInitialFamilyGroupIdForChild(
    string connectionString,
    HttpRequest request,
    JsonObject body,
    string parentAppUserId)
{
    if (HasFamilyGroupSelector(request, body))
    {
        return await ResolveFamilyGroupId(connectionString, request, body);
    }

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT fg.id
        FROM family_groups fg
        LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
        WHERE fg.created_by = @user_id OR fgu.user_id = @user_id
        ORDER BY fg.id
        LIMIT 1
        """, conn);
    cmd.Parameters.AddWithValue("user_id", parentAppUserId);
    var result = await cmd.ExecuteScalarAsync();
    if (result is not null && result is not DBNull)
    {
        return Convert.ToInt32(result, CultureInfo.InvariantCulture);
    }

    return await EnsureFamilyGroup(conn, DefaultFamilyGroupName, parentAppUserId);
}

static async Task<int> ResolveChildFamilyGroupId(
    string connectionString,
    HttpRequest request,
    JsonObject? body,
    int childId,
    string parentAppUserId)
{
    if (HasFamilyGroupSelector(request, body))
    {
        return await ResolveFamilyGroupId(connectionString, request, body);
    }

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT c.family_group_id
        FROM children c
        JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
        WHERE c.id = @child_id
          AND c.status = 'active'
          AND cub.parent_app_user_id = @parent_app_user_id
        ORDER BY c.id
        LIMIT 1
        """, conn);
    cmd.Parameters.AddWithValue("child_id", childId);
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    var result = await cmd.ExecuteScalarAsync();
    return result is not null && result is not DBNull
        ? Convert.ToInt32(result, CultureInfo.InvariantCulture)
        : -1;
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

static string GetUnifiedContact(HttpRequest request) =>
    FirstClaim(request, ClaimTypes.Email, "email", ClaimTypes.MobilePhone, "phone_number", "phone") ?? "";

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

static async Task<List<Dictionary<string, object?>>> GetChildren(
    string connectionString,
    int? familyGroupId = null,
    string? childProfileKey = null,
    string? ownerAppUserId = null)
{
    await using var conn = await OpenConnection(connectionString);
    if (!string.IsNullOrWhiteSpace(ownerAppUserId) && familyGroupId is null)
    {
        await using var ownedCmd = new NpgsqlCommand("""
            SELECT COALESCE(rep.id, cub.child_id, 0) AS id,
                   rep.family_group_id,
                   fg.name AS family_group_name,
                   cub.child_profile_key AS profile_key,
                   cp.name,
                   cp.status,
                   cp.note,
                   cp.created_at,
                   cp.updated_at,
                   COALESCE(a.points, 0) AS score,
                   COALESCE(a.cash_cny, 0) AS cash,
                   COALESCE(a.items_count, 0) AS items
            FROM child_user_bindings cub
            JOIN child_profiles cp ON cp.profile_key = cub.child_profile_key
            LEFT JOIN LATERAL (
                SELECT c.id, c.family_group_id
                FROM children c
                WHERE c.profile_key = cub.child_profile_key
                  AND c.status = 'active'
                ORDER BY CASE WHEN c.id = cub.child_id THEN 0 ELSE 1 END, c.id
                LIMIT 1
            ) rep ON true
            LEFT JOIN family_groups fg ON fg.id = rep.family_group_id
            LEFT JOIN accounts a ON a.profile_key = cub.child_profile_key
            WHERE cub.parent_app_user_id = @owner_app_user_id
              AND cp.status = 'active'
              AND (@child_profile_key IS NULL OR cub.child_profile_key = @child_profile_key)
            ORDER BY cp.name, cub.child_profile_key
            """, conn);
        ownedCmd.Parameters.Add(new NpgsqlParameter("owner_app_user_id", NpgsqlDbType.Varchar)
        {
            Value = ownerAppUserId
        });
        ownedCmd.Parameters.Add(new NpgsqlParameter("child_profile_key", NpgsqlDbType.Varchar)
        {
            Value = string.IsNullOrWhiteSpace(childProfileKey) ? DBNull.Value : childProfileKey
        });

        var ownedRows = new List<Dictionary<string, object?>>();
        await using var ownedReader = await ownedCmd.ExecuteReaderAsync();
        while (await ownedReader.ReadAsync())
        {
            ownedRows.Add(new Dictionary<string, object?>
            {
                ["id"] = ownedReader.Int("id"),
                ["familyGroupId"] = ownedReader.Int("family_group_id"),
                ["family_group_id"] = ownedReader.Int("family_group_id"),
                ["familyGroupName"] = ownedReader.String("family_group_name"),
                ["family_group_name"] = ownedReader.String("family_group_name"),
                ["profileKey"] = ownedReader.String("profile_key"),
                ["profile_key"] = ownedReader.String("profile_key"),
                ["name"] = ownedReader.String("name"),
                ["status"] = ownedReader.String("status"),
                ["note"] = ownedReader.String("note"),
                ["createdAt"] = ownedReader.DateTime("created_at").ToString("O"),
                ["updatedAt"] = ownedReader.DateTime("updated_at").ToString("O"),
                ["score"] = ownedReader.Decimal("score"),
                ["cash"] = ownedReader.Decimal("cash"),
                ["items"] = ownedReader.Int("items")
            });
        }
        return ownedRows;
    }

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
          AND (@family_group_id IS NOT NULL OR c.family_group_id IS NOT NULL)
          AND (@child_profile_key IS NULL OR c.profile_key = @child_profile_key)
          AND (
              @owner_app_user_id IS NULL OR EXISTS (
                  SELECT 1
                  FROM child_user_bindings cub
                  WHERE cub.child_profile_key = c.profile_key
                    AND cub.parent_app_user_id = @owner_app_user_id
              )
          )
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
    cmd.Parameters.Add(new NpgsqlParameter("owner_app_user_id", NpgsqlDbType.Varchar)
    {
        Value = string.IsNullOrWhiteSpace(ownerAppUserId) ? DBNull.Value : ownerAppUserId
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

static async Task<Dictionary<string, object>> GetRules(string connectionString, string? parentAppUserId = null)
{
    await using var conn = await OpenConnection(connectionString);
    var publicRules = await ReadRules(conn, "owner_app_user_id IS NULL");
    var personalRules = string.IsNullOrWhiteSpace(parentAppUserId)
        ? new List<Dictionary<string, object?>>()
        : await ReadRules(conn, "owner_app_user_id = @parent_app_user_id", parentAppUserId);

    var hasTemplate = false;
    var rules = publicRules;
    if (!string.IsNullOrWhiteSpace(parentAppUserId))
    {
        await using (var templateCmd = new NpgsqlCommand("SELECT EXISTS (SELECT 1 FROM user_rule_templates WHERE parent_app_user_id = @parent_app_user_id)", conn))
        {
            templateCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            hasTemplate = Convert.ToBoolean(await templateCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
        }
        if (hasTemplate)
        {
            rules = new List<Dictionary<string, object?>>();
            await using var cmd = new NpgsqlCommand("""
                SELECT r.*
                FROM user_rule_template_items item
                JOIN rules r ON r.id = item.rule_id
                WHERE item.parent_app_user_id = @parent_app_user_id
                  AND (r.owner_app_user_id IS NULL OR r.owner_app_user_id = @parent_app_user_id)
                ORDER BY item.sort_order, r.id
                """, conn);
            cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) rules.Add(ReadRule(reader));
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

    return new Dictionary<string, object>
    {
        ["rules"] = rules,
        ["publicRules"] = publicRules,
        ["personalRules"] = personalRules,
        ["templateRuleIds"] = rules.Select(rule => GetInt(rule, "id")).ToList(),
        ["hasTemplate"] = hasTemplate,
        ["redlines"] = redlines
    };
}

static async Task<List<Dictionary<string, object?>>> ReadRules(
    NpgsqlConnection conn,
    string whereSql,
    string? parentAppUserId = null)
{
    var rules = new List<Dictionary<string, object?>>();
    await using var cmd = new NpgsqlCommand($"SELECT * FROM rules WHERE {whereSql} ORDER BY id", conn);
    if (!string.IsNullOrWhiteSpace(parentAppUserId)) cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync()) rules.Add(ReadRule(reader));
    return rules;
}

static async Task<Dictionary<string, object?>> CreatePersonalRule(
    string connectionString,
    string parentAppUserId,
    JsonObject body)
{
    var name = body.String("name").Trim();
    if (string.IsNullOrWhiteSpace(name)) return new Dictionary<string, object?> { ["error"] = "规则名称不能为空" };

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var hadTemplate = false;
        await using (var existsCmd = new NpgsqlCommand("SELECT EXISTS (SELECT 1 FROM user_rule_templates WHERE parent_app_user_id = @parent_app_user_id)", conn, tx))
        {
            existsCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            hadTemplate = Convert.ToBoolean(await existsCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
        }
        await using (var templateCmd = new NpgsqlCommand("""
            INSERT INTO user_rule_templates (parent_app_user_id)
            VALUES (@parent_app_user_id)
            ON CONFLICT (parent_app_user_id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            """, conn, tx))
        {
            templateCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await templateCmd.ExecuteNonQueryAsync();
        }
        if (!hadTemplate)
        {
            await using var seedCmd = new NpgsqlCommand("""
                INSERT INTO user_rule_template_items (parent_app_user_id, rule_id, sort_order)
                SELECT @parent_app_user_id, id, (ROW_NUMBER() OVER (ORDER BY id) - 1)::INTEGER
                FROM rules
                WHERE owner_app_user_id IS NULL
                ORDER BY id
                """, conn, tx);
            seedCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await seedCmd.ExecuteNonQueryAsync();
        }

        Dictionary<string, object?> rule;
        await using (var insertCmd = new NpgsqlCommand("""
            INSERT INTO rules (name, category, points, cash_cny, description, owner_app_user_id)
            VALUES (@name, @category, @points, @cash_cny, @description, @owner_app_user_id)
            RETURNING *
            """, conn, tx))
        {
            insertCmd.Parameters.AddWithValue("name", name);
            insertCmd.Parameters.AddWithValue("category", body.String("category"));
            insertCmd.Parameters.AddWithValue("points", NormalizeRulePoints(body));
            insertCmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash_cny") ?? 0);
            insertCmd.Parameters.AddWithValue("description", body.String("description"));
            insertCmd.Parameters.AddWithValue("owner_app_user_id", parentAppUserId);
            await using var reader = await insertCmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            rule = ReadRule(reader);
        }

        await using (var itemCmd = new NpgsqlCommand("""
            INSERT INTO user_rule_template_items (parent_app_user_id, rule_id, sort_order)
            SELECT @parent_app_user_id, @rule_id, COALESCE(MAX(sort_order), -1) + 1
            FROM user_rule_template_items
            WHERE parent_app_user_id = @parent_app_user_id
            """, conn, tx))
        {
            itemCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            itemCmd.Parameters.AddWithValue("rule_id", GetInt(rule, "id"));
            await itemCmd.ExecuteNonQueryAsync();
        }
        await tx.CommitAsync();
        return new Dictionary<string, object?> { ["rule"] = rule, ["hasTemplate"] = true };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> SaveRuleTemplate(
    string connectionString,
    string parentAppUserId,
    IReadOnlyList<int> ruleIds)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        if (ruleIds.Count > 0)
        {
            await using var validateCmd = new NpgsqlCommand("""
                SELECT COUNT(*)
                FROM rules
                WHERE id = ANY(@rule_ids)
                  AND (owner_app_user_id IS NULL OR owner_app_user_id = @parent_app_user_id)
                """, conn, tx);
            validateCmd.Parameters.AddWithValue("rule_ids", NpgsqlDbType.Array | NpgsqlDbType.Integer, ruleIds.ToArray());
            validateCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            var allowedCount = Convert.ToInt32(await validateCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
            if (allowedCount != ruleIds.Count)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "模板包含不存在或不属于当前家长的规则" };
            }
        }

        await using (var templateCmd = new NpgsqlCommand("""
            INSERT INTO user_rule_templates (parent_app_user_id)
            VALUES (@parent_app_user_id)
            ON CONFLICT (parent_app_user_id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            """, conn, tx))
        {
            templateCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await templateCmd.ExecuteNonQueryAsync();
        }
        await using (var deleteCmd = new NpgsqlCommand("DELETE FROM user_rule_template_items WHERE parent_app_user_id = @parent_app_user_id", conn, tx))
        {
            deleteCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await deleteCmd.ExecuteNonQueryAsync();
        }
        for (var index = 0; index < ruleIds.Count; index++)
        {
            await using var itemCmd = new NpgsqlCommand("""
                INSERT INTO user_rule_template_items (parent_app_user_id, rule_id, sort_order)
                VALUES (@parent_app_user_id, @rule_id, @sort_order)
                """, conn, tx);
            itemCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            itemCmd.Parameters.AddWithValue("rule_id", ruleIds[index]);
            itemCmd.Parameters.AddWithValue("sort_order", index);
            await itemCmd.ExecuteNonQueryAsync();
        }
        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["status"] = "ok",
            ["hasTemplate"] = true,
            ["templateRuleIds"] = ruleIds
        };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
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

static async Task<Dictionary<string, object?>> CreateTransaction(
    string connectionString,
    JsonObject body,
    int? familyGroupId = null,
    string? parentAppUserId = null)
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
        var idempotencyKey = body.String("idempotency_key").Trim();

        if (!string.IsNullOrWhiteSpace(parentAppUserId))
        {
            await using var ownerCmd = new NpgsqlCommand("""
                SELECT COUNT(*)
                FROM children c
                JOIN child_user_bindings cub ON cub.child_profile_key = c.profile_key
                WHERE c.id = @child_id
                  AND cub.parent_app_user_id = @parent_app_user_id
                  AND c.status = 'active'
                """, conn, tx);
            ownerCmd.Parameters.AddWithValue("child_id", childId);
            ownerCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            if (Convert.ToInt32(await ownerCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "只能操作自己名下的孩子" };
            }
        }
        else if (familyGroupId is not null)
        {
            await using var childCmd = new NpgsqlCommand("SELECT COUNT(*) FROM children WHERE id = @child_id AND family_group_id = @family_group_id", conn, tx);
            childCmd.Parameters.AddWithValue("child_id", childId);
            childCmd.Parameters.AddWithValue("family_group_id", familyGroupId.Value);
            if (Convert.ToInt32(await childCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "孩子不属于当前圈子" };
            }
        }

        await using var cmd = new NpgsqlCommand("""
            INSERT INTO transactions (date, child_id, type, direction, category, description, points, cash_cny, items, notes, idempotency_key)
            VALUES (@date, @child_id, @type, @direction, @category, @description, @points, @cash_cny, @items, @notes, @idempotency_key)
            ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL AND idempotency_key <> '' DO NOTHING
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
        cmd.Parameters.Add(new NpgsqlParameter("idempotency_key", NpgsqlDbType.Varchar)
        {
            Value = string.IsNullOrWhiteSpace(idempotencyKey) ? DBNull.Value : idempotencyKey
        });

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            await reader.CloseAsync();
            await using var existingCmd = new NpgsqlCommand("SELECT * FROM transactions WHERE idempotency_key = @idempotency_key", conn, tx);
            existingCmd.Parameters.AddWithValue("idempotency_key", idempotencyKey);
            await using var existingReader = await existingCmd.ExecuteReaderAsync();
            if (!await existingReader.ReadAsync())
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "积分请求幂等冲突，请稍后重试" };
            }
            var existingTransaction = ReadTransaction(existingReader);
            await existingReader.CloseAsync();
            await tx.CommitAsync();
            return new Dictionary<string, object?>
            {
                ["transaction"] = existingTransaction,
                ["status"] = "ok",
                ["deduplicated"] = true
            };
        }
        var transaction = ReadTransaction(reader);
        await reader.CloseAsync();

        await UpdateAccount(conn, tx, childId, type, direction, points, cash, itemText);
        await tx.CommitAsync();

        return new Dictionary<string, object?> { ["transaction"] = transaction, ["status"] = "ok", ["deduplicated"] = false };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>> DeleteChildMembership(string connectionString, int id, string parentAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        string profileKey;
        await using (var lookup = new NpgsqlCommand("""
            SELECT COALESCE(c.profile_key, cub.child_profile_key) AS profile_key
            FROM child_user_bindings cub
            LEFT JOIN children c
              ON c.profile_key = cub.child_profile_key
             AND c.id = @id
            WHERE cub.parent_app_user_id = @parent_app_user_id
              AND (c.id IS NOT NULL OR cub.child_id = @id)
            ORDER BY CASE WHEN c.id IS NOT NULL THEN 0 ELSE 1 END
            LIMIT 1
            FOR UPDATE OF cub
            """, conn, tx))
        {
            lookup.Parameters.AddWithValue("id", id);
            lookup.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            var value = await lookup.ExecuteScalarAsync();
            if (value is null || value is DBNull)
            {
                await tx.RollbackAsync();
                return new Dictionary<string, object?> { ["error"] = "孩子不存在，或只有孩子的所属账号可以删除" };
            }
            profileKey = Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
        }

        await using (var bindingCmd = new NpgsqlCommand("""
            DELETE FROM child_user_bindings
            WHERE parent_app_user_id = @parent_app_user_id
              AND child_profile_key = @profile_key
            """, conn, tx))
        {
            bindingCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            bindingCmd.Parameters.AddWithValue("profile_key", profileKey);
            await bindingCmd.ExecuteNonQueryAsync();
        }

        await using (var parentCodeCmd = new NpgsqlCommand("""
            UPDATE child_auth_codes
            SET used_at = CURRENT_TIMESTAMP
            WHERE child_profile_key = @profile_key
              AND parent_app_user_id = @parent_app_user_id
              AND used_at IS NULL
            """, conn, tx))
        {
            parentCodeCmd.Parameters.AddWithValue("profile_key", profileKey);
            parentCodeCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await parentCodeCmd.ExecuteNonQueryAsync();
        }

        await using (var parentDeviceCmd = new NpgsqlCommand("""
            UPDATE watch_device_bindings
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE child_profile_key = @profile_key
              AND parent_app_user_id = @parent_app_user_id
              AND revoked_at IS NULL
            """, conn, tx))
        {
            parentDeviceCmd.Parameters.AddWithValue("profile_key", profileKey);
            parentDeviceCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
            await parentDeviceCmd.ExecuteNonQueryAsync();
        }

        var remainingBindings = 0;
        await using (var remainingCmd = new NpgsqlCommand("""
            SELECT COUNT(*)
            FROM child_user_bindings
            WHERE child_profile_key = @profile_key
            """, conn, tx))
        {
            remainingCmd.Parameters.AddWithValue("profile_key", profileKey);
            remainingBindings = Convert.ToInt32(await remainingCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
        }

        if (remainingBindings == 0)
        {
            await using (var codeCmd = new NpgsqlCommand("""
                UPDATE child_auth_codes
                SET used_at = CURRENT_TIMESTAMP
                WHERE child_profile_key = @profile_key
                  AND used_at IS NULL
                """, conn, tx))
            {
                codeCmd.Parameters.AddWithValue("profile_key", profileKey);
                await codeCmd.ExecuteNonQueryAsync();
            }

            await using (var deviceCmd = new NpgsqlCommand("""
                UPDATE watch_device_bindings
                SET revoked_at = CURRENT_TIMESTAMP
                WHERE child_profile_key = @profile_key
                  AND revoked_at IS NULL
                """, conn, tx))
            {
                deviceCmd.Parameters.AddWithValue("profile_key", profileKey);
                await deviceCmd.ExecuteNonQueryAsync();
            }

            await using (var deleteCmd = new NpgsqlCommand("DELETE FROM children WHERE profile_key = @profile_key", conn, tx))
            {
                deleteCmd.Parameters.AddWithValue("profile_key", profileKey);
                await deleteCmd.ExecuteNonQueryAsync();
            }

            await using (var profileCmd = new NpgsqlCommand("""
                DELETE FROM child_profiles cp
                WHERE cp.profile_key = @profile_key
                  AND NOT EXISTS (
                      SELECT 1
                      FROM children c
                      WHERE c.profile_key = cp.profile_key
                  )
                  AND NOT EXISTS (
                      SELECT 1
                      FROM child_user_bindings cub
                      WHERE cub.child_profile_key = cp.profile_key
                  )
                """, conn, tx))
            {
                profileCmd.Parameters.AddWithValue("profile_key", profileKey);
                await profileCmd.ExecuteNonQueryAsync();
            }
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["status"] = "ok",
            ["removedOwnerBinding"] = true,
            ["deletedChildRows"] = remainingBindings == 0
        };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<Dictionary<string, object?>?> GetParentOwnedChild(string connectionString, int childId, int familyGroupId, string parentAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    return await GetChildForFamily(conn, null, childId, familyGroupId, parentAppUserId);
}

static async Task<Dictionary<string, object?>> GetWatchSettings(string connectionString, string childProfileKey)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT watch_face, updated_at
        FROM watch_face_preferences
        WHERE child_profile_key = @child_profile_key
        """, conn);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);
    await using var reader = await cmd.ExecuteReaderAsync();
    if (await reader.ReadAsync())
    {
        return new Dictionary<string, object?>
        {
            ["watchFace"] = NormalizeWatchFace(reader.String("watch_face")),
            ["updatedAt"] = reader.DateTime("updated_at").ToString("O")
        };
    }

    return new Dictionary<string, object?>
    {
        ["watchFace"] = "world",
        ["updatedAt"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
    };
}

static async Task<Dictionary<string, object?>> UpdateWatchSettings(string connectionString, string childProfileKey, string watchFace)
{
    var normalized = NormalizeWatchFace(watchFace);
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO watch_face_preferences (child_profile_key, watch_face, updated_at)
        VALUES (@child_profile_key, @watch_face, CURRENT_TIMESTAMP)
        ON CONFLICT (child_profile_key) DO UPDATE SET
            watch_face = EXCLUDED.watch_face,
            updated_at = CURRENT_TIMESTAMP
        RETURNING watch_face, updated_at
        """, conn);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);
    cmd.Parameters.AddWithValue("watch_face", normalized);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return new Dictionary<string, object?>
    {
        ["watchFace"] = reader.String("watch_face"),
        ["updatedAt"] = reader.DateTime("updated_at").ToString("O")
    };
}

static async Task<Dictionary<string, object?>> CreateWatchFriendCode(string connectionString, WatchDeviceBinding binding, int expiresInMinutes)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        await using (var expireCmd = new NpgsqlCommand("""
            UPDATE child_friend_codes
            SET used_at = CURRENT_TIMESTAMP
            WHERE child_profile_key = @child_profile_key
              AND used_at IS NULL
              AND expires_at > CURRENT_TIMESTAMP
            """, conn, tx))
        {
            expireCmd.Parameters.AddWithValue("child_profile_key", binding.ChildProfileKey);
            await expireCmd.ExecuteNonQueryAsync();
        }

        var code = "";
        var codeHash = "";
        var created = false;
        for (var i = 0; i < 8; i++)
        {
            code = GenerateNumericCode(8);
            codeHash = HashSecret(code);
            await using var existsCmd = new NpgsqlCommand("SELECT COUNT(*) FROM child_friend_codes WHERE code_hash = @code_hash", conn, tx);
            existsCmd.Parameters.AddWithValue("code_hash", codeHash);
            if (Convert.ToInt32(await existsCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
            {
                created = true;
                break;
            }
        }
        if (!created)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "好友认证码生成失败" };
        }

        var expiresAt = DateTime.UtcNow.AddMinutes(expiresInMinutes);
        await using (var insertCmd = new NpgsqlCommand("""
            INSERT INTO child_friend_codes (child_profile_key, parent_app_user_id, code_hash, expires_at)
            VALUES (@child_profile_key, @parent_app_user_id, @code_hash, @expires_at)
            """, conn, tx))
        {
            insertCmd.Parameters.AddWithValue("child_profile_key", binding.ChildProfileKey);
            insertCmd.Parameters.AddWithValue("parent_app_user_id", binding.ParentAppUserId);
            insertCmd.Parameters.AddWithValue("code_hash", codeHash);
            insertCmd.Parameters.AddWithValue("expires_at", expiresAt);
            await insertCmd.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["code"] = code,
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

static async Task<Dictionary<string, object?>> AddWatchFriendByCode(string connectionString, WatchDeviceBinding binding, string rawCode)
{
    var code = NormalizeDigits(rawCode);
    if (code.Length != 8)
    {
        return new Dictionary<string, object?> { ["error"] = "请输入 8 位好友认证码" };
    }

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        int codeId;
        string targetProfileKey;
        string targetParentAppUserId;
        await using (var lookupCmd = new NpgsqlCommand("""
            SELECT id, child_profile_key, parent_app_user_id
            FROM child_friend_codes
            WHERE code_hash = @code_hash
              AND used_at IS NULL
              AND expires_at > CURRENT_TIMESTAMP
            FOR UPDATE
            """, conn, tx))
        {
            lookupCmd.Parameters.AddWithValue("code_hash", HashSecret(code));
            await using var reader = await lookupCmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
            {
                return new Dictionary<string, object?> { ["error"] = "好友认证码无效或已过期" };
            }

            codeId = reader.Int("id");
            targetProfileKey = reader.String("child_profile_key");
            targetParentAppUserId = reader.String("parent_app_user_id");
        }

        if (string.Equals(targetProfileKey, binding.ChildProfileKey, StringComparison.Ordinal))
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "不能添加自己为好友" };
        }

        var ordered = OrderFriendKeys(binding.ChildProfileKey, targetProfileKey);
        int friendshipId;
        bool friendshipCreated;
        await using (var insertCmd = new NpgsqlCommand("""
            INSERT INTO child_friendships
                (child_profile_key_a, child_profile_key_b, status, created_by_child_profile_key, created_by_code_id)
            VALUES
                (@child_profile_key_a, @child_profile_key_b, 'active', @created_by_child_profile_key, @created_by_code_id)
            ON CONFLICT (child_profile_key_a, child_profile_key_b) DO UPDATE SET
                status = 'active',
                updated_at = CURRENT_TIMESTAMP
            RETURNING id, (xmax = 0) AS created
            """, conn, tx))
        {
            insertCmd.Parameters.AddWithValue("child_profile_key_a", ordered.A);
            insertCmd.Parameters.AddWithValue("child_profile_key_b", ordered.B);
            insertCmd.Parameters.AddWithValue("created_by_child_profile_key", binding.ChildProfileKey);
            insertCmd.Parameters.AddWithValue("created_by_code_id", codeId);
            await using var reader = await insertCmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            friendshipId = reader.Int("id");
            friendshipCreated = reader.Bool("created");
        }

        await using (var useCodeCmd = new NpgsqlCommand("UPDATE child_friend_codes SET used_at = CURRENT_TIMESTAMP WHERE id = @id", conn, tx))
        {
            useCodeCmd.Parameters.AddWithValue("id", codeId);
            await useCodeCmd.ExecuteNonQueryAsync();
        }

        var childName = await GetChildNameByProfileKey(conn, tx, binding.ChildProfileKey);
        var friendName = await GetChildNameByProfileKey(conn, tx, targetProfileKey);
        if (friendshipCreated)
        {
            await InsertFriendNotifications(conn, tx, friendshipId, binding.ChildProfileKey, targetProfileKey, childName, friendName);
        }

        await tx.CommitAsync();
        return new Dictionary<string, object?>
        {
            ["status"] = "ok",
            ["friendshipId"] = friendshipId,
            ["friend"] = new Dictionary<string, object?>
            {
                ["profileKey"] = targetProfileKey,
                ["name"] = friendName,
                ["parentAppUserId"] = targetParentAppUserId
            },
            ["friends"] = await GetChildFriends(connectionString, binding.ChildProfileKey),
            ["leaderboard"] = await GetChildFriendLeaderboard(connectionString, binding.ChildProfileKey)
        };
    }
    catch (Exception ex)
    {
        await tx.RollbackAsync();
        return new Dictionary<string, object?> { ["error"] = ex.Message };
    }
}

static async Task<List<Dictionary<string, object?>>> GetChildFriends(string connectionString, string childProfileKey)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT cf.id, other_cp.profile_key, other_cp.name,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items,
               cf.created_at
        FROM child_friendships cf
        JOIN child_profiles other_cp ON other_cp.profile_key = CASE
            WHEN cf.child_profile_key_a = @child_profile_key THEN cf.child_profile_key_b
            ELSE cf.child_profile_key_a
        END
        LEFT JOIN accounts a ON a.profile_key = other_cp.profile_key
        WHERE cf.status = 'active'
          AND @child_profile_key IN (cf.child_profile_key_a, cf.child_profile_key_b)
          AND other_cp.status = 'active'
        ORDER BY other_cp.name
        """, conn);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);

    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new Dictionary<string, object?>
        {
            ["friendshipId"] = reader.Int("id"),
            ["profileKey"] = reader.String("profile_key"),
            ["name"] = reader.String("name"),
            ["score"] = reader.Decimal("score"),
            ["cash"] = reader.Decimal("cash"),
            ["items"] = reader.Int("items"),
            ["createdAt"] = reader.DateTime("created_at").ToString("O")
        });
    }
    return rows;
}

static async Task<List<Dictionary<string, object?>>> GetChildFriendLeaderboard(string connectionString, string childProfileKey)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        WITH visible_children AS (
            SELECT CAST(@child_profile_key AS varchar) AS profile_key, true AS is_self
            UNION
            SELECT CASE
                WHEN cf.child_profile_key_a = @child_profile_key THEN cf.child_profile_key_b
                ELSE cf.child_profile_key_a
            END AS profile_key, false AS is_self
            FROM child_friendships cf
            WHERE cf.status = 'active'
              AND @child_profile_key IN (cf.child_profile_key_a, cf.child_profile_key_b)
        )
        SELECT vc.profile_key, vc.is_self, cp.name,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items
        FROM visible_children vc
        JOIN child_profiles cp ON cp.profile_key = vc.profile_key AND cp.status = 'active'
        LEFT JOIN accounts a ON a.profile_key = vc.profile_key
        ORDER BY COALESCE(a.points, 0) DESC, cp.name
        """, conn);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);

    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    var rank = 1;
    while (await reader.ReadAsync())
    {
        rows.Add(new Dictionary<string, object?>
        {
            ["rank"] = rank++,
            ["profileKey"] = reader.String("profile_key"),
            ["name"] = reader.String("name"),
            ["score"] = reader.Decimal("score"),
            ["cash"] = reader.Decimal("cash"),
            ["items"] = reader.Int("items"),
            ["isSelf"] = reader.Bool("is_self")
        });
    }
    return rows;
}

static Dictionary<string, object?> ReadFriendNotification(IDataRecord reader) => new()
{
    ["id"] = reader.Int("id"),
    ["childProfileKey"] = reader.String("child_profile_key"),
    ["childName"] = reader.HasColumn("child_name") ? reader.String("child_name") : "",
    ["friendProfileKey"] = reader.String("friend_profile_key"),
    ["friendName"] = reader.HasColumn("friend_name") ? reader.String("friend_name") : "",
    ["friendshipId"] = reader.Int("friendship_id"),
    ["message"] = reader.String("message"),
    ["readAt"] = NullableDateTimeString(reader, "read_at"),
    ["createdAt"] = reader.DateTime("created_at").ToString("O")
};

static async Task<List<Dictionary<string, object?>>> GetChildFriendNotifications(string connectionString, string parentAppUserId, bool unreadOnly)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT cfn.id, cfn.child_profile_key, cp.name AS child_name,
               cfn.friend_profile_key, fcp.name AS friend_name,
               cfn.friendship_id, cfn.message, cfn.read_at, cfn.created_at
        FROM child_friend_notifications cfn
        LEFT JOIN child_profiles cp ON cp.profile_key = cfn.child_profile_key
        LEFT JOIN child_profiles fcp ON fcp.profile_key = cfn.friend_profile_key
        WHERE cfn.parent_app_user_id = @parent_app_user_id
          AND (@unread_only = false OR cfn.read_at IS NULL)
        ORDER BY cfn.created_at DESC, cfn.id DESC
        LIMIT 50
        """, conn);
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    cmd.Parameters.AddWithValue("unread_only", unreadOnly);
    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(ReadFriendNotification(reader));
    }
    return rows;
}

static async Task<Dictionary<string, object?>> MarkChildFriendNotificationRead(string connectionString, int notificationId, string parentAppUserId)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        UPDATE child_friend_notifications
        SET read_at = CURRENT_TIMESTAMP
        WHERE id = @id
          AND parent_app_user_id = @parent_app_user_id
        """, conn);
    cmd.Parameters.AddWithValue("id", notificationId);
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    return await cmd.ExecuteNonQueryAsync() == 0
        ? new Dictionary<string, object?> { ["error"] = "通知不存在" }
        : new Dictionary<string, object?> { ["status"] = "ok" };
}

static async Task<string> GetChildNameByProfileKey(NpgsqlConnection conn, NpgsqlTransaction tx, string childProfileKey)
{
    await using var cmd = new NpgsqlCommand("SELECT name FROM child_profiles WHERE profile_key = @profile_key", conn, tx);
    cmd.Parameters.AddWithValue("profile_key", childProfileKey);
    return Convert.ToString(await cmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) ?? "孩子";
}

static async Task InsertFriendNotifications(
    NpgsqlConnection conn,
    NpgsqlTransaction tx,
    int friendshipId,
    string childProfileKey,
    string friendProfileKey,
    string childName,
    string friendName)
{
    await using var cmd = new NpgsqlCommand("""
        INSERT INTO child_friend_notifications
            (parent_app_user_id, child_profile_key, friend_profile_key, friendship_id, message)
        SELECT DISTINCT cub.parent_app_user_id,
               @child_profile_key,
               @friend_profile_key,
               @friendship_id,
               @message
        FROM child_user_bindings cub
        WHERE cub.child_profile_key = @child_profile_key
        UNION
        SELECT DISTINCT cub.parent_app_user_id,
               @friend_profile_key,
               @child_profile_key,
               @friendship_id,
               @reverse_message
        FROM child_user_bindings cub
        WHERE cub.child_profile_key = @friend_profile_key
        """, conn, tx);
    cmd.Parameters.AddWithValue("child_profile_key", childProfileKey);
    cmd.Parameters.AddWithValue("friend_profile_key", friendProfileKey);
    cmd.Parameters.AddWithValue("friendship_id", friendshipId);
    cmd.Parameters.AddWithValue("message", $"{childName} 已添加 {friendName} 为手表好友");
    cmd.Parameters.AddWithValue("reverse_message", $"{friendName} 已添加 {childName} 为手表好友");
    await cmd.ExecuteNonQueryAsync();
}

static async Task<Dictionary<string, object?>> CreateChildAuthCode(string connectionString, int childId, int familyGroupId, string parentAppUserId, int expiresInMinutes)
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        var child = await GetChildForFamily(conn, tx, childId, familyGroupId, parentAppUserId);
        if (child is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "孩子不属于当前圈子，或只有孩子的所属账号可以生成认证码" };
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
    var child = await GetChildForFamily(conn, null, childId, familyGroupId, parentAppUserId);
    if (child is null)
    {
        return new Dictionary<string, object?> { ["error"] = "孩子不属于当前圈子，或只有孩子的所属账号可以查看设备" };
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
    var child = await GetChildForFamily(conn, null, childId, familyGroupId, parentAppUserId);
    if (child is null)
    {
        return new Dictionary<string, object?> { ["error"] = "孩子不属于当前圈子，或只有孩子的所属账号可以解绑设备" };
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
        var child = await GetChildForFamily(conn, tx, childId, familyGroupId, parentAppUserId);
        if (child is null)
        {
            await tx.RollbackAsync();
            return new Dictionary<string, object?> { ["error"] = "孩子不属于当前圈子，或只有孩子的所属账号可以生成解绑码" };
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

static async Task<Dictionary<string, object?>?> GetChildForFamily(
    NpgsqlConnection conn,
    NpgsqlTransaction? tx,
    int childId,
    int familyGroupId,
    string? parentAppUserId = null)
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
          AND (
              @parent_app_user_id IS NULL OR EXISTS (
                  SELECT 1
                  FROM child_user_bindings cub
                  WHERE cub.child_profile_key = c.profile_key
                    AND cub.parent_app_user_id = @parent_app_user_id
              )
          )
        """, conn, tx);
    cmd.Parameters.AddWithValue("child_id", childId);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.Add(new NpgsqlParameter("parent_app_user_id", NpgsqlDbType.Varchar)
    {
        Value = string.IsNullOrWhiteSpace(parentAppUserId) ? DBNull.Value : parentAppUserId
    });
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

static async Task<Dictionary<string, object?>> GetParentWatchRewardRequests(
    string connectionString,
    int? familyGroupId,
    string parentAppUserId,
    string status,
    int limit)
{
    await using var conn = await OpenConnection(connectionString);
    if (familyGroupId is not null)
    {
        await using var accessCmd = new NpgsqlCommand("""
            SELECT COUNT(*)
            FROM family_groups fg
            LEFT JOIN family_group_users fgu
              ON fgu.family_group_id = fg.id AND fgu.user_id = @parent_app_user_id
            WHERE fg.id = @family_group_id
              AND (fg.created_by = @parent_app_user_id OR fgu.user_id = @parent_app_user_id OR @parent_app_user_id = @default_user_id)
            """, conn);
        accessCmd.Parameters.AddWithValue("family_group_id", familyGroupId.Value);
        accessCmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
        accessCmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
        if (Convert.ToInt32(await accessCmd.ExecuteScalarAsync(), CultureInfo.InvariantCulture) == 0)
        {
            return new Dictionary<string, object?> { ["error"] = "你不是该圈子成员" };
        }
    }

    var normalizedStatus = status.Trim();
    await using var cmd = new NpgsqlCommand("""
        SELECT wrr.*, COALESCE(cp.name, c.name) AS child_name, r.name AS rule_name
        FROM watch_reward_requests wrr
        JOIN children c ON c.id = wrr.child_id
        JOIN child_user_bindings cub
          ON cub.child_profile_key = c.profile_key AND cub.parent_app_user_id = @parent_app_user_id
        LEFT JOIN child_profiles cp ON cp.profile_key = c.profile_key
        LEFT JOIN rules r ON r.id = wrr.rule_id
        LEFT JOIN family_groups fg ON fg.id = wrr.family_group_id
        LEFT JOIN family_group_users fgu
          ON fgu.family_group_id = wrr.family_group_id AND fgu.user_id = @parent_app_user_id
        WHERE (@family_group_id IS NULL OR wrr.family_group_id = @family_group_id)
          AND (@status = '' OR wrr.status = @status)
          AND (fg.created_by = @parent_app_user_id OR fgu.user_id = @parent_app_user_id OR @parent_app_user_id = @default_user_id)
        ORDER BY wrr.requested_at DESC, wrr.id DESC
        LIMIT @limit
        """, conn);
    cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
    {
        Value = familyGroupId is null ? DBNull.Value : familyGroupId.Value
    });
    cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
    cmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
    cmd.Parameters.AddWithValue("status", normalizedStatus);
    cmd.Parameters.AddWithValue("limit", limit);

    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(ReadWatchRewardRequest(reader));
    }

    return new Dictionary<string, object?>
    {
        ["familyGroupId"] = familyGroupId,
        ["requests"] = rows
    };
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
        return new Dictionary<string, object?> { ["error"] = "孩子不属于当前圈子" };
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

static async Task<Dictionary<string, object?>> ApproveWatchRewardRequest(
    string connectionString,
    int id,
    int? requestedFamilyGroupId,
    string parentAppUserId,
    string reviewNote)
{
    Dictionary<string, object?> request;
    await using (var conn = await OpenConnection(connectionString))
    await using (var cmd = new NpgsqlCommand("""
        SELECT wrr.*, c.name AS child_name, r.name AS rule_name
        FROM watch_reward_requests wrr
        JOIN children c ON c.id = wrr.child_id
        JOIN child_user_bindings cub
          ON cub.child_profile_key = c.profile_key AND cub.parent_app_user_id = @parent_app_user_id
        LEFT JOIN family_groups fg ON fg.id = wrr.family_group_id
        LEFT JOIN family_group_users fgu
          ON fgu.family_group_id = wrr.family_group_id AND fgu.user_id = @parent_app_user_id
        LEFT JOIN rules r ON r.id = wrr.rule_id
        WHERE wrr.id = @id
          AND (@family_group_id IS NULL OR wrr.family_group_id = @family_group_id)
          AND (fg.created_by = @parent_app_user_id OR fgu.user_id = @parent_app_user_id OR @parent_app_user_id = @default_user_id)
        """, conn))
    {
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
        {
            Value = requestedFamilyGroupId is null ? DBNull.Value : requestedFamilyGroupId.Value
        });
        cmd.Parameters.AddWithValue("parent_app_user_id", parentAppUserId);
        cmd.Parameters.AddWithValue("default_user_id", DefaultUserId);
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

    var familyGroupId = GetInt(request, "familyGroupId");
    var transactionResult = await CreateTransaction(connectionString, new JsonObject
    {
        ["child_id"] = GetInt(request, "childId"),
        ["type"] = "points",
        ["direction"] = "+",
        ["points"] = GetDecimal(request, "points"),
        ["category"] = Convert.ToString(request["category"], CultureInfo.InvariantCulture) ?? "手表申请",
        ["description"] = Convert.ToString(request["title"], CultureInfo.InvariantCulture) ?? "手表积分申请",
        ["notes"] = $"手表端申请 #{id}"
    }, familyGroupId, parentAppUserId);

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
        ["isRedLine"] = points < 0,
        ["score"] = points,
        ["enabled"] = true,
        ["ownerAppUserId"] = reader.HasColumn("owner_app_user_id") && !reader.IsDBNull(reader.GetOrdinal("owner_app_user_id"))
            ? reader.String("owner_app_user_id")
            : null,
        ["sourceRedlineId"] = reader.HasColumn("source_redline_id") && !reader.IsDBNull(reader.GetOrdinal("source_redline_id"))
            ? reader.Int("source_redline_id")
            : null,
        ["isPublic"] = !reader.HasColumn("owner_app_user_id") || reader.IsDBNull(reader.GetOrdinal("owner_app_user_id")),
        ["createdAt"] = reader.DateTime("created_at").ToString("O"),
        ["updatedAt"] = reader.HasColumn("updated_at") ? reader.DateTime("updated_at").ToString("O") : reader.DateTime("created_at").ToString("O")
    };
}

static decimal NormalizeRulePoints(JsonObject body)
{
    var points = body.Decimal("points") ?? body.Decimal("score") ?? 0;
    var ruleType = body.String("rule_type");
    if (string.IsNullOrWhiteSpace(ruleType)) ruleType = body.String("ruleType");
    return ruleType.Trim().Equals("redline", StringComparison.OrdinalIgnoreCase)
        ? -Math.Abs(points)
        : ruleType.Trim().Equals("reward", StringComparison.OrdinalIgnoreCase)
            ? Math.Abs(points)
            : points;
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

static string NormalizeDigits(string value) =>
    new(value.Trim().Where(char.IsAsciiDigit).ToArray());

static string NormalizeWatchFace(string value) => value.Trim().ToLowerInvariant() switch
{
    "world" or "minecraft" or "我的世界" => "world",
    "hellokitty" or "hello_kitty" or "kitty" or "hello kitty" or "hellokitty表盘" or "hello kitty表盘" => "hellokitty",
    "starlight" or "star" or "星光梦可" => "starlight",
    "dinosaur" or "dino" or "恐龙乐园" => "dinosaur",
    "rainbow" or "彩虹糖果" => "rainbow",
    "space" or "宇宙探险" => "space",
    _ => "world"
};

static (string A, string B) OrderFriendKeys(string first, string second) =>
    string.CompareOrdinal(first, second) <= 0 ? (first, second) : (second, first);

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

static string GenerateNumericCode(int length)
{
    Span<char> chars = stackalloc char[length];
    for (var i = 0; i < chars.Length; i++)
    {
        chars[i] = (char)('0' + RandomNumberGenerator.GetInt32(10));
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

static string LimitText(string value, int maxLength) =>
    string.IsNullOrEmpty(value) || value.Length <= maxLength ? value : value[..maxLength];

static string SanitizeFeedbackUrl(string value, HttpRequest request)
{
    if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")) return "";
    var requestHost = request.Host.Host;
    var allowed = string.Equals(uri.Host, requestHost, StringComparison.OrdinalIgnoreCase)
        || uri.Host is "happylife.ai.impx.net" or "localhost" or "127.0.0.1";
    if (!allowed) return "";

    var blockedKeys = new[] { "token", "code", "auth", "key", "password", "secret" };
    var builder = new UriBuilder(uri) { Query = "" };
    foreach (var pair in Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(uri.Query))
    {
        if (blockedKeys.Any(key => pair.Key.Contains(key, StringComparison.OrdinalIgnoreCase))) continue;
        foreach (var item in pair.Value)
        {
            builder.Query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.AddQueryString(builder.Query.TrimStart('?'), pair.Key, item ?? "");
        }
    }
    return LimitText(builder.Uri.ToString(), 1000);
}

static string SanitizeFeedbackPath(string value)
{
    if (string.IsNullOrWhiteSpace(value) || !value.StartsWith('/')) return "";
    if (!Uri.TryCreate($"https://feedback.invalid{value}", UriKind.Absolute, out var uri)) return "";

    var blockedKeys = new[] { "token", "code", "auth", "key", "password", "secret" };
    var builder = new UriBuilder(uri) { Query = "" };
    foreach (var pair in Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(uri.Query))
    {
        if (blockedKeys.Any(key => pair.Key.Contains(key, StringComparison.OrdinalIgnoreCase))) continue;
        foreach (var item in pair.Value)
        {
            builder.Query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.AddQueryString(builder.Query.TrimStart('?'), pair.Key, item ?? "");
        }
    }
    return LimitText($"{builder.Path}{builder.Query}{builder.Fragment}", 500);
}

static string FormatFeedbackPageContext(JsonObject source)
{
    var rows = new[]
    {
        ("页面标题", source.String("pageTitle")),
        ("页面路径", source.String("path")),
        ("视口", source.String("viewport")),
        ("浏览器", source.String("userAgent")),
        ("采集时间", source.String("capturedAt"))
    };
    return string.Join('\n', rows.Where(row => !string.IsNullOrWhiteSpace(row.Item2)).Select(row => $"{row.Item1}：{row.Item2}"));
}

static string GetAtlasFeedbackBaseUrl() =>
    (Environment.GetEnvironmentVariable("FAMILY_REWARD_ATLAS_URL") ?? "https://home.ai.impx.net").TrimEnd('/');

static void AddAtlasFeedbackHeaders(HttpRequestMessage message, AppUserProfile profile)
{
    var stableUserId = string.IsNullOrWhiteSpace(profile.UnifiedUserId) ? profile.AppUserId : profile.UnifiedUserId;
    message.Headers.TryAddWithoutValidation("X-Atlas-User-Id", stableUserId);
    message.Headers.TryAddWithoutValidation("X-User-Id", stableUserId);
    message.Headers.TryAddWithoutValidation("X-User-Name", profile.Username);
}

static bool LegacyFeedbackEndpointsRetired() => true;

static async Task<IResult> ProxyAtlasFeedback(
    IHttpClientFactory httpClientFactory,
    AppUserProfile profile,
    HttpMethod method,
    string path,
    JsonNode? payload = null)
{
    var result = await SendAtlasFeedback(httpClientFactory, profile, method, path, payload);
    return result.Error ?? Results.Json(result.Payload ?? new JsonObject(), statusCode: result.StatusCode);
}

static async Task<(JsonNode? Payload, IResult? Error, int StatusCode)> FetchAtlasFeedback(
    IHttpClientFactory httpClientFactory,
    AppUserProfile profile,
    string path) => await SendAtlasFeedback(httpClientFactory, profile, HttpMethod.Get, path);

static async Task<(JsonNode? Payload, IResult? Error, int StatusCode)> SendAtlasFeedback(
    IHttpClientFactory httpClientFactory,
    AppUserProfile profile,
    HttpMethod method,
    string path,
    JsonNode? payload = null)
{
    using var message = new HttpRequestMessage(method, $"{GetAtlasFeedbackBaseUrl()}{path}");
    AddAtlasFeedbackHeaders(message, profile);
    if (payload is not null)
    {
        message.Content = new StringContent(payload.ToJsonString(FamilyRewardJson.CreateOptions()), Encoding.UTF8, "application/json");
    }
    var client = httpClientFactory.CreateClient();
    client.Timeout = TimeSpan.FromSeconds(8);
    try
    {
        using var response = await client.SendAsync(message);
        var text = await response.Content.ReadAsStringAsync();
        JsonNode? responsePayload = null;
        try { responsePayload = JsonNode.Parse(text); } catch { }
        if (!response.IsSuccessStatusCode)
        {
            var upstreamMessage = (responsePayload as JsonObject)?.String("message");
            return (null, Results.Json(new
            {
                error = string.IsNullOrWhiteSpace(upstreamMessage) ? "反馈服务暂时不可用，请稍后重试" : upstreamMessage
            }, statusCode: StatusCodes.Status502BadGateway), StatusCodes.Status502BadGateway);
        }
        return (responsePayload, null, (int)response.StatusCode);
    }
    catch (TaskCanceledException)
    {
        return (null, Results.Json(new { error = "反馈服务响应超时，请稍后重试" }, statusCode: StatusCodes.Status503ServiceUnavailable), StatusCodes.Status503ServiceUnavailable);
    }
    catch (HttpRequestException)
    {
        return (null, Results.Json(new { error = "反馈服务暂时无法连接，请稍后重试" }, statusCode: StatusCodes.Status503ServiceUnavailable), StatusCodes.Status503ServiceUnavailable);
    }
}

sealed class SystemConfigStore
{
    private readonly string _connectionString;
    private readonly string _legacyPath;

    public SystemConfigStore(string connectionString, string contentRoot)
    {
        _connectionString = connectionString;
        _legacyPath = Path.Combine(contentRoot, "system_config.json");
    }

    public async Task<JsonObject> LoadAsync()
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT config_json::text FROM system_config WHERE id = 1", conn);
        var stored = Convert.ToString(await command.ExecuteScalarAsync(), CultureInfo.InvariantCulture);
        if (!string.IsNullOrWhiteSpace(stored))
        {
            try
            {
                var config = JsonNode.Parse(stored) as JsonObject ?? Defaults();
                var changed = EnsureDefaults(config);
                if (changed)
                {
                    await UpsertAsync(conn, config);
                }
                AgentFreeGatewayConfiguration.Set(config["agent"]?.AsObject().String("gatewayBaseUrl"));
                return config;
            }
            catch
            {
                return Defaults();
            }
        }

        var migrated = LoadLegacy();
        EnsureDefaults(migrated);
        await UpsertAsync(conn, migrated);
        AgentFreeGatewayConfiguration.Set(migrated["agent"]?.AsObject().String("gatewayBaseUrl"));
        return migrated;
    }

    public async Task<JsonObject> SaveAsync(JsonObject body)
    {
        var current = await LoadAsync();
        Merge(current["voice"]!.AsObject(), body["voice"] as JsonObject);
        Merge(current["agent"]!.AsObject(), body["agent"] as JsonObject);
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync();
        await UpsertAsync(conn, current);
        AgentFreeGatewayConfiguration.Set(current["agent"]?.AsObject().String("gatewayBaseUrl"));
        return current;
    }

    private async Task UpsertAsync(NpgsqlConnection conn, JsonObject config)
    {
        await using var command = new NpgsqlCommand("""
            INSERT INTO system_config (id, config_json, updated_at)
            VALUES (1, @config_json::jsonb, CURRENT_TIMESTAMP)
            ON CONFLICT (id) DO UPDATE SET config_json = EXCLUDED.config_json, updated_at = CURRENT_TIMESTAMP
            """, conn);
        command.Parameters.AddWithValue("config_json", config.ToJsonString(FamilyRewardJson.CreateOptions()));
        await command.ExecuteNonQueryAsync();
    }

    private JsonObject LoadLegacy()
    {
        if (!File.Exists(_legacyPath)) return Defaults();
        try
        {
            return JsonNode.Parse(File.ReadAllText(_legacyPath)) as JsonObject ?? Defaults();
        }
        catch
        {
            return Defaults();
        }
    }

    private static void Merge(JsonObject target, JsonObject? source)
    {
        if (source is null) return;
        foreach (var item in source)
        {
            target[item.Key] = item.Value?.DeepClone();
        }
    }

    private static bool EnsureDefaults(JsonObject config)
    {
        var changed = false;
        var agent = config["agent"] as JsonObject;
        if (agent is null)
        {
            agent = new JsonObject();
            changed = true;
        }
        if (agent["webAppBotId"] is null)
        {
            agent["webAppBotId"] = "web-jiajaifen-chat";
            changed = true;
        }
        if (agent["gatewayBaseUrl"] is null)
        {
            agent["gatewayBaseUrl"] = "https://agent.ai.impx.net";
            changed = true;
        }
        foreach (var legacyKey in new[] { "endpoint", "apiKey", "model", "timeout_seconds", "profile", "workingDirectory", "systemPrompt" })
        {
            changed |= agent.Remove(legacyKey);
        }
        if (config["agent"] is not JsonObject)
        {
            config["agent"] = agent;
        }
        return changed;
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
            ["webAppBotId"] = "web-jiajaifen-chat",
            ["gatewayBaseUrl"] = "https://agent.ai.impx.net"
        }
    };
}

static class AgentFreeGatewayConfiguration
{
    private static string _baseUrl = (Environment.GetEnvironmentVariable("AGENTFREE_BASE_URL") ?? "https://agent.ai.impx.net").TrimEnd('/');

    public static string BaseUrl => Volatile.Read(ref _baseUrl);

    public static void Set(string? value)
    {
        if (Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps))
        {
            Volatile.Write(ref _baseUrl, uri.GetLeftPart(UriPartial.Authority).TrimEnd('/'));
        }
    }
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

    public static bool Bool(this IDataRecord reader, string name)
    {
        var value = reader[name];
        return value is not DBNull && Convert.ToBoolean(value, CultureInfo.InvariantCulture);
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

    public static bool? Bool(this IQueryCollection query, string name)
    {
        var value = query.String(name);
        if (string.IsNullOrWhiteSpace(value)) return null;
        return bool.TryParse(value, out var parsed)
            ? parsed
            : value is "1" or "yes" or "on";
    }
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
