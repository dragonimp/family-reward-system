internal sealed record GenealogyBaseRelationship(long FromPersonId, long ToPersonId, string Kind);
internal sealed record GenealogyInferredRelationship(long PersonId, string DisplayName, string Kind)
{
    public long Id => PersonId;
}

internal static class GenealogyInference
{
    public static IReadOnlyList<GenealogyInferredRelationship> Infer(
        long personId,
        IReadOnlyDictionary<long, string> names,
        IEnumerable<GenealogyBaseRelationship> relationships)
    {
        var parents = new Dictionary<long, HashSet<long>>();
        var children = new Dictionary<long, HashSet<long>>();
        var direct = new HashSet<long> { personId };

        static void Link(Dictionary<long, HashSet<long>> graph, long key, long value)
        {
            if (!graph.TryGetValue(key, out var neighbors)) graph[key] = neighbors = [];
            neighbors.Add(value);
        }

        foreach (var relation in relationships)
        {
            if (relation.Kind == "parent")
            {
                Link(parents, relation.ToPersonId, relation.FromPersonId);
                Link(children, relation.FromPersonId, relation.ToPersonId);
            }
            if (relation.Kind is "parent" or "spouse")
            {
                if (relation.FromPersonId == personId) direct.Add(relation.ToPersonId);
                if (relation.ToPersonId == personId) direct.Add(relation.FromPersonId);
            }
        }

        IEnumerable<long> Parents(long id) => parents.GetValueOrDefault(id) ?? [];
        IEnumerable<long> Children(long id) => children.GetValueOrDefault(id) ?? [];

        var ownParents = Parents(personId).ToHashSet();
        var siblings = ownParents.SelectMany(Children).Where(id => id != personId).ToHashSet();
        var parentSiblings = ownParents
            .SelectMany(parent => Parents(parent).SelectMany(Children))
            .Where(id => !ownParents.Contains(id) && id != personId)
            .ToHashSet();

        var result = new List<GenealogyInferredRelationship>();
        var seen = direct;
        void Add(string kind, IEnumerable<long> candidates)
        {
            foreach (var id in candidates.Where(names.ContainsKey)
                         .OrderBy(id => names[id], StringComparer.Ordinal).ThenBy(id => id))
                if (seen.Add(id)) result.Add(new(id, names[id], kind));
        }

        Add("sibling", siblings);
        Add("grandparent", ownParents.SelectMany(Parents));
        Add("grandchild", Children(personId).SelectMany(Children));
        Add("parentSibling", parentSiblings);
        Add("siblingChild", siblings.SelectMany(Children));
        Add("cousin", parentSiblings.SelectMany(Children));
        return result;
    }
}
