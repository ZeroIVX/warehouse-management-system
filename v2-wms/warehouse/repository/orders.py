# -*- coding: utf-8 -*-
"""
单据与库位的数据访问。

三张单据（入库 / 出库 / 盘点）的读写都在这里，逻辑保持"只拼 SQL、不做判断"。
真正的校验在存储过程里，这一层负责把界面上的操作翻译成参数。
"""
from __future__ import annotations

import datetime as dt

import pandas as pd

from warehouse.db import engine


# ==========================================================================
# 库位
# ==========================================================================

def zone_options(warehouse_id: int | None = None) -> list[tuple]:
    """库区下拉；不传仓库则列出全部"""
    df = engine.fetch_df("""
        SELECT z.ZoneID, w.WarehouseName + N' / ' + z.ZoneName AS Label
        FROM dbo.WarehouseZone z
                 INNER JOIN dbo.Warehouse w ON z.WarehouseID = w.WarehouseID
        WHERE (:wid IS NULL OR z.WarehouseID = :wid)
        ORDER BY w.WarehouseName, z.ZoneCode
    """, {"wid": warehouse_id})
    return [(int(r[0]), r[1]) for r in df.itertuples(index=False, name=None)]


def location_options(warehouse_id: int | None = None, zone_type: str | None = None) -> list[tuple]:
    """库位下拉：只列可用（未锁定）的货位"""
    sql = """
        SELECT l.LocationID,
               w.WarehouseName + N' / ' + z.ZoneCode + N' / ' + l.LocationCode
               + N'（剩 ' + CAST(l.Capacity - ISNULL(u.Used, 0) AS NVARCHAR) + N'）' AS Label
        FROM dbo.StorageLocation l
                 INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
                 INNER JOIN dbo.Warehouse w ON z.WarehouseID = w.WarehouseID
                 LEFT JOIN (SELECT LocationID, SUM(Storing) AS Used
                            FROM dbo.Storage GROUP BY LocationID) u ON u.LocationID = l.LocationID
        WHERE l.IsLocked = 0
          AND (:wid IS NULL OR w.WarehouseID = :wid)
          AND (:zt IS NULL OR z.ZoneType = :zt)
        ORDER BY w.WarehouseName, z.ZoneCode, l.LocationCode
    """
    df = engine.fetch_df(sql, {"wid": warehouse_id, "zt": zone_type})
    return [(int(r[0]), r[1]) for r in df.itertuples(index=False, name=None)]


def location_utilization(warehouse_id: int | None = None) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT WarehouseName AS [仓库], ZoneCode AS [库区], ZoneType AS [类型],
               LocationCode AS [货位], Capacity AS [容量],
               UsedQty AS [已用], UnitCount AS [库存单元],
               CAST(UsagePercent AS DECIMAL(5,1)) AS [使用率%],
               CASE WHEN IsLocked = 1 THEN N'锁定' ELSE N'可用' END AS [状态]
        FROM dbo.vw_LocationUtilization
        WHERE (:wid IS NULL OR WarehouseName = (SELECT WarehouseName FROM dbo.Warehouse WHERE WarehouseID = :wid))
        ORDER BY WarehouseName, ZoneCode, LocationCode
    """, {"wid": warehouse_id})


# ==========================================================================
# 入库单
# ==========================================================================

def next_order_no(prefix: str) -> str:
    """单号：前缀 + 日期 + 三位流水，取当天已有最大值 +1"""
    today = dt.date.today().strftime("%Y%m%d")
    head = f"{prefix}{today}"
    val = engine.fetch_scalar("""
        SELECT MAX(CAST(RIGHT(OrderNo, 3) AS INT))
        FROM dbo.InboundOrder
        WHERE OrderNo LIKE :p
    """, {"p": head + "%"})
    seq = (int(val) if val else 0) + 1
    return f"{head}{seq:03d}"


def create_inbound(order_type: str, warehouse_id: int, supplier_id: int | None,
                   expected: dt.date | None, remark: str | None,
                   lines: list[dict]) -> int:
    """
    新建入库单（草稿/待收货）+ 明细行。

    单头与明细必须同一事务 —— 否则可能留下没有明细的空单。
    明细是用户一次填完的列表，逐行 INSERT 即可。
    """
    from sqlalchemy import text

    order_no = next_order_no("PO")
    with engine.get_engine().begin() as conn:
        # 用 OUTPUT INSERTED 取主键。
        # 不要用 SELECT SCOPE_IDENTITY() —— pyodbc 下这条语句常常拿到 NULL，
        # 结果 OrderID 变成空值，往明细表插的时候直接撞 NOT NULL 约束。
        order_id = conn.execute(text("""
            INSERT INTO dbo.InboundOrder (OrderNo, OrderType, WarehouseID, SupplierID, Status, ExpectedDate, Remark)
            OUTPUT INSERTED.OrderID
            VALUES (:no, :tp, :wh, :sup, N'待收货', :exp, :rmk)
        """), {"no": order_no, "tp": order_type, "wh": warehouse_id,
               "sup": supplier_id, "exp": expected, "rmk": remark}).scalar()

        for idx, line in enumerate(lines, start=1):
            conn.execute(text("""
                INSERT INTO dbo.InboundOrderLine
                    (OrderID, LineNumber, ItemID, PlannedQty, LocationID, BatchNo, ProductionDate, ExpiryDate)
                VALUES (:oid, :ln, :item, :qty, :loc, :batch, :prod, :exp)
            """), {"oid": order_id, "ln": idx, "item": line["item_id"], "qty": line["qty"],
                   "loc": line.get("location_id"), "batch": line.get("batch_no"),
                   "prod": line.get("production_date"), "exp": line.get("expiry_date")})

    return int(order_id)


def list_inbound_orders(status: str | None = None) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT OrderID, WarehouseID, OrderNo AS [单号], OrderType AS [类型], Status AS [状态],
               WarehouseName AS [仓库], SupplierName AS [供应商],
               ExpectedDate AS [预计到货], PlannedTotal AS [计划量],
               ReceivedTotal AS [已收], PendingTotal AS [待收],
               CAST(Progress AS DECIMAL(5,1)) AS [进度%],
               CreatedAt AS [创建时间]
        FROM dbo.vw_InboundOrderStatus
        WHERE (:st IS NULL OR Status = :st)
        ORDER BY OrderID DESC
    """, {"st": status})


