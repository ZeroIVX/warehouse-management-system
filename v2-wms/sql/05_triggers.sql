/* ============================================================================
   05 触发器 —— 把"不能靠自觉"的不变式钉在数据库里
   ----------------------------------------------------------------------------
   三个触发器各守一条不变式：

     T1 TR_Record_StockSync   有流水就必须有库存变动
     T2 TR_Storage_SyncUsage  仓库使用量恒等于该仓库库存之和
     T3 TR_Assignment_Audit   权限的任何增删都留痕

   T1 这一版的三处升级（对应现实仓储的作业要求）：
     [E1] 库存单元从「物品+仓库+供应商」扩到「+批次+货位」。
          同一供应商的两批货必须分开记账，否则 FEFO 失效。
     [E2] 出库策略由 FIFO 改为 FEFO（First Expired First Out）。
          食品、医药、化工的效期是硬约束，只按入库先后出会让临期货烂在库里。
          没有效期的批次排在最后，再按批次先后。
     [E3] 每一条批次级变动都记进 StockAudit，带上批次号与货位，
          出问题时能一路追到"是哪一箱在哪一格"。
   ============================================================================ */

USE WarehouseDB_V2;
GO

/* ---------------------------------------------------------------------------
   T1 流水 -> 库存同步
   --------------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_Record_StockSync
    ON dbo.Record
    AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;

    DECLARE @RecordID    INT,
            @ItemID      INT,
            @WarehouseID INT,
            @SupplierID  INT,
            @BatchNo     NVARCHAR(40),
            @LocationID  INT,
            @OperatorID  INT,
            @OpType      NVARCHAR(10),
            @Qty         INT,
            @IsInbound   BIT;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.RecordID, i.ItemID, i.WarehouseID, i.SupplierID, i.BatchNo,
               i.LocationID, i.OperatorID, i.OperationType, i.OperationQuantity
        FROM inserted i
        ORDER BY i.RecordID;

    OPEN cur;
    FETCH NEXT FROM cur INTO @RecordID, @ItemID, @WarehouseID, @SupplierID, @BatchNo,
                             @LocationID, @OperatorID, @OpType, @Qty;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- 盘盈也是加库存，盘亏与报损都是减库存
        SET @IsInbound = CASE WHEN @OpType IN (N'入库', N'调拨入', N'盘盈') THEN 1 ELSE 0 END;

        IF @IsInbound = 1
        BEGIN
            /* --- 入库：五元组（物品/仓库/供应商/批次/货位）相同则合并，否则新建库存单元 --- */
            DECLARE @ExistSID INT, @Before INT, @After INT;

            SELECT @ExistSID = StorageID, @Before = Storing
            FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
            WHERE ItemID = @ItemID
              AND WarehouseID = @WarehouseID
              AND ISNULL(SupplierID, 0) = ISNULL(@SupplierID, 0)
              AND ISNULL(BatchNo, N'') = ISNULL(@BatchNo, N'')
              AND ISNULL(LocationID, 0) = ISNULL(@LocationID, 0);

            IF @ExistSID IS NULL
            BEGIN
                SET @Before = 0;
                SET @After = @Qty;

                INSERT INTO dbo.Storage (ItemID, WarehouseID, SupplierID, BatchNo,
                                         LocationID, Storing, LastUpdate)
                VALUES (@ItemID, @WarehouseID, @SupplierID, @BatchNo,
                        @LocationID, @Qty, GETDATE());
            END
            ELSE
            BEGIN
                SET @After = @Before + @Qty;

                UPDATE dbo.Storage
                SET Storing = @After, LastUpdate = GETDATE()
                WHERE StorageID = @ExistSID;
            END

            INSERT INTO dbo.StockAudit (RecordID, ItemID, WarehouseID, SupplierID, BatchNo,
                                        LocationID, ActionType, ChangeQty, BeforeQty, AfterQty)
            VALUES (@RecordID, @ItemID, @WarehouseID, @SupplierID, @BatchNo,
                    @LocationID, @OpType, @Qty, @Before, @After);
        END
        ELSE
        BEGIN
            /* --- 出库：先加锁算可用量，再按 FEFO 逐批扣减 --- */
            DECLARE @Total INT;

            SELECT @Total = ISNULL(SUM(Storing), 0)
            FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
            WHERE ItemID = @ItemID
              AND WarehouseID = @WarehouseID
              AND (@SupplierID IS NULL OR ISNULL(SupplierID, 0) = ISNULL(@SupplierID, 0));

            IF @Total < @Qty
                THROW 50004, N'库存不足（触发器复核未通过）', 1;

            DECLARE @Remain   INT = @Qty,
                    @CurSID   INT,
                    @CurSup   INT,
                    @CurQty   INT,
                    @CurBatch NVARCHAR(40),
                    @CurLoc   INT,
                    @Take     INT;

            /* 先到期先出：
                 1. 有效期的排在无有效期之前
                 2. 有效期内按失效日期升序（越临期越先出）
                 3. 同效期或无有效期时，按 StorageID（批次到达先后）
               注意不能用 LastUpdate 排序 —— 它每次变动都被覆盖。 */
            DECLARE fefo CURSOR LOCAL FAST_FORWARD FOR
                SELECT StorageID, SupplierID, Storing, BatchNo, LocationID
                FROM dbo.Storage WITH (UPDLOCK, HOLDLOCK)
                WHERE ItemID = @ItemID
                  AND WarehouseID = @WarehouseID
                  AND Storing > 0
                  AND (@SupplierID IS NULL OR ISNULL(SupplierID, 0) = ISNULL(@SupplierID, 0))
                ORDER BY CASE WHEN ExpiryDate IS NULL THEN 1 ELSE 0 END,
                         ExpiryDate ASC,
                         StorageID ASC;

            OPEN fefo;
            FETCH NEXT FROM fefo INTO @CurSID, @CurSup, @CurQty, @CurBatch, @CurLoc;

            WHILE @@FETCH_STATUS = 0 AND @Remain > 0
            BEGIN
                SET @Take = CASE WHEN @CurQty >= @Remain THEN @Remain ELSE @CurQty END;

                UPDATE dbo.Storage
                SET Storing = Storing - @Take, LastUpdate = GETDATE()
                WHERE StorageID = @CurSID;

                INSERT INTO dbo.StockAudit (RecordID, ItemID, WarehouseID, SupplierID, BatchNo,
                                            LocationID, ActionType, ChangeQty, BeforeQty, AfterQty)
                VALUES (@RecordID, @ItemID, @WarehouseID, @CurSup, @CurBatch,
                        @CurLoc, @OpType, -@Take, @CurQty, @CurQty - @Take);

                SET @Remain = @Remain - @Take;
                FETCH NEXT FROM fefo INTO @CurSID, @CurSup, @CurQty, @CurBatch, @CurLoc;
            END

            CLOSE fefo;
            DEALLOCATE fefo;
        END

        FETCH NEXT FROM cur INTO @RecordID, @ItemID, @WarehouseID, @SupplierID, @BatchNo,
                                 @LocationID, @OperatorID, @OpType, @Qty;
    END

    CLOSE cur;
    DEALLOCATE cur;
