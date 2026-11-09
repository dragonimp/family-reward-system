using System.Text.Json;

namespace LinkoFamily;

// Reuses the activity map's Leaflet/OSM presentation. No login token or user
// metadata enters the renderer; only this view's validated route coordinates.
internal sealed class ExerciseRouteView : ContentView
{
    readonly WebView map = new() { HeightRequest = 300 };
    readonly Label state = MomentStyle.Caption("地图加载中…");
    string route = "[]"; bool live, ready; int revision;
    public ExerciseRouteView(bool expanded = false)
    {
        if (expanded) { map.HeightRequest = -1; map.MinimumHeightRequest = 300; }
        var grid = new Grid { RowDefinitions = new RowDefinitionCollection { new(GridLength.Star), new(GridLength.Auto) } };
        grid.Add(map); grid.Add(state, 0, 1); Content = grid;
        map.Navigated += async (_, e) => { ready = e.Result == WebNavigationResult.Success; if (ready) { if (route == "[]") state.Text = "开启地图模式并开始运动后，GPS 轨迹会显示在这里。"; await Draw(); } else state.Text = "地图暂未加载，请检查网络。轨迹记录不受影响。"; };
        map.Navigating += (_, e) => { if (e.Url.StartsWith("http", StringComparison.OrdinalIgnoreCase)) { e.Cancel = true; if (Uri.TryCreate(e.Url, UriKind.Absolute, out var url)) _ = AgentIdentity.Maui.InAppWebLinks.OpenAsync(url); } };
        map.Source = new HtmlWebViewSource { Html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
            <style>html,body,#map{height:100%;margin:0}button{position:absolute;z-index:1000;right:12px;top:12px;padding:10px;border:0;border-radius:12px;background:white}</style></head><body><div id="map"></div><button onclick="fit()" aria-label="查看完整轨迹">◎</button>
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script><script>
            const map=L.map('map').setView([0,0],2);L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{attribution:'© OpenStreetMap contributors'}).addTo(map);const layers=L.featureGroup().addTo(map);let fitted=false;
            function fit(){if(layers.getLayers().length)map.fitBounds(layers.getBounds(),{maxZoom:17,padding:[25,25]});}
            window.drawRoute=(segments,live,reset)=>{layers.clearLayers();const points=segments.flat();segments.forEach(s=>{if(s.length>1)L.polyline(s,{color:'#149EA7',weight:5}).addTo(layers);});if(points.length){L.circleMarker(points[0],{color:'green',radius:6}).bindTooltip('起点').addTo(layers);L.circleMarker(points[points.length-1],{color:'#149EA7',radius:7}).bindTooltip(live?'当前位置':'终点').addTo(layers);if(!fitted||reset){fit();fitted=true;}else if(live)map.panTo(points[points.length-1]);}else fitted=false;map.invalidateSize();return 'ready';};
            </script></body></html>
            """ };
    }
    public void Update(IReadOnlyList<ExercisePanel.WorkoutPoint> points, bool running, bool reset = false)
    {
        var segments = ExerciseRouteGeometry.Segments(points.Select(p => new ExerciseRouteCoordinate(p.Latitude, p.Longitude, p.RecordedAt, p.Segment)));
        var next = JsonSerializer.Serialize(segments);
        if (next == route && live == running && !reset) return;
        route = next; live = running; revision++;
        state.Text = points.Count == 0 ? "开启地图模式并开始运动后，GPS 轨迹会显示在这里。" : $"已记录 {points.Count} 个轨迹点";
        if (ready && map.Handler != null && IsLoaded) _ = Draw(reset);
    }
    async Task Draw(bool reset = false)
    {
        if (map.Handler == null || !IsLoaded) return;
        var current = revision;
        try {
            var result = await map.EvaluateJavaScriptAsync($"window.drawRoute && window.drawRoute({route},{(live ? "true" : "false")},{(reset ? "true" : "false")})");
            if (current == revision && !(result?.Contains("ready", StringComparison.Ordinal) ?? false)) state.Text = "地图暂未加载，请检查网络。轨迹记录不受影响。";
        } catch { if (current == revision) state.Text = "地图暂未加载，请检查网络。轨迹记录不受影响。"; }
    }
}
