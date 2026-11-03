# -*- coding: utf-8 -*-
r"""
数据库层冒烟测试 —— 验证存储过程与触发器的行为是否符合预期。

全程包在一个外层事务里，跑完 ROLLBACK，不会污染业务数据。

用法：python tests/db_smoke.py
"""
import sys
from pathlib import Path

import pyodbc

# 允许在 tests/ 目录下直接运行
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from warehouse import config  # noqa: E402

CONN = config.odbc_connection_string()

PASS, FAIL = "  [PASS]", "  [FAIL]"
results = []


def check(name, cond, detail=""):
    results.append((name, cond))
    print(f"{PASS if cond else FAIL} {name} {detail}")


def scalar(cur, sql, *params):
    cur.execute(sql, *params)
    row = cur.fetchone()
    return row[0] if row else None


def main():
    cn = pyodbc.connect(CONN)
    cn.autocommit = False
    cur = cn.cursor()

    # ---------- 准备：挑一组可用的测试三元组 ----------
    cur.execute("""
        SELECT TOP 1 sa.StaffID, sa.WarehouseID
        FROM StaffAssignment sa JOIN Staff s ON sa.StaffID = s.StaffID
        WHERE s.IsActive = 1 ORDER BY sa.StaffID
    """)
    staff_id, wh_id = cur.fetchone()

    cur.execute("""
        SELECT TOP 1 i.ItemID, st.SupplierID, st.Storing
        FROM Storage st JOIN Item i ON st.ItemID = i.ItemID
        WHERE st.WarehouseID = ? AND st.Storing > 10 ORDER BY st.StorageID
    """, wh_id)
    item_id, sup_id, stock = cur.fetchone()

    print(f"测试上下文: 员工={staff_id} 仓库={wh_id} 物品={item_id} 供应商={sup_id} 现有库存={stock}\n")

    before_stock = scalar(cur, """
        SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?
    """, item_id, wh_id)
    before_usage = scalar(cur, "SELECT WarehouseUsage FROM Warehouse WHERE WarehouseID=?", wh_id)
    before_audit = scalar(cur, "SELECT COUNT(*) FROM StockAudit")

    # ---------- C1 正常入库 ----------
    rec_id = 0
    cur.execute("DECLARE @r INT; EXEC dbo.sp_PostOperation ?,?,?,?,?,?,?, @r OUTPUT; SELECT @r",
                item_id, wh_id, sup_id, staff_id, "入库", 10, "冒烟测试-入库")
    rec_id = cur.fetchone()[0]
    after_stock = scalar(cur, "SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                         item_id, wh_id)
    check("C1 入库后库存 +10", after_stock == before_stock + 10, f"({before_stock} -> {after_stock})")

    after_audit = scalar(cur, "SELECT COUNT(*) FROM StockAudit")
    check("C1 入库产生 1 条库存审计", after_audit == before_audit + 1)

    cur.execute("SELECT BeforeQty, AfterQty FROM StockAudit WHERE RecordID=?", rec_id)
    a_before, a_after = cur.fetchone()
    check("C1 审计记录变动前后值", a_after - a_before == 10, f"({a_before} -> {a_after})")

    usage_now = scalar(cur, "SELECT WarehouseUsage FROM Warehouse WHERE WarehouseID=?", wh_id)
    check("C1 仓库使用量同步 +10", usage_now == before_usage + 10, f"({before_usage} -> {usage_now})")

    # ---------- C2 出库走 FIFO ----------
    cur.execute("""
        SELECT TOP 1 StorageID, Storing FROM Storage
        WHERE ItemID=? AND WarehouseID=? AND Storing>0 ORDER BY StorageID
    """, item_id, wh_id)
    first_sid, first_qty = cur.fetchone()

    cur.execute("DECLARE @r INT; EXEC dbo.sp_PostOperation ?,?,?,?,?,?,?, @r OUTPUT; SELECT @r",
                item_id, wh_id, sup_id, staff_id, "出库", 5, "冒烟测试-出库")
    rec_out = cur.fetchone()[0]

    cur.execute("SELECT BeforeQty FROM StockAudit WHERE RecordID=? ORDER BY AuditID", rec_out)
    fifo_before = cur.fetchone()[0]
    cur.execute("SELECT Storing FROM Storage WHERE StorageID=?", first_sid)
    first_after = cur.fetchone()[0]
    check("C2 出库优先扣最早批次(StorageID 升序)",
          first_after == first_qty - 5 and fifo_before == first_qty,
          f"(批次{first_sid}: {first_qty} -> {first_after})")

    # ---------- C3 权限校验 ----------
    cur.execute("""
        SELECT TOP 1 s.StaffID FROM Staff s
        WHERE s.StaffID NOT IN (SELECT StaffID FROM StaffAssignment WHERE WarehouseID=?)
    """, wh_id)
    row = cur.fetchone()
    if row:
        try:
            cur.execute("DECLARE @r INT; EXEC dbo.sp_PostOperation ?,?,?,?,?,?,?, @r OUTPUT",
                        item_id, wh_id, sup_id, row[0], "入库", 1, "越权测试")
            check("C3 无权限员工被拒绝", False, "应当抛 50003")
        except pyodbc.Error as e:
            check("C3 无权限员工被拒绝", "50003" in str(e))
    else:
        print("  [SKIP] C3 没有可用于越权测试的员工")

    # ---------- C4 库存不足 ----------
    try:
        cur.execute("DECLARE @r INT; EXEC dbo.sp_PostOperation ?,?,?,?,?,?,?, @r OUTPUT",
                    item_id, wh_id, sup_id, staff_id, "出库", 999999, "超量测试")
        check("C4 超量出库被拒绝", False, "应当抛 50004")
    except pyodbc.Error as e:
        check("C4 超量出库被拒绝", "50004" in str(e))

    # ---------- C5 非法数量 ----------
    try:
        cur.execute("DECLARE @r INT; EXEC dbo.sp_PostOperation ?,?,?,?,?,?,?, @r OUTPUT",
                    item_id, wh_id, sup_id, staff_id, "入库", 0, "零数量测试")
        check("C5 数量为 0 被拒绝", False, "应当抛 50006")
    except pyodbc.Error as e:
        check("C5 数量为 0 被拒绝", "50006" in str(e))

    # ---------- C6 调拨：两条流水同组 ----------
    cur.execute("SELECT TOP 1 WarehouseID FROM Warehouse WHERE WarehouseID<>?", wh_id)
    dst_wh = cur.fetchone()[0]

    cur.execute("SELECT TOP 1 StaffID FROM StaffAssignment WHERE WarehouseID=? AND StaffID<>?",
                dst_wh, staff_id)
    row = cur.fetchone()
    dst_staff = row[0] if row else staff_id

    stock_before_transfer = scalar(cur, """
        SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?
    """, item_id, wh_id)

    cur.execute("""
        DECLARE @g UNIQUEIDENTIFIER;
        EXEC dbo.sp_TransferStock ?,?,?,?,?,?,?,?, @g OUTPUT;
        SELECT @g
    """, item_id, wh_id, dst_wh, sup_id, 3, staff_id, dst_staff, "冒烟测试-调拨")
    group_id = cur.fetchone()[0]

    cnt = scalar(cur, "SELECT COUNT(*) FROM Record WHERE TransferGroupID=?", group_id)
    check("C6 调拨生成 2 条流水且同组", cnt == 2, f"({cnt} 条)")

    src_after = scalar(cur, "SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                       item_id, wh_id)
    check("C6 源仓库扣减 3", src_after == stock_before_transfer - 3,
          f"({stock_before_transfer} -> {src_after})")

    # ---------- C7 失败的调拨不留半条记录 ----------
    # 先提交前面的操作：存储过程失败时会 ROLLBACK 整个事务链，
    # 若不先落地，回滚会把 C6 的成果一起带走，测出来的是"减少"而非"不变"。
    cn.commit()
    rec_before_fail = scalar(cur, "SELECT COUNT(*) FROM Record")
    try:
        cur.execute("""
            DECLARE @g UNIQUEIDENTIFIER;
            EXEC dbo.sp_TransferStock ?,?,?,?,?,?,?,?, @g OUTPUT
        """, item_id, wh_id, dst_wh, sup_id, 999999, staff_id, dst_staff, "应当失败")
        check("C7 超量调拨被拒绝", False)
    except pyodbc.Error as e:
        rec_after_fail = scalar(cur, "SELECT COUNT(*) FROM Record")
        check("C7 超量调拨被拒绝且无残留记录",
              "50004" in str(e) and rec_after_fail == rec_before_fail,
              f"({rec_before_fail} -> {rec_after_fail})")

    # ---------- C8 审计表字段语义 ----------
    cur.execute("SELECT TOP 1 BeforeQty, AfterQty, ChangeQty FROM StockAudit ORDER BY AuditID DESC")
    b, a, c = cur.fetchone()
    check("C8 StockAudit 满足 After = Before + Change", a == b + c, f"({b}+{c}={a})")

    cur.rollback()
    cn.close()

    ok = sum(1 for _, c in results if c)
    total = len(results)
    print(f"\n{'=' * 46}\n通过 {ok}/{total}")
    print("提示：失败用例会让存储过程回滚整个事务链，库里可能残留测试流水。")
    print("      需要恢复干净数据时，按顺序重跑 sql/01~06 即可（脚本幂等）。")
    return 0 if ok == total else 1


if __name__ == "__main__":
    sys.exit(main())