END;
GO


/* ---------------------------------------------------------------------------
   T2 库存变动 -> 仓库使用量同步
   --------------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_Storage_SyncUsage
    ON dbo.Storage
    AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    /* 只重算本次受影响的仓库，避免全表扫描。
       若这次是 UPDATE 且数量压根没变（比如只刷新了 LastUpdate），直接跳过。 */
    IF EXISTS (SELECT 1 FROM inserted)
       AND EXISTS (SELECT 1 FROM deleted)      -- 两侧都有 = UPDATE
       AND NOT UPDATE(Storing)
        RETURN;

    ;WITH touched AS (SELECT WarehouseID FROM inserted
                      UNION
                      SELECT WarehouseID FROM deleted)
    UPDATE w
    SET w.WarehouseUsage = ISNULL((SELECT SUM(s.Storing)
                                   FROM dbo.Storage s
                                   WHERE s.WarehouseID = w.WarehouseID), 0)
    FROM dbo.Warehouse w
             INNER JOIN touched t ON w.WarehouseID = t.WarehouseID;
END;
GO


/* ---------------------------------------------------------------------------
   T3 权限变更 -> 审计留痕
   --------------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_Assignment_Audit
    ON dbo.StaffAssignment
    AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- 新增的授权
    INSERT INTO dbo.PermissionAudit (StaffID, WarehouseID, ActionType, OperatorNote)
    SELECT i.StaffID, i.WarehouseID, N'权限授予', N'触发器记录'
    FROM inserted i;

    -- 撤销的授权（同一批次里既增又删时两边都要记，原版这里漏了）
    INSERT INTO dbo.PermissionAudit (StaffID, WarehouseID, ActionType, OperatorNote)
    SELECT d.StaffID, d.WarehouseID, N'权限撤销', N'触发器记录'
    FROM deleted d;
END;
GO
