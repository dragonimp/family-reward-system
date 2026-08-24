using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;
using MimeKit.Utils;
using Npgsql;
using NpgsqlTypes;

sealed class XiaotiancaiDeviceTestEmailService(IWebHostEnvironment environment, IHttpClientFactory httpClientFactory)
{
    private const string ApkFileName = "家加分手表积分_1.0.0_100_signed.apk";
    private const string ReportFileName = "家加分手表积分_测试报告.pdf";
    private const string MetadataFileName = "release-metadata.json";
    private readonly string _releaseDirectory = ResolveReleaseDirectory(environment.ContentRootPath);

    public async Task<XiaotiancaiDeviceTestEmailPreview> GetPreviewAsync(
        string connectionString,
        string requestedBy,
        CancellationToken cancellationToken)
    {
        var release = await LoadReleaseAsync(cancellationToken);
        var configuration = ReadConfiguration();
        var credential = await TryResolveCredentialAsync(configuration, includeSecret: false, cancellationToken);
        var submissions = await ListSubmissionsAsync(connectionString, cancellationToken);
        var previousMessageId = submissions.FirstOrDefault(item => item.Status == "sent")?.MessageId
            ?? configuration.ThreadMessageId;
        return new XiaotiancaiDeviceTestEmailPreview(
            configuration.ToAddress,
            configuration.FromAddress,
            "Z8A",
            release.AppName,
            release.PackageId,
            release.VersionName,
            release.VersionCode,
            release.LastVerifiedAt,
            release.ApkSha256,
            release.ReportSha256,
            previousMessageId,
            BuildSubject(previousMessageId, "Z8A"),
            BuildBody(release, "Z8A"),
            release.Attachments,
            configuration.IsConfigured,
            credential is not null,
            requestedBy,
            submissions);
    }

    public async Task<XiaotiancaiDeviceTestEmailSubmission> SendAsync(
        string connectionString,
        string requestedBy,
        XiaotiancaiDeviceTestEmailRequest request,
        CancellationToken cancellationToken)
    {
        if (!request.Confirmed)
            throw new XiaotiancaiEmailValidationException("请先确认收件人、正文和附件哈希");
        var deviceModel = NormalizeDeviceModel(request.DeviceModel);
        var release = await LoadReleaseAsync(cancellationToken);
        if (!FixedTimeEquals(request.ExpectedApkSha256, release.ApkSha256)
            || !FixedTimeEquals(request.ExpectedReportSha256, release.ReportSha256))
            throw new XiaotiancaiEmailConflictException("发布材料已变化，请刷新预览后重新确认");

        var configuration = ReadConfiguration();
        if (!configuration.IsConfigured)
            throw new XiaotiancaiEmailConfigurationException("小天才申请邮件发送凭证尚未配置");

        var previousMessageId = await GetPreviousMessageIdAsync(connectionString, cancellationToken)
            ?? configuration.ThreadMessageId;
        var subject = BuildSubject(previousMessageId, deviceModel);
        var body = BuildBody(release, deviceModel);
        var attachmentManifest = JsonSerializer.Serialize(release.Attachments);
        var submissionId = await BeginSubmissionAsync(
            connectionString,
            requestedBy,
            configuration,
            deviceModel,
            release,
            subject,
            previousMessageId,
            attachmentManifest,
            cancellationToken);

        try
        {
            var credential = await TryResolveCredentialAsync(configuration, includeSecret: true, cancellationToken)
                ?? throw new XiaotiancaiEmailConfigurationException("用户中心中未找到可用的发件邮箱凭证");
            var message = BuildMessage(configuration, release, subject, body, previousMessageId);
            using var smtp = new SmtpClient();
            await smtp.ConnectAsync(configuration.SmtpHost, configuration.SmtpPort, SecureSocketOptions.SslOnConnect, cancellationToken);
            await smtp.AuthenticateAsync(credential.Username, credential.Password, cancellationToken);
            var providerResponse = await smtp.SendAsync(message, cancellationToken);
            await smtp.DisconnectAsync(true, cancellationToken);
            return await CompleteSubmissionAsync(
                connectionString,
                submissionId,
                message.MessageId,
                providerResponse,
                cancellationToken);
        }
        catch (Exception exception)
        {
            var safeError = SanitizeFailure(exception.Message);
            await FailSubmissionAsync(connectionString, submissionId, safeError, cancellationToken);
            if (exception is XiaotiancaiEmailException) throw;
            throw new XiaotiancaiEmailSendException($"邮件发送失败：{safeError}");
        }
    }

