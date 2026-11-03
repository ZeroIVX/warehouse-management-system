# -*- coding: utf-8 -*-
r"""
WMS 作业层冒烟测试：收货、发货（FEFO）、盘点结案。

用法：python tests/wms_smoke.py
注意：会写入真实数据，跑完建议重跑 sql/01~06 复位。
"""
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

import pyodbc

# 允许在 tests/ 目录下直接运行
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from warehouse import config  # noqa: E402

CONN = config.odbc_connection_string()

results = []


def check(name, cond, detail=""):
    results.append(bool(cond))
    print(f"  [{'PASS' if cond else 'FAIL'}] {name} {detail}")


def main():
    cn = pyodbc.connect(CONN, autocommit=False)
    cur = cn.cursor()

    # ---------- 准备 ----------
    cur.execute("SELECT TOP 1 sa.WarehouseID, sa.StaffID FROM StaffAssignment sa "
                "JOIN Staff s ON sa.StaffID = s.StaffID "
                "WHERE s.IsActive = 1 ORDER BY sa.WarehouseID")
    wh_id, staff_id = cur.fetchone()

    cur.execute("SELECT TOP 1 ItemID FROM Item ORDER BY ItemID")
    item_id = cur.fetchone()[0]

    cur.execute("SELECT TOP 1 LocationID FROM StorageLocation "
                "JOIN WarehouseZone ON StorageLocation.ZoneID=WarehouseZone.ZoneID "
                "WHERE WarehouseZone.WarehouseID=? AND WarehouseZone.ZoneType=N'存储区'", wh_id)
    loc_id = cur.fetchone()[0]

    cur.execute("SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                item_id, wh_id)
    stock_before = cur.fetchone()[0]

    print(f"上下文: 仓库={wh_id} 员工={staff_id} 物品={item_id} 库位={loc_id} 现库存={stock_before}\n")

    # ---------- C1 建入库单 ----------
    cur.execute("""
        INSERT INTO InboundOrder (OrderNo, OrderType, WarehouseID, SupplierID, Status, ExpectedDate)
        OUTPUT INSERTED.OrderID
        VALUES (?, N'采购入库', ?, 1, N'待收货', ?)
    """, f"PO-TEST-{datetime.now():%H%M%S%f}", wh_id, date.today())
    in_order = cur.fetchone()[0]

    cur.execute("""
        INSERT INTO InboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty, LocationID, BatchNo, ExpiryDate)
        OUTPUT INSERTED.LineID
        VALUES (?, 1, ?, 100, ?, ?, ?)
    """, in_order, item_id, loc_id, "BATCH-TEST-A", date.today() + timedelta(days=30))
    in_line = cur.fetchone()[0]
    cn.commit()
    check("C1 入库单已创建（计划 100）", in_order > 0, f"OrderID={in_order}")

    # ---------- C2 部分收货 ----------
    cur.execute("DECLARE @r INT; EXEC dbo.sp_ReceiveInbound ?, 60, ?, ?, NULL, ?, ?, @r OUTPUT; SELECT @r",
                in_line, loc_id, "BATCH-TEST-A", date.today() + timedelta(days=30), staff_id)
    cur.fetchone()
    cn.commit()

    cur.execute("SELECT ReceivedQty FROM InboundOrderLine WHERE LineID=?", in_line)
    check("C2 行收货量 = 60", cur.fetchone()[0] == 60)

    cur.execute("SELECT Status FROM InboundOrder WHERE OrderID=?", in_order)
    check("C2 单头状态 = 部分收货", cur.fetchone()[0] == "部分收货")

    cur.execute("SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                item_id, wh_id)
    check("C2 库存增加 60", cur.fetchone()[0] == stock_before + 60)

    # ---------- C3 超量收货被拒 ----------
    try:
        cur.execute("DECLARE @r INT; EXEC dbo.sp_ReceiveInbound ?, 50, ?, ?, NULL, ?, ?, @r OUTPUT",
                    in_line, loc_id, "BATCH-TEST-A", date.today() + timedelta(days=30), staff_id)
        check("C3 超量收货被拒绝", False)
    except pyodbc.Error as e:
        cn.rollback()
        check("C3 超量收货被拒绝", "50006" in str(e))

    # ---------- C4 收完剩余 -> 已完成 ----------
    cur.execute("DECLARE @r INT; EXEC dbo.sp_ReceiveInbound ?, 40, ?, ?, NULL, ?, ?, @r OUTPUT; SELECT @r",
                in_line, loc_id, "BATCH-TEST-A", date.today() + timedelta(days=30), staff_id)
    cur.fetchone()
    cn.commit()

    cur.execute("SELECT Status FROM InboundOrder WHERE OrderID=?", in_order)
    check("C4 收完后状态 = 已完成", cur.fetchone()[0] == "已完成")

    # ---------- C5 建出库单并发货 ----------
    cur.execute("""
        INSERT INTO OutboundOrder (OrderNo, OrderType, WarehouseID, CustomerID, Status)
        OUTPUT INSERTED.OrderID
        VALUES (?, N'销售出库', ?, 1, N'待拣货')
    """, f"SO-TEST-{datetime.now():%H%M%S%f}", wh_id)
    out_order = cur.fetchone()[0]

    cur.execute("""
        INSERT INTO OutboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty)
        OUTPUT INSERTED.LineID
        VALUES (?, 1, ?, 30)
    """, out_order, item_id)
    out_line = cur.fetchone()[0]
    cn.commit()

    cur.execute("DECLARE @r INT; EXEC dbo.sp_ShipOutbound ?, 30, ?, @r OUTPUT; SELECT @r",
                out_line, staff_id)
    cur.fetchone()
    cn.commit()

    cur.execute("SELECT Status FROM OutboundOrder WHERE OrderID=?", out_order)
    check("C5 发货后单头状态 = 已完成", cur.fetchone()[0] == "已完成")

    cur.execute("SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                item_id, wh_id)
    check("C5 净增 70（收 100 发 30）", cur.fetchone()[0] == stock_before + 70)

    # ---------- C6 FEFO 顺序 ----------
    # 回查每次出库涉及批次的效期：有有效期的批次必须排在没有有效期的之前，
    # 且效期本身单调不减（越临期越先出）。
    cur.execute("""
        SELECT COUNT(*) FROM (
            SELECT st.ExpiryDate,
                   LEAD(st.ExpiryDate) OVER (ORDER BY a.AuditID) AS NextExp,
                   a.AuditID
            FROM StockAudit a
                     LEFT JOIN Storage st
                               ON st.ItemID = a.ItemID
                                   AND st.WarehouseID = a.WarehouseID
                                   AND ISNULL(st.BatchNo, N'') = ISNULL(a.BatchNo, N'')
                                   AND ISNULL(st.LocationID, 0) = ISNULL(a.LocationID, 0)
            WHERE a.ItemID = ? AND a.WarehouseID = ? AND a.ChangeQty < 0
        ) x
        WHERE NextExp IS NOT NULL
          AND (
            -- 无有效期的批次被排到了有有效期的批次之前 = 违反 FEFO
            (ExpiryDate IS NULL AND NextExp IS NOT NULL)
            OR (ExpiryDate IS NOT NULL AND NextExp IS NOT NULL AND ExpiryDate > NextExp)
          )
    """, item_id, wh_id)
    check("C6 出库按效期从近到远扣减（FEFO）", cur.fetchone()[0] == 0)

    # ---------- C7 盘点：盘亏 ----------
    cur.execute("""
        INSERT INTO StocktakeOrder (StocktakeNo, WarehouseID, Status)
        OUTPUT INSERTED.StocktakeID
        VALUES (?, ?, N'盘点中')
    """, f"ST-TEST-{datetime.now():%H%M%S%f}", wh_id)
    st_id = cur.fetchone()[0]

    cur.execute("""
        INSERT INTO StocktakeLine (StocktakeID, StorageID, ItemID, LocationID, BatchNo, BookQty, CountedQty)
        SELECT TOP 1 ?, StorageID, ItemID, LocationID, BatchNo, Storing, Storing - 5
        FROM Storage WHERE ItemID=? AND WarehouseID=? AND Storing > 10 ORDER BY StorageID
    """, st_id, item_id, wh_id)
    cn.commit()

    cur.execute("SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                item_id, wh_id)
    before_st = cur.fetchone()[0]

    cur.execute("DECLARE @a INT; EXEC dbo.sp_CompleteStocktake ?, ?, @a OUTPUT; SELECT @a",
                st_id, staff_id)
    adjusted = cur.fetchone()[0]
    cn.commit()

    cur.execute("SELECT ISNULL(SUM(Storing),0) FROM Storage WHERE ItemID=? AND WarehouseID=?",
                item_id, wh_id)
    after_st = cur.fetchone()[0]
    check("C7 盘点产生 1 条调整", adjusted == 1, f"({after_st - before_st})")
    check("C7 盘亏后库存 -5", after_st == before_st - 5)

    cur.execute("SELECT Status FROM StocktakeOrder WHERE StocktakeID=?", st_id)
    check("C7 盘点单状态 = 已完成", cur.fetchone()[0] == "已完成")

    cur.execute("SELECT TOP 1 OperationType FROM Record WHERE SourceType=N'盘点单' AND SourceOrderID=? ORDER BY RecordID DESC", st_id)
    row = cur.fetchone()
    check("C7 生成的是「盘亏」流水", row and row[0] == "盘亏", row[0] if row else "")

    # ---------- C8 重复结案被拒 ----------
    try:
        cur.execute("DECLARE @a INT; EXEC dbo.sp_CompleteStocktake ?, ?, @a OUTPUT", st_id, staff_id)
        check("C8 重复结案被拒绝", False)
    except pyodbc.Error as e:
        cn.rollback()
        check("C8 重复结案被拒绝", "50006" in str(e))

    cn.close()
    ok, total = sum(results), len(results)
    print(f"\n{'=' * 44}\n通过 {ok}/{total}")
    return 0 if ok == total else 1


if __name__ == "__main__":
    sys.exit(main())
