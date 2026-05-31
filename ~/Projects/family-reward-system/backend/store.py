"""家庭奖励管理系统"""
import datetime as dt
import random
from contextlib import contextmanager
from typing import Optional

# ─── Models ───────────────────────────────────────────────────────────────

class Child:
    def __init__(self, id: int, name: str, status: str = "active", note: str = ""):
        self.id = id
        self.name = name
        self.status = status
        self.note = note
        self.created_at = dt.datetime.utcnow()

class Account:
    def __init__(self, child_id: int, points: int = 0, cash_cny: float = 0,
                 items_count: int = 0, items_detail: str = ""):
        self.child_id = child_id
        self.points = points
        self.cash_cny = cash_cny
        self.items_count = items_count
        self.items_detail = items_detail
        self.points_earned = points
        self.points_spent = 0
        self.cash_earned = cash_cny
        self.cash_spent = 0

class Transaction:
    def __init__(self, child_id: int, txn_type: str = "points", direction: str = "+",
                 category: str = "", description: str = "", points: float = 0,
                 cash_cny: float = 0, items: str = "", notes: str = "",
                 date: Optional[dt.date] = None):
        self.id = 0
        self.transaction_date = date or dt.date.today()
        self.child_id = child_id
        self.type = txn_type
        self.direction = direction
        self.category = category
        self.description = description
        self.points = points
        self.cash_cny = cash_cny
        self.items = items
        self.notes = notes

class Rule:
    def __init__(self, name: str, category: str = "", points: int = 0,
                 cash_cny: float = 0, description: str = ""):
        self.id = 0
        self.name = name
        self.category = category
        self.points = points
        self.cash_cny = cash_cny
        self.description = description

class RedLine:
    def __init__(self, order_num: int, rule: str, proposer: str = "",
                 description: str = "", penalty_points: int = 0):
        self.id = 0
        self.order_num = order_num
        self.rule = rule
        self.proposer = proposer
        self.description = description
        self.penalty_points = penalty_points

# ─── Data Store (in-memory) ───────────────────────────────────────────────

