namespace LinkoFamily;

public sealed class DiningSyncRequest
{
    public Guid OperationId { get; set; } = Guid.NewGuid();
    public DiningArchive? Baseline { get; set; }
    public DiningArchive Archive { get; set; } = new();
}
public sealed class DiningSyncState
{
    public DiningArchive Archive { get; set; } = new();
    public DiningArchive? Baseline { get; set; }
    public DiningSyncRequest? Outbox { get; set; }
}
