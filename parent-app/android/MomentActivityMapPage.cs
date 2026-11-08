using System.Text.Json;

namespace LinkoFamily;
internal sealed class MomentActivityMapPage : ContentPage
{
    readonly FamilyStore store; readonly MomentScope scope;
    readonly WebView map = new() { MinimumHeightRequest = 350 };
    readonly Label status = MomentStyle.Caption("正在加载活动地点…");
    CancellationTokenSource? running;
    public MomentActivityMapPage(FamilyStore store, MomentScope scope, string title)
    {
        this.store = store; this.scope = scope; Title = "活动地图"; BackgroundColor = MomentStyle.Background;
        var grid = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Auto), new(GridLength.Star) }, Padding = 12 };
        grid.Add(status); grid.Add(map, 0, 1); Content = grid;
        map.Source = new HtmlWebViewSource { Html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
            <style>html,body,#map{height:100%;margin:0}</style></head><body><div id="map"></div>
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script><script>
            const map=L.map('map').setView([0,0],2);L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{attribution:'© OpenStreetMap contributors'}).addTo(map);let markers=L.featureGroup().addTo(map),fitted=false;
            window.updatePoints=points=>{markers.clearLayers();points.forEach(p=>{const label=document.createElement('div');label.textContent=p.name;L.marker([p.latitude,p.longitude]).bindPopup(label).addTo(markers);});if(points.length&&!fitted){map.fitBounds(markers.getBounds(),{maxZoom:16,padding:[20,20]});fitted=true;}};
            </script></body></html>
            """ };
        map.Navigating += (_, e) => { if (e.Url.StartsWith("http", StringComparison.OrdinalIgnoreCase)) { e.Cancel = true; _ = AgentIdentity.Maui.InAppWebLinks.OpenAsync(new Uri(e.Url)); } };
    }
    protected override void OnAppearing() { base.OnAppearing(); running?.Cancel(); running = new CancellationTokenSource(); _ = Refresh(running.Token); }
    protected override void OnDisappearing() { running?.Cancel(); base.OnDisappearing(); }
    async Task Refresh(CancellationToken ct)
    {
        var account = store.SessionVersion;
        try {
            while (!ct.IsCancellationRequested && account == store.SessionVersion) {
                var rows = await store.CallAsync(scope.Api + "/locations", ct:ct); var visits = await store.CallAsync(scope.Api + "/checkins", ct:ct);
                if (account != store.SessionVersion || ct.IsCancellationRequested) return;
                var points = new List<object>();
                foreach (var row in rows.EnumerateArray()) if (row.TryGetProperty("expiresAt", out var expiry) && DateTimeOffset.TryParse(expiry.GetString(), out var end) && end > DateTimeOffset.UtcNow) Add(row, "name");
                foreach (var row in visits.EnumerateArray()) Add(row, "address");
                void Add(JsonElement row, string name) { if (!row.TryGetProperty("latitude", out var lat) || !row.TryGetProperty("longitude", out var lon) || !lat.TryGetDouble(out var x) || !lon.TryGetDouble(out var y) || !double.IsFinite(x) || !double.IsFinite(y) || Math.Abs(x)>90 || Math.Abs(y)>180) return; var text=row.TryGetProperty(name,out var label)?label.ToString():"活动地点"; points.Add(new {latitude=x,longitude=y,name=text}); }
                status.Text = points.Count == 0 ? "暂无活动打卡或在线成员位置。" : $"{points.Count} 个活动地点 · 位置共享由成员自行开启";
                await map.EvaluateJavaScriptAsync("window.updatePoints&&window.updatePoints("+JsonSerializer.Serialize(points)+")");
                await Task.Delay(5000, ct);
            }
        } catch (OperationCanceledException) { } catch { status.Text = "地图暂时无法加载，请返回重试。"; }
    }
}
