# -*- coding: utf-8 -*-
"""审计查询：操作流水、库存变动、权限变动。"""
from __future__ import annotations

import pandas as pd

from warehouse.db import engine


def operation_log(op_type: str | None = None,
                  keyword: str | None = None,
                  start=None,
                  end=None,
                  limit: int | None = None) -> pd.DataFrame:
    """
    操作流水。op_type 传 None 表示全部。

    日期范围与关键词都下推到 SQL —— 数据量涨起来以后，
    在 pandas 里过滤意味着把整表拉进内存再丢掉大部分。
    limit 用 TOP 同理。
    """
    sql = """
        SELECT RecordID      AS [编号],
               OperationTime AS [时间],
               OperationType AS [类型],
               ItemName      AS [物品],
               ItemType      AS [规格],
               OperationQuantity AS [数量],
               WarehouseName AS [仓库],
               SupplierName  AS [供应商],
               OperatorName  AS [经办人],
               BizType       AS [业务],
               Remarks       AS [备注]
        FROM dbo.vw_OperationLog
        WHERE (:tp IS NULL OR OperationType = :tp)
          AND (:kw IS NULL OR ItemName LIKE N'%' + :kw + N'%'
                          OR OperatorName LIKE N'%' + :kw + N'%')
          AND (:st IS NULL OR OperationTime >= :st)
          AND (:en IS NULL OR OperationTime < DATEADD(day, 1, :en))
        ORDER BY OperationTime DESC, RecordID DESC
    """
    params = {
        "tp": op_type,
        "kw": keyword or None,
        "st": str(start) if start else None,
        "en": str(end) if end else None,
    }

    if limit:
        sql = sql.replace("SELECT RecordID", f"SELECT TOP {int(limit)} RecordID", 1)

    return engine.fetch_df(sql, params)


def stock_audit(action_type: str | None = None, limit: int | None = None) -> pd.DataFrame:
    sql = """
        SELECT AuditID     AS [编号],
               AuditTime   AS [时间],
               ActionType  AS [动作],
               ItemName    AS [物品],
               WarehouseName AS [仓库],
               SupplierName  AS [批次供应商],
               ChangeQty   AS [变动],
               BeforeQty   AS [变动前],
               AfterQty    AS [变动后],
               RecordID    AS [关联流水]
        FROM dbo.vw_StockAudit
        WHERE (:tp IS NULL OR ActionType = :tp)
        ORDER BY AuditTime DESC, AuditID DESC
    """
    if limit:
        sql = sql.replace("SELECT AuditID", f"SELECT TOP {int(limit)} AuditID", 1)
    return engine.fetch_df(sql, {"tp": action_type})


def permission_audit(action_type: str | None = None, limit: int | None = None) -> pd.DataFrame:
    sql = """
        SELECT AuditID     AS [编号],
               AuditTime   AS [时间],
               ActionType  AS [动作],
               StaffName   AS [员工],
               WarehouseName AS [仓库],
               OperatorNote  AS [说明]
        FROM dbo.vw_PermissionAudit
        WHERE (:tp IS NULL OR ActionType = :tp)
        ORDER BY AuditTime DESC, AuditID DESC
    """
    if limit:
        sql = sql.replace("SELECT AuditID", f"SELECT TOP {int(limit)} AuditID", 1)
    return engine.fetch_df(sql, {"tp": action_type})


def transfer_group(group_id: str) -> pd.DataFrame:
    """按调拨组号还原一对流水，用于核对调拨是否两端都落地"""
    return engine.fetch_df("""
        SELECT RecordID, OperationTime, OperationType, ItemName,
               WarehouseName, OperationQuantity, OperatorName, Remarks
        FROM dbo.vw_OperationLog
        WHERE TransferGroupID = :g
        ORDER BY RecordID
    """, {"g": group_id})


def daily_trend(days: int = 14) -> pd.DataFrame:
    """
    出入库趋势。

    锚点取「库里最新一条流水的日期」而不是今天 —— 真实运行时两者等价，
    但如果数据是一段历史（比如答辩演示用的是几个月前的数据），
    以今天为锚会得到一张全 0 的空图。

    日期序列用递归 CTE 补全，避免折线把相隔很远的两个点直接连起来。
    """
    return engine.fetch_df("""
        WITH anchor AS (
            SELECT CAST(ISNULL((SELECT MAX(OperationTime) FROM dbo.Record), GETDATE()) AS DATE) AS d
        ),
        span AS (
            SELECT DATEADD(day, -(:days - 1), (SELECT d FROM anchor)) AS d
            UNION ALL
            SELECT DATEADD(day, 1, d) FROM span WHERE d < (SELECT d FROM anchor)
        ),
        agg AS (
            SELECT CAST(OperationTime AS DATE) AS d,
                   SUM(CASE WHEN OperationType IN (N'入库', N'调拨入')
                            THEN OperationQuantity ELSE 0 END) AS InQty,
                   SUM(CASE WHEN OperationType IN (N'出库', N'调拨出')
                            THEN OperationQuantity ELSE 0 END) AS OutQty
            FROM dbo.Record
            WHERE OperationTime >= DATEADD(day, -(:days - 1), (SELECT d FROM anchor))
            GROUP BY CAST(OperationTime AS DATE)
        )
        SELECT s.d AS [日期],
               ISNULL(a.InQty, 0)  AS [入库],
               ISNULL(a.OutQty, 0) AS [出库]
        FROM span s
                 LEFT JOIN agg a ON s.d = a.d
        ORDER BY s.d
        OPTION (MAXRECURSION 400)
    """, {"days": days})


def recent_activity(limit: int = 8) -> pd.DataFrame:
    """最近的流水，用于首页活动流"""
    return engine.fetch_df("""
        SELECT TOP (:lim) OperationTime, OperationType, ItemName,
               OperationQuantity, WarehouseName, OperatorName
        FROM dbo.vw_OperationLog
        ORDER BY OperationTime DESC, RecordID DESC
    """, {"lim": limit})


def audit_stats() -> dict:
    """审计页顶部的几个数：总量、今日、近七日、权限变动数"""
    row = engine.fetch_one("""
        SELECT (SELECT COUNT(*) FROM dbo.StockAudit)                                   AS total_stock,
               (SELECT COUNT(*) FROM dbo.StockAudit
                WHERE AuditTime >= CAST(GETDATE() AS DATE))                            AS today_stock,
               (SELECT COUNT(*) FROM dbo.StockAudit
                WHERE AuditTime >= DATEADD(day, -7, GETDATE()))                        AS week_stock,
               (SELECT COUNT(*) FROM dbo.PermissionAudit)                              AS total_perm
    """)
    if not row:
        return {}
    return dict(zip(["total_stock", "today_stock", "week_stock", "total_perm"], row))