def inbound_lines(order_id: int) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT l.LineID, l.LineNumber AS [行号], i.ItemName AS [物品], i.ItemType AS [规格],
               l.PlannedQty AS [计划], l.ReceivedQty AS [已收],
               l.PlannedQty - l.ReceivedQty AS [待收],
               ISNULL(l.BatchNo, N'—') AS [批次], l.ExpiryDate AS [效期],
               ISNULL(lc.LocationCode, N'未指定') AS [货位]
        FROM dbo.InboundOrderLine l
                 INNER JOIN dbo.Item i ON l.ItemID = i.ItemID
                 LEFT JOIN dbo.StorageLocation lc ON l.LocationID = lc.LocationID
        WHERE l.OrderID = :oid
        ORDER BY l.LineNumber
    """, {"oid": order_id})


def receive_line(line_id: int, qty: int, location_id: int | None, batch_no: str | None,
                 production_date, expiry_date, operator_id: int) -> int:
    result = engine.call_procedure("sp_ReceiveInbound", [
        ("LineID", line_id),
        ("Qty", qty),
        ("LocationID", location_id),
        ("BatchNo", batch_no),
        ("ProductionDate", production_date),
        ("ExpiryDate", expiry_date),
        ("OperatorID", operator_id),
    ])
    return int(result.get("RecordID") or 0)


# ==========================================================================
# 出库单
# ==========================================================================

def next_ship_no() -> str:
    today = dt.date.today().strftime("%Y%m%d")
    head = f"SO{today}"
    val = engine.fetch_scalar("""
        SELECT MAX(CAST(RIGHT(OrderNo, 3) AS INT))
        FROM dbo.OutboundOrder WHERE OrderNo LIKE :p
    """, {"p": head + "%"})
    seq = (int(val) if val else 0) + 1
    return f"{head}{seq:03d}"


def create_outbound(order_type: str, warehouse_id: int, customer_id: int | None,
                    required: dt.date | None, remark: str | None,
                    lines: list[dict]) -> int:
    from sqlalchemy import text

    order_no = next_ship_no()
    with engine.get_engine().begin() as conn:
        order_id = conn.execute(text("""
            INSERT INTO dbo.OutboundOrder (OrderNo, OrderType, WarehouseID, CustomerID, Status, RequiredDate, Remark)
            OUTPUT INSERTED.OrderID
            VALUES (:no, :tp, :wh, :cus, N'待拣货', :req, :rmk)
        """), {"no": order_no, "tp": order_type, "wh": warehouse_id,
               "cus": customer_id, "req": required, "rmk": remark}).scalar()

        for idx, line in enumerate(lines, start=1):
            conn.execute(text("""
                INSERT INTO dbo.OutboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty)
                VALUES (:oid, :ln, :item, :qty)
            """), {"oid": order_id, "ln": idx, "item": line["item_id"], "qty": line["qty"]})

    return int(order_id)


def list_outbound_orders(status: str | None = None) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT OrderID, WarehouseID, OrderNo AS [单号], OrderType AS [类型], Status AS [状态],
               WarehouseName AS [仓库], CustomerName AS [客户],
               RequiredDate AS [要求发货], PlannedTotal AS [计划量],
               PickedTotal AS [已发], PendingTotal AS [待发],
               CAST(Progress AS DECIMAL(5,1)) AS [进度%],
               CreatedAt AS [创建时间]
        FROM dbo.vw_OutboundOrderStatus
        WHERE (:st IS NULL OR Status = :st)
        ORDER BY OrderID DESC
    """, {"st": status})


