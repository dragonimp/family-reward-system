using System.Data;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;

var apiUrls = Environment.GetEnvironmentVariable("FAMILY_REWARD_API_URLS") ?? "http://0.0.0.0:5102";
var apiUri = new Uri(apiUrls.Replace("0.0.0.0", "localhost", StringComparison.OrdinalIgnoreCase));
Environment.SetEnvironmentVariable("ASPNETCORE_URLS", apiUrls);
const string FamilyRewardMcpToolName = "family_reward_tool";
const string FamilyRewardMcpServiceName = "family-reward-mcp";

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
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});
builder.Services.AddHttpClient();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();

var connectionString = BuildConnectionString(builder.Configuration);
await InitDatabase(connectionString);

app.MapGet("/health", () => Results.Json(new
{
    status = "ok",
    version = "3.0.0",
    stack = "aspnet-core",
    db = "postgresql"
}));

app.MapGet("/api/children", async () => Results.Json(await GetChildren(connectionString)));

app.MapGet("/api/children/{id:int}", async (int id) =>
{
    var child = (await GetChildren(connectionString)).FirstOrDefault(c => GetInt(c, "id") == id);
    return child is null ? Results.NotFound(new { error = "不存在" }) : Results.Json(child);
});

app.MapPost("/api/children", async (JsonObject body) =>
{
    var created = await CreateChildCore(connectionString, body);
    if (!created.Success)
    {
        return Results.BadRequest(new { error = created.Error });
    }
    return Results.Created($"/api/children/{GetInt(created.Child!, "id")}", created.Child);
});

app.MapPut("/api/children/{id:int}", async (int id, JsonObject body) =>
{
    await using var conn = await OpenConnection(connectionString);
    await using var tx = await conn.BeginTransactionAsync();
    await using var cmd = new NpgsqlCommand("""
        UPDATE children
        SET name = @name, note = @note, status = @status, updated_at = CURRENT_TIMESTAMP
        WHERE id = @id
        RETURNING id, name, status, note, created_at, updated_at
        """, conn, tx);
    cmd.Parameters.AddWithValue("id", id);
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
    accountCmd.Parameters.AddWithValue("points", body.Int("score") is int score ? score : DBNull.Value);
    accountCmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash") is decimal cash ? cash : DBNull.Value);
    accountCmd.Parameters.AddWithValue("items_count", body.Int("items") is int items ? items : DBNull.Value);
    await accountCmd.ExecuteNonQueryAsync();
    await tx.CommitAsync();

    var updated = (await GetChildren(connectionString)).First(c => GetInt(c, "id") == id);
    return Results.Json(updated);
});

app.MapDelete("/api/children/{id:int}", async (int id) =>
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("DELETE FROM children WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", id);
    await cmd.ExecuteNonQueryAsync();
    return Results.Json(new { status = "ok" });
});

app.MapGet("/api/transactions", async (HttpRequest request) =>
{
    var query = request.Query;
    var childId = query.Int("childId") ?? query.Int("child_id");
    var type = NormalizeTransactionType(query.String("type"));
    var category = query.String("category");
    var search = query.String("search");
    var startDate = query.String("startDate");
    var endDate = query.String("endDate");
    var page = query.Int("page") ?? 1;
    var pageSize = query.Int("pageSize") ?? query.Int("page_size") ?? 50;

    var where = new List<string> { "1=1" };
    var parameters = new List<NpgsqlParameter>();
    AddFilter(where, parameters, childId is null, "t.child_id = @child_id", "child_id", childId ?? 0);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(type), "t.type = @type", "type", type);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(category), "t.category = @category", "category", category);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(search), "t.description ILIKE @search", "search", $"%{search}%");
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(startDate), "t.date >= @start_date", "start_date", startDate);
    AddFilter(where, parameters, string.IsNullOrWhiteSpace(endDate), "t.date <= @end_date", "end_date", endDate);

    var whereSql = string.Join(" AND ", where);
    await using var conn = await OpenConnection(connectionString);

    await using var countCmd = new NpgsqlCommand($"SELECT COUNT(*) FROM transactions t WHERE {whereSql}", conn);
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

app.MapGet("/api/stats/dashboard", async () =>
{
    var children = await GetChildren(connectionString);
    var transactions = await GetRecentTransactions(connectionString, 20);
    return Results.Json(new { children, recent = transactions });
});

