/* ============================================================================
   04 存储过程 —— 业务事务的边界都放这里
   ----------------------------------------------------------------------------
   为什么把出入库做成存储过程，而不是在 Python 里拼 INSERT：

   1. 原子性。一次出库 = 校验权限 + 校验库存 + 写流水 + 触发器扣库存。
      放在应用里，任何一步失败都靠应用回滚，进程被 kill 就留下半截数据；
      放在存储过程里，事务边界由数据库守护。

   2. 并发。原版的库存校验发生在 SELECT，扣减发生在触发器，两者之间没有锁，
      两个会话同时出库会超卖。这里用 UPDLOCK + HOLDLOCK 把"读-判-写"
      包成一个可串行化的临界区。

   3. 规则唯一。出入库规则只有一份实现，Python / 未来的 REST API / 其他客户端
      都调用同一个过程，不会出现"某条路径忘了校验"。

   错误码约定（应用层按号映射成友好提示）：
     50001 物品不存在        50002 仓库不存在
     50003 员工无该仓库权限  50004 库存不足
     50005 库容不足          50006 参数不合法
   ============================================================================ */

USE WarehouseDB_V2;
GO

/* ---------------------------------------------------------------------------
   P1 出入库统一入口
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_PostOperation
    @ItemID        INT,
    @WarehouseID   INT,
    @SupplierID    INT = NULL,
    @OperatorID    INT,
    @OperationType NVARCHAR(10),      -- 入库 / 出库
    @Quantity      INT,
    @Remarks       NVARCHAR(200) = NULL,
    @RecordID      INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity IS NULL OR @Quantity <= 0
        THROW 50006, N'数量必须大于 0', 1;
    IF @OperationType NOT IN (N'入库', N'出库')
        THROW 50006, N'操作类型只能是入库或出库', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. 实体存在性
        IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE ItemID = @ItemID)
            THROW 50001, N'物品不存在', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Warehouse WHERE WarehouseID = @WarehouseID)
            THROW 50002, N'仓库不存在', 1;

        -- 2. 操作人必须是在职且被授权该仓库
        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
                       WHERE sa.StaffID = @OperatorID
                         AND sa.WarehouseID = @WarehouseID
                         AND s.IsActive = 1)
            THROW 50003, N'操作人无权操作该仓库（未授权或已离职）', 1;

        IF @SupplierID IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Supplier WHERE SupID = @SupplierID)
            THROW 50006, N'供应商不存在', 1;

        -- 3. 前置校验（带锁，避免校验与扣减之间被其他会话插队）
        IF @OperationType = N'出库'
        BEGIN
            DECLARE @Available INT;

            SELECT @Available = ISNULL(SUM(Storing), 0)
            FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
            WHERE ItemID = @ItemID
              AND WarehouseID = @WarehouseID
              AND (@SupplierID IS NULL OR ISNULL(SupplierID, 0) = ISNULL(@SupplierID, 0));

            IF @Available < @Quantity
                THROW 50004, N'库存不足，当前可用量不足本次出库数量', 1;
        END
        ELSE
        BEGIN
            DECLARE @Free INT;

            SELECT @Free = WarehouseSize - WarehouseUsage
            FROM dbo.Warehouse WITH (UPDLOCK, HOLDLOCK)
            WHERE WarehouseID = @WarehouseID;

            IF @Free < @Quantity
                THROW 50005, N'库容不足，该仓库剩余空间放不下本次入库', 1;
        END

        -- 4. 落流水。库存的实际增减由触发器 TR_Record_StockSync 完成，
        --    保证"只要有一条流水，库存就一定同步"这一不变式。
        INSERT INTO dbo.Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                OperationType, OperationQuantity, Remarks)
        VALUES (@ItemID, @WarehouseID, @SupplierID, @OperatorID,
                @OperationType, @Quantity, @Remarks);

        SET @RecordID = CAST(SCOPE_IDENTITY() AS INT);

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------------
   P2 跨仓库调拨 —— 两条流水 + 一次事务，要么都成、要么都不成
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_TransferStock
    @ItemID          INT,
    @SrcWarehouseID  INT,
    @DstWarehouseID  INT,
    @SupplierID      INT = NULL,
    @Quantity        INT,
    @OutOperatorID   INT,             -- 发货人，需源仓库权限
    @InOperatorID    INT,             -- 收货人，需目标仓库权限
    @Remarks         NVARCHAR(200) = NULL,
    @TransferGroupID UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity IS NULL OR @Quantity <= 0
        THROW 50006, N'调拨数量必须大于 0', 1;
    IF @SrcWarehouseID = @DstWarehouseID
        THROW 50006, N'源仓库与目标仓库不能相同', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE ItemID = @ItemID)
            THROW 50001, N'物品不存在', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Warehouse WHERE WarehouseID = @SrcWarehouseID)
            THROW 50002, N'源仓库不存在', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Warehouse WHERE WarehouseID = @DstWarehouseID)
            THROW 50002, N'目标仓库不存在', 1;

        -- 双向权限校验：发货人管源库，收货人管目标库
        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
                       WHERE sa.StaffID = @OutOperatorID
                         AND sa.WarehouseID = @SrcWarehouseID
                         AND s.IsActive = 1)
            THROW 50003, N'发货人无权操作源仓库', 1;
        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
                       WHERE sa.StaffID = @InOperatorID
                         AND sa.WarehouseID = @DstWarehouseID
                         AND s.IsActive = 1)
            THROW 50003, N'收货人无权操作目标仓库', 1;

        -- 源库存加锁校验
        DECLARE @Available INT;
        SELECT @Available = ISNULL(SUM(Storing), 0)
        FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
        WHERE ItemID = @ItemID
          AND WarehouseID = @SrcWarehouseID
          AND (@SupplierID IS NULL OR ISNULL(SupplierID, 0) = ISNULL(@SupplierID, 0));

        IF @Available < @Quantity
            THROW 50004, N'源仓库库存不足', 1;

        -- 目标库容校验
        DECLARE @Free INT;
        SELECT @Free = WarehouseSize - WarehouseUsage
        FROM dbo.Warehouse WITH (UPDLOCK, HOLDLOCK)
        WHERE WarehouseID = @DstWarehouseID;

        IF @Free < @Quantity
            THROW 50005, N'目标仓库剩余库容不足', 1;

        SET @TransferGroupID = NEWID();

        INSERT INTO dbo.Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                OperationType, OperationQuantity, Remarks, TransferGroupID)
        VALUES (@ItemID, @SrcWarehouseID, @SupplierID, @OutOperatorID,
                N'调拨出', @Quantity, ISNULL(@Remarks, N'调拨-发货'), @TransferGroupID);

        INSERT INTO dbo.Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                OperationType, OperationQuantity, Remarks, TransferGroupID)
        VALUES (@ItemID, @DstWarehouseID, @SupplierID, @InOperatorID,
                N'调拨入', @Quantity, ISNULL(@Remarks, N'调拨-收货'), @TransferGroupID);

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------------
   P3 重算仓库使用量 —— 数据修复/巡检工具
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_RecalcWarehouseUsage
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    UPDATE w
    SET w.WarehouseUsage = ISNULL(x.Total, 0)
    FROM dbo.Warehouse w
             LEFT JOIN (SELECT WarehouseID, SUM(Storing) AS Total
                        FROM dbo.Storage
                        GROUP BY WarehouseID) x ON w.WarehouseID = x.WarehouseID;

    COMMIT TRANSACTION;

    SELECT WarehouseName, WarehouseSize, WarehouseUsage,
           CAST(WarehouseUsage * 100.0 / NULLIF(WarehouseSize, 0) AS DECIMAL(5, 2)) AS UsagePercent
    FROM dbo.Warehouse
    ORDER BY WarehouseID;
END;
GO


/* ---------------------------------------------------------------------------
   P4 收货上架 —— 按入库单行收货
   ---------------------------------------------------------------------------
   与 sp_PostOperation 的区别：这里必须挂在一张入库单的某一行上，
   收完要回写行收货量、推进单头状态，并记录批次与货位。
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ReceiveInbound
    @LineID         INT,
    @Qty            INT,
    @LocationID     INT = NULL,
    @BatchNo        NVARCHAR(40) = NULL,
    @ProductionDate DATE = NULL,
    @ExpiryDate     DATE = NULL,
    @OperatorID     INT,
    @RecordID       INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Qty IS NULL OR @Qty <= 0
        THROW 50006, N'收货数量必须大于 0', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrderID INT, @ItemID INT, @Planned INT, @Received INT,
                @WarehouseID INT, @SupplierID INT, @OrderStatus NVARCHAR(10),
                @Remain INT, @Free INT;

        SELECT @OrderID = l.OrderID, @ItemID = l.ItemID, @Planned = l.PlannedQty,
               @Received = l.ReceivedQty,
               @WarehouseID = o.WarehouseID, @SupplierID = o.SupplierID,
               @OrderStatus = o.Status
        FROM dbo.InboundOrderLine l WITH (UPDLOCK, HOLDLOCK)
                 INNER JOIN dbo.InboundOrder o ON l.OrderID = o.OrderID
        WHERE l.LineID = @LineID;

        IF @OrderID IS NULL
            THROW 50001, N'入库单行不存在', 1;
        IF @OrderStatus IN (N'已完成', N'已取消')
            THROW 50006, N'该入库单已完成或已取消，不能再收货', 1;

        SET @Remain = @Planned - @Received;
        IF @Qty > @Remain
            THROW 50006, N'收货数量超过该行剩余待收数量', 1;

        -- 经办人必须是该仓库的在职员工
        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff st ON sa.StaffID = st.StaffID
                       WHERE sa.StaffID = @OperatorID
                         AND sa.WarehouseID = @WarehouseID
                         AND st.IsActive = 1)
            THROW 50003, N'操作人无权操作该仓库', 1;

        -- 库位必须属于本仓库
        IF @LocationID IS NOT NULL
            AND NOT EXISTS (SELECT 1
                            FROM dbo.StorageLocation l
                                     INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
                            WHERE l.LocationID = @LocationID AND z.WarehouseID = @WarehouseID)
            THROW 50006, N'该库位不属于本仓库', 1;

        -- 库容校验
        SELECT @Free = WarehouseSize - WarehouseUsage
        FROM dbo.Warehouse WITH (UPDLOCK, HOLDLOCK)
        WHERE WarehouseID = @WarehouseID;

        IF @Free < @Qty
            THROW 50005, N'库容不足，该仓库剩余空间放不下本次收货', 1;

        INSERT INTO dbo.Record (ItemID, WarehouseID, SupplierID, BatchNo, LocationID, OperatorID,
                                OperationType, OperationQuantity, Remarks,
                                SourceType, SourceOrderID, SourceLineID)
        VALUES (@ItemID, @WarehouseID, @SupplierID, @BatchNo, @LocationID, @OperatorID,
                N'入库', @Qty, N'入库单收货',
                N'入库单', @OrderID, @LineID);

        SET @RecordID = CAST(SCOPE_IDENTITY() AS INT);

        UPDATE dbo.InboundOrderLine
        SET ReceivedQty = ReceivedQty + @Qty,
            LocationID  = ISNULL(LocationID, @LocationID),
            BatchNo     = ISNULL(BatchNo, @BatchNo),
            ProductionDate = ISNULL(ProductionDate, @ProductionDate),
            ExpiryDate  = ISNULL(ExpiryDate, @ExpiryDate)
        WHERE LineID = @LineID;

        -- 推单头状态：全收完则完成，否则部分收货
        IF NOT EXISTS (SELECT 1 FROM dbo.InboundOrderLine
                       WHERE OrderID = @OrderID AND ReceivedQty < PlannedQty)
            UPDATE dbo.InboundOrder
            SET Status = N'已完成', CompletedAt = GETDATE()
            WHERE OrderID = @OrderID;
        ELSE
            UPDATE dbo.InboundOrder SET Status = N'部分收货'
            WHERE OrderID = @OrderID AND Status IN (N'草稿', N'待收货');

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------------
   P5 拣货发货 —— 按出库单行发货
   ---------------------------------------------------------------------------
   库存足够时按 FEFO 自动选批次，不需要人工指定扣哪一批。
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ShipOutbound
    @LineID     INT,
    @Qty        INT,
    @OperatorID INT,
    @RecordID   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Qty IS NULL OR @Qty <= 0
        THROW 50006, N'发货数量必须大于 0', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrderID INT, @ItemID INT, @Planned INT, @Picked INT,
                @WarehouseID INT, @SupplierID INT, @OrderStatus NVARCHAR(10),
                @Remain INT, @Available INT;

        SELECT @OrderID = l.OrderID, @ItemID = l.ItemID, @Planned = l.PlannedQty,
               @Picked = l.PickedQty,
               @WarehouseID = o.WarehouseID, @SupplierID = o.CustomerID,
               @OrderStatus = o.Status
        FROM dbo.OutboundOrderLine l WITH (UPDLOCK, HOLDLOCK)
                 INNER JOIN dbo.OutboundOrder o ON l.OrderID = o.OrderID
        WHERE l.LineID = @LineID;

        IF @OrderID IS NULL
            THROW 50001, N'出库单行不存在', 1;
        IF @OrderStatus IN (N'已完成', N'已取消')
            THROW 50006, N'该出库单已完成或已取消，不能再发货', 1;

        SET @Remain = @Planned - @Picked;
        IF @Qty > @Remain
            THROW 50006, N'发货数量超过该行剩余待发数量', 1;

        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff st ON sa.StaffID = st.StaffID
                       WHERE sa.StaffID = @OperatorID
                         AND sa.WarehouseID = @WarehouseID
                         AND st.IsActive = 1)
            THROW 50003, N'操作人无权操作该仓库', 1;

        SELECT @Available = ISNULL(SUM(Storing), 0)
        FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
        WHERE ItemID = @ItemID AND WarehouseID = @WarehouseID;

        IF @Available < @Qty
            THROW 50004, N'库存不足，无法满足本次发货', 1;

        INSERT INTO dbo.Record (ItemID, WarehouseID, OperatorID,
                                OperationType, OperationQuantity, Remarks,
                                SourceType, SourceOrderID, SourceLineID)
        VALUES (@ItemID, @WarehouseID, @OperatorID,
                N'出库', @Qty, N'出库单发货',
                N'出库单', @OrderID, @LineID);

        SET @RecordID = CAST(SCOPE_IDENTITY() AS INT);

        UPDATE dbo.OutboundOrderLine
        SET PickedQty = PickedQty + @Qty
        WHERE LineID = @LineID;

        IF NOT EXISTS (SELECT 1 FROM dbo.OutboundOrderLine
                       WHERE OrderID = @OrderID AND PickedQty < PlannedQty)
            UPDATE dbo.OutboundOrder
            SET Status = N'已完成', ShippedAt = GETDATE()
            WHERE OrderID = @OrderID;
        ELSE
            UPDATE dbo.OutboundOrder SET Status = N'拣货中'
            WHERE OrderID = @OrderID AND Status IN (N'草稿', N'待拣货');

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------------
   P6 盘点结案 —— 把实盘差异转成盘盈/盘亏流水
   ---------------------------------------------------------------------------
   未录入实盘数的行视为"未盘"，不产生调整，避免把漏盘当成盘亏。
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CompleteStocktake
    @StocktakeID INT,
    @OperatorID  INT,
    @Adjusted    INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 调用方传进来的 OUTPUT 变量通常是 NULL，不先置 0 会让累加结果一直是 NULL
    SET @Adjusted = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @WarehouseID INT, @Status NVARCHAR(10);

        SELECT @WarehouseID = WarehouseID, @Status = Status
        FROM dbo.StocktakeOrder WITH (UPDLOCK, HOLDLOCK)
        WHERE StocktakeID = @StocktakeID;

        IF @WarehouseID IS NULL
            THROW 50001, N'盘点单不存在', 1;
        IF @Status = N'已完成'
            THROW 50006, N'该盘点单已结案', 1;

        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff st ON sa.StaffID = st.StaffID
                       WHERE sa.StaffID = @OperatorID
                         AND sa.WarehouseID = @WarehouseID
                         AND st.IsActive = 1)
            THROW 50003, N'操作人无权操作该仓库', 1;

        DECLARE @LineID INT, @StorageID INT, @ItemID INT, @LocationID INT,
                @BatchNo NVARCHAR(40), @Book INT, @Counted INT, @Diff INT, @Type NVARCHAR(10);

        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT LineID, StorageID, ItemID, LocationID, BatchNo, BookQty, CountedQty
            FROM dbo.StocktakeLine
            WHERE StocktakeID = @StocktakeID AND CountedQty IS NOT NULL;

        OPEN cur;
        FETCH NEXT FROM cur INTO @LineID, @StorageID, @ItemID, @LocationID,
                                 @BatchNo, @Book, @Counted;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @Diff = @Counted - @Book;

            IF @Diff <> 0
            BEGIN
                SET @Type = CASE WHEN @Diff > 0 THEN N'盘盈' ELSE N'盘亏' END;

                INSERT INTO dbo.Record (ItemID, WarehouseID, BatchNo, LocationID, OperatorID,
                                        OperationType, OperationQuantity, Remarks,
                                        SourceType, SourceOrderID, SourceLineID)
                VALUES (@ItemID, @WarehouseID, @BatchNo, @LocationID, @OperatorID,
                        @Type, ABS(@Diff), N'盘点差异调整',
                        N'盘点单', @StocktakeID, @LineID);

                SET @Adjusted = @Adjusted + 1;
            END

            FETCH NEXT FROM cur INTO @LineID, @StorageID, @ItemID, @LocationID,
                                     @BatchNo, @Book, @Counted;
        END

        CLOSE cur;
        DEALLOCATE cur;

        UPDATE dbo.StocktakeOrder
        SET Status = N'已完成', CompletedAt = GETDATE()
        WHERE StocktakeID = @StocktakeID;

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------------
   P7 调拨单发货 —— 一次生成两条配对流水
   ---------------------------------------------------------------------------
   与 P2（sp_TransferStock，无单据的裸调拨）的区别：
   这里必须挂在一张调拨单的某一行上，发货后回写行数量、推进单头状态，
   流水上带 SourceType=N'调拨单' 与单据号，事后可追溯。
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ShipTransfer
    @LineID          INT,
    @Qty             INT,
    @TransferGroupID UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Qty IS NULL OR @Qty <= 0
        THROW 50006, N'调拨数量必须大于 0', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @TransferID INT, @ItemID INT, @SupplierID INT, @Planned INT, @Shipped INT,
                @SrcWh INT, @DstWh INT, @SrcOp INT, @DstOp INT, @Status NVARCHAR(10),
                @Remain INT, @Avail INT, @Free INT;

        SELECT @TransferID = l.TransferID, @ItemID = l.ItemID, @SupplierID = l.SupplierID,
               @Planned = l.PlannedQty, @Shipped = l.ShippedQty,
               @SrcWh = t.SrcWarehouseID, @DstWh = t.DstWarehouseID,
               @SrcOp = t.SrcOperatorID, @DstOp = t.DstOperatorID, @Status = t.Status
        FROM dbo.TransferOrderLine l WITH (UPDLOCK, HOLDLOCK)
                 INNER JOIN dbo.TransferOrder t ON l.TransferID = t.TransferID
        WHERE l.LineID = @LineID;

        IF @TransferID IS NULL
            THROW 50001, N'调拨单行不存在', 1;
        IF @Status IN (N'已完成', N'已取消')
            THROW 50006, N'该调拨单已完成或已取消，不能再发货', 1;

        SET @Remain = @Planned - @Shipped;
        IF @Qty > @Remain
            THROW 50006, N'发货数量超过该行剩余待发数量', 1;

        -- 双向权限：发货人管源库，收货人管目标库
        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff st ON sa.StaffID = st.StaffID
                       WHERE sa.StaffID = @SrcOp AND sa.WarehouseID = @SrcWh AND st.IsActive = 1)
            THROW 50003, N'发货人无权操作源仓库', 1;
        IF NOT EXISTS (SELECT 1
                       FROM dbo.StaffAssignment sa
                                INNER JOIN dbo.Staff st ON sa.StaffID = st.StaffID
                       WHERE sa.StaffID = @DstOp AND sa.WarehouseID = @DstWh AND st.IsActive = 1)
            THROW 50003, N'收货人无权操作目标仓库', 1;

        SELECT @Avail = ISNULL(SUM(Storing), 0)
        FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
        WHERE ItemID = @ItemID AND WarehouseID = @SrcWh
          AND (@SupplierID IS NULL OR ISNULL(SupplierID, 0) = ISNULL(@SupplierID, 0));

        IF @Avail < @Qty
            THROW 50004, N'源仓库库存不足', 1;

        SELECT @Free = WarehouseSize - WarehouseUsage
        FROM dbo.Warehouse WITH (UPDLOCK, HOLDLOCK)
        WHERE WarehouseID = @DstWh;

        IF @Free < @Qty
            THROW 50005, N'目标仓库剩余库容不足', 1;

        SET @TransferGroupID = NEWID();

        INSERT INTO dbo.Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                OperationType, OperationQuantity, Remarks, TransferGroupID,
                                SourceType, SourceOrderID, SourceLineID)
        VALUES (@ItemID, @SrcWh, @SupplierID, @SrcOp,
                N'调拨出', @Qty, N'调拨单发货', @TransferGroupID,
                N'调拨单', @TransferID, @LineID);

        INSERT INTO dbo.Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                OperationType, OperationQuantity, Remarks, TransferGroupID,
                                SourceType, SourceOrderID, SourceLineID)
        VALUES (@ItemID, @DstWh, @SupplierID, @DstOp,
                N'调拨入', @Qty, N'调拨单收货', @TransferGroupID,
                N'调拨单', @TransferID, @LineID);

        UPDATE dbo.TransferOrderLine
        SET ShippedQty = ShippedQty + @Qty
        WHERE LineID = @LineID;

        IF NOT EXISTS (SELECT 1 FROM dbo.TransferOrderLine
                       WHERE TransferID = @TransferID AND ShippedQty < PlannedQty)
            UPDATE dbo.TransferOrder
            SET Status = N'已完成', CompletedAt = GETDATE(),
                ShippedAt = ISNULL(ShippedAt, GETDATE())
            WHERE TransferID = @TransferID;
        ELSE
            UPDATE dbo.TransferOrder
            SET Status = N'部分发货', ShippedAt = ISNULL(ShippedAt, GETDATE())
            WHERE TransferID = @TransferID AND Status = N'待发货';

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