def outbound_lines(order_id: int) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT l.LineID, l.ItemID, l.LineNumber AS [行号], i.ItemName AS [物品], i.ItemType AS [规格],
               l.PlannedQty AS [计划], l.PickedQty AS [已发],
               l.PlannedQty - l.PickedQty AS [待发]
        FROM dbo.OutboundOrderLine l
                 INNER JOIN dbo.Item i ON l.ItemID = i.ItemID
        WHERE l.OrderID = :oid
        ORDER BY l.LineNumber
    """, {"oid": order_id})


def ship_line(line_id: int, qty: int, operator_id: int) -> int:
    result = engine.call_procedure("sp_ShipOutbound", [
        ("LineID", line_id), ("Qty", qty), ("OperatorID", operator_id),
    ])
    return int(result.get("RecordID") or 0)


# ==========================================================================
# 盘点
# ==========================================================================

def create_stocktake(warehouse_id: int, zone_id: int | None, remark: str | None) -> int:
    """
    建盘点单并自动带出账面数。

    只带"有库存的"批次，账面数为 0 的空货位不需要盘。
    """
    from sqlalchemy import text

    today = dt.date.today().strftime("%Y%m%d")
    val = engine.fetch_scalar("""
        SELECT MAX(CAST(RIGHT(StocktakeNo, 3) AS INT))
        FROM dbo.StocktakeOrder WHERE StocktakeNo LIKE :p
    """, {"p": f"ST{today}%"})
    seq = (int(val) if val else 0) + 1
    no = f"ST{today}{seq:03d}"

    with engine.get_engine().begin() as conn:
        st_id = conn.execute(text("""
            INSERT INTO dbo.StocktakeOrder (StocktakeNo, WarehouseID, ZoneID, Status, StartedAt, Remark)
            OUTPUT INSERTED.StocktakeID
            VALUES (:no, :wh, :zone, N'盘点中', GETDATE(), :rmk)
        """), {"no": no, "wh": warehouse_id, "zone": zone_id, "rmk": remark}).scalar()

        conn.execute(text("""
            INSERT INTO dbo.StocktakeLine
                (StocktakeID, StorageID, ItemID, LocationID, BatchNo, BookQty, CountedQty)
            SELECT :sid, s.StorageID, s.ItemID, s.LocationID, s.BatchNo, s.Storing, NULL
            FROM dbo.Storage s
                     LEFT JOIN dbo.StorageLocation l ON s.LocationID = l.LocationID
                     LEFT JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
            WHERE s.WarehouseID = :wh
              AND s.Storing > 0
              AND (:zone IS NULL OR z.ZoneID = :zone)
        """), {"sid": st_id, "wh": warehouse_id, "zone": zone_id})

    return int(st_id)


def list_stocktakes() -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT st.StocktakeID, st.WarehouseID, st.StocktakeNo AS [盘点单号],
               w.WarehouseName AS [仓库],
               ISNULL(z.ZoneName, N'全仓') AS [范围],
               st.Status AS [状态],
               (SELECT COUNT(*) FROM dbo.StocktakeLine l WHERE l.StocktakeID = st.StocktakeID) AS [行数],
               (SELECT COUNT(*) FROM dbo.StocktakeLine l
                WHERE l.StocktakeID = st.StocktakeID AND l.CountedQty IS NOT NULL) AS [已盘],
               st.StartedAt AS [开始时间], st.CompletedAt AS [结案时间]
        FROM dbo.StocktakeOrder st
                 INNER JOIN dbo.Warehouse w ON st.WarehouseID = w.WarehouseID
                 LEFT JOIN dbo.WarehouseZone z ON st.ZoneID = z.ZoneID
        ORDER BY st.StocktakeID DESC
    """)


