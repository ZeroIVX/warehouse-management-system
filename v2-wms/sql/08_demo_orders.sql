/* ============================================================================
   08 单据演示数据（可选）
   ----------------------------------------------------------------------------
   生成三种状态的单据，用来演示作业流程：
     · 已完成   —— 全部收/发货完毕
     · 部分收货 —— 到货一半，剩余待收
     · 待收货   —— 刚建单，还没动
   以及一张进行中的盘点单。

   全部走存储过程，保证库存、审计、单据状态三者自洽。
   ============================================================================ */

USE WarehouseDB_V2;
GO

SET NOCOUNT ON;

DECLARE @wh INT, @sup INT, @staff INT, @cus INT;
DECLARE @order INT, @line1 INT, @line2 INT, @item1 INT, @item2 INT;
DECLARE @loc1 INT, @loc2 INT;
DECLARE @today VARCHAR(8) = FORMAT(GETDATE(), 'yyyyMMdd');

SELECT TOP 1 @wh = WarehouseID, @staff = sa.StaffID
FROM dbo.StaffAssignment sa
         INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
WHERE s.IsActive = 1 ORDER BY sa.WarehouseID;

SELECT TOP 1 @sup = SupID FROM dbo.Supplier ORDER BY SupID;
SELECT TOP 1 @cus = CustomerID FROM dbo.Customer ORDER BY CustomerID;

SELECT TOP 1 @loc1 = l.LocationID
FROM dbo.StorageLocation l
         INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
WHERE z.WarehouseID = @wh AND z.ZoneType = N'存储区' ORDER BY l.LocationCode;
SELECT TOP 1 @loc2 = l.LocationID
FROM dbo.StorageLocation l
         INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
WHERE z.WarehouseID = @wh AND z.ZoneType = N'存储区' ORDER BY l.LocationCode DESC;

SELECT TOP 1 @item1 = ItemID FROM dbo.Item ORDER BY ItemID;
SELECT TOP 1 @item2 = ItemID FROM dbo.Item ORDER BY ItemID DESC;

/* ---------------- 入库单 1：全部收货，已完成 ---------------- */
INSERT INTO dbo.InboundOrder (OrderNo, OrderType, WarehouseID, SupplierID, Status, ExpectedDate, Remark)
VALUES (CONCAT('PO', @today, '001'), N'采购入库', @wh, @sup, N'待收货',
        DATEADD(day, -10, CAST(GETDATE() AS DATE)), N'一月常规补货');

SET @order = CAST(SCOPE_IDENTITY() AS INT);

INSERT INTO dbo.InboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty, LocationID, BatchNo, ExpiryDate)
VALUES (@order, 1, @item1, 80, @loc1, CONCAT('B', @today, '-A01'), DATEADD(day, 240, CAST(GETDATE() AS DATE)));
SET @line1 = CAST(SCOPE_IDENTITY() AS INT);

INSERT INTO dbo.InboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty, LocationID, BatchNo)
VALUES (@order, 2, @item2, 40, @loc2, CONCAT('B', @today, '-A02'));
SET @line2 = CAST(SCOPE_IDENTITY() AS INT);

EXEC dbo.sp_ReceiveInbound @LineID = @line1, @Qty = 80, @OperatorID = @staff;
EXEC dbo.sp_ReceiveInbound @LineID = @line2, @Qty = 40, @OperatorID = @staff;
GO

/* ---------------- 入库单 2：部分收货 ---------------- */
DECLARE @wh2 INT, @staff2 INT, @sup2 INT, @order2 INT, @line21 INT;
DECLARE @loc21 INT, @item21 INT;
DECLARE @today2 VARCHAR(8) = FORMAT(GETDATE(), 'yyyyMMdd');

SELECT TOP 1 @wh2 = WarehouseID, @staff2 = sa.StaffID
FROM dbo.StaffAssignment sa INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
WHERE s.IsActive = 1 ORDER BY sa.WarehouseID DESC;
SELECT TOP 1 @sup2 = SupID FROM dbo.Supplier ORDER BY SupID DESC;
SELECT TOP 1 @loc21 = l.LocationID
FROM dbo.StorageLocation l INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
WHERE z.WarehouseID = @wh2 AND z.ZoneType = N'存储区' ORDER BY l.LocationCode;
SELECT TOP 1 @item21 = ItemID FROM dbo.Item ORDER BY ItemID;

