/* ============================================================================
   07 演示数据（可选）
   ----------------------------------------------------------------------------
   目的：让首页趋势图、审计页在演示时有内容可看。

   为什么走 sp_PostOperation 而不是直接 INSERT Record：
     直接插流水会触发库存同步，但绕过了权限与库存校验，容易造出
     "库存为负""经办人无权限"这类脏数据，演示时反而露馅。
     走存储过程，生成出来的数据必然满足所有不变式。

   时间的处理：
     存储过程用 GETDATE() 打时间戳，这里生成完再回填到当天的营业时段，
     否则所有流水都挤在同一秒，趋势图只有一个柱子。

   可重复执行：每次追加一批，不会破坏已有数据。
   ============================================================================ */

USE WarehouseDB_V2;
GO

SET NOCOUNT ON;

DECLARE @today DATE = CAST(GETDATE() AS DATE);
DECLARE @day   DATE = DATEADD(day, -13, @today);

DECLARE @wh INT, @staff INT, @item INT, @sup INT, @qty INT, @isIn BIT;
DECLARE @op NVARCHAR(10), @rid INT, @ok INT = 0, @fail INT = 0;
DECLARE @stamp DATETIME;

WHILE @day <= @today
BEGIN
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT sa.WarehouseID, sa.StaffID
        FROM dbo.StaffAssignment sa
                 INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
        WHERE s.IsActive = 1
        GROUP BY sa.WarehouseID, sa.StaffID;

    OPEN cur;
    FETCH NEXT FROM cur INTO @wh, @staff;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT TOP 1 @item = ItemID FROM dbo.Item ORDER BY NEWID();
        SET @sup = (SELECT TOP 1 SupID FROM dbo.Supplier ORDER BY NEWID());
        SET @qty = 1 + ABS(CHECKSUM(NEWID())) % 12;
        SET @isIn = CASE WHEN ABS(CHECKSUM(NEWID())) % 10 < 6 THEN 1 ELSE 0 END;
        SET @op = CASE WHEN @isIn = 1 THEN N'入库' ELSE N'出库' END;

        BEGIN TRY
            EXEC dbo.sp_PostOperation
                 @ItemID = @item, @WarehouseID = @wh, @SupplierID = @sup,
                 @OperatorID = @staff, @OperationType = @op,
                 @Quantity = @qty, @Remarks = N'演示数据', @RecordID = @rid OUTPUT;

            -- 回填时间到当天 08:00 - 17:00 之间
            SET @stamp = DATEADD(minute, 480 + ABS(CHECKSUM(NEWID())) % 540, CAST(@day AS DATETIME));

            UPDATE dbo.Record SET OperationTime = @stamp WHERE RecordID = @rid;
            UPDATE dbo.StockAudit SET AuditTime = @stamp WHERE RecordID = @rid;

            SET @ok += 1;
        END TRY
        BEGIN CATCH
            -- 库存不足 / 库容不足都会走到这里，跳过即可
            SET @fail += 1;
        END CATCH

        FETCH NEXT FROM cur INTO @wh, @staff;
    END

    CLOSE cur;
    DEALLOCATE cur;

    SET @day = DATEADD(day, 1, @day);
END

SELECT @ok AS [生成流水], @fail AS [跳过] ;
GO

/* 生成完复核一次：使用量必须等于库存汇总（触发器若失守这里会暴露） */
SELECT w.WarehouseName,
       w.WarehouseUsage,
       ISNULL((SELECT SUM(Storing) FROM dbo.Storage s WHERE s.WarehouseID = w.WarehouseID), 0) AS CalcUsage
FROM dbo.Warehouse w
ORDER BY w.WarehouseID;
GO