def stocktake_lines(stocktake_id: int) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT l.LineID, i.ItemName AS [物品], i.ItemType AS [规格],
               ISNULL(lc.LocationCode, N'未上架') AS [货位],
               ISNULL(l.BatchNo, N'—') AS [批次],
               l.BookQty AS [账面], l.CountedQty AS [实盘],
               l.Variance AS [差异]   -- 未盘时为 NULL，不要兜底成 0 免得看着像已盘平
        FROM dbo.StocktakeLine l
                 INNER JOIN dbo.Item i ON l.ItemID = i.ItemID
                 LEFT JOIN dbo.StorageLocation lc ON l.LocationID = lc.LocationID
        WHERE l.StocktakeID = :sid
        ORDER BY l.LineID
    """, {"sid": stocktake_id})


def set_counted(line_id: int, counted: int) -> None:
    engine.execute(
        "UPDATE dbo.StocktakeLine SET CountedQty = :q WHERE LineID = :id",
        {"q": counted, "id": line_id},
    )


def complete_stocktake(stocktake_id: int, operator_id: int) -> int:
    result = engine.call_procedure("sp_CompleteStocktake", [
        ("StocktakeID", stocktake_id), ("OperatorID", operator_id),
    ])
    return int(result.get("Adjusted") or 0)


# ==========================================================================
# 客户
# ==========================================================================

def customer_options() -> list[tuple]:
    return [(int(r[0]), r[1]) for r in engine.fetch_df(
        "SELECT CustomerID, CustomerName FROM dbo.Customer ORDER BY CustomerName"
    ).itertuples(index=False, name=None)]

# ==========================================================================
# 调拨单
# ==========================================================================

def next_transfer_no() -> str:
    today = dt.date.today().strftime("%Y%m%d")
    head = f"TR{today}"
    val = engine.fetch_scalar("""
        SELECT MAX(CAST(RIGHT(TransferNo, 3) AS INT))
        FROM dbo.TransferOrder WHERE TransferNo LIKE :p
    """, {"p": head + "%"})
    seq = (int(val) if val else 0) + 1
    return f"{head}{seq:03d}"


def create_transfer(src_warehouse_id: int, dst_warehouse_id: int,
                    src_operator_id: int | None, dst_operator_id: int | None,
                    remark: str | None, lines: list[dict]) -> int:
    """建调拨单。单头的两个仓库不能相同（由 CK_Tr_Diff 兜底）。"""
    from sqlalchemy import text

    no = next_transfer_no()
    with engine.get_engine().begin() as conn:
        tid = conn.execute(text("""
            INSERT INTO dbo.TransferOrder
                (TransferNo, SrcWarehouseID, DstWarehouseID, SrcOperatorID, DstOperatorID, Status, Remark)
            OUTPUT INSERTED.TransferID
            VALUES (:no, :src, :dst, :sop, :dop, N'待发货', :rmk)
        """), {"no": no, "src": src_warehouse_id, "dst": dst_warehouse_id,
               "sop": src_operator_id, "dop": dst_operator_id, "rmk": remark}).scalar()

        for idx, line in enumerate(lines, start=1):
            conn.execute(text("""
                INSERT INTO dbo.TransferOrderLine (TransferID, LineNumber, ItemID, SupplierID, PlannedQty)
                VALUES (:tid, :ln, :item, :sup, :qty)
            """), {"tid": tid, "ln": idx, "item": line["item_id"],
                   "sup": line.get("supplier_id"), "qty": line["qty"]})

    return int(tid)


def list_transfer_orders(status: str | None = None) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT TransferID, TransferNo AS [单号], Status AS [状态],
               SrcWarehouseName AS [源仓库], DstWarehouseName AS [目标仓库],
               SrcOperatorName AS [发货人], DstOperatorName AS [收货人],
               PlannedTotal AS [计划量], ShippedTotal AS [已发], PendingTotal AS [待发],
               CAST(Progress AS DECIMAL(5,1)) AS [进度%],
               CreatedAt AS [创建时间]
        FROM dbo.vw_TransferOrderStatus
        WHERE (:st IS NULL OR Status = :st)
        ORDER BY TransferID DESC
    """, {"st": status})


def transfer_lines(transfer_id: int) -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT l.LineID, l.ItemID, l.LineNumber AS [行号],
               i.ItemName AS [物品], i.ItemType AS [规格],
               l.PlannedQty AS [计划], l.ShippedQty AS [已发],
               l.PlannedQty - l.ShippedQty AS [待发]
        FROM dbo.TransferOrderLine l
                 INNER JOIN dbo.Item i ON l.ItemID = i.ItemID
        WHERE l.TransferID = :tid
        ORDER BY l.LineNumber
    """, {"tid": transfer_id})


def ship_transfer_line(line_id: int, qty: int) -> str:
    result = engine.call_procedure("sp_ShipTransfer", [
        ("LineID", line_id), ("Qty", qty),
    ])
    return str(result.get("TransferGroupID") or "")
