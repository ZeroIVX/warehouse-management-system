/* ============================================================================
   03 视图层
   ----------------------------------------------------------------------------
   视图在这里承担三件事：
     1. 把多表 JOIN 固化下来，应用层只写 SELECT ... FROM vw_X，不再重复拼 SQL
        也顺带消除了"各处 JOIN 写法不一致"导致的口径矛盾
     2. 作为只读出口，给报表/审计用（权限上可以只授视图不授表）
     3. 把易错的 NULL 语义集中处理一次

   原版教训：库存查询用了 INNER JOIN Supplier，导致 SupplierID 为 NULL 的
   库存整行消失（实测隐藏 104 件），而出库流程却能扣减这些"看不见"的库存。
   这里统一改为 LEFT JOIN，并用 ISNULL 兜底显示。
   ============================================================================ */

USE WarehouseDB_V2;
GO

/* ---------------------------------------------------------------------------
   V1 库存明细：库存页、出库时的可用量、调拨源仓库列表
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_StockOverview
AS
SELECT st.StorageID,
       i.ItemID,
       i.ItemName,
       i.ItemType,
       f.FactName,
       st.WarehouseID,
       w.WarehouseName,
       wt.TypeName AS WarehouseType,
       st.SupplierID,
       ISNULL(s.SupName, N'未指定供应商') AS SupplierName,
       st.BatchNo,
       st.LocationID,
       ISNULL(l.LocationCode, N'未上架') AS LocationCode,
       st.ProductionDate,
       st.ExpiryDate,
       -- 剩余保质天数：负值表示已过期
       CASE WHEN st.ExpiryDate IS NULL THEN NULL
            ELSE DATEDIFF(day, CAST(GETDATE() AS DATE), st.ExpiryDate) END AS DaysToExpire,
       st.Storing,
       st.LastUpdate,
       -- 小计金额，报表直接用，避免前端再算
       CAST(st.Storing * i.Price AS DECIMAL(18, 2)) AS Amount
FROM dbo.Storage st
         INNER JOIN dbo.Item i ON st.ItemID = i.ItemID
         INNER JOIN dbo.Warehouse w ON st.WarehouseID = w.WarehouseID
         LEFT JOIN dbo.Supplier s ON st.SupplierID = s.SupID
         LEFT JOIN dbo.Factory f ON i.FactoryID = f.FactID
         LEFT JOIN dbo.WarehouseType wt ON w.WarehouseTypeID = wt.TypeID
         LEFT JOIN dbo.StorageLocation l ON st.LocationID = l.LocationID;
GO

/* ---------------------------------------------------------------------------
   V2 仓库容量利用：把使用量/库容/使用率算好，前端不做除法
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_WarehouseUtilization
AS
SELECT        w.WarehouseID,
       w.WarehouseName,
       wt.TypeName AS WarehouseType,
       w.WarehouseAddress,
       w.WarehouseSize,
       w.WarehouseUsage,
       w.WarehouseSize - w.WarehouseUsage AS FreeSpace,
       CAST(CASE
                WHEN w.WarehouseSize = 0 THEN 0
                ELSE w.WarehouseUsage * 100.0 / w.WarehouseSize
           END AS DECIMAL(5, 2))           AS UsagePercent,
       (SELECT COUNT(*) FROM dbo.Storage st WHERE st.WarehouseID = w.WarehouseID) AS BatchCount
FROM dbo.Warehouse w
         INNER JOIN dbo.WarehouseType wt ON w.WarehouseTypeID = wt.TypeID;
GO

/* ---------------------------------------------------------------------------
   V3 库存预警：按「物品 × 仓库」汇总后判断，而不是按批次
   ---------------------------------------------------------------------------
   安全库存是业务口径，看的是"这个物品在这个仓库还剩多少"，
   拆到供应商批次去看会产生大量假警报 —— 同一物品三个供应商各存 15 件，
   实际有 45 件，按批次判断却会报三次缺货。
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_StockAlert
AS
SELECT o.ItemID,
       o.ItemName,
       o.ItemType,
       o.WarehouseID,
       o.WarehouseName,
       SUM(o.Storing)                 AS TotalStock,
       CAST(20 AS INT)                AS SafetyStock,
       CAST(20 - SUM(o.Storing) AS INT) AS Shortage
FROM dbo.vw_StockOverview o
GROUP BY o.ItemID, o.ItemName, o.ItemType, o.WarehouseID, o.WarehouseName
HAVING SUM(o.Storing) < 20;
GO

/* ---------------------------------------------------------------------------
   V4 员工权限：员工 × 仓库 的授权关系（含未分配员工）
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_StaffPermission
AS
SELECT s.StaffID,
       s.StaffName,
       s.StaffTel,
       CASE WHEN s.IsActive = 1 THEN N'在职' ELSE N'离职' END AS StatusText,
       s.IsActive,
       sa.WarehouseID,
       w.WarehouseName
FROM dbo.Staff s
         LEFT JOIN dbo.StaffAssignment sa ON s.StaffID = sa.StaffID
         LEFT JOIN dbo.Warehouse w ON sa.WarehouseID = w.WarehouseID;
GO

/* ---------------------------------------------------------------------------
   V5 操作流水：把人名/物品名/仓库名都翻译好，调拨记录标注成组
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_OperationLog
AS
SELECT r.RecordID,
       r.OperationTime,
       r.OperationType,
       i.ItemName,
       i.ItemType,
       r.OperationQuantity,
       w.WarehouseName,
       ISNULL(s.SupName, N'未指定') AS SupplierName,
       ISNULL(st.StaffName, N'未知') AS OperatorName,
       r.Remarks,
       r.TransferGroupID,
       CASE WHEN r.TransferGroupID IS NULL THEN N'常规' ELSE N'调拨' END AS BizType
FROM dbo.Record r
         INNER JOIN dbo.Item i ON r.ItemID = i.ItemID
         INNER JOIN dbo.Warehouse w ON r.WarehouseID = w.WarehouseID
         LEFT JOIN dbo.Supplier s ON r.SupplierID = s.SupID
         LEFT JOIN dbo.Staff st ON r.OperatorID = st.StaffID;
GO

/* ---------------------------------------------------------------------------
   V6 库存审计：把批次级变动翻译成可读的"哪个物品在哪个仓库变动了多少"
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_StockAudit
AS
SELECT a.AuditID,
       a.AuditTime,
       a.ActionType,
       i.ItemName,
       w.WarehouseName,
       ISNULL(s.SupName, N'未指定') AS SupplierName,
       a.ChangeQty,
       a.BeforeQty,
       a.AfterQty,
       a.RecordID
FROM dbo.StockAudit a
         INNER JOIN dbo.Item i ON a.ItemID = i.ItemID
         INNER JOIN dbo.Warehouse w ON a.WarehouseID = w.WarehouseID
         LEFT JOIN dbo.Supplier s ON a.SupplierID = s.SupID;
GO

/* ---------------------------------------------------------------------------
   V7 权限审计
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_PermissionAudit
AS
SELECT pa.AuditID,
       pa.AuditTime,
       pa.ActionType,
       pa.StaffID,
       ISNULL(st.StaffName, N'已删除员工') AS StaffName,
       pa.WarehouseID,
       ISNULL(w.WarehouseName, N'已删除仓库') AS WarehouseName,
       pa.OperatorNote
FROM dbo.PermissionAudit pa
         LEFT JOIN dbo.Staff st ON pa.StaffID = st.StaffID
         LEFT JOIN dbo.Warehouse w ON pa.WarehouseID = w.WarehouseID;
GO

/* ---------------------------------------------------------------------------
   V8 库位利用：哪个货位满了、哪个还空着
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_LocationUtilization
AS
SELECT l.LocationID,
       w.WarehouseName,
       z.ZoneCode,
       z.ZoneName,
       z.ZoneType,
       l.LocationCode,
       l.Capacity,
       l.IsLocked,
       ISNULL(SUM(s.Storing), 0) AS UsedQty,
       COUNT(s.StorageID)       AS UnitCount,
       CAST(CASE WHEN l.Capacity = 0 THEN 0
                 ELSE ISNULL(SUM(s.Storing), 0) * 100.0 / l.Capacity END AS DECIMAL(5, 2)) AS UsagePercent
FROM dbo.StorageLocation l
         INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
         INNER JOIN dbo.Warehouse w ON z.WarehouseID = w.WarehouseID
         LEFT JOIN dbo.Storage s ON s.LocationID = l.LocationID
GROUP BY l.LocationID, w.WarehouseName, z.ZoneCode, z.ZoneName, z.ZoneType,
         l.LocationCode, l.Capacity, l.IsLocked;
GO


/* ---------------------------------------------------------------------------
   V9 效期预警：临期、过期的批次
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_ExpiryAlert
AS
SELECT o.StorageID,
       o.ItemName,
       o.ItemType,
       o.WarehouseName,
       o.LocationCode,
       o.BatchNo,
       o.ExpiryDate,
       o.DaysToExpire,
       o.Storing,
       CASE WHEN o.DaysToExpire < 0 THEN N'已过期'
            WHEN o.DaysToExpire <= 30 THEN N'临期'
            WHEN o.DaysToExpire <= 90 THEN N'关注'
            ELSE N'正常' END AS ExpiryStatus
FROM dbo.vw_StockOverview o
WHERE o.ExpiryDate IS NOT NULL
  AND o.Storing > 0;
GO


/* ---------------------------------------------------------------------------
   V10 入库单进度：计划多少、已收多少、还剩多少
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_InboundOrderStatus
AS
SELECT o.OrderID,
       o.WarehouseID,
       o.OrderNo,
       o.OrderType,
       o.Status,
       w.WarehouseName,
       ISNULL(s.SupName, N'—') AS SupplierName,
       o.ExpectedDate,
       o.CreatedAt,
       o.CompletedAt,
       COUNT(l.LineID)                AS LineCount,
       ISNULL(SUM(l.PlannedQty), 0)   AS PlannedTotal,
       ISNULL(SUM(l.ReceivedQty), 0)  AS ReceivedTotal,
       ISNULL(SUM(l.PlannedQty), 0) - ISNULL(SUM(l.ReceivedQty), 0) AS PendingTotal,
       CAST(CASE WHEN ISNULL(SUM(l.PlannedQty), 0) = 0 THEN 0
                 ELSE SUM(l.ReceivedQty) * 100.0 / SUM(l.PlannedQty) END AS DECIMAL(5, 1)) AS Progress
FROM dbo.InboundOrder o
         INNER JOIN dbo.Warehouse w ON o.WarehouseID = w.WarehouseID
         LEFT JOIN dbo.Supplier s ON o.SupplierID = s.SupID
         LEFT JOIN dbo.InboundOrderLine l ON o.OrderID = l.OrderID
GROUP BY o.OrderID, o.WarehouseID, o.OrderNo, o.OrderType, o.Status, w.WarehouseName,
         s.SupName, o.ExpectedDate, o.CreatedAt, o.CompletedAt;
GO


/* ---------------------------------------------------------------------------
   V11 出库单进度
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_OutboundOrderStatus
AS
SELECT o.OrderID,
       o.WarehouseID,
       o.OrderNo,
       o.OrderType,
       o.Status,
       w.WarehouseName,
       ISNULL(c.CustomerName, N'—') AS CustomerName,
       o.RequiredDate,
       o.CreatedAt,
       o.ShippedAt,
       COUNT(l.LineID)               AS LineCount,
       ISNULL(SUM(l.PlannedQty), 0)  AS PlannedTotal,
       ISNULL(SUM(l.PickedQty), 0)   AS PickedTotal,
       ISNULL(SUM(l.PlannedQty), 0) - ISNULL(SUM(l.PickedQty), 0) AS PendingTotal,
       CAST(CASE WHEN ISNULL(SUM(l.PlannedQty), 0) = 0 THEN 0
                 ELSE SUM(l.PickedQty) * 100.0 / SUM(l.PlannedQty) END AS DECIMAL(5, 1)) AS Progress
FROM dbo.OutboundOrder o
         INNER JOIN dbo.Warehouse w ON o.WarehouseID = w.WarehouseID
         LEFT JOIN dbo.Customer c ON o.CustomerID = c.CustomerID
         LEFT JOIN dbo.OutboundOrderLine l ON o.OrderID = l.OrderID
GROUP BY o.OrderID, o.WarehouseID, o.OrderNo, o.OrderType, o.Status, w.WarehouseName,
         c.CustomerName, o.RequiredDate, o.CreatedAt, o.ShippedAt;
GO


/* ---------------------------------------------------------------------------
   V12 补货建议
   ---------------------------------------------------------------------------
   只对"这个仓库确实经营过这个物品"的组合给建议 —— 否则 11 个物品 × 5 个仓库
   会列出 55 行从未有货的噪音。
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_Replenishment
AS
SELECT i.ItemID,
       i.ItemName,
       i.ItemType,
       w.WarehouseID,
       w.WarehouseName,
       ISNULL(SUM(st.Storing), 0) AS OnHand,
       CAST(20 AS INT)            AS SafetyStock,
       CAST(20 - ISNULL(SUM(st.Storing), 0) AS INT) AS Shortage
FROM dbo.Item i
         CROSS JOIN dbo.Warehouse w
         LEFT JOIN dbo.Storage st ON st.ItemID = i.ItemID AND st.WarehouseID = w.WarehouseID
WHERE EXISTS (SELECT 1 FROM dbo.Record r
              WHERE r.ItemID = i.ItemID AND r.WarehouseID = w.WarehouseID)
GROUP BY i.ItemID, i.ItemName, i.ItemType, w.WarehouseID, w.WarehouseName
HAVING ISNULL(SUM(st.Storing), 0) < 20;
GO

/* ---------------------------------------------------------------------------
   V13 调拨单进度
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_TransferOrderStatus
AS
SELECT t.TransferID,
       t.TransferNo,
       t.Status,
       sw.WarehouseName AS SrcWarehouseName,
       dw.WarehouseName AS DstWarehouseName,
       ISNULL(ss.StaffName, N'—') AS SrcOperatorName,
       ISNULL(ds.StaffName, N'—') AS DstOperatorName,
       t.CreatedAt,
       t.ShippedAt,
       t.CompletedAt,
       COUNT(l.LineID)               AS LineCount,
       ISNULL(SUM(l.PlannedQty), 0)  AS PlannedTotal,
       ISNULL(SUM(l.ShippedQty), 0)  AS ShippedTotal,
       ISNULL(SUM(l.PlannedQty), 0) - ISNULL(SUM(l.ShippedQty), 0) AS PendingTotal,
       CAST(CASE WHEN ISNULL(SUM(l.PlannedQty), 0) = 0 THEN 0
                 ELSE SUM(l.ShippedQty) * 100.0 / SUM(l.PlannedQty) END AS DECIMAL(5, 1)) AS Progress
FROM dbo.TransferOrder t
         INNER JOIN dbo.Warehouse sw ON t.SrcWarehouseID = sw.WarehouseID
         INNER JOIN dbo.Warehouse dw ON t.DstWarehouseID = dw.WarehouseID
         LEFT JOIN dbo.Staff ss ON t.SrcOperatorID = ss.StaffID
         LEFT JOIN dbo.Staff ds ON t.DstOperatorID = ds.StaffID
         LEFT JOIN dbo.TransferOrderLine l ON t.TransferID = l.TransferID
GROUP BY t.TransferID, t.TransferNo, t.Status, sw.WarehouseName, dw.WarehouseName,
         ss.StaffName, ds.StaffName, t.CreatedAt, t.ShippedAt, t.CompletedAt;
GO