    private async Task<XiaotiancaiRelease> LoadReleaseAsync(CancellationToken cancellationToken)
    {
        var metadataPath = Path.Combine(_releaseDirectory, MetadataFileName);
        var apkPath = Path.Combine(_releaseDirectory, ApkFileName);
        var reportPath = Path.Combine(_releaseDirectory, ReportFileName);
        if (!File.Exists(metadataPath) || !File.Exists(apkPath) || !File.Exists(reportPath))
            throw new XiaotiancaiEmailConfigurationException("小天才发布材料不完整");

        await using var metadataStream = File.OpenRead(metadataPath);
        var metadata = await JsonSerializer.DeserializeAsync<XiaotiancaiReleaseMetadata>(
            metadataStream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true },
            cancellationToken) ?? throw new XiaotiancaiEmailConfigurationException("发布元数据无法解析");
        var reportSha256 = metadata.Files.FirstOrDefault(item => item.Name == ReportFileName)?.Sha256
            ?? throw new XiaotiancaiEmailConfigurationException("发布元数据缺少测试报告哈希");
        var actualApkSha256 = await ComputeSha256Async(apkPath, cancellationToken);
        var actualReportSha256 = await ComputeSha256Async(reportPath, cancellationToken);
        if (!FixedTimeEquals(actualApkSha256, metadata.Apk.Sha256)
            || !FixedTimeEquals(actualReportSha256, reportSha256))
            throw new XiaotiancaiEmailConflictException("APK 或测试报告与发布元数据不一致");