app.MapGet("/api/stats/leaderboard", async () =>
{
    var children = await GetChildren(connectionString);
    return Results.Json(children
        .Select(c => new { id = GetInt(c, "id"), name = c["name"], points = GetInt(c, "score") })
        .OrderByDescending(c => c.points));
});

app.MapGet("/api/stats/categories", async () =>
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT category, COALESCE(SUM(points), 0) AS total
        FROM transactions
        GROUP BY category
        ORDER BY category
        """, conn);
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

app.MapPost("/api/agent/parse-reward", async (JsonObject body, IHttpClientFactory httpClientFactory) =>
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

    var children = await GetChildren(connectionString);
    var rules = await GetRules(connectionString);
    var prompt = $$$"""
        你是家庭积分系统的语音纠错和结构化解析智能体。
        用户语音识别文本可能把孩子名字、规则名称识别错。请根据候选孩子和规则语义，选择最可能的孩子和操作。

        候选孩子 JSON:
        {{JsonSerializer.Serialize(children)}}

        候选规则 JSON:
        {{JsonSerializer.Serialize(rules)}}

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

    var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
    {
        Content = new StringContent(payload.ToJsonString(), Encoding.UTF8, "application/json")
    };
    var apiKey = agent.String("apiKey");
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
        Content = new StringContent(payload.ToJsonString(), Encoding.UTF8, "application/json")
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
        var directResult = await InvokeFamilyRewardMcpTool(body, connectionString);
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
                instructions = "Use tools/list and tools/call with tool='family_reward_tool'."
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

                if (!string.Equals(toolName, FamilyRewardMcpToolName, StringComparison.Ordinal))
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
                var toolResult = await InvokeFamilyRewardMcpTool(arguments, connectionString);
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
            title = "家庭积分系统 MCP 服务（统一工具）",
            description = "提供孩子管理、积分变更与积分查询的统一入口，适配智能体工具调用。"
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
        tools = new[]
        {
            new
            {
                name = FamilyRewardMcpToolName,
                description = "家庭积分系统统一工具：支持新增孩子、积分增减、积分查询。",
                inputSchema = new
                {
                    type = "object",
                    properties = new
                    {
                        action = new
                        {
                            type = "string",
                            description = "add_child / adjust_score / query_score / query_children",
                            @enum = new[] { "add_child", "adjust_score", "query_score", "query_children" }
                        },
                        child_id = new { type = "integer", description = "孩子ID（优先使用）" },
                        childId = new { type = "integer", description = "孩子ID（兼容写法）" },
                        child_name = new { type = "string", description = "孩子姓名（按名字匹配）" },
                        name = new { type = "string", description = "新建孩子姓名（add_child 必填）" },
                        note = new { type = "string", description = "备注（add_child 可选）" },
                        score = new { type = "number", description = "新增孩子初始积分（add_child）" },
                        cash = new { type = "number", description = "新增孩子初始现金（add_child）" },
                        items = new { type = "integer", description = "新增孩子初始物品数（add_child）" },
                        delta = new { type = "number", description = "积分增减量（adjust_score），正数加分，负数扣分" },
                        amount = new { type = "number", description = "积分增减量（adjust_score，delta 别名）" },
                        direction = new { type = "string", description = "可选，'+' 或 '-'，默认按 delta 的正负" },
                        date = new { type = "string", description = "交易日期，格式 YYYY-MM-DD" },
                        category = new { type = "string", description = "分类（adjust_score）" },
                        description = new { type = "string", description = "交易描述（adjust_score）" },
                        include_transactions = new { type = "boolean", description = "query_score 是否返回最近交易记录" },
                        limit = new { type = "integer", description = "query_score 最近交易条数（默认20）" }
                    },
                    required = new[] { "action" }
                }
            }
        }
    };
}

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
    var catalogNode = JsonSerializer.SerializeToNode(catalog) as JsonObject;
    var tools = catalogNode?["tools"];
    return new
    {
        tools,
        nextCursor = (string?)null
    };
}

static object BuildMcpToolCallResult(object toolResult)
{
    var toolPayload = JsonSerializer.Serialize(toolResult);
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
            new { type = "text", text = toolPayload }
        },
        structuredContent = toolResult,
        isError
    };
}