class DataStore:
    def __init__(self):
        self._children: dict[int, Child] = {}
        self._accounts: dict[int, Account] = {}
        self._transactions: list[Transaction] = []
        self._rules: list[Rule] = []
        self._redlines: list[RedLine] = []
        self._next_txn_id = 1
        self._next_rule_id = 1
        self._next_redline_id = 1
        self._next_child_id = 1
        self._seeded = False

    def _init(self):
        if self._seeded:
            return
        names = ["彦谦", "玥玥", "嘟嘟", "薇薇", "小宇"]
        data = [
            (1, 108, 230.0, 2, "2个铲子", 108, 0, 300.0, 70.0),
            (2, 123, 30.0, 1, "水培栽培", 144, 21, 50.0, 20.0),
            (3, 100, 0.0, 0, "", 100, 0, 0.0, 0.0),
            (4, 100, 0.0, 0, "", 100, 0, 0.0, 0.0),
            (5, 100, 0.0, 0, "", 100, 0, 0.0, 0.0),
        ]
        for i, name in enumerate(names):
            cid = i + 1
            self._children[cid] = Child(id=cid, name=name)
            a = data[i]
            self._accounts[cid] = Account(child_id=cid, points=a[1], cash_cny=a[2],
                                          items_count=a[3], items_detail=a[4])
            self._accounts[cid].points_earned = a[5]
            self._accounts[cid].points_spent = a[6]
            self._accounts[cid].cash_earned = a[7]
            self._accounts[cid].cash_spent = a[8]

        default_rules = [
            Rule("按时/及时完成作业", "学习", 5, 0, "规定时间内完成"),
            Rule("主动完成作业", "学习", 3, 0, "不用催促"),
            Rule("作业优秀/全对", "学习", 2, 0, "额外奖励"),
            Rule("主动刷牙", "规矩", 2, 0, "早晚各一次"),
            Rule("好好吃饭", "规矩", 2, 0, "不挑食、按时吃"),
            Rule("自己收拾玩具", "规矩", 2, 0, "玩完归位"),
            Rule("按时睡觉", "规矩", 2, 0, "不拖延"),
            Rule("主动看书", "学习", 3, 0, "自己拿起书看"),
            Rule("帮忙做家务", "帮忙", 3, 0, "倒垃圾、擦桌子等"),
            Rule("分享玩具", "规矩", 2, 0, "不抢不争"),
            Rule("说谢谢/对不起", "规矩", 1, 0, "礼貌用语"),
            Rule("帮助他人", "帮忙", 3, 0, "帮助弟弟妹妹或他人"),
            Rule("遵守红线", "规矩", 5, 0, "连续一段时间遵守红线规则"),
            Rule("耐心等待", "规矩", 5, 0, "排队、等待时不急躁"),
        ]
        for r in default_rules:
            r.id = self._next_rule_id
            self._next_rule_id += 1
            self._rules.append(r)

        default_redlines = [
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
        for o, rule, proposer, desc, penalty in default_redlines:
            rl = RedLine(o, rule, proposer, desc, penalty)
            rl.id = self._next_redline_id
            self._next_redline_id += 1
            self._redlines.append(rl)

        self._next_child_id = 6
        self._seeded = True

    # Children
    def get_all_children(self):
        self._init()
        return list(self._children.values())

    def get_child(self, cid: int) -> Optional[Child]:
        self._init()
        return self._children.get(cid)

    def add_child(self, name: str, note: str = "") -> Child:
        self._init()
        for c in self._children.values():
            if c.name == name:
                raise ValueError("该孩子已存在")
        cid = self._next_child_id
        self._next_child_id += 1
        child = Child(id=cid, name=name, note=note)
        self._children[cid] = child
        self._accounts[cid] = Account(child_id=cid)
        return child

    def update_child(self, cid: int, name: str, note: str = None, status: str = None):
        self._init()
        child = self._children.get(cid)
        if not child:
            raise ValueError("孩子不存在")
        if name: child.name = name
        if note is not None: child.note = note
        if status: child.status = status
        return child

    def delete_child(self, cid: int):
        self._init()
        if cid not in self._children:
            raise ValueError("孩子不存在")
        del self._children[cid]
        if cid in self._accounts:
            del self._accounts[cid]
        self._transactions[:] = [t for t in self._transactions if t.child_id != cid]

    # Accounts
    def get_account(self, cid: int) -> Optional[Account]:
        self._init()
        return self._accounts.get(cid)

    def init_account(self, cid: int, points: int, cash_cny: float) -> Account:
        self._init()
        if cid not in self._accounts:
            raise ValueError("孩子不存在")
        acc = self._accounts[cid]
        old_points = acc.points
        acc.points = points
        acc.cash_cny = cash_cny
        acc.points_earned = points
        acc.points_spent = 0
        acc.cash_earned = cash_cny
        acc.cash_spent = 0
        return acc

    # Transactions
    def create_transaction(self, child_id: int, txn_type: str = "points",
                           direction: str = "+", category: str = "",
                           description: str = "", points: float = 0,
                           cash_cny: float = 0, items: str = "",
                           notes: str = "", date: Optional[dt.date] = None) -> tuple[Transaction, Account]:
        self._init()
        if child_id not in self._accounts:
            raise ValueError("孩子不存在")
        acc = self._accounts[child_id]
        if direction == "-" and txn_type == "points" and points > acc.points:
            raise ValueError("积分不足")
        if direction == "-" and txn_type == "cash" and cash_cny > acc.cash_cny:
            raise ValueError("现金不足")

        txn = Transaction(child_id, txn_type, direction, category, description,
                          points, cash_cny, items, notes, date)
        txn.id = self._next_txn_id
        self._next_txn_id += 1

        if txn_type == "points":
            if direction == "+":
                acc.points += int(points)
                acc.points_earned += int(points)
            else:
                acc.points -= int(points)
                acc.points_spent += int(points)
        if txn_type == "cash":
            if direction == "+":
                acc.cash_cny += cash_cny
                acc.cash_earned += cash_cny
            else:
                acc.cash_cny -= cash_cny
                acc.cash_spent += cash_cny
        if txn_type == "items" and direction == "+":
            acc.items_count += 1
            if acc.items_count == 1:
                acc.items_detail = items
            else:
                acc.items_detail = f"{acc.items_detail},{items}"
        if txn_type == "items" and direction == "-":
            acc.items_count -= 1
            if acc.items_count == 0:
                acc.items_detail = ""

        self._transactions.append(txn)
        return txn, acc

    def delete_transaction(self, txn_id: int):
        self._init()
        txn = next((t for t in self._transactions if t.id == txn_id), None)
        if not txn:
            raise ValueError("交易不存在")
        acc = self._accounts.get(txn.child_id)
        if not acc:
            raise ValueError("账户不存在")

        if txn.type == "points":
            if txn.direction == "+":
                acc.points -= int(txn.points)
                acc.points_earned -= int(txn.points)
            else:
                acc.points += int(txn.points)
                acc.points_spent -= int(txn.points)
        if txn.type == "cash":
            if txn.direction == "+":
                acc.cash_cny -= txn.cash_cny
                acc.cash_earned -= txn.cash_cny
            else:
                acc.cash_cny += txn.cash_cny
                acc.cash_spent -= txn.cash_cny
        if txn.type == "items" and txn.direction == "+":
            acc.items_count -= 1
            if acc.items_count == 0: acc.items_detail = ""
        if txn.type == "items" and txn.direction == "-":
            acc.items_count += 1
            acc.items_detail = txn.items

        self._transactions.remove(txn)

    def get_transactions(self, child_id: int = None, txn_type: str = None,
                         category: str = None, date_from: Optional[dt.date] = None,
                         date_to: Optional[dt.date] = None, search: str = None,
                         page: int = 1, page_size: int = 50) -> tuple[list[Transaction], int]:
        self._init()
        q = self._transactions[:]
        if child_id: q = [t for t in q if t.child_id == child_id]
        if txn_type: q = [t for t in q if t.type == txn_type]
        if category: q = [t for t in q if t.category == category]
        if date_from: q = [t for t in q if t.transaction_date >= date_from]
        if date_to: q = [t for t in q if t.transaction_date <= date_to]
        if search: q = [t for t in q if search in t.description]
        q.sort(key=lambda t: t.transaction_date, reverse=True)
        q.sort(key=lambda t: t.id, reverse=True)
        total = len(q)
        q = q[(page - 1) * page_size: page * page_size]
        return q, total

    # Rules
    def get_all_rules(self) -> list[Rule]:
        self._init()
        return self._rules[:]

    def add_rule(self, name: str, category: str = "", points: int = 0,
                 cash_cny: float = 0, description: str = "") -> Rule:
        self._init()
        for r in self._rules:
            if r.name == name:
                raise ValueError("该规则名称已存在")
        r = Rule(name, category, points, cash_cny, description)
        r.id = self._next_rule_id
        self._next_rule_id += 1
        self._rules.append(r)
        return r

    def update_rule(self, rid: int, name: str = None, category: str = None,
                    points: int = None, cash_cny: float = None, description: str = None) -> Rule:
        self._init()
        r = next((r for r in self._rules if r.id == rid), None)
        if not r: raise ValueError("规则不存在")
        if name: r.name = name
        if category: r.category = category
        if points is not None: r.points = points
        if cash_cny is not None: r.cash_cny = cash_cny
        if description: r.description = description
        return r

    def delete_rule(self, rid: int):
        self._init()
        r = next((r for r in self._rules if r.id == rid), None)
        if not r: raise ValueError("规则不存在")
        self._rules.remove(r)

    # RedLines
    def get_redlines(self) -> list[RedLine]:
        self._init()
        return sorted(self._redlines, key=lambda r: r.order_num)

    def update_redline(self, rid: int, order_num: int = None, rule: str = None,
                       proposer: str = None, description: str = None,
                       penalty_points: int = None) -> RedLine:
        self._init()
        r = next((r for r in self._redlines if r.id == rid), None)
        if not r: raise ValueError("红线不存在")
        if order_num is not None: r.order_num = order_num
        if rule: r.rule = rule
        if proposer: r.proposer = proposer
        if description: r.description = description
        if penalty_points is not None: r.penalty_points = penalty_points
        return r

    # Stats
    def get_dashboard(self) -> dict:
        self._init()
        children = self.get_all_children()
        txns, _ = self.get_transactions(page_size=20)
        now = dt.datetime.utcnow()
        month_start = dt.date(now.year, now.month, 1)
        month_txns = [t for t in self._transactions if t.transaction_date >= month_start]
        monthly_data = []
        for day in range(1, now.day + 1):
            d = dt.date(now.year, now.month, day)
            earned = sum(t.points for t in month_txns if t.transaction_date == d and t.direction == "+" and t.type == "points")
            spent = sum(t.points for t in month_txns if t.transaction_date == d and t.direction == "-" and t.type == "points")
            monthly_data.append({"Date": day, "Earned": earned, "Spent": spent})
        return {"children": children, "recent": txns, "monthly": monthly_data}

    def get_child_stats(self, cid: int) -> Optional[dict]:
        self._init()
        acc = self._accounts.get(cid)
        if not acc: return None
        txns, _ = self.get_transactions(child_id=cid)
        cat_stats = {}
        for t in txns:
            cat_stats[t.category] = cat_stats.get(t.category, {"count": 0, "points": 0})
            cat_stats[t.category]["count"] += 1
            cat_stats[t.category]["points"] += t.points
        return {
            "points": acc.points, "cash_cny": acc.cash_cny,
            "items_count": acc.items_count, "items_detail": acc.items_detail,
            "points_earned": acc.points_earned, "points_spent": acc.points_spent,
            "cash_earned": acc.cash_earned, "cash_spent": acc.cash_spent,
            "total_transactions": len(txns), "category_stats": cat_stats
        }

    def get_leaderboard(self) -> list[dict]:
        self._init()
        children = []
        for c in self._children.values():
            acc = self._accounts.get(c.id)
            children.append({
                "name": c.name, "id": c.id,
                "points": acc.points if acc else 0
            })
        children.sort(key=lambda x: x["points"], reverse=True)
        return children

# Global store
store = DataStore()
