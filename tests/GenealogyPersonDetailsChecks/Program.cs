using System.Text.Json.Nodes;

static GenealogyPersonDetails Read(string json)
{
    if (!GenealogyPersonDetailsParser.TryRead(JsonNode.Parse(json)!.AsObject(), out var details, out var error))
        throw new Exception($"Expected valid: {json}: {error}");
    return details;
}
static void Reject(string json)
{
    if (GenealogyPersonDetailsParser.TryRead(JsonNode.Parse(json)!.AsObject(), out _, out _))
        throw new Exception($"Expected rejection: {json}");
}
if (Read("{}").BirthProvided) throw new Exception("Old client omission must preserve existing birth date");
if (Read("{\"birthYear\":\"1980\"}").BirthMonth is not null) throw new Exception("Year only gained a month");
if (Read("{\"birthYear\":1980,\"birthMonth\":7}").BirthDay is not null) throw new Exception("Month only gained a day");
if (Read("{\"birthYear\":2000,\"birthMonth\":2,\"birthDay\":29,\"gender\":\"female\"}").Gender != "female") throw new Exception("Valid leap date or gender changed");
if (!Read("{\"gender\":\"\",\"birthYear\":\"\"}").BirthProvided) throw new Exception("Explicit clear must be recognized");
Reject("{\"birthMonth\":5}");
Reject("{\"birthYear\":2001,\"birthDay\":3}");
Reject("{\"birthYear\":2001,\"birthMonth\":2,\"birthDay\":29}");
Reject("{\"birthYear\":0}");
Reject("{\"birthYear\":2000,\"birthMonth\":13}");
Reject("{\"gender\":\"unknown\"}");
Console.WriteLine("Genealogy person details checks passed");
