using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AgentIdentity.NativeClient;

namespace LinkoFamily;

public sealed class FamilyStore
{
    private static readonly Uri Origin = new("https://happylife.ai.impx.net/");
    private const string SessionKey = "linko_family_android_session";
    private readonly NativeSessionHandler session;
    private readonly HttpClient api;
    private readonly HttpClient loginHttp = new() { BaseAddress = Origin, Timeout = TimeSpan.FromSeconds(30) };
    private CancellationTokenSource? loginCancellation;
    private int generation;

    public FamilyStore()
    {
        session = new NativeSessionHandler(Origin,
            () => SecureStorage.Default.GetAsync(SessionKey),
            value => value is null ? ClearStoredSessionAsync() : SecureStorage.Default.SetAsync(SessionKey, value));
        api = new HttpClient(session) { BaseAddress = Origin, Timeout = TimeSpan.FromSeconds(35) };
    }

    private static Task ClearStoredSessionAsync()
    {
        SecureStorage.Default.Remove(SessionKey);
        return Task.CompletedTask;
    }

    public bool Authenticated { get; private set; }
    public bool ParentReady => Profile is { } profile && profile.Text("role") == "parent" && !profile.Bool("needsRole");
    public string? DisplayCode { get; private set; }
    public FamilyRecord? Profile { get; private set; }
    public List<FamilyRecord> Groups { get; private set; } = [];
    public List<FamilyRecord> Children { get; private set; } = [];
    public List<FamilyRecord> Rules { get; private set; } = [];
    public List<FamilyRecord> Requests { get; private set; } = [];
    public List<FamilyRecord> Transactions { get; private set; } = [];
    public int GroupId { get; private set; }
    public int LedgerPage { get; private set; } = 1;
    public int LedgerTotal { get; private set; }
    public string Scope => GroupId == 0 ? "" : $"familyGroupId={GroupId}";

    public async Task RestoreAsync()
    {
        Authenticated = !string.IsNullOrEmpty(await session.GetTokenAsync());
        if (Authenticated) await LoadAsync();
    }

    public async Task LoginAsync(bool register, Action<string> showCode, CancellationToken cancellationToken)
    {
        CancelLogin();
        var attempt = ++generation;
        loginCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var login = loginCancellation;
        var identity = new NativeLoginClient(loginHttp);
        var result = await identity.LoginSessionAsync(
            async (url, ct) =>
            {
                await Launcher.Default.OpenAsync(url);
                ct.ThrowIfCancellationRequested();
                return true;
            },
            code => { DisplayCode = code; MainThread.BeginInvokeOnMainThread(() => showCode(code)); },
            register,
            login.Token);
        if (attempt != generation || login.IsCancellationRequested) throw new OperationCanceledException();
        await session.SaveAsync(result, login.Token);
        if (attempt != generation || login.IsCancellationRequested)
        {
            Logout();
            throw new OperationCanceledException();
        }
        Authenticated = true;
        DisplayCode = null;
        await LoadAsync();
    }

    public void CancelLogin()
    {
        loginCancellation?.Cancel();
        loginCancellation?.Dispose();
        loginCancellation = null;
        DisplayCode = null;
        ++generation;
    }

    public void Logout()
    {
        CancelLogin();
        session.Clear();
        SecureStorage.Default.Remove(SessionKey);
        Authenticated = false;
        Profile = null;
        GroupId = 0;
        Groups = []; Children = []; Rules = []; Requests = []; Transactions = [];
    }

