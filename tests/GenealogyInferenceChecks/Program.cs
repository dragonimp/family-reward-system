var names = Enumerable.Range(1, 11).ToDictionary(id => (long)id, id => $"人物{id}");
var edges = new List<GenealogyBaseRelationship>
{
    new(2, 1, "parent"), new(3, 1, "parent"),
    new(2, 4, "parent"), new(3, 4, "parent"),
    new(5, 2, "parent"), new(5, 6, "parent"),
    new(6, 7, "parent"), new(1, 8, "parent"),
    new(8, 9, "parent"), new(4, 10, "parent"),
    new(1, 11, "spouse")
};

static void Expect(IEnumerable<GenealogyInferredRelationship> result, long id, string kind)
{
    if (result.Count(item => item.PersonId == id && item.Kind == kind) != 1)
        throw new Exception($"Expected exactly one {kind} relation to {id}");
}

var inferred = GenealogyInference.Infer(1, names, edges);
Expect(inferred, 4, "sibling");
Expect(inferred, 5, "grandparent");
Expect(inferred, 9, "grandchild");
Expect(inferred, 6, "parentSibling");
Expect(inferred, 10, "siblingChild");
Expect(inferred, 7, "cousin");
if (inferred.Count != 6 || inferred.Any(item => item.PersonId is 1 or 2 or 3 or 8 or 11))
    throw new Exception("Direct relations or self were inferred");
var json = System.Text.Json.JsonSerializer.Serialize(inferred[0],
    new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web));
if (!json.Contains("\"id\":4") || !json.Contains("\"personId\":4"))
    throw new Exception("Native and web clients need stable inferred person identifiers");

var halfSiblingEdges = edges.Where(edge => edge != new GenealogyBaseRelationship(3, 4, "parent")).ToList();
Expect(GenealogyInference.Infer(1, names, halfSiblingEdges), 4, "sibling");

var noSharedParentEdges = edges.Where(edge => edge.ToPersonId != 4 || edge.Kind != "parent").ToList();
var recomputed = GenealogyInference.Infer(1, names, noSharedParentEdges);
if (recomputed.Any(item => item.PersonId is 4 or 10))
    throw new Exception("Removed parent edges must remove sibling-derived relations");

if (GenealogyInference.Infer(1, names, [new(1, 11, "spouse")]).Count != 0)
    throw new Exception("A spouse alone cannot imply a blood relationship");

Console.WriteLine("Genealogy inference checks passed");
