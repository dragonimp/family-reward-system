using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

var dsn = new Npgsql.NpgsqlConnectionStringBuilder(
    Environment.GetEnvironmentVariable("MOMENT_QA_DSN") ?? "");
if (dsn.Host != "/tmp" || !System.Text.RegularExpressions.Regex.IsMatch(dsn.Database ?? "", "^dining_social_test_[0-9a-f]{32}$"))
    throw new InvalidOperationException("The test harness requires an isolated local dining_social_test database.");
var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://127.0.0.1:28463");
builder.Services.AddAuthentication("fixture").AddScheme<AuthenticationSchemeOptions, FixtureAuthentication>("fixture", null);
builder.Services.AddAuthorization();
var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();
app.MapDiningGatherings(dsn.ConnectionString,
    request => request.HttpContext.User.FindFirstValue(ClaimTypes.NameIdentifier));
app.MapDiningCircle(dsn.ConnectionString, request => request.HttpContext.User.FindFirstValue(ClaimTypes.NameIdentifier));
app.Run();

sealed class FixtureAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger,
    System.Text.Encodings.Web.UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Guid.TryParse(Request.Headers["X-Fixture-User"], out var id))
            return Task.FromResult(AuthenticateResult.NoResult());
        var identity = new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, id.ToString("D"))], Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name)));
    }
}
