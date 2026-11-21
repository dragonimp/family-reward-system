namespace LinkoFamily;

public sealed class FamilyApiException(string message, System.Net.HttpStatusCode? statusCode = null) : Exception(message)
{
    public System.Net.HttpStatusCode? StatusCode { get; } = statusCode;
}
