# -*- coding: utf-8 -*-
"""
库存查询。

全部走视图，不再随手拼 JOIN —— 原版库存页用 INNER JOIN Supplier，
把 SupplierID 为 NULL 的批次整行过滤掉了（实测隐藏 104 件），
而出库流程又能扣减这些"看不见"的库存，两处口径互相矛盾。
"""
from __future__ import annotations

import pandas as pd

from warehouse.db import engine


def stock_overview(keyword: str | None = None,
                   warehouse_id: int | None = None,
                   item_type: str | None = None) -> pd.DataFrame:
    """
    库存明细。

    筛选条件全部以参数传入，并用 (:p IS NULL OR 条件) 的写法让同一条 SQL
    适配所有组合，避免在 Python 里拼 WHERE 子句（那正是原版的注入来源）。
    """
    return engine.fetch_df("""
        SELECT ItemName  AS [物品],
               ItemType  AS [规格],
               FactName  AS [生产厂家],
               WarehouseName AS [仓库],
               WarehouseType AS [仓库类型],
               LocationCode  AS [货位],
               BatchNo       AS [批次],
               SupplierName  AS [供应商],
               ExpiryDate    AS [效期],
               Storing       AS [当前库存],
               Amount        AS [库存金额],
               LastUpdate    AS [更新时间]
        FROM dbo.vw_StockOverview
        WHERE (:kw  IS NULL OR ItemName LIKE N'%' + :kw + N'%')
          AND (:wid IS NULL OR WarehouseID = :wid)
          AND (:tp  IS NULL OR ItemType LIKE N'%' + :tp + N'%')
        ORDER BY WarehouseName, ItemName
    """, {"kw": keyword or None, "wid": warehouse_id, "tp": item_type or None})


def stock_alerts(threshold: int = 20) -> pd.DataFrame:
    """
    库存预警：按「物品 × 仓库」汇总后低于安全线。

    不按供应商批次判断 —— 安全库存是业务口径，同一物品三个供应商各存 15 件，
    实际有 45 件，按批次判断会报三次假警报。
    """
    return engine.fetch_df("""
        SELECT ItemName    AS [物品],
               ItemType    AS [规格],
               WarehouseName AS [仓库],
               TotalStock  AS [库存],
               SafetyStock AS [安全库存],
               Shortage    AS [缺口]
        FROM dbo.vw_StockAlert
        WHERE TotalStock < :th
        ORDER BY TotalStock
    """, {"th": threshold})


def available_qty(item_id: int, warehouse_id: int, supplier_id: int | None = None) -> int:
    """某物品在某仓库的可用量；指定供应商时只算该供应商批次"""
    val = engine.fetch_scalar("""
        SELECT ISNULL(SUM(Storing), 0)
        FROM dbo.Storage
        WHERE ItemID = :iid AND WarehouseID = :wid
          AND (:sid IS NULL OR ISNULL(SupplierID, 0) = ISNULL(:sid, 0))
    """, {"iid": item_id, "wid": warehouse_id, "sid": supplier_id})
    return int(val or 0)


def warehouses_with_stock(item_id: int) -> list[tuple]:
    """该物品有货的仓库 —— 出库/调拨的源仓库候选"""
    df = engine.fetch_df("""
        SELECT w.WarehouseID, w.WarehouseName, SUM(st.Storing) AS Qty
        FROM dbo.Storage st
                 INNER JOIN dbo.Warehouse w ON st.WarehouseID = w.WarehouseID
        WHERE st.ItemID = :iid AND st.Storing > 0
        GROUP BY w.WarehouseID, w.WarehouseName
        ORDER BY w.WarehouseName
    """, {"iid": item_id})
    return [(int(r.WarehouseID), f"{r.WarehouseName}（余 {int(r.Qty)}）")
            for r in df.itertuples()] if not df.empty else []


