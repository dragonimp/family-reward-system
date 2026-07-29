using AgentIdentity.Sdk;
using Microsoft.AspNetCore.HttpOverrides;
using System.Data;
using System.Globalization;
using System.Text.Encodings.Web;
using System.Net.Http.Headers;
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

app.MapGet("/api/family-groups", async (HttpRequest request) =>
{
    var userId = GetRequestUserId(request);
    return Results.Json(await GetFamilyGroups(connectionString, userId));
});

app.MapPost("/api/family-groups", async (JsonObject body, HttpRequest request) =>
{
    var userId = body.String("user_id");
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = body.String("userId");
    }
    if (string.IsNullOrWhiteSpace(userId))
    {
        userId = GetRequestUserId(request);
    }

    var created = await CreateFamilyGroup(connectionString, body.String("name"), userId, body.String("description"));
    if (!created.Success)
    {
        return Results.BadRequest(new { error = created.Error });
    }

    return Results.Created($"/api/family-groups/{GetInt(created.Group!, "id")}", created.Group);
});

app.MapPut("/api/family-groups/{id:int}/users", async (int id, JsonObject body) =>
{
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
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    return Results.Json(await GetChildren(connectionString, familyGroupId));
});

app.MapGet("/api/children/{id:int}", async (int id, HttpRequest request) =>
{
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var child = (await GetChildren(connectionString, familyGroupId)).FirstOrDefault(c => GetInt(c, "id") == id);
    return child is null ? Results.NotFound(new { error = "不存在" }) : Results.Json(child);
});

app.MapPost("/api/children", async (JsonObject body, HttpRequest request) =>
{
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
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request, body);
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    await using var cmd = new NpgsqlCommand("""
        UPDATE children
        SET name = @name, note = @note, status = @status, updated_at = CURRENT_TIMESTAMP
        WHERE id = @id AND family_group_id = @family_group_id
        RETURNING id, name, status, note, created_at, updated_at
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    cmd.Parameters.AddWithValue("name", body.String("name"));
    cmd.Parameters.AddWithValue("note", body.String("note"));
    cmd.Parameters.AddWithValue("status", body.String("status", "active"));
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        await tx.RollbackAsync();
        return Results.NotFound(new { error = "不存在" });
    }
    await reader.CloseAsync();

    await using var accountCmd = new NpgsqlCommand("""
        INSERT INTO accounts (child_id, points, cash_cny, items_count)
        VALUES (@child_id, COALESCE(@points, 0), COALESCE(@cash_cny, 0), COALESCE(@items_count, 0))
        ON CONFLICT (child_id) DO UPDATE SET
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
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM children WHERE id = @id AND family_group_id = @family_group_id", conn);
    cmd.Parameters.AddWithValue("id", id);
    cmd.Parameters.AddWithValue("family_group_id", familyGroupId);
    await cmd.ExecuteNonQueryAsync();
    return Results.Json(new { status = "ok" });
});

