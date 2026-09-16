import http from "node:http";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

// Render the current H5 markup/CSS without executing device/API code or loading family data.
const source = fs.readFileSync(new URL("../../FamilyReward.Api/Program.cs", import.meta.url), "utf8");
const route = source.split('app.MapGet("/watch", () =>')[1];
if (!route) throw new Error("Cannot locate the watch route");
const html = route.split('var html = """')[1]?.split('""";')[0];
if (!html?.includes("<script>")) throw new Error("Cannot extract watch markup");
const fixture = html.slice(html.indexOf("<!doctype"), html.indexOf("<script>")) + "</body></html>";
const index = `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<title>H5 手表布局回归</title>
<style>body{font:16px system-ui}#frames{display:flex;gap:12px;flex-wrap:wrap}iframe{border:1px solid #888}pre{white-space:pre-wrap}</style>
<h1>H5 手表布局回归</h1><p>本地源码、无家庭数据、无接口调用。检查表盘外框边界与 8:9 比例。</p>
<pre id="results">检查中</pre><div id="frames"></div>
<script>
const sizes=[[192,192],[194,368],[240,240],[320,360],[466,466],[368,194]];
Promise.all(sizes.map(([w,h])=>new Promise(resolve=>{
  const frame=document.createElement('iframe');
  frame.width=w;frame.height=h;frame.title=w+'×'+h;frame.src='/watch.html';
  frame.onload=()=>{
    const rect=frame.contentDocument.querySelector('.watch-shell').getBoundingClientRect();
    const ok=rect.left>=-0.5&&rect.top>=-0.5&&rect.right<=w+0.5&&rect.bottom<=h+0.5
      &&Math.abs(rect.width/rect.height-8/9)<0.005;
    resolve((ok?'PASS':'FAIL')+' '+w+'×'+h+': '+rect.width.toFixed(1)+'×'+rect.height.toFixed(1));
  };
  document.querySelector('#frames').append(frame);
}))).then(rows=>document.querySelector('#results').textContent=rows.join('\\n'));
</script></html>`;
const port = Number(process.env.WATCH_LAYOUT_PORT || 5188);
const server = http.createServer((request, response) => {
  response.setHeader("Content-Type", "text/html; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  if (request.url === "/") response.end(index);
  else if (request.url === "/watch.html") response.end(fixture);
  else { response.statusCode = 404; response.end(); }
});
server.listen(port, "127.0.0.1", () => {
  console.log(`Watch layout preview: http://127.0.0.1:${port}`);
  console.log(`Source: ${fileURLToPath(new URL("../../FamilyReward.Api/Program.cs", import.meta.url))}`);
});