    public async Task<JsonElement> CallAsync(string path, HttpMethod? method = null, object? body = null)
    {
        if (!path.StartsWith("/api/", StringComparison.Ordinal)) throw new InvalidOperationException("Invalid business path.");
        using var request = new HttpRequestMessage(method ?? HttpMethod.Get, path);
        request.Headers.Accept.ParseAdd("application/json");
        if (body is not null) request.Content = JsonContent.Create(body);
        using var response = await api.SendAsync(request);
        if (response.StatusCode == HttpStatusCode.Unauthorized)
        {
            Logout();
            throw new FamilyApiException("登录已过期，请重新登录。");
        }
        var content = await response.Content.ReadAsStringAsync();
        JsonElement data;
        try { data = JsonDocument.Parse(string.IsNullOrWhiteSpace(content) ? "{}" : content).RootElement.Clone(); }
        catch (JsonException) { throw new FamilyApiException($"服务返回的数据格式不正确（{(int)response.StatusCode}）。"); }
        if (!response.IsSuccessStatusCode)
        {
            var message = new FamilyRecord(data).Text("error");
            if (string.IsNullOrEmpty(message)) message = new FamilyRecord(data).Text("message");
            throw new FamilyApiException(string.IsNullOrEmpty(message) ? $"请求失败（{(int)response.StatusCode}）。" : message);
        }
        return data;
    }

    public async Task LoadAsync()
    {
        var current = generation;
        var profile = new FamilyRecord(await CallAsync("/api/user/profile?channel=pc"));
        if (current != generation) return;
        Profile = profile;
        if (!ParentReady) return;
        var groups = FamilyRecord.Array(await CallAsync("/api/family-groups"));
        if (current != generation) return;
        Groups = groups;
        if (!groups.Any(item => item.Id == GroupId)) GroupId = groups.FirstOrDefault().Id;
        await LoadFamilyAsync(current);
    }

    public async Task SelectParentAsync()
    {
        await CallAsync("/api/user/profile", HttpMethod.Post, new { channel = "pc", role = "parent" });
        await LoadAsync();
    }

    public async Task SelectGroupAsync(int id)
    {
        if (!Groups.Any(item => item.Id == id)) throw new FamilyApiException("无法访问该家庭。");
        ++generation;
        GroupId = id;
        Children = []; Rules = []; Requests = []; Transactions = [];
        await LoadFamilyAsync(generation);
    }

    private async Task LoadFamilyAsync(int current)
    {
        var children = FamilyRecord.Array(await CallAsync($"/api/children?{Scope}"));
        var rules = FamilyRecord.Array(await CallAsync("/api/rules"), "rules");
        var requests = FamilyRecord.Array(await CallAsync("/api/reward-requests?limit=50"), "requests");
        var ledger = await CallAsync("/api/transactions?page=1&pageSize=30");
        var data = new FamilyRecord(ledger).Get("data");
        var transactions = FamilyRecord.Array(data, "items");
        if (current != generation) return;
        Children = children; Rules = rules; Requests = requests; Transactions = transactions;
        LedgerTotal = new FamilyRecord(data).Int("total");
        LedgerPage = 1;
    }

    public async Task LoadMoreLedgerAsync()
    {
        if (Transactions.Count >= LedgerTotal) return;
        var page = LedgerPage + 1;
        var result = await CallAsync($"/api/transactions?page={page}&pageSize=30");
        var data = new FamilyRecord(result).Get("data");
        Transactions.AddRange(FamilyRecord.Array(data, "items"));
        LedgerPage = page;
    }
}

public sealed class FamilyApiException(string message) : Exception(message);

public readonly record struct FamilyRecord(JsonElement Data)
{
    public int Id => Int("id");
    public JsonElement Get(string key) => Data.ValueKind == JsonValueKind.Object && Data.TryGetProperty(key, out var value) ? value : default;
    public string Text(string key)
    {
        var value = Get(key);
        return value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    }
    public int Int(string key)
    {
        var value = Get(key);
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var result) ? result : 0;
    }
    public decimal Number(string key)
    {
        var value = Get(key);
        return value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var result) ? result : 0;
    }
    public bool Bool(string key) => Get(key).ValueKind == JsonValueKind.True;
    public static List<FamilyRecord> Array(JsonElement value, string? key = null)
    {
        if (key is not null) value = new FamilyRecord(value).Get(key);
        if (value.ValueKind != JsonValueKind.Array) throw new FamilyApiException("服务返回的列表格式不正确。");
        return value.EnumerateArray().Select(row => new FamilyRecord(row)).ToList();
    }
}
