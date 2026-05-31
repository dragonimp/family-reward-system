#!/usr/bin/env python3
"""家庭奖励管理系统 - 后端服务器 (PostgreSQL持久化版)"""
import json, os, datetime as dt, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import psycopg2
import psycopg2.extras

# ─── 数据库连接配置 ────────────────────────────────────────────────────────

DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'family_rewards',
    'user': 'postgres',
    'password': os.environ.get('PG_PASSWORD', ''),
}

def get_db_connection():
    """获取数据库连接"""
    return psycopg2.connect(**DB_CONFIG)

# ─── 数据库操作函数 ─────────────────────────────────────────────────────────

def init_db():
    """初始化数据库表结构"""
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        # 检查表是否存在，不存在则创建
        tables = [
            """CREATE TABLE IF NOT EXISTS children (
                id SERIAL PRIMARY KEY,
                name VARCHAR(50) NOT NULL UNIQUE,
                status VARCHAR(20) DEFAULT 'active',
                note TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )""",
            """CREATE TABLE IF NOT EXISTS accounts (
                id SERIAL PRIMARY KEY,
                child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
                points INTEGER DEFAULT 0,
                cash_cny NUMERIC(10,2) DEFAULT 0,
                items_count INTEGER DEFAULT 0,
                items_detail TEXT,
                points_earned INTEGER DEFAULT 0,
                points_spent INTEGER DEFAULT 0,
                cash_earned NUMERIC(10,2) DEFAULT 0,
                cash_spent NUMERIC(10,2) DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(child_id)
            )""",
            """CREATE TABLE IF NOT EXISTS transactions (
                id SERIAL PRIMARY KEY,
                date DATE NOT NULL,
                child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
                type VARCHAR(20) NOT NULL,
                direction VARCHAR(10) NOT NULL,
                category VARCHAR(50),
                description TEXT,
                points NUMERIC(10,2) DEFAULT 0,
                cash_cny NUMERIC(10,2) DEFAULT 0,
                items TEXT,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                CHECK (direction IN ('+', '-'))
            )""",
            """CREATE TABLE IF NOT EXISTS rules (
                id SERIAL PRIMARY KEY,
                name VARCHAR(200) NOT NULL,
                category VARCHAR(50),
                points NUMERIC(10,2) DEFAULT 0,
                cash_cny NUMERIC(10,2) DEFAULT 0,
                description TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )""",
            """CREATE TABLE IF NOT EXISTS redlines (
                id SERIAL PRIMARY KEY,
                order_num INTEGER,
                rule VARCHAR(200),
                proposer VARCHAR(50),
                description TEXT,
                penalty_points INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )""",
        ]
        for table_sql in tables:
            cur.execute(table_sql)
        
        # 创建索引
        indexes = [
            "CREATE INDEX IF NOT EXISTS idx_tx_child ON transactions(child_id)",
            "CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date)",
            "CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type)",
        ]
        for idx_sql in indexes:
            cur.execute(idx_sql)
        
        conn.commit()
        print("✅ 数据库表初始化完成")
    except Exception as e:
        print(f"❌ 数据库初始化失败: {e}")
        conn.rollback()
    finally:
        conn.close()

def get_all_children():
    """获取所有孩子"""
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT * FROM children WHERE status = 'active' ORDER BY id")
        return cur.fetchall()
    finally:
        conn.close()

def get_accounts():
    """获取所有账户"""
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT * FROM accounts ORDER BY child_id")
        return cur.fetchall()
    finally:
        conn.close()