def suppliers_of_item_in_warehouse(item_id: int, warehouse_id: int) -> list[tuple]:
    """
    该物品在该仓库下有库存的供应商。

    始终把 None（不指定供应商）放在第一位：这也是一个合法的扣减口径，
    指代"该仓库该物品的全部批次"。
    """
    df = engine.fetch_df("""
        SELECT DISTINCT st.SupplierID, s.SupName
        FROM dbo.Storage st
                 LEFT JOIN dbo.Supplier s ON st.SupplierID = s.SupID
        WHERE st.ItemID = :iid AND st.WarehouseID = :wid AND st.Storing > 0
        ORDER BY s.SupName
    """, {"iid": item_id, "wid": warehouse_id})

    result: list[tuple] = [(None, "⚪ 不指定供应商（按批次先进先出）")]
    for r in df.itertuples():
        if r.SupplierID is not None and pd.notna(r.SupplierID):
            result.append((int(r.SupplierID), r.SupName))
    return result


def warehouse_utilization() -> pd.DataFrame:
    return engine.fetch_df("SELECT * FROM dbo.vw_WarehouseUtilization ORDER BY WarehouseID")


def summary_metrics() -> dict:
    row = engine.fetch_one("""
        SELECT (SELECT COUNT(*) FROM dbo.Item)                                  AS item_count,
               (SELECT COUNT(*) FROM dbo.Warehouse)                             AS warehouse_count,
               (SELECT ISNULL(SUM(Storing), 0) FROM dbo.Storage)                AS total_stock,
               (SELECT ISNULL(SUM(Storing * i.Price), 0)
                FROM dbo.Storage st JOIN dbo.Item i ON st.ItemID = i.ItemID)    AS total_amount,
               (SELECT COUNT(*) FROM dbo.Record)                                AS record_count,
               (SELECT COUNT(*) FROM dbo.vw_StockAlert)                         AS alert_count
    """)
    if not row:
        return {}
    keys = ["item_count", "warehouse_count", "total_stock", "total_amount",
            "record_count", "alert_count"]
    return dict(zip(keys, row))


def stock_by_warehouse() -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT WarehouseName AS [仓库], SUM(Storing) AS [库存量]
        FROM dbo.vw_StockOverview
        GROUP BY WarehouseName
        ORDER BY [库存量] DESC
    """)


def stock_by_type() -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT ISNULL(ItemType, N'未分类') AS [规格], SUM(Storing) AS [库存量]
        FROM dbo.vw_StockOverview
        GROUP BY ItemType
        ORDER BY [库存量] DESC
    """)


def expiry_alerts(days: int = 90) -> pd.DataFrame:
    """临期/过期批次。days 之外的不提示。"""
    return engine.fetch_df("""
        SELECT ItemName    AS [物品],
               ItemType    AS [规格],
               WarehouseName AS [仓库],
               LocationCode AS [货位],
               BatchNo     AS [批次],
               ExpiryDate  AS [效期],
               DaysToExpire AS [剩余天数],
               Storing     AS [库存],
               ExpiryStatus AS [状态]
        FROM dbo.vw_ExpiryAlert
        WHERE DaysToExpire <= :d
        ORDER BY DaysToExpire
    """, {"d": days})


def replenishment() -> pd.DataFrame:
    """补货建议：只覆盖该仓库确实经营过的物品"""
    return engine.fetch_df("""
        SELECT ItemName AS [物品], ItemType AS [规格], WarehouseName AS [仓库],
               OnHand AS [现有], SafetyStock AS [安全线], Shortage AS [建议补货]
        FROM dbo.vw_Replenishment
        ORDER BY Shortage DESC
    """)

def category_distribution() -> pd.DataFrame:
    """按品类汇总：库存量、金额、批次数。大屏的「结构」维度。"""
    return engine.fetch_df("""
        SELECT ISNULL(ItemType, N'未分类') AS Category,
               SUM(Storing)                AS Qty,
               SUM(Amount)                 AS Amount,
               COUNT(*)                    AS BatchCount
        FROM dbo.vw_StockOverview
        GROUP BY ItemType
        ORDER BY Amount DESC
    """)


def top_items(limit: int = 10, by: str = "qty") -> pd.DataFrame:
    """库存量或金额 TOP N，用于大屏排行榜"""
    order = "Qty DESC" if by == "qty" else "Amount DESC"
    return engine.fetch_df(f"""
        SELECT TOP (:lim) ItemName AS ItemName,
               ItemType          AS ItemType,
               SUM(Storing)      AS Qty,
               SUM(Amount)       AS Amount
        FROM dbo.vw_StockOverview
        GROUP BY ItemName, ItemType
        ORDER BY {order}
    """, {"lim": limit})