static async Task<object> InvokeFamilyRewardMcpTool(JsonObject arguments, string connectionString)
{
    var action = arguments.String("action", "").Trim().ToLowerInvariant();
    if (string.IsNullOrWhiteSpace(action))
    {
        return new { ok = false, error = "缺少 action 参数" };
    }

    return action switch
    {
        "add_child" => await McpAddChild(connectionString, arguments),
        "create_child" => await McpAddChild(connectionString, arguments),
        "adjust_score" => await McpAdjustScore(connectionString, arguments),
        "query_score" => await McpQueryScore(connectionString, arguments),
        "query_children" => await McpQueryChildren(connectionString),
        _ => new { ok = false, error = $"不支持的 action: {action}" }
    };
}

static async Task<object> McpAddChild(string connectionString, JsonObject arguments)
{
    var result = await CreateChildCore(connectionString, arguments);
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
    var children = await GetChildren(connectionString);
    var target = ResolveChildByReference(children, arguments);
    if (target is null)
    {
        return new { ok = false, error = "未找到目标孩子" };
    }

    var delta = arguments.Decimal("delta") ?? arguments.Decimal("amount");
    if (delta is null || delta == 0)
    {
        return new { ok = false, error = "adjust_score 需要提供非0的 delta 或 amount" };
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

    var updated = (await GetChildren(connectionString)).FirstOrDefault(c => GetInt(c, "id") == GetInt(target, "id"));
    return new { ok = true, action = "adjust_score", child = updated, transaction = tx["transaction"] };
}

static async Task<object> McpQueryScore(string connectionString, JsonObject arguments)
{
    var children = await GetChildren(connectionString);
    var target = ResolveChildByReference(children, arguments);
    var limit = arguments.Int("limit") ?? 20;

    if (target is null)
    {
        return new { ok = true, action = "query_score", children = children };
    }

    var records = (await GetRecentTransactions(connectionString, Math.Clamp(limit, 1, 200)))
        .Where(tx => GetInt(tx, "child_id") == GetInt(target, "id"))
        .ToList();
    return new
    {
        ok = true,
        action = "query_score",
        child = target,
        transactions = arguments.Bool("include_transactions") ? records : null,
        total = records.Count
    };
}

static async Task<object> McpQueryChildren(string connectionString)
{
    return new
    {
        ok = true,
        action = "query_children",
        children = await GetChildren(connectionString)
    };
}

static Dictionary<string, object?>? ResolveChildByReference(List<Dictionary<string, object?>> children, JsonObject arguments)
{
    var childId = arguments.Int("child_id") ?? arguments.Int("childId");
    if (childId is not null)
    {
        return children.FirstOrDefault(c => GetInt(c, "id") == childId);
    }

    var childName = arguments.String("child_name");
    if (string.IsNullOrWhiteSpace(childName))
    {
        childName = arguments.String("name");
    }
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

static async Task<(bool Success, Dictionary<string, object?>? Child, string? Error)> CreateChildCore(string connectionString, JsonObject body)
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
            INSERT INTO children (name, status, note)
            VALUES (@name, 'active', @note)
            RETURNING id, name, status, note, created_at, updated_at
            """, conn, tx);
        cmd.Parameters.AddWithValue("name", name);
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
        accountCmd.Parameters.AddWithValue("points", body.Int("score") ?? body.Int("points") ?? 0);
        accountCmd.Parameters.AddWithValue("cash_cny", body.Decimal("cash") ?? body.Decimal("cash_cny") ?? 0);
        accountCmd.Parameters.AddWithValue("items_count", body.Int("items") ?? 0);
        await accountCmd.ExecuteNonQueryAsync();

        await tx.CommitAsync();
        var created = (await GetChildren(connectionString)).First(c => GetInt(c, "id") == GetInt(child, "id"));
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
    return conn;
}

static async Task InitDatabase(string connectionString)
{
    await using var conn = await OpenConnection(connectionString);
    var statements = new[]
    {
        """
        CREATE TABLE IF NOT EXISTS children (
            id SERIAL PRIMARY KEY,
            name VARCHAR(50) NOT NULL UNIQUE,
            status VARCHAR(20) DEFAULT 'active',
            note TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS accounts (
            id SERIAL PRIMARY KEY,
            child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
            points INTEGER DEFAULT 0,
            cash_cny NUMERIC(10,2) DEFAULT 0,
            items_count INTEGER DEFAULT 0,
            items_detail TEXT,
            points_earned INTEGER DEFAULT 0,
            points_spent INTEGER DEFAULT 0,
            cash_earned NUMERIC(10,2) DEFAULT 0,
            cash_spent NUMERIC(10,2) DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(child_id)
        )
        """,
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
        "CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type)"
    };

    foreach (var sql in statements)
    {
        await using var cmd = new NpgsqlCommand(sql, conn);
        await cmd.ExecuteNonQueryAsync();
    }

    var children = new (string Name, int Points, decimal Cash, int Items, string Detail, int Earned, int Spent, decimal CashEarned, decimal CashSpent)[]
    {
        ("彦谦", 108, 230, 2, "2个铲子", 108, 0, 300, 70),
        ("玥玥", 123, 30, 1, "水培栽培", 144, 21, 50, 20),
        ("嘟嘟", 100, 0, 0, "", 100, 0, 0, 0),
        ("薇薇", 100, 0, 0, "", 100, 0, 0, 0),
        ("小宇", 100, 0, 0, "", 100, 0, 0, 0)
    };

    foreach (var child in children)
    {
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO children (name, status, note)
            VALUES (@name, 'active', '')
            ON CONFLICT (name) DO NOTHING;
            INSERT INTO accounts (
                child_id, points, cash_cny, items_count, items_detail,
                points_earned, points_spent, cash_earned, cash_spent
            )
            SELECT c.id, @points, @cash, @items, @detail, @earned, @spent, @cash_earned, @cash_spent
            FROM children c
            WHERE c.name = @name
            ON CONFLICT (child_id) DO NOTHING;
            """, conn);
        cmd.Parameters.AddWithValue("name", child.Name);
        cmd.Parameters.AddWithValue("points", child.Points);
        cmd.Parameters.AddWithValue("cash", child.Cash);
        cmd.Parameters.AddWithValue("items", child.Items);
        cmd.Parameters.AddWithValue("detail", child.Detail);
        cmd.Parameters.AddWithValue("earned", child.Earned);
        cmd.Parameters.AddWithValue("spent", child.Spent);
        cmd.Parameters.AddWithValue("cash_earned", child.CashEarned);
        cmd.Parameters.AddWithValue("cash_spent", child.CashSpent);
        await cmd.ExecuteNonQueryAsync();
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

static async Task<List<Dictionary<string, object?>>> GetChildren(string connectionString)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT c.id, c.name, c.status, c.note, c.created_at, c.updated_at,
               COALESCE(a.points, 0) AS score,
               COALESCE(a.cash_cny, 0) AS cash,
               COALESCE(a.items_count, 0) AS items
        FROM children c
        LEFT JOIN accounts a ON a.child_id = c.id
        WHERE c.status = 'active'
        ORDER BY c.id
        """, conn);
    var rows = new List<Dictionary<string, object?>>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new Dictionary<string, object?>
        {
            ["id"] = reader.Int("id"),
            ["name"] = reader.String("name"),
            ["status"] = reader.String("status"),
            ["note"] = reader.String("note"),
            ["createdAt"] = reader.DateTime("created_at").ToString("O"),
            ["updatedAt"] = reader.DateTime("updated_at").ToString("O"),
            ["score"] = reader.Int("score"),
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

static async Task<List<Dictionary<string, object?>>> GetRecentTransactions(string connectionString, int limit)
{
    await using var conn = await OpenConnection(connectionString);
    await using var cmd = new NpgsqlCommand("""
        SELECT t.*, c.name AS child_name
        FROM transactions t
        LEFT JOIN children c ON c.id = t.child_id
        ORDER BY t.date DESC, t.id DESC
        LIMIT @limit
        """, conn);
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
    cmd.Parameters.AddWithValue("points", Convert.ToInt32(Math.Abs(points), CultureInfo.InvariantCulture));
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

static int GetInt(IReadOnlyDictionary<string, object?> row, string key) =>
    Convert.ToInt32(row[key], CultureInfo.InvariantCulture);

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
            File.WriteAllText(_path, defaults.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
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
        File.WriteAllText(_path, current.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
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