def get_transactions(child_id=None, txn_type=None, category=None, page=1, page_size=50):
    """获取交易记录"""
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        query = """
            SELECT t.*, c.name as child_name 
            FROM transactions t 
            LEFT JOIN children c ON t.child_id = c.id
            WHERE 1=1
        """
        params = []
        if child_id:
            query += " AND t.child_id = %s"
            params.append(child_id)
        if txn_type:
            query += " AND t.type = %s"
            params.append(txn_type)
        if category:
            query += " AND t.category = %s"
            params.append(category)
        
        query += " ORDER BY t.date DESC, t.id DESC"
        
        # 获取总数
        count_query = query.replace("SELECT t.*, c.name as child_name", "SELECT count(*)")
        cur.execute(count_query, params)
        total = cur.fetchone()[0]
        
        # 分页
        query += " LIMIT %s OFFSET %s"
        offset = (page - 1) * page_size
        params.extend([page_size, offset])
        
        cur.execute(query, params)
        rows = cur.fetchall()
        
        # 转换Decimal类型
        result = []
        for row in rows:
            row_dict = dict(row)
            for key, value in row_dict.items():
                if hasattr(value, '__float__'):
                    row_dict[key] = float(value)
            result.append(row_dict)
        
        return {"items": result, "total": total, "page": page, "page_size": page_size}
    finally:
        conn.close()

def get_rules():
    """获取规则"""
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT * FROM rules ORDER BY id")
        rules = cur.fetchall()
        
        cur.execute("SELECT * FROM redlines ORDER BY order_num")
        redlines = cur.fetchall()
        
        # 转换Decimal
        for rule in rules:
            for key, value in rule.items():
                if hasattr(value, '__float__'):
                    rule[key] = float(value)
        for rl in redlines:
            for key, value in rl.items():
                if hasattr(value, '__float__'):
                    rl[key] = float(value)
        
        return {"rules": rules, "redlines": redlines}
    finally:
        conn.close()