app.MapGet("/api/transactions", async (HttpRequest request) =>
{
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

app.MapPost("/api/transactions", async (JsonObject body) =>
{
    var result = await CreateTransaction(connectionString, body);
    return result.ContainsKey("error") ? Results.BadRequest(result) : Results.Json(result);
});

app.MapPost("/api/transactions/batch", async (JsonArray body) =>
{
    var results = new List<object>();
    foreach (var node in body.OfType<JsonObject>())
    {
        var result = await CreateTransaction(connectionString, node);
        results.Add(new
        {
            child_id = node.Int("child_id") ?? node.Int("childId"),
            success = !result.ContainsKey("error"),
            error = result.TryGetValue("error", out var error) ? error : null
        });
    }

    return Results.Json(new { results });
});

app.MapDelete("/api/transactions/{id:int}", async (int id) =>
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM transactions WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", id);
    await cmd.ExecuteNonQueryAsync();
    return Results.Json(new { status = "ok" });
});

app.MapGet("/api/rules", async () => Results.Json(await GetRules(connectionString)));

app.MapPost("/api/rules", async (JsonObject body) =>
{
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

app.MapPut("/api/rules/{id:int}", async (int id, JsonObject body) =>
{
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

app.MapDelete("/api/rules/{id:int}", async (int id) =>
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM rules WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", id);
    await cmd.ExecuteNonQueryAsync();
    return Results.Json(new { status = "ok" });
});

app.MapGet("/api/stats/dashboard", async (HttpRequest request) =>
{
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var children = await GetChildren(connectionString, familyGroupId);
    var transactions = await GetRecentTransactions(connectionString, 20, familyGroupId);
    return Results.Json(new { children, recent = transactions });
});

app.MapGet("/api/stats/leaderboard", async (HttpRequest request) =>
{
    var familyGroupId = await ResolveFamilyGroupId(connectionString, request);
    var children = await GetChildren(connectionString, familyGroupId);
    return Results.Json(children
        .Select(c => new { id = GetInt(c, "id"), name = c["name"], points = GetDecimal(c, "score") })
        .OrderByDescending(c => c.points));
});

app.MapGet("/api/stats/categories", async (HttpRequest request) =>
{
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

app.MapGet("/api/system/config", () => Results.Json(configStore.Load()));

app.MapPut("/api/system/config", (JsonObject body) =>
{
    var saved = configStore.Save(body);
    return Results.Json(saved);
});

app.MapPost("/api/agent/parse-reward", async (JsonObject body, IHttpClientFactory httpClientFactory, HttpRequest request) =>
{
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
        你是家庭积分系统的语音纠错和结构化解析智能体。
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

app.MapPost("/api/agent/invoke", async (JsonObject body, IHttpClientFactory httpClientFactory) =>
{
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

    var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
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
        request.Headers.Authorization = AuthenticationHeaderValue.Parse(
            apiKey.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? apiKey : $"Bearer {apiKey}");
    }

    var client = httpClientFactory.CreateClient();
    client.Timeout = TimeSpan.FromSeconds(agent.Int("timeout_seconds") ?? 20);
    try
    {
        var response = await client.SendAsync(request);
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

static object BuildMcpServiceDescriptor()
{
    return new
    {
        service = new
        {
            name = FamilyRewardMcpServiceName,
            version = "3.0.0",
            title = "家庭积分系统 MCP 服务（能力拆分）",
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
            RETURNING id, name, status, note, created_at, updated_at
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
            INSERT INTO accounts (child_id, points, cash_cny, items_count)
            VALUES (@child_id, COALESCE(@points, 0), COALESCE(@cash_cny, 0), COALESCE(@items_count, 0))
            ON CONFLICT (child_id) DO UPDATE SET
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

    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM children WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", GetInt(target, "id"));
    var affected = await cmd.ExecuteNonQueryAsync();
    return affected > 0
        ? new { ok = true, action = "delete_child", child = target }
        : new { ok = false, error = "孩子不存在" };
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

static async Task<Dictionary<string, object?>> DeleteTransaction(string connectionString, int id)
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

static async Task<Dictionary<string, object?>?> ReadTransactionForUpdate(NpgsqlConnection conn, NpgsqlTransaction tx, int id)
{
    await using var cmd = new NpgsqlCommand("""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        WHERE t.id = @id
        FOR UPDATE OF t
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
    await using var reader = await cmd.ExecuteReaderAsync();
    return await reader.ReadAsync() ? ReadTransaction(reader) : null;
}

static async Task ReverseTransactionAccountEffect(NpgsqlConnection conn, NpgsqlTransaction tx, IReadOnlyDictionary<string, object?> transaction)
{
    var reverseDirection = string.Equals(Convert.ToString(transaction["direction"], CultureInfo.InvariantCulture), "-", StringComparison.Ordinal)
        ? "+"
        : "-";
    await UpdateAccount(
        conn,
        tx,
        GetInt(transaction, "child_id"),
        Convert.ToString(transaction["rawType"], CultureInfo.InvariantCulture) ?? "points",
        reverseDirection,
        GetDecimal(transaction, "points"),
        GetDecimal(transaction, "cash_cny"),
        Convert.ToString(transaction["items"], CultureInfo.InvariantCulture) ?? "");
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

    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO children (family_group_id, name, status, note)
            VALUES (@family_group_id, @name, @status, @note)
            RETURNING id, name, status, note, created_at, updated_at
            """, conn, tx);
        cmd.Parameters.AddWithValue("family_group_id", familyGroupId is null ? DBNull.Value : familyGroupId.Value);
        cmd.Parameters.AddWithValue("name", name);
        cmd.Parameters.AddWithValue("status", body.String("status", "active"));
        cmd.Parameters.AddWithValue("note", body.String("note"));
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        var child = ReadChild(reader);
        await reader.CloseAsync();

        await using var accountCmd = new NpgsqlCommand("""
            INSERT INTO accounts (child_id, points, cash_cny, items_count)
            VALUES (@child_id, @points, @cash_cny, @items_count)
            """, conn, tx);
        accountCmd.Parameters.AddWithValue("child_id", GetInt(child, "id"));
        accountCmd.Parameters.AddWithValue("points", body.Decimal("score") ?? body.Decimal("points") ?? 0);
        accountCmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash") ?? body.Decimal("cash_cny") ?? 0);
        accountCmd.Parameters.AddWithValue("items_count", body.Int("items") ?? 0);
        await accountCmd.ExecuteNonQueryAsync();

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
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_children_family_group_name ON children(family_group_id, name)",
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
        "ALTER TABLE accounts ALTER COLUMN points TYPE NUMERIC(10,2) USING points::numeric",
        "ALTER TABLE accounts ALTER COLUMN points_earned TYPE NUMERIC(10,2) USING points_earned::numeric",
        "ALTER TABLE accounts ALTER COLUMN points_spent TYPE NUMERIC(10,2) USING points_spent::numeric",
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
        "CREATE INDEX IF NOT EXISTS idx_family_group_users_user ON family_group_users(user_id)"
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
        var id = await EnsureFamilyGroup(conn, name, userId, description);
        await using var cmd = new NpgsqlCommand("""
            SELECT fg.id, fg.name, fg.description, fg.created_by, fgu.role, fg.created_at, fg.updated_at
            FROM family_groups fg
            LEFT JOIN family_group_users fgu ON fgu.family_group_id = fg.id AND fgu.user_id = @user_id
            WHERE fg.id = @id
            """, conn);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("user_id", string.IsNullOrWhiteSpace(userId) ? DefaultUserId : userId);
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
    var userId = request.Headers.TryGetValue("X-User-Id", out var headerUserId) ? headerUserId.ToString() : "";
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

static async Task<List<Dictionary<string, object?>>> GetChildren(string connectionString, int? familyGroupId = null)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT c.id, c.family_group_id, fg.name AS family_group_name,
               c.name, c.status, c.note, c.created_at, c.updated_at,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items
        FROM children c
        LEFT JOIN family_groups fg ON fg.id = c.family_group_id
        LEFT JOIN accounts a ON a.child_id = c.id
        WHERE c.status = 'active' AND (@family_group_id IS NULL OR c.family_group_id = @family_group_id)
        ORDER BY c.id
        """, conn);
    cmd.Parameters.Add(new NpgsqlParameter("family_group_id", NpgsqlDbType.Integer)
    {
        Value = familyGroupId is null ? DBNull.Value : familyGroupId.Value
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

static async Task<Dictionary<string, object?>> CreateTransaction(string connectionString, JsonObject body)
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

static async Task UpdateAccount(NpgsqlConnection conn, NpgsqlTransaction tx, int childId, string type, string direction, decimal points, decimal cash, string items)
{
    var sign = direction == "-" ? -1 : 1;
    var sql = type switch
    {
        "points" => sign > 0
            ? "UPDATE accounts SET points = points + @points, points_earned = points_earned + @points, updated_at = CURRENT_TIMESTAMP WHERE child_id = @child_id"
            : "UPDATE accounts SET points = points - @points, points_spent = points_spent + @points, updated_at = CURRENT_TIMESTAMP WHERE child_id = @child_id",
        "cash" => sign > 0
            ? "UPDATE accounts SET cash_cny = cash_cny + @cash, cash_earned = cash_earned + @cash, updated_at = CURRENT_TIMESTAMP WHERE child_id = @child_id"
            : "UPDATE accounts SET cash_cny = cash_cny - @cash, cash_spent = cash_spent + @cash, updated_at = CURRENT_TIMESTAMP WHERE child_id = @child_id",
        "items" => sign > 0
            ? "UPDATE accounts SET items_count = items_count + 1, items_detail = CONCAT_WS(', ', NULLIF(items_detail, ''), @items), updated_at = CURRENT_TIMESTAMP WHERE child_id = @child_id"
            : "UPDATE accounts SET items_count = GREATEST(items_count - 1, 0), updated_at = CURRENT_TIMESTAMP WHERE child_id = @child_id",
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
            ["systemPrompt"] = "你是家庭积分系统智能助手，输出简短可执行建议。"
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
