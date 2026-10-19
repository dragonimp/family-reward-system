using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace LinkoFamily;

public sealed record FeedbackWallPost(int Id, string Category, string Title, string Content,
    DateTimeOffset CreatedAt, bool RequestedPublic, string ModerationStatus, string Status,
    string? ReplyContent, int Upvotes, int Downvotes, int Score, int MyVote, bool IsMine);

public sealed record FeedbackWallSnapshot(int Total, int Wishes, int Opinions, int Upvotes,
    int Downvotes, IReadOnlyList<FeedbackWallPost> Items);

// The native login is issued for happylife.ai. User Center validates that audience
// for this wall; no credentials or feedback records are stored by Linko Moment.
public sealed class FeedbackWallClient
{
    private static readonly Uri Origin = new("https://auth.ai.xmkurt.com");
    private static readonly Uri Wall = new(Origin, "/api/feedback/wall/happylife.ai");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly HttpClient SharedHttp = new(new HttpClientHandler
    {
        AllowAutoRedirect = false,
        UseCookies = false
    }) { Timeout = TimeSpan.FromSeconds(35) };

    private readonly Func<CancellationToken, Task<string?>> readToken;
    private readonly Func<bool> needsLogin;
    private readonly Func<long> accountVersion;
    private readonly HttpClient http;

    public FeedbackWallClient(Func<CancellationToken, Task<string?>> readToken,
        Func<bool> needsLogin, Func<long> accountVersion, HttpClient? http = null)
    {
        this.readToken = readToken;
        this.needsLogin = needsLogin;
        this.accountVersion = accountVersion;
        this.http = http ?? SharedHttp;
    }

    public Task<FeedbackWallSnapshot> PublicAsync(CancellationToken ct = default)
        => SendAsync<FeedbackWallSnapshot>(HttpMethod.Get, Wall, null, false, ct);

    public Task<IReadOnlyList<FeedbackWallPost>> MineAsync(CancellationToken ct = default)
        => SendAsync<IReadOnlyList<FeedbackWallPost>>(HttpMethod.Get, new Uri(Wall + "/mine"), null, true, ct);

    public Task<FeedbackWallPost> CreateAsync(Guid requestId, string category, string title,
        string content, bool requestedPublic, CancellationToken ct = default)
        => SendAsync<FeedbackWallPost>(HttpMethod.Post, Wall,
            new { requestId, category, title, content, requestedPublic }, true, ct);

    public Task<FeedbackWallPost> VoteAsync(int id, int value, CancellationToken ct = default)
        => SendAsync<FeedbackWallPost>(HttpMethod.Put, new Uri(Wall + $"/{id}/vote"),
            new { value }, true, ct);

    private async Task<T> SendAsync<T>(HttpMethod method, Uri uri, object? body, bool requiredLogin, CancellationToken ct)
    {
        if (uri.Scheme != Uri.UriSchemeHttps || uri.GetLeftPart(UriPartial.Authority) != Origin.AbsoluteUri.TrimEnd('/'))
            throw new InvalidOperationException("反馈地址无效。");
        var version = accountVersion();
        string? token = null;
        if (requiredLogin && needsLogin()) throw LoginRequired();
        if (!needsLogin())
        {
            token = await readToken(ct);
            if (string.IsNullOrWhiteSpace(token)) throw LoginRequired();
        }
        if (accountVersion() != version) throw new OperationCanceledException("账号已切换，请刷新反馈。", ct);
        using var request = new HttpRequestMessage(method, uri);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (body is not null) request.Content = new StringContent(JsonSerializer.Serialize(body, Json), Encoding.UTF8, "application/json");
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (accountVersion() != version) throw new OperationCanceledException("账号已切换，请刷新反馈。", ct);
        if (response.StatusCode == HttpStatusCode.Unauthorized) throw LoginRequired();
        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync(ct);
            string? message = null;
            try
            {
                using var document = JsonDocument.Parse(error);
                message = document.RootElement.GetProperty("message").GetString();
            }
            catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException) { }
            throw new HttpRequestException(message ?? $"反馈服务返回错误（{(int)response.StatusCode}）。", null, response.StatusCode);
        }
        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        var result = await JsonSerializer.DeserializeAsync<T>(stream, Json, ct)
            ?? throw new InvalidDataException("反馈服务返回空内容。");
        if (accountVersion() != version) throw new OperationCanceledException("账号已切换，请刷新反馈。", ct);
        return result;
    }

    private static HttpRequestException LoginRequired()
        => new("请先在“我的”登录用户中心。", null, HttpStatusCode.Unauthorized);
}