def create_transaction(txn):
    """创建交易并更新账户"""
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        # 插入交易
        cur.execute("""
            INSERT INTO transactions (date, child_id, type, direction, category, 
                                     description, points, cash_cny, items, notes)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING *
        """, (
            txn['date'], txn['child_id'], txn['type'], txn['direction'],
            txn.get('category', ''), txn.get('description', ''),
            txn.get('points', 0), txn.get('cash_cny', 0),
            txn.get('items', ''), txn.get('notes', '')
        ))
        
        new_txn = cur.fetchone()
        new_txn_dict = dict(new_txn)
        for key, value in new_txn_dict.items():
            if hasattr(value, '__float__'):
                new_txn_dict[key] = float(value)
        
        # 更新账户
        cid = txn['child_id']
        txn_type = txn['type']
        direction = txn['direction']
        points = float(txn.get('points', 0))
        cash_cny = float(txn.get('cash_cny', 0))
        
        # 获取当前账户
        cur.execute("SELECT * FROM accounts WHERE child_id = %s", (cid,))
        acc = cur.fetchone()
        if not acc:
            conn.rollback()
            return {"error": "账户不存在"}
        
        if txn_type == 'points':
            if direction == '+':
                cur.execute("UPDATE accounts SET points = points + %s, points_earned = points_earned + %s, updated_at = CURRENT_TIMESTAMP WHERE child_id = %s",
                           (int(points), int(points), cid))
            else:
                cur.execute("UPDATE accounts SET points = points - %s, points_spent = points_spent + %s, updated_at = CURRENT_TIMESTAMP WHERE child_id = %s",
                           (int(points), int(points), cid))
        elif txn_type == 'cash':
            if direction == '+':
                cur.execute("UPDATE accounts SET cash_cny = cash_cny + %s, cash_earned = cash_earned + %s, updated_at = CURRENT_TIMESTAMP WHERE child_id = %s",
                           (cash_cny, cash_cny, cid))
            else:
                cur.execute("UPDATE accounts SET cash_cny = cash_cny - %s, cash_spent = cash_spent + %s, updated_at = CURRENT_TIMESTAMP WHERE child_id = %s",
                           (cash_cny, cash_cny, cid))
        elif txn_type == 'items':
            if direction == '+':
                cur.execute("UPDATE accounts SET items_count = items_count + 1, items_detail = CASE WHEN items_detail = '' OR items_detail IS NULL THEN %s ELSE items_detail || ', ' || %s END, updated_at = CURRENT_TIMESTAMP WHERE child_id = %s",
                           (txn.get('items', ''), txn.get('items', ''), cid))
            else:
                cur.execute("UPDATE accounts SET items_count = GREATEST(items_count - 1, 0), updated_at = CURRENT_TIMESTAMP WHERE child_id = %s",
                           (cid,))
        
        conn.commit()
        
        # 获取更新后的账户
        cur.execute("SELECT * FROM accounts WHERE child_id = %s", (cid,))
        updated_acc = cur.fetchone()
        updated_acc_dict = dict(updated_acc)
        for key, value in updated_acc_dict.items():
            if hasattr(value, '__float__'):
                updated_acc_dict[key] = float(value)
        
        return {"transaction": new_txn_dict, "account": updated_acc_dict}
    except Exception as e:
        conn.rollback()
        return {"error": str(e)}
    finally:
        conn.close()

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
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        params = parse_qs(parsed.query)

        # Health
        if path == "/health":
            return self._send_json({"status": "ok", "version": "2.0.0", "db": "postgresql"})

        # SPA fallback
        if path == "" or path == "/" or path == "/dashboard" or path.startswith("/children") or path.startswith("/rules") or path.startswith("/transactions") or path.startswith("/reward") or path.startswith("/stats"):
            self._send_file("frontend/static/index.html", "text/html")
            return

        # API: children
        if path == "/api/children":
            children = get_all_children()
            accounts = {acc['child_id']: acc for acc in get_accounts()}
            
            result = []
            for c in children:
                cid = c['id']
                acc = accounts.get(cid, {})
                result.append({
                    "id": cid,
                    "name": c['name'],
                    "status": c.get('status', 'active'),
                    "note": c.get('note', ''),
                    "createdAt": c.get('created_at', '').isoformat() if hasattr(c.get('created_at'), 'isoformat') else str(c.get('created_at', '')),
                    "updatedAt": c.get('updated_at', '').isoformat() if hasattr(c.get('updated_at'), 'isoformat') else str(c.get('updated_at', '')),
                    "score": acc.get('points', 0),
                    "cash": float(acc.get('cash_cny', 0)),
                    "items": acc.get('items_count', 0),
                })
            self._send_json(result)

        elif path.startswith("/api/children/") and path.count("/") == 3:
            cid = int(path.split("/")[-1])
            children = get_all_children()
            accounts = {acc['child_id']: acc for acc in get_accounts()}
            child = None
            for c in children:
                if c['id'] == cid:
                    child = dict(c)
                    break
            if not child:
                return self._send_json({"error": "不存在"}, 404)
            child["account"] = accounts.get(cid, {})
            self._send_json(child)

        # API: transactions
        elif path == "/api/transactions":
            child_id = int(params.get("child_id", [None])[0]) if params.get("child_id") else None
            txn_type = params.get("type", [None])[0]
            category = params.get("category", [None])[0]
            page = int(params.get("page", [1])[0])
            ps = int(params.get("page_size", [50])[0])
            
            result = get_transactions(child_id, txn_type, category, page, ps)
            self._send_json(result)

        # API: rules
        elif path == "/api/rules":
            data = get_rules()
            self._send_json(data)

        # API: stats
        elif path == "/api/stats/dashboard":
            children = get_all_children()
            accounts = {acc['child_id']: acc for acc in get_accounts()}
            children_with_acc = []
            for c in children:
                cid = c['id']
                acc = accounts.get(cid, {})
                children_with_acc.append({**dict(c), **acc})
            
            result = get_transactions(page=1, page_size=20)
            self._send_json({"children": children_with_acc, "recent": result.get('items', [])})

        elif path == "/api/stats/leaderboard":
            accounts = get_accounts()
            children = {c['id']: c['name'] for c in get_all_children()}
            lb = []
            for acc in accounts:
                lb.append({
                    "id": acc['child_id'],
                    "name": children.get(acc['child_id'], f"孩子{acc['child_id']}"),
                    "points": acc.get('points', 0)
                })
            lb.sort(key=lambda x: x['points'], reverse=True)
            self._send_json(lb)

        elif path == "/api/stats/children":
            children = get_all_children()
            accounts = {acc['child_id']: acc for acc in get_accounts()}
            result = []
            for c in children:
                cid = c['id']
                acc = accounts.get(cid, {})
                result.append({
                    "id": cid,
                    "name": c['name'],
                    "score": acc.get('points', 0),
                    "cash": float(acc.get('cash_cny', 0)),
                    "items": acc.get('items_count', 0),
                    "createdAt": c.get('created_at', ''),
                    "updatedAt": c.get('updated_at', '')
                })
            self._send_json(result)

        elif path == "/api/stats/categories":
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT category, SUM(points) as total FROM transactions GROUP BY category")
                result = [{"category": row[0], "total": float(row[1]) if row[1] else 0} for row in cur.fetchall()]
                self._send_json(result)
            finally:
                conn.close()

        elif path == "/api/stats/trend":
            child_id = params.get("childId", [None])[0]
            months = int(params.get("months", [6])[0])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                query = "SELECT date, SUM(points) as score FROM transactions WHERE 1=1"
                if child_id:
                    query += " AND child_id = %s"
                    cur.execute(query, (child_id,))
                else:
                    cur.execute(query)
                from collections import defaultdict
                daily = defaultdict(int)
                for row in cur.fetchall():
                    daily[str(row[0])] += float(row[1])
                trend = [{"date": k, "score": v, "cash": 0, "item": 0} for k, v in sorted(daily.items(), reverse=True)[:months]]
                self._send_json(trend)
            finally:
                conn.close()

        elif path.startswith("/api/stats/child/"):
            cid = int(path.split("/")[-1])
            accounts = get_accounts()
            acc = next((a for a in accounts if a['child_id'] == cid), None)
            if not acc:
                return self._send_json({"error": "不存在"}, 404)
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT count(*) FROM transactions WHERE child_id = %s", (cid,))
                total_txns = cur.fetchone()[0]
                result = {**acc, "total_transactions": total_txns}
                for k, v in result.items():
                    if hasattr(v, '__float__'):
                        result[k] = float(v)
                self._send_json(result)
            finally:
                conn.close()

        else:
            self._send_file("frontend/static" + path, self._guess_mime(path))

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "/api/children":
            body = self._read_body()
            name = body.get("name", "")
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT id FROM children WHERE name = %s", (name,))
                if cur.fetchone():
                    self._send_json({"error": "该孩子已存在"}, 400)
                    return
                
                cur.execute("INSERT INTO children (name, status, note) VALUES (%s, 'active', %s) RETURNING id",
                           (name, body.get("note", "")))
                cid = cur.fetchone()[0]
                conn.commit()
                # 创建账户
                cur.execute("INSERT INTO accounts (child_id) VALUES (%s)", (cid,))
                conn.commit()
                self._send_json({"id": cid, "name": name, "status": "active"}, 201)
            finally:
                conn.close()

        elif path == "/api/transactions":
            body = self._read_body()
            result = create_transaction(body)
            if "error" in result:
                return self._send_json(result, 400)
            self._send_json(result)

        elif path == "/api/transactions/batch":
            body = self._read_body()
            results = []
            for req in body:
                result = create_transaction(req)
                results.append({
                    "child_id": req.get("child_id"),
                    "success": "error" not in result,
                    "error": result.get("error")
                })
            self._send_json({"results": results})

        elif path.startswith("/api/rules"):
            body = self._read_body()
            name = body.get("name", "")
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT id FROM rules WHERE name = %s", (name,))
                if cur.fetchone():
                    self._send_json({"error": "该规则名称已存在"}, 400)
                    return
                
                cur.execute("""
                    INSERT INTO rules (name, category, points, cash_cny, description)
                    VALUES (%s, %s, %s, %s, %s) RETURNING *
                """, (name, body.get("category", ""), float(body.get("points", 0)),
                      float(body.get("cash_cny", 0)), body.get("description", "")))
                new_rule = cur.fetchone()
                conn.commit()
                rule = dict(new_rule)
                for k, v in rule.items():
                    if hasattr(v, '__float__'):
                        rule[k] = float(v)
                self._send_json(rule, 201)
            finally:
                conn.close()

        else:
            self._send_json({"error": "not found"}, 404)

    def do_PUT(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        body = self._read_body()

        if path.startswith("/api/children/"):
            cid = int(path.split("/")[-1])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("UPDATE children SET name=%s, note=%s, status=%s, updated_at=CURRENT_TIMESTAMP WHERE id=%s",
                           (body.get("name", ""), body.get("note", ""), body.get("status", "active"), cid))
                conn.commit()
                cur.execute("SELECT * FROM children WHERE id = %s", (cid,))
                child = cur.fetchone()
                self._send_json(dict(child))
            finally:
                conn.close()

        elif path.startswith("/api/rules/"):
            rid = int(path.split("/")[-1])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("""
                    UPDATE rules SET name=%s, category=%s, points=%s, cash_cny=%s, description=%s, updated_at=CURRENT_TIMESTAMP
                    WHERE id=%s RETURNING *
                """, (body.get("name", ""), body.get("category", ""), float(body.get("points", 0)),
                      float(body.get("cash_cny", 0)), body.get("description", ""), rid))
                rule = cur.fetchone()
                conn.commit()
                rule = dict(rule)
                for k, v in rule.items():
                    if hasattr(v, '__float__'):
                        rule[k] = float(v)
                self._send_json(rule)
            finally:
                conn.close()

        elif path.startswith("/api/redlines/"):
            rid = int(path.split("/")[-1])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("""
                    UPDATE redlines SET rule=%s, penalty_points=%s, description=%s, updated_at=CURRENT_TIMESTAMP
                    WHERE id=%s RETURNING *
                """, (body.get("rule", ""), int(body.get("penalty_points", 0)),
                      body.get("description", ""), rid))
                rl = cur.fetchone()
                conn.commit()
                self._send_json(dict(rl))
            finally:
                conn.close()

        else:
            self._send_json({"error": "not found"}, 404)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path.startswith("/api/children/"):
            cid = int(path.split("/")[-1])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("DELETE FROM children WHERE id = %s", (cid,))
                conn.commit()
                self._send_json({"status": "ok"})
            finally:
                conn.close()

        elif path.startswith("/api/transactions/"):
            txn_id = int(path.split("/")[-1])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT * FROM transactions WHERE id = %s", (txn_id,))
                txn = cur.fetchone()
                if not txn:
                    return self._send_json({"error": "不存在"}, 404)
                cur.execute("DELETE FROM transactions WHERE id = %s", (txn_id,))
                conn.commit()
                self._send_json({"status": "ok"})
            finally:
                conn.close()

        elif path.startswith("/api/rules/"):
            rid = int(path.split("/")[-1])
            conn = get_db_connection()
            try:
                cur = conn.cursor()
                cur.execute("DELETE FROM rules WHERE id = %s", (rid,))
                conn.commit()
                self._send_json({"status": "ok"})
            finally:
                conn.close()

        else:
            self._send_json({"error": "not found"}, 404)

    def _send_file(self, path, mime="text/html"):
        try:
            project_root = os.path.join(os.path.dirname(__file__), '..')
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
    print("🔧 初始化数据库...")
    init_db()
    server = HTTPServer(("0.0.0.0", 5102), APIHandler)
    print("🎉 家庭奖励管理系统 v2.0.0 (PostgreSQL) 启动成功！")
    print("📍 API: http://localhost:5102")
    print("💡 按 Ctrl+C 停止")
    server.serve_forever()
