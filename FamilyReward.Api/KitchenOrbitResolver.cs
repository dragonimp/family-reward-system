using System.Text.Json.Nodes;

internal static class KitchenOrbitResolver
{
    // The SDK directory is already scoped to this authenticated user's WebApp grants.
    internal static int? Select(JsonArray authorized, string username, int? configured)
    {
        var active = authorized.OfType<JsonObject>().Where(a => string.Equals(a["status"]?.ToString(), "Active", StringComparison.OrdinalIgnoreCase));
        var target = configured.HasValue
            ? active.FirstOrDefault(a => int.TryParse(a["id"]?.ToString(), out var id) && id == configured)
            : active.FirstOrDefault(a => a["agentType"]?.ToString() == "Goldfish"
                && string.Equals(a["ownerUsername"]?.ToString(), username, StringComparison.OrdinalIgnoreCase));
        return int.TryParse(target?["id"]?.ToString(), out var selected) ? selected : null;
    }
}