        var attachments = new List<XiaotiancaiEmailAttachment>
        {
            new(ApkFileName, new FileInfo(apkPath).Length, actualApkSha256, "application/vnd.android.package-archive"),
            new(ReportFileName, new FileInfo(reportPath).Length, actualReportSha256, "application/pdf"),
            new(MetadataFileName, new FileInfo(metadataPath).Length, await ComputeSha256Async(metadataPath, cancellationToken), "application/json")
        };
        return new XiaotiancaiRelease(
            metadata.AppName,
            metadata.PackageId,
            metadata.VersionName,
            metadata.VersionCode,
            metadata.LastVerifiedAt,
            actualApkSha256,
            actualReportSha256,
            apkPath,
            reportPath,
            metadataPath,
            attachments);
    }

    private async Task<XiaotiancaiEmailCredential?> TryResolveCredentialAsync(
        XiaotiancaiEmailConfiguration configuration,
        bool includeSecret,
        CancellationToken cancellationToken)
    {
        if (!configuration.IsConfigured) return null;
        using var http = httpClientFactory.CreateClient();
        http.Timeout = TimeSpan.FromSeconds(20);
        using var listRequest = CreateUserCenterRequest(
            HttpMethod.Get,
            $"{configuration.UserCenterUrl}/auth/api/security-authorizations/application-credentials",
            configuration.SecurityAuthorizationCode);
        using var listResponse = await http.SendAsync(listRequest, cancellationToken);
        if (!listResponse.IsSuccessStatusCode) return null;
        var credentials = await listResponse.Content.ReadFromJsonAsync<List<UserCenterCredential>>(
            cancellationToken: cancellationToken) ?? [];
        var candidate = credentials.SingleOrDefault(item =>
            item.Provider.Equals("email", StringComparison.OrdinalIgnoreCase)
            && (configuration.CredentialId <= 0 || item.Id == configuration.CredentialId)
            && (string.IsNullOrWhiteSpace(configuration.CredentialName) || item.Name == configuration.CredentialName)
            && (string.IsNullOrWhiteSpace(configuration.FromAddress)
                || string.Equals(item.Username, configuration.FromAddress, StringComparison.OrdinalIgnoreCase)));
        if (candidate is null || string.IsNullOrWhiteSpace(candidate.Username) || !includeSecret)
            return candidate is null || string.IsNullOrWhiteSpace(candidate.Username) ? null : new(candidate.Username, "");

        using var runtimeRequest = CreateUserCenterRequest(
            HttpMethod.Get,
            $"{configuration.UserCenterUrl}/auth/api/security-authorizations/application-credentials/{candidate.Id}/runtime",
            configuration.SecurityAuthorizationCode);
        using var runtimeResponse = await http.SendAsync(runtimeRequest, cancellationToken);
        if (!runtimeResponse.IsSuccessStatusCode) return null;
        var runtime = await runtimeResponse.Content.ReadFromJsonAsync<UserCenterCredentialRuntime>(
            cancellationToken: cancellationToken);
        return runtime is null || string.IsNullOrWhiteSpace(runtime.Username) || string.IsNullOrWhiteSpace(runtime.Password)
            ? null
            : new(runtime.Username, runtime.Password);
    }

    private MimeMessage BuildMessage(
        XiaotiancaiEmailConfiguration configuration,
        XiaotiancaiRelease release,
        string subject,
        string body,
        string? previousMessageId)
    {
        var message = new MimeMessage();
        message.From.Add(new MailboxAddress("厦门图灵软件有限公司", configuration.FromAddress));
        message.To.Add(MailboxAddress.Parse(configuration.ToAddress));
        message.Subject = subject;
        message.MessageId = MimeUtils.GenerateMessageId("impx.net");
        if (!string.IsNullOrWhiteSpace(previousMessageId))
        {
            var normalized = NormalizeMessageId(previousMessageId);
            message.InReplyTo = normalized;
            message.References.Add(normalized);
        }
        var builder = new BodyBuilder { TextBody = body };
        builder.Attachments.Add(release.ApkPath, ContentType.Parse("application/vnd.android.package-archive"));
        builder.Attachments.Add(release.ReportPath, ContentType.Parse("application/pdf"));
        builder.Attachments.Add(release.MetadataPath, ContentType.Parse("application/json"));
        message.Body = builder.ToMessageBody();
        return message;
    }

    private static string BuildSubject(string? previousMessageId, string deviceModel) => string.IsNullOrWhiteSpace(previousMessageId)
        ? $"〖版本验收〗家加分手表积分｜{deviceModel} 真机调试与开发接入申请"
        : $"Re: 〖版本验收〗家加分手表积分｜{deviceModel} 真机调试与开发接入申请（最新验证材料）";

    private static string BuildBody(XiaotiancaiRelease release, string deviceModel) => $"""
        小天才开放平台团队，您好：

        现发送“家加分手表积分”当前最新验证材料。如本邮件属于重发，请以本邮件附件替代此前同主题邮件中的附件。

        应用信息：
        - 应用名称：{release.AppName}
        - 包名：{release.PackageId}
        - 当前发布版本：{release.VersionName}（versionCode {release.VersionCode}）
        - 目标机型：小天才 {deviceModel}
        - 目标环境：小天才定制 Android 8.1、320×360
        - APK SHA-256：{release.ApkSha256}
        - 最新测试报告 SHA-256：{release.ReportSha256}

        Android 8.1/API 27 AOSP、WebView 61、320×360 环境的前置兼容检查已通过；小天才 {deviceModel} 物理真机结论仍待贵方开放调试能力后执行。

        烦请协助确认：
        1. {deviceModel} 是否属于当前可开发、可测试及可提审机型；
        2. 开发数据线的获取方式；
        3. {deviceModel} 的 ADB 调试权限、固件要求及测试环境切换流程；
        4. 是否必须接入小天才账号 SDK、应用服务号或 JSBridge；
        5. 正式版本验收和真机测试报告的最新要求。

        附件：
        1. 正式签名 APK
        2. 最新测试报告
        3. 发布验证元数据

        谢谢。

        厦门图灵软件有限公司
        联系邮箱：dragonimp@impx.net
        """;

    private static async Task<int> BeginSubmissionAsync(
        string connectionString,
        string requestedBy,
        XiaotiancaiEmailConfiguration configuration,
        string deviceModel,
        XiaotiancaiRelease release,
        string subject,
        string? previousMessageId,
        string attachmentManifest,
        CancellationToken cancellationToken)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(cancellationToken);
        await using var cmd = new NpgsqlCommand("""
            WITH expired AS (
                UPDATE xiaotiancai_device_test_email_submissions
                SET status = 'failed', error_message = '发送进程中断，可重新发送', updated_at = CURRENT_TIMESTAMP
                WHERE status = 'sending' AND created_at < CURRENT_TIMESTAMP - INTERVAL '10 minutes'
            )
            INSERT INTO xiaotiancai_device_test_email_submissions
                (requested_by, recipient, sender, device_model, version_name, version_code,
                 subject, previous_message_id, attachment_manifest, status)
            VALUES
                (@requested_by, @recipient, @sender, @device_model, @version_name, @version_code,
                 @subject, @previous_message_id, @attachment_manifest, 'sending')
            RETURNING id
            """, conn);
        cmd.Parameters.AddWithValue("requested_by", requestedBy);
        cmd.Parameters.AddWithValue("recipient", configuration.ToAddress);
        cmd.Parameters.AddWithValue("sender", configuration.FromAddress);
        cmd.Parameters.AddWithValue("device_model", deviceModel);
        cmd.Parameters.AddWithValue("version_name", release.VersionName);
        cmd.Parameters.AddWithValue("version_code", release.VersionCode);
        cmd.Parameters.AddWithValue("subject", subject);
        cmd.Parameters.AddWithValue("previous_message_id", (object?)previousMessageId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("attachment_manifest", NpgsqlDbType.Jsonb, attachmentManifest);
        try
        {
            return Convert.ToInt32(await cmd.ExecuteScalarAsync(cancellationToken));
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw new XiaotiancaiEmailConflictException("已有一封申请邮件正在发送，请稍后刷新");
        }
    }

    private static async Task<XiaotiancaiDeviceTestEmailSubmission> CompleteSubmissionAsync(
        string connectionString,
        int id,
        string messageId,
        string providerResponse,
        CancellationToken cancellationToken)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(cancellationToken);
        await using var cmd = new NpgsqlCommand("""
            UPDATE xiaotiancai_device_test_email_submissions
            SET status = 'sent', message_id = @message_id, provider_response = @provider_response,
                sent_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE id = @id
            RETURNING id, requested_by, recipient, sender, device_model, version_name, version_code,
                      subject, message_id, previous_message_id, attachment_manifest::text, status,
                      provider_response, error_message, sent_at, created_at, updated_at
            """, conn);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("message_id", messageId);
        cmd.Parameters.AddWithValue("provider_response", Truncate(providerResponse, 1000));
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
            throw new XiaotiancaiEmailSendException("邮件已发送，但发送记录写入失败");
        return ReadSubmission(reader);
    }

    private static async Task FailSubmissionAsync(
        string connectionString,
        int id,
        string error,
        CancellationToken cancellationToken)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(cancellationToken);
        await using var cmd = new NpgsqlCommand("""
            UPDATE xiaotiancai_device_test_email_submissions
            SET status = 'failed', error_message = @error_message, updated_at = CURRENT_TIMESTAMP
            WHERE id = @id
            """, conn);
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("error_message", Truncate(error, 1000));
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<string?> GetPreviousMessageIdAsync(string connectionString, CancellationToken cancellationToken)
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(cancellationToken);
        await using var cmd = new NpgsqlCommand("""
            SELECT message_id
            FROM xiaotiancai_device_test_email_submissions
            WHERE status = 'sent' AND message_id IS NOT NULL
            ORDER BY sent_at DESC NULLS LAST, id DESC
            LIMIT 1
            """, conn);
        return Convert.ToString(await cmd.ExecuteScalarAsync(cancellationToken));
    }

    private static async Task<List<XiaotiancaiDeviceTestEmailSubmission>> ListSubmissionsAsync(
        string connectionString,
        CancellationToken cancellationToken)
    {
        var result = new List<XiaotiancaiDeviceTestEmailSubmission>();
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(cancellationToken);
        await using var cmd = new NpgsqlCommand("""
            SELECT id, requested_by, recipient, sender, device_model, version_name, version_code,
                   subject, message_id, previous_message_id, attachment_manifest::text, status,
                   provider_response, error_message, sent_at, created_at, updated_at
            FROM xiaotiancai_device_test_email_submissions
            ORDER BY created_at DESC, id DESC
            LIMIT 20
            """, conn);
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken)) result.Add(ReadSubmission(reader));
        return result;
    }

    private static XiaotiancaiDeviceTestEmailSubmission ReadSubmission(NpgsqlDataReader reader) => new(
        reader.GetInt32(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetString(4),
        reader.GetString(5),
        reader.GetInt32(6),
        reader.GetString(7),
        reader.IsDBNull(8) ? null : reader.GetString(8),
        reader.IsDBNull(9) ? null : reader.GetString(9),
        JsonSerializer.Deserialize<List<XiaotiancaiEmailAttachment>>(reader.GetString(10)) ?? [],
        reader.GetString(11),
        reader.IsDBNull(12) ? null : reader.GetString(12),
        reader.IsDBNull(13) ? null : reader.GetString(13),
        reader.IsDBNull(14) ? null : reader.GetDateTime(14),
        reader.GetDateTime(15),
        reader.GetDateTime(16));

    private static XiaotiancaiEmailConfiguration ReadConfiguration()
    {
        var baseUrl = (Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_USER_CENTER_URL")
            ?? "https://auth.ai.xmkurt.com").TrimEnd('/');
        var credentialId = int.TryParse(Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_CREDENTIAL_ID"), out var id) ? id : 0;
        var smtpPort = int.TryParse(Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_SMTP_PORT"), out var port) ? port : 465;
        return new(
            baseUrl,
            Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_SECURITY_AUTHORIZATION_CODE")?.Trim() ?? "",
            credentialId,
            Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_CREDENTIAL_NAME")?.Trim() ?? "",
            Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_FROM")?.Trim() ?? "dragonimp@impx.net",
            Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_TO")?.Trim() ?? "developer@eebbk.com",
            Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_SMTP_HOST")?.Trim() ?? "smtp.qq.com",
            smtpPort,
            Environment.GetEnvironmentVariable("XIAOTIANCAI_EMAIL_THREAD_MESSAGE_ID")?.Trim() ?? "");
    }

    private static HttpRequestMessage CreateUserCenterRequest(HttpMethod method, string url, string code)
    {
        var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", code);
        return request;
    }

    private static string ResolveReleaseDirectory(string contentRoot)
    {
        var configured = Environment.GetEnvironmentVariable("XIAOTIANCAI_RELEASE_DIR")?.Trim();
        if (!string.IsNullOrWhiteSpace(configured)) return Path.GetFullPath(configured);
        var published = Path.Combine(contentRoot, "xiaotiancai-release");
        if (Directory.Exists(published)) return published;
        return Path.GetFullPath(Path.Combine(contentRoot, "..", "docs", "publishing", "xiaotiancai", "release-bundle"));
    }

    private static string NormalizeDeviceModel(string? value)
    {
        var normalized = (value ?? "").Trim().ToUpperInvariant();
        if (normalized.Length is < 2 or > 20 || normalized.Any(ch => !char.IsAsciiLetterOrDigit(ch) && ch is not '-' and not '_'))
            throw new XiaotiancaiEmailValidationException("请输入有效的小天才设备型号");
        return normalized;
    }

    private static string NormalizeMessageId(string value)
    {
        var normalized = value.Trim();
        if (!normalized.StartsWith('<')) normalized = $"<{normalized}";
        if (!normalized.EndsWith('>')) normalized = $"{normalized}>";
        return normalized;
    }

    private static bool FixedTimeEquals(string? left, string right)
    {
        if (string.IsNullOrWhiteSpace(left)) return false;
        var leftBytes = Encoding.ASCII.GetBytes(left.Trim().ToLowerInvariant());
        var rightBytes = Encoding.ASCII.GetBytes(right.Trim().ToLowerInvariant());
        return leftBytes.Length == rightBytes.Length && CryptographicOperations.FixedTimeEquals(leftBytes, rightBytes);
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexStringLower(hash);
    }

    private static string SanitizeFailure(string value) => Truncate(
        System.Text.RegularExpressions.Regex.Replace(value, "aia_[A-Za-z0-9]+", "[redacted]"),
        1000);

    private static string Truncate(string value, int maxLength) => value.Length <= maxLength ? value : value[..maxLength];

    private sealed record XiaotiancaiRelease(
        string AppName,
        string PackageId,
        string VersionName,
        int VersionCode,
        DateTimeOffset LastVerifiedAt,
        string ApkSha256,
        string ReportSha256,
        string ApkPath,
        string ReportPath,
        string MetadataPath,
        List<XiaotiancaiEmailAttachment> Attachments);

    private sealed record XiaotiancaiEmailConfiguration(
        string UserCenterUrl,
        string SecurityAuthorizationCode,
        int CredentialId,
        string CredentialName,
        string FromAddress,
        string ToAddress,
        string SmtpHost,
        int SmtpPort,
        string ThreadMessageId)
    {
        public bool IsConfigured => !string.IsNullOrWhiteSpace(SecurityAuthorizationCode)
            && !string.IsNullOrWhiteSpace(FromAddress)
            && !string.IsNullOrWhiteSpace(ToAddress);
    }

    private sealed record XiaotiancaiEmailCredential(string Username, string Password);
    private sealed record UserCenterCredential(int Id, string Provider, string Name, string? Username);
    private sealed record UserCenterCredentialRuntime(string Username, string Password);
    private sealed record XiaotiancaiReleaseMetadata(
        string AppName,
        string PackageId,
        string VersionName,
        int VersionCode,
        DateTimeOffset LastVerifiedAt,
        XiaotiancaiReleaseApk Apk,
        List<XiaotiancaiReleaseFile> Files);
    private sealed record XiaotiancaiReleaseApk(string File, long SizeBytes, string Sha256);
    private sealed record XiaotiancaiReleaseFile(string Name, string Sha256);
}

sealed record XiaotiancaiDeviceTestEmailRequest(
    string DeviceModel,
    bool Confirmed,
    string ExpectedApkSha256,
    string ExpectedReportSha256);

sealed record XiaotiancaiDeviceTestEmailPreview(
    string Recipient,
    string Sender,
    string DeviceModel,
    string AppName,
    string PackageId,
    string VersionName,
    int VersionCode,
    DateTimeOffset LastVerifiedAt,
    string ApkSha256,
    string ReportSha256,
    string? PreviousMessageId,
    string Subject,
    string Body,
    List<XiaotiancaiEmailAttachment> Attachments,
    bool SendingConfigured,
    bool CredentialReady,
    string RequestedBy,
    List<XiaotiancaiDeviceTestEmailSubmission> Submissions);

sealed record XiaotiancaiEmailAttachment(string FileName, long SizeBytes, string Sha256, string ContentType);

sealed record XiaotiancaiDeviceTestEmailSubmission(
    int Id,
    string RequestedBy,
    string Recipient,
    string Sender,
    string DeviceModel,
    string VersionName,
    int VersionCode,
    string Subject,
    string? MessageId,
    string? PreviousMessageId,
    List<XiaotiancaiEmailAttachment> Attachments,
    string Status,
    string? ProviderResponse,
    string? ErrorMessage,
    DateTime? SentAt,
    DateTime CreatedAt,
    DateTime UpdatedAt);

abstract class XiaotiancaiEmailException(string message) : Exception(message);
sealed class XiaotiancaiEmailValidationException(string message) : XiaotiancaiEmailException(message);
sealed class XiaotiancaiEmailConflictException(string message) : XiaotiancaiEmailException(message);
sealed class XiaotiancaiEmailConfigurationException(string message) : XiaotiancaiEmailException(message);
sealed class XiaotiancaiEmailSendException(string message) : XiaotiancaiEmailException(message);