INSERT INTO dbo.InboundOrder (OrderNo, OrderType, WarehouseID, SupplierID, Status, ExpectedDate, Remark)
VALUES (CONCAT('PO', @today2, '002'), N'采购入库', @wh2, @sup2, N'待收货',
        DATEADD(day, 2, CAST(GETDATE() AS DATE)), N'分两批到货，首批已到');
SET @order2 = CAST(SCOPE_IDENTITY() AS INT);

INSERT INTO dbo.InboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty, LocationID, BatchNo)
VALUES (@order2, 1, @item21, 120, @loc21, CONCAT('B', @today2, '-B01'));
SET @line21 = CAST(SCOPE_IDENTITY() AS INT);

EXEC dbo.sp_ReceiveInbound @LineID = @line21, @Qty = 70, @OperatorID = @staff2;
GO

/* ---------------- 入库单 3：待收货（刚建单） ---------------- */
INSERT INTO dbo.InboundOrder (OrderNo, OrderType, WarehouseID, SupplierID, Status, ExpectedDate, Remark)
SELECT CONCAT('PO', FORMAT(GETDATE(), 'yyyyMMdd'), '003'), N'采购入库',
       (SELECT TOP 1 WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID),
       (SELECT TOP 1 SupID FROM dbo.Supplier ORDER BY SupID),
       N'待收货', DATEADD(day, 5, CAST(GETDATE() AS DATE)), N'下周一到货';

INSERT INTO dbo.InboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty)
SELECT SCOPE_IDENTITY(), 1, (SELECT TOP 1 ItemID FROM dbo.Item ORDER BY ItemID), 60;
GO

/* ---------------- 出库单 1：已发货完成 ---------------- */
DECLARE @owh INT, @ostaff INT, @ocus INT, @oorder INT, @oline INT, @oitem INT;
DECLARE @oday VARCHAR(8) = FORMAT(GETDATE(), 'yyyyMMdd');

SELECT TOP 1 @owh = WarehouseID, @ostaff = sa.StaffID
FROM dbo.StaffAssignment sa INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
WHERE s.IsActive = 1 ORDER BY sa.WarehouseID;
SELECT TOP 1 @ocus = CustomerID FROM dbo.Customer ORDER BY CustomerID;
SELECT TOP 1 @oitem = ItemID FROM dbo.Item ORDER BY ItemID;

INSERT INTO dbo.OutboundOrder (OrderNo, OrderType, WarehouseID, CustomerID, Status, RequiredDate, Remark)
VALUES (CONCAT('SO', @oday, '001'), N'销售出库', @owh, @ocus, N'待拣货',
        DATEADD(day, -3, CAST(GETDATE() AS DATE)), N'客户订单，已发出');
SET @oorder = CAST(SCOPE_IDENTITY() AS INT);

INSERT INTO dbo.OutboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty)
VALUES (@oorder, 1, @oitem, 20);
SET @oline = CAST(SCOPE_IDENTITY() AS INT);

EXEC dbo.sp_ShipOutbound @LineID = @oline, @Qty = 20, @OperatorID = @ostaff;
GO

/* ---------------- 出库单 2：待拣货（刚建单） ---------------- */
INSERT INTO dbo.OutboundOrder (OrderNo, OrderType, WarehouseID, CustomerID, Status, RequiredDate, Remark)
SELECT CONCAT('SO', FORMAT(GETDATE(), 'yyyyMMdd'), '002'), N'销售出库',
       (SELECT TOP 1 WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID),
       (SELECT TOP 1 CustomerID FROM dbo.Customer ORDER BY CustomerID DESC),
       N'待拣货', DATEADD(day, 1, CAST(GETDATE() AS DATE)), N'明日发货';

INSERT INTO dbo.OutboundOrderLine (OrderID, LineNumber, ItemID, PlannedQty)
SELECT SCOPE_IDENTITY(), 1, (SELECT TOP 1 ItemID FROM dbo.Item ORDER BY ItemID DESC), 15;
GO

/* ---------------- 盘点单：进行中，留待演示 ---------------- */
DECLARE @swh INT, @szone INT, @sno VARCHAR(20);

SELECT TOP 1 @swh = WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID;
SELECT TOP 1 @szone = z.ZoneID FROM dbo.WarehouseZone z
WHERE z.WarehouseID = @swh AND z.ZoneType = N'存储区';
SET @sno = CONCAT('ST', FORMAT(GETDATE(), 'yyyyMMdd'), '001');

