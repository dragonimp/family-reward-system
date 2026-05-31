#!/usr/bin/env python3
"""家庭奖励管理系统 - 后端服务器 (文件持久化版)"""
import json, os, datetime as dt, threading, csv, re
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# ─── File paths ────────────────────────────────────────────────────────────

# 数据文件在同级目录的 data/ 子目录
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
os.makedirs(DATA_DIR, exist_ok=True)
ACCOUNT_FILE = os.path.join(DATA_DIR, 'reward-account.md')
LOG_FILE = os.path.join(DATA_DIR, 'reward-log.csv')
RULES_FILE = os.path.join(DATA_DIR, 'rules.json')
REDLINES_FILE = os.path.join(DATA_DIR, 'redlines.json')

# ─── In-memory store ──────────────────────────────────────────────────────

children_db = {}
accounts_db = {}
transactions_db = []
rules_db = []
redlines_db = []
next_id = {"child": 6, "rule": 15, "redline": 11, "txn": 1}

def parse_account_file():
    """从 reward-account.md 解析账户数据"""
    result = []
    if not os.path.exists(ACCOUNT_FILE):
        return result
    with open(ACCOUNT_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    # 解析每个孩子区块 --- 格式: ### 彦谦\n- 当前余额：积分=108 | 现金=230元 | 物品=2件...
    children = re.split(r'\n### ', content)
    for child_block in children:
        lines = child_block.strip().split('\n')
        if not lines:
            continue
        first_line = lines[0].strip().split(' ')[0]
        # 跳过非孩子名的块（如标题块 "#"）
        if first_line in ('#', ''):
            continue
        name = first_line
        points = cash = items_count = 0
        items_detail = ""
        points_earned = points_spent = cash_earned = cash_spent = 0
        
        for line in lines[1:]:
            line = line.strip().lstrip('- ')
            
            # 解析余额行: "当前余额：积分=108 | 现金=230元 | 物品=2件（2个铲子）"
            if '当前余额' in line or '当前余额：' in line:
                m = re.search(r'积分=(\d+)', line)
                if m: points = int(m.group(1))
                m = re.search(r'现金=(\d+)', line)
                if m: cash = int(m.group(1))
                m = re.search(r'物品=(\d+)件', line)
                if m: items_count = int(m.group(1))
                # 提取物品详情: (2个铲子)
                m = re.search(r'物品=\d+件（(.+?)）', line)
                if m: items_detail = m.group(1)
            
            # 解析累计行: "累计：积分获得=108 | 积分消耗=0 | 现金获得=300元 | 现金支出=70元"
            elif '累计' in line:
                m = re.search(r'积分获得=(\d+)', line)
                if m: points_earned = int(m.group(1))
                m = re.search(r'积分消耗=(\d+)', line)
                if m: points_spent = int(m.group(1))
                m = re.search(r'现金获得=(\d+)', line)
                if m: cash_earned = int(m.group(1))
                m = re.search(r'现金支出=(\d+)', line)
                if m: cash_spent = int(m.group(1))
        
        result.append((name, points, cash, items_count, items_detail,
                      points_earned, points_spent, cash_earned, cash_spent))
    return result

def parse_log_file():
    """从 reward-log.csv 解析交易记录"""
    txns = []
    if not os.path.exists(LOG_FILE):
        return txns
    with open(LOG_FILE, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            txn = {
                'date': row.get('date', row.get('日期', '')),
                'child_id': _child_name_to_id(row.get('child', row.get('孩子', ''))),
                'type': row.get('type', row.get('类型', 'points')),
                'direction': row.get('direction', row.get('方向', '+')),
                'category': row.get('category', row.get('类别', '')),
                'description': row.get('description', row.get('描述', '')),
                'points': float(row.get('points', row.get('积分', 0)) or 0),
                'cash_cny': float(row.get('cash_cny', row.get('现金', 0)) or 0),
                'items': row.get('items', row.get('物品', '')),
                'notes': row.get('notes', row.get('备注', '')),
            }
            # 分配ID
            txn['id'] = next_id["txn"]; next_id["txn"] += 1
            txns.append(txn)
    return txns

def _child_name_to_id(name):
    """名字转ID"""
    names = {"彦谦": 1, "玥玥": 2, "嘟嘟": 3, "薇薇": 4, "小宇": 5}
    return names.get(name, 1)

def load_rules():
    """加载规则数据"""
    if os.path.exists(RULES_FILE):
        with open(RULES_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    return None

def load_redlines():
    """加载红线数据"""
    if os.path.exists(REDLINES_FILE):
        with open(REDLINES_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    return None

def save_account_file():
    """保存账户数据到文件"""
    with open(ACCOUNT_FILE, 'w', encoding='utf-8') as f:
        f.write("# 家庭奖励系统 - 账户余额\n")
        f.write(f"更新时间: {dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        for cid, acc in accounts_db.items():
            child = children_db.get(cid, {})
            name = child.get("name", f"孩子{cid}")
            f.write(f"### {name}\n")
            f.write(f"- 当前积分: {acc.get('points', 0)}\n")
            f.write(f"- 当前现金: {acc.get('cash_cny', 0)} 元\n")
            f.write(f"- 物品: {acc.get('items_count', 0)}\n")
            if acc.get('items_detail'):
                f.write(f"- 物品详情: {acc['items_detail']}\n")
            f.write(f"- 累计获得积分: {acc.get('points_earned', 0)}\n")
            f.write(f"- 累计消费积分: {acc.get('points_spent', 0)}\n")
            f.write(f"- 累计获得现金: {acc.get('cash_earned', 0)} 元\n")
            f.write(f"- 累计消费现金: {acc.get('cash_spent', 0)} 元\n\n")

def save_log_file():
    """保存交易记录到文件"""
    with open(LOG_FILE, 'w', 'utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['date', 'child_id', 'type', 'direction', 
                                                'category', 'description', 'points', 'cash_cny', 
                                                'items', 'notes'])
        writer.writeheader()
        for txn in transactions_db:
            writer.writerow({k: txn.get(k, '') for k in writer.fieldnames})

def init_data():
    """从文件加载数据，如果文件不存在则使用默认值"""
    if children_db: return
    
    # 1. 先初始化默认孩子
    names = ["彦谦", "玥玥", "嘟嘟", "薇薇", "小宇"]
    for cid, name in enumerate(names, 1):
        children_db[cid] = {"id": cid, "name": name, "status": "active", 
                           "note": "", "created_at": "2026-01-01T00:00:00Z"}
        accounts_db[cid] = {"child_id": cid, "points": 0, "cash_cny": 0.0, 
                           "items_count": 0, "items_detail": "", "points_earned": 0, 
                           "points_spent": 0, "cash_earned": 0.0, "cash_spent": 0.0}
    
    # 2. 尝试从文件加载账户数据
    account_data = parse_account_file()
    if account_data:
        for cid, (name, points, cash, items_count, items_detail, 
                  pe, ps, ce, cs) in enumerate(account_data, 1):
            if cid in accounts_db:
                accounts_db[cid].update({
                    "points": points, "cash_cny": cash, "items_count": items_count,
                    "items_detail": items_detail, "points_earned": pe,
                    "points_spent": ps, "cash_earned": ce, "cash_spent": cs
                })
    else:
        # 文件不存在，使用默认初始值
        defaults = [
            (108, 230.0, 2, "2个铲子", 108, 0, 300.0, 70.0),
            (123, 30.0, 1, "水培栽培", 144, 21, 50.0, 20.0),
            (100, 0.0, 0, "", 100, 0, 0.0, 0.0),
            (100, 0.0, 0, "", 100, 0, 0.0, 0.0),
            (100, 0.0, 0, "", 100, 0, 0.0, 0.0),
        ]
        for cid, (pts, cash, items, detail, pe, ps, ce, cs) in enumerate(defaults, 1):
            accounts_db[cid].update({
                "points": pts, "cash_cny": cash, "items_count": items,
                "items_detail": detail, "points_earned": pe,
                "points_spent": ps, "cash_earned": ce, "cash_spent": cs
            })
        # 保存默认数据到文件
        save_account_file()
    
    # 3. 从CSV加载交易记录
    loaded_txns = parse_log_file()
    if loaded_txns:
        transactions_db.extend(loaded_txns)
    
    # 4. 加载规则
    saved_rules = load_rules()
    if saved_rules:
        rules_db.extend(saved_rules)
    else:
        # 默认规则
        defaults = [
            ("按时/及时完成作业", "学习", 5, 0, "规定时间内完成"),
            ("主动完成作业", "学习", 3, 0, "不用催促"),
            ("作业优秀/全对", "学习", 2, 0, "额外奖励"),
            ("主动刷牙", "规矩", 2, 0, "早晚各一次"),
            ("好好吃饭", "规矩", 2, 0, "不挑食、按时吃"),
            ("自己收拾玩具", "规矩", 2, 0, "玩完归位"),
            ("按时睡觉", "规矩", 2, 0, "不拖延"),
            ("主动看书", "学习", 3, 0, "自己拿起书看"),
            ("帮忙做家务", "帮忙", 3, 0, "倒垃圾、擦桌子等"),
            ("分享玩具", "规矩", 2, 0, "不抢不争"),
            ("说谢谢/对不起", "规矩", 1, 0, "礼貌用语"),
            ("帮助他人", "帮忙", 3, 0, "帮助弟弟妹妹或他人"),
            ("遵守红线", "规矩", 5, 0, "连续一段时间遵守红线规则"),
            ("耐心等待", "规矩", 5, 0, "排队、等待时不急躁"),
        ]
        for name, cat, pts, cash, desc in defaults:
            rid = next_id["rule"]; next_id["rule"] += 1
            rules_db.append({"id": rid, "name": name, "category": cat, 
                           "points": pts, "cash_cny": cash, "description": desc})
        # 保存规则
        with open(RULES_FILE, 'w', encoding='utf-8') as f:
            json.dump(rules_db, f, ensure_ascii=False, indent=2)
    
    # 5. 加载红线
    saved_redlines = load_redlines()
    if saved_redlines:
        redlines_db.extend(saved_redlines)
    else:
        rds = [
            (1, "不大喊大叫", "彦谦", "无论什么原因都不允许大喊大叫、乱发脾气", 10),
            (2, "不跟紧大人", "", "外出时必须紧跟父母，不得独自跑开、躲藏", 15),
            (3, "不碰危险物品", "", "不碰剪刀、刀具、火源、药品、电源插座", 20),
            (4, "不私自下水", "", "靠近水边必须有大人陪同，不得独自下水", 20),
            (5, "不跟陌生人走", "", "无论什么理由，不得跟随陌生人离开", 20),
            (6, "不打人/不骂人", "", "不得伤害他人身体或语言侮辱", 15),
            (7, "不撒谎", "", "做错事必须承认，不得隐瞒欺骗", 10),
            (8, "不破坏公物", "", "不得故意损坏公共设施或他人物品", 15),
            (9, "不爬高危险处", "", "不攀爬栏杆、假山、树木、高楼窗户", 20),
            (10, "不乱吃东西", "", "不吃陌生人给的食物，不乱吃不明物品", 15),
        ]
        for o, rule, prop, desc, penalty in rds:
            rid = next_id["redline"]; next_id["redline"] += 1
            redlines_db.append({"id": rid, "order_num": o, "rule": rule, 
                               "proposer": prop, "description": desc, "penalty_points": penalty})
        # 保存红线
        with open(REDLINES_FILE, 'w', encoding='utf-8') as f:
            json.dump(redlines_db, f, ensure_ascii=False, indent=2)

def get_account(cid):
    init_data()
    return accounts_db.get(cid)

def update_account(cid, d):
    init_data()
    acc = accounts_db.get(cid)
    if not acc: raise ValueError("孩子不存在")
    for k, v in d.items():
        acc[k] = v
    return acc

# ─── HTTP Handler ──────────────────────────────────────────────────────────

class APIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # suppress logs

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0: return {}
        return json.loads(self.rfile.read(length))

    def _get_params(self):
        parsed = urlparse(self.path)
        return parse_qs(parsed.query)

    def do_GET(self):
        init_data()
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        params = parse_qs(parsed.query)

        # Health
        if path == "/health":
            return self._send_json({"status": "ok", "version": "1.0.0"})

        # SPA fallback: serve index.html for non-API routes
        if path == "" or path == "/" or path == "/dashboard" or path.startswith("/children") or path.startswith("/rules") or path.startswith("/transactions") or path.startswith("/reward") or path.startswith("/stats"):
            self._send_file("frontend/static/index.html", "text/html")
            return

        # API routes - must come after SPA but before general file serving
        if path == "/api/children":
            # Return children with account data
            result = []
            for c in children_db.values():
                acc = accounts_db.get(c["id"], {})
                child_with_account = {
                    "id": c["id"],
                    "name": c["name"],
                    "status": c["status"],
                    "note": c.get("note", ""),
                    "createdAt": c.get("created_at", ""),
                    "updatedAt": c.get("created_at", ""),
                    "score": acc.get("points", 0),
                    "cash": acc.get("cash_cny", 0),
                    "items": acc.get("items_count", 0),
                }
                result.append(child_with_account)
            self._send_json(result)
        elif path.startswith("/api/children/") and path.count("/") == 3:
            cid = int(path.split("/")[-1])
            child = children_db.get(cid)
            if not child: return self._send_json({"error": "不存在"}, 404)
            child["account"] = accounts_db.get(cid, {})
            self._send_json(child)
        elif path == "/api/transactions":
            cid = int(params.get("child_id", [None])[0]) if params.get("child_id") else None
            txn_type = params.get("type", [None])[0]
            category = params.get("category", [None])[0]
            page = int(params.get("page", [1])[0])
            ps = int(params.get("page_size", [50])[0])
            q = [t for t in transactions_db]
            if cid: q = [t for t in q if t["child_id"] == cid]
            if txn_type: q = [t for t in q if t["type"] == txn_type]
            if category: q = [t for t in q if t.get("category") == category]
            q.sort(key=lambda t: (t["date"], t["id"]), reverse=True)
            total = len(q)
            self._send_json({"items": q[(page-1)*ps:page*ps], "total": total, "page": page, "page_size": ps})
        elif path == "/api/rules":
            self._send_json({"rules": rules_db, "redlines": sorted(redlines_db, key=lambda r: r["order_num"])})
        elif path == "/api/stats/dashboard":
            children = [{"id": c["id"], "name": c["name"], "status": c["status"], "note": c.get("note"),
                        **accounts_db.get(c["id"], {})} for c in children_db.values()]
            recent = sorted(transactions_db, key=lambda t: (t["date"], t["id"]), reverse=True)[:20]
            self._send_json({"children": children, "recent": recent})
        elif path == "/api/stats/children":
            children = [{"id": c["id"], "name": c["name"], "score": accounts_db.get(c["id"], {}).get("points", 0),
                        "cash": accounts_db.get(c["id"], {}).get("cash_cny", 0),
                        "items": accounts_db.get(c["id"], {}).get("items_count", 0),
                        "createdAt": c.get("created_at"), "updatedAt": c.get("created_at")}
                        for c in children_db.values()]
            self._send_json(children)
        elif path == "/api/stats/categories":
            cats: dict[str, int] = {}
            for t in transactions_db:
                cat = t.get("category", "其他")
                pts = t.get("points", 0)
                cats[cat] = cats.get(cat, 0) + pts
            self._send_json([{"category": k, "total": v} for k, v in cats.items()])
        elif path == "/api/stats/trend":
            child_id = params.get("childId", [None])[0]
            months = int(params.get("months", [6])[0])
            if child_id:
                txns = [t for t in transactions_db if t["child_id"] == int(child_id)]
            else:
                txns = transactions_db
            from collections import defaultdict
            daily = defaultdict(int)
            for t in txns:
                daily[t["date"]] += t.get("points", 0)
            trend = [{"date": k, "score": v, "cash": 0, "item": 0} for k, v in sorted(daily.items(), reverse=True)[:months]]
            self._send_json(trend)
        elif path.startswith("/api/stats/child/"):
            cid = int(path.split("/")[-1])
            acc = accounts_db.get(cid)
            if not acc: return self._send_json({"error": "不存在"}, 404)
            txns = [t for t in transactions_db if t["child_id"] == cid]
            self._send_json({**acc, "total_transactions": len(txns)})
        elif path == "/api/stats/leaderboard":
            lb = [{"id": c["id"], "name": c["name"], "points": accounts_db.get(c["id"], {}).get("points", 0)}
                  for c in children_db.values()]
            lb.sort(key=lambda x: x["points"], reverse=True)
            self._send_json(lb)
        else:
            self._send_file("frontend/static" + path, self._guess_mime(path))

    def do_POST(self):
        init_data()
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "/api/children":
            body = self._read_body()
            name = body.get("name", "")
            for c in children_db.values():
                if c["name"] == name:
                    return self._send_json({"error": "该孩子已存在"}, 400)
            cid = next_id["child"]; next_id["child"] += 1
            child = {"id": cid, "name": name, "status": "active", "note": body.get("note", "")}
            children_db[cid] = child
            accounts_db[cid] = {"child_id": cid, "points": 0, "cash_cny": 0.0, "items_count": 0,
                               "items_detail": "", "points_earned": 0, "points_spent": 0,
                               "cash_earned": 0.0, "cash_spent": 0.0}
            self._send_json(child, 201)

        elif path == "/api/children/{cid}/init":
            # POST /api/children/{id}/init via GET workaround
            pass

        elif path == "/api/transactions":
            body = self._read_body()
            cid = body["child_id"]
            acc = accounts_db.get(cid)
            if not acc: return self._send_json({"error": "孩子不存在"}, 400)
            txn_type = body.get("type", "points")
            direction = body.get("direction", "+")
            category = body.get("category", "")
            description = body.get("description", "")
            points = float(body.get("points", 0))
            cash_cny = float(body.get("cash_cny", 0))
            items = body.get("items", "")
            notes = body.get("notes", "")
            date_str = body.get("date") or dt.date.today().isoformat()

            if direction == "-" and txn_type == "points" and points > acc["points"]:
                return self._send_json({"error": "积分不足"}, 400)
            if direction == "-" and txn_type == "cash" and cash_cny > acc["cash_cny"]:
                return self._send_json({"error": "现金不足"}, 400)

            txn = {
                "id": next_id["txn"], "date": date_str, "child_id": cid,
                "type": txn_type, "direction": direction, "category": category,
                "description": description, "points": points, "cash_cny": cash_cny,
                "items": items, "notes": notes
            }
            next_id["txn"] += 1

            if txn_type == "points":
                if direction == "+": acc["points"] += int(points); acc["points_earned"] += int(points)
                else: acc["points"] -= int(points); acc["points_spent"] += int(points)
            if txn_type == "cash":
                if direction == "+": acc["cash_cny"] += cash_cny; acc["cash_earned"] += cash_cny
                else: acc["cash_cny"] -= cash_cny; acc["cash_spent"] += cash_cny
            if txn_type == "items" and direction == "+":
                acc["items_count"] += 1
                acc["items_detail"] = items if acc["items_count"] == 1 else f"{acc['items_detail']},{items}"
            if txn_type == "items" and direction == "-":
                acc["items_count"] -= 1
                if acc["items_count"] == 0: acc["items_detail"] = ""

            transactions_db.append(txn)
            self._send_json({"transaction": txn, "account": acc})

        elif path == "/api/transactions/batch":
            body = self._read_body()
            results = []
            for req in body:
                try:
                    txn, acc = self._create_txn(req)
                    results.append({"child_id": req["child_id"], "success": True})
                except Exception as e:
                    results.append({"child_id": req.get("child_id"), "error": str(e)})
            self._send_json({"results": results})

        elif path == "/api/rules":
            body = self._read_body()
            name = body.get("name", "")
            for r in rules_db:
                if r["name"] == name:
                    return self._send_json({"error": "该规则名称已存在"}, 400)
            rid = next_id["rule"]; next_id["rule"] += 1
            rule = {"id": rid, "name": name, "category": body.get("category", ""),
                   "points": int(body.get("points", 0)), "cash_cny": float(body.get("cash_cny", 0)),
                   "description": body.get("description", "")}
            rules_db.append(rule)
            self._send_json(rule, 201)

        elif path.startswith("/api/children/") and path.endswith("/init"):
            cid = int(path.split("/")[-2])
            body = self._read_body()
            acc = accounts_db.get(cid)
            if not acc: return self._send_json({"error": "不存在"}, 400)
            acc["points"] = int(body.get("points", 0))
            acc["cash_cny"] = float(body.get("cash_cny", 0))
            acc["points_earned"] = acc["points"]
            acc["points_spent"] = 0
            acc["cash_earned"] = acc["cash_cny"]
            acc["cash_spent"] = 0
            self._send_json(acc)

        else:
            self._send_json({"error": "not found"}, 404)

    def do_PUT(self):
        init_data()
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        body = self._read_body()

        if path.startswith("/api/children/"):
            cid = int(path.split("/")[-1])
            child = children_db.get(cid)
            if not child: return self._send_json({"error": "不存在"}, 404)
            child["name"] = body.get("name", child["name"])
            child["note"] = body.get("note", child.get("note", ""))
            child["status"] = body.get("status", child.get("status", "active"))
            self._send_json(child)

        elif path.startswith("/api/rules/"):
            rid = int(path.split("/")[-1])
            rule = next((r for r in rules_db if r["id"] == rid), None)
            if not rule: return self._send_json({"error": "规则不存在"}, 404)
            rule["name"] = body.get("name", rule["name"])
            rule["category"] = body.get("category", rule["category"])
            rule["points"] = int(body.get("points", rule["points"]))
            rule["cash_cny"] = float(body.get("cash_cny", rule["cash_cny"]))
            rule["description"] = body.get("description", rule["description"])
            self._send_json(rule)

        elif path.startswith("/api/redlines/"):
            rid = int(path.split("/")[-1])
            rl = next((r for r in redlines_db if r["id"] == rid), None)
            if not rl: return self._send_json({"error": "不存在"}, 404)
            rl["rule"] = body.get("rule", rl["rule"])
            rl["penalty_points"] = int(body.get("penalty_points", rl["penalty_points"]))
            rl["description"] = body.get("description", rl["description"])
            self._send_json(rl)

        else:
            self._send_json({"error": "not found"}, 404)

    def do_DELETE(self):
        init_data()
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path.startswith("/api/children/"):
            cid = int(path.split("/")[-1])
            if cid not in children_db: return self._send_json({"error": "不存在"}, 404)
            del children_db[cid]
            if cid in accounts_db: del accounts_db[cid]
            global transactions_db
            transactions_db = [t for t in transactions_db if t["child_id"] != cid]
            self._send_json({"status": "ok"})

        elif path.startswith("/api/transactions/"):
            txn_id = int(path.split("/")[-1])
            txn = next((t for t in transactions_db if t["id"] == txn_id), None)
            if not txn: return self._send_json({"error": "不存在"}, 404)
            acc = accounts_db.get(txn["child_id"])
            if acc:
                if txn["type"] == "points":
                    if txn["direction"] == "+": acc["points"] -= int(txn["points"]); acc["points_earned"] -= int(txn["points"])
                    else: acc["points"] += int(txn["points"]); acc["points_spent"] -= int(txn["points"])
                if txn["type"] == "cash":
                    if txn["direction"] == "+": acc["cash_cny"] -= txn["cash_cny"]; acc["cash_earned"] -= txn["cash_cny"]
                    else: acc["cash_cny"] += txn["cash_cny"]; acc["cash_spent"] -= txn["cash_cny"]
            transactions_db.remove(txn)
            self._send_json({"status": "ok"})

        elif path.startswith("/api/rules/"):
            rid = int(path.split("/")[-1])
            rule = next((r for r in rules_db if r["id"] == rid), None)
            if not rule: return self._send_json({"error": "不存在"}, 404)
            rules_db.remove(rule)
            self._send_json({"status": "ok"})

        else:
            self._send_json({"error": "not found"}, 404)

    def _send_file(self, path, mime="text/html"):
        try:
            # Build absolute path relative to project root
            project_root = os.path.join(os.path.dirname(__file__), '..')
            # Remove leading / from path
            rel = path.lstrip('/')
            if not rel:
                return self._send_json({"error": "no file path"}, 400)
            full = os.path.normpath(os.path.join(project_root, rel))
            if os.path.exists(full) and os.path.isfile(full):
                with open(full, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self._send_json({"error": "not found: " + path}, 404)
        except Exception as e:
            self._send_json({"error": str(e)}, 500)

    def _guess_mime(self, path):
        if path.endswith(".css"): return "text/css"
        if path.endswith(".js"): return "application/javascript"
        if path.endswith(".json"): return "application/json"
        if path.endswith(".png"): return "image/png"
        if path.endswith(".jpg") or path.endswith(".jpeg"): return "image/jpeg"
        return "text/html"

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 5102), APIHandler)
    print("🎉 家庭奖励管理系统 v1.0.0 启动成功！")
    print("📍 API: http://localhost:5102")
    print("📍 API Docs: http://localhost:5102/health")
    print("💡 按 Ctrl+C 停止")
    server.serve_forever()