def warehouse_share() -> pd.DataFrame:
    """各仓库库存量与金额占比"""
    return engine.fetch_df("""
        SELECT WarehouseName AS WarehouseName,
               SUM(Storing)  AS Qty,
               SUM(Amount)   AS Amount,
               COUNT(*)      AS BatchCount
        FROM dbo.vw_StockOverview
        GROUP BY WarehouseName
        ORDER BY Qty DESC
    """)


def turnover(days: int = 90) -> pd.DataFrame:
    """
    周转分析：近 N 天出库量 / 当前库存 = 周转次数，再折算周转天数。

    周转天数越短说明货卖得越快；超过 90 天通常视为呆滞。
    没有出库记录的仓库周转天数记为 NULL（不是 0 —— 0 会被误读成"周转极快"）。
    """
    return engine.fetch_df("""
        WITH outflow AS (
            SELECT WarehouseID, SUM(OperationQuantity) AS OutQty
            FROM dbo.Record
            WHERE OperationType IN (N'出库', N'调拨出')
              AND OperationTime >= DATEADD(day, -:days, GETDATE())
            GROUP BY WarehouseID
        ),
        stockq AS (
            SELECT WarehouseID, SUM(Storing) AS OnHand
            FROM dbo.Storage
            GROUP BY WarehouseID
        )
        SELECT w.WarehouseName AS WarehouseName,
               ISNULL(q.OnHand, 0) AS OnHand,
               ISNULL(o.OutQty, 0) AS OutQty,
               CASE WHEN ISNULL(o.OutQty, 0) = 0 OR ISNULL(q.OnHand, 0) = 0 THEN NULL
                    ELSE CAST(:days * 1.0 * ISNULL(q.OnHand, 0) / o.OutQty AS DECIMAL(8, 1))
               END AS TurnoverDays
        FROM dbo.Warehouse w
                 LEFT JOIN outflow o ON w.WarehouseID = o.WarehouseID
                 LEFT JOIN stockq q ON w.WarehouseID = q.WarehouseID
        ORDER BY w.WarehouseID
    """, {"days": days})


def location_heat() -> pd.DataFrame:
    """库位占用热力：按库区看货位使用率"""
    return engine.fetch_df("""
        SELECT WarehouseName, ZoneCode, ZoneType, LocationCode,
               UsedQty, Capacity,
               CAST(UsagePercent AS DECIMAL(5,1)) AS UsagePercent
        FROM dbo.vw_LocationUtilization
        ORDER BY WarehouseName, ZoneCode, LocationCode
    """)

def warehouse_locations(warehouse_id: int) -> pd.DataFrame:
    """某个仓库的全部货位及其占用情况 —— 货位矩阵图的数据源"""
    return engine.fetch_df("""
        SELECT LocationCode, ZoneCode, ZoneName, ZoneType,
               UsedQty, Capacity,
               CAST(UsagePercent AS DECIMAL(6,1)) AS UsagePercent
        FROM dbo.vw_LocationUtilization
        WHERE WarehouseName = (SELECT WarehouseName FROM dbo.Warehouse
                               WHERE WarehouseID = :wid)
        ORDER BY ZoneCode, LocationCode
    """, {"wid": warehouse_id})

def location_item_mix(warehouse_id: int) -> pd.DataFrame:
    """
    货位里的品类构成：每个货位放了哪些品类、各多少件。

    一个货位可以同时存放多个品类的货（不同批次），所以这里返回明细，
    由界面层聚合出"主品类"（存量最多的那个）用于着色。
    """
    return engine.fetch_df("""
        SELECT l.LocationCode,
               z.ZoneCode,
               i.ItemType,
               SUM(s.Storing) AS Qty
        FROM dbo.Storage s
                 INNER JOIN dbo.StorageLocation l ON s.LocationID = l.LocationID
                 INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
                 INNER JOIN dbo.Item i ON s.ItemID = i.ItemID
        WHERE z.WarehouseID = :wid
        GROUP BY l.LocationCode, z.ZoneCode, i.ItemType
        HAVING SUM(s.Storing) > 0
    """, {"wid": warehouse_id})