INSERT INTO dbo.StocktakeOrder (StocktakeNo, WarehouseID, ZoneID, Status, StartedAt, Remark)
VALUES (@sno, @swh, @szone, N'盘点中', GETDATE(), N'月度循环盘点');

INSERT INTO dbo.StocktakeLine (StocktakeID, StorageID, ItemID, LocationID, BatchNo, BookQty, CountedQty)
SELECT SCOPE_IDENTITY(), s.StorageID, s.ItemID, s.LocationID, s.BatchNo, s.Storing, NULL
FROM dbo.Storage s
         LEFT JOIN dbo.StorageLocation l ON s.LocationID = l.LocationID
         LEFT JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
WHERE s.WarehouseID = @swh AND s.Storing > 0 AND z.ZoneID = @szone;
GO

/* ---------------- 调拨单 1：已全部发货 ---------------- */
DECLARE @tsrc INT, @tdst INT, @tsop INT, @tdop INT, @titem INT, @torder INT, @tline INT;
DECLARE @tno VARCHAR(20) = CONCAT('TR', FORMAT(GETDATE(), 'yyyyMMdd'), '001');

SELECT TOP 1 @tsrc = WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID;
SELECT TOP 1 @tdst = WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID DESC;
SELECT TOP 1 @tsop = StaffID FROM dbo.StaffAssignment
WHERE WarehouseID = @tsrc AND StaffID IN (SELECT StaffID FROM dbo.Staff WHERE IsActive = 1);
SELECT TOP 1 @tdop = StaffID FROM dbo.StaffAssignment
WHERE WarehouseID = @tdst AND StaffID IN (SELECT StaffID FROM dbo.Staff WHERE IsActive = 1);
SELECT TOP 1 @titem = ItemID FROM dbo.Item ORDER BY ItemID;

INSERT INTO dbo.TransferOrder (TransferNo, SrcWarehouseID, DstWarehouseID,
                               SrcOperatorID, DstOperatorID, Status, Remark)
VALUES (@tno, @tsrc, @tdst, @tsop, @tdop, N'待发货', N'跨仓调剂库存');

SET @torder = CAST(SCOPE_IDENTITY() AS INT);

INSERT INTO dbo.TransferOrderLine (TransferID, LineNumber, ItemID, PlannedQty)
VALUES (@torder, 1, @titem, 10);
SET @tline = CAST(SCOPE_IDENTITY() AS INT);

BEGIN TRY
    DECLARE @g UNIQUEIDENTIFIER;
    EXEC dbo.sp_ShipTransfer @LineID = @tline, @Qty = 10, @TransferGroupID = @g OUTPUT;
END TRY
BEGIN CATCH
    -- 源仓无货就跳过，不影响其它演示数据
    DELETE FROM dbo.TransferOrder WHERE TransferID = @torder;
END CATCH
GO

/* ---------------- 调拨单 2：待发货（留作演示） ---------------- */
INSERT INTO dbo.TransferOrder (TransferNo, SrcWarehouseID, DstWarehouseID,
                               SrcOperatorID, DstOperatorID, Status, Remark)
SELECT CONCAT('TR', FORMAT(GETDATE(), 'yyyyMMdd'), '002'),
       (SELECT TOP 1 WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID DESC),
       (SELECT TOP 1 WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID),
       (SELECT TOP 1 sa.StaffID FROM dbo.StaffAssignment sa
        WHERE sa.WarehouseID = (SELECT TOP 1 WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID DESC)),
       (SELECT TOP 1 sa.StaffID FROM dbo.StaffAssignment sa
        WHERE sa.WarehouseID = (SELECT TOP 1 WarehouseID FROM dbo.Warehouse ORDER BY WarehouseID)),
       N'待发货', N'下周一安排发运';

INSERT INTO dbo.TransferOrderLine (TransferID, LineNumber, ItemID, PlannedQty)
SELECT SCOPE_IDENTITY(), 1, (SELECT TOP 1 ItemID FROM dbo.Item ORDER BY ItemID DESC), 8;
GO

SELECT (SELECT COUNT(*) FROM dbo.InboundOrder)  AS [入库单],
       (SELECT COUNT(*) FROM dbo.OutboundOrder) AS [出库单],
       (SELECT COUNT(*) FROM dbo.StocktakeOrder) AS [盘点单],
       (SELECT COUNT(*) FROM dbo.TransferOrder) AS [调拨单],
       (SELECT COUNT(*) FROM dbo.Record)        AS [流水总数];
GO
