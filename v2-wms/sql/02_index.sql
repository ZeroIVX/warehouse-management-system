/* ============================================================================
   02 索引设计
   ----------------------------------------------------------------------------
   原则：索引跟着查询走，不跟着表走。这里每一条索引都能对应到应用里的
        一个真实查询路径，序号即用途说明。

   注意：外键本身不会自动建索引，而 SQL Server 在删除/更新父表时会去
        子表反查，缺索引会导致全表扫描甚至锁升级。
   ============================================================================ */

USE WarehouseDB_V2;
GO

/* 筛选索引与计算列上的索引要求会话开启 QUOTED_IDENTIFIER */
SET QUOTED_IDENTIFIER ON;
GO

/* ---- I1 库存明细页：按 物品 + 仓库 定位，并且总是要取数量与供应商 ----
   覆盖索引，查询只读索引页不回表 */
CREATE INDEX IX_Storage_Item_Warehouse
    ON dbo.Storage (ItemID, WarehouseID)
    INCLUDE (SupplierID, Storing, LastUpdate);
GO

/* ---- I2 按仓库汇总库存（仓库储量图、容量校验）---- */
CREATE INDEX IX_Storage_Warehouse
    ON dbo.Storage (WarehouseID)
    INCLUDE (Storing);
GO

/* ---- I3 同一物品跨仓库查找（出库时列出"哪些仓库有货"）---- */
CREATE INDEX IX_Storage_Supplier
    ON dbo.Storage (SupplierID)
    INCLUDE (ItemID, Storing);
GO

/* ---- I4 流水页：默认按时间倒序翻页，最热查询 ---- */
CREATE INDEX IX_Record_Time
    ON dbo.Record (OperationTime DESC)
    INCLUDE (ItemID, WarehouseID, OperationType, OperationQuantity, OperatorID);
GO

/* ---- I5 流水页按物品筛选 ---- */
CREATE INDEX IX_Record_Item
    ON dbo.Record (ItemID, OperationTime DESC);
GO

/* ---- I6 流水页按仓库筛选 / 调拨成组追溯 ---- */
CREATE INDEX IX_Record_Warehouse
    ON dbo.Record (WarehouseID, OperationTime DESC);
CREATE INDEX IX_Record_Transfer
    ON dbo.Record (TransferGroupID)
    WHERE TransferGroupID IS NOT NULL;   -- 筛选索引：只索引调拨记录
GO

/* ---- I7 权限校验：主键是 (StaffID, WarehouseID)，但"按仓库查员工"
       是反向前缀，用不上主键索引，必须单独建 ---- */
CREATE INDEX IX_Assignment_Warehouse
    ON dbo.StaffAssignment (WarehouseID, StaffID);
GO

/* ---- I8 物品页按名称/规格模糊检索 ----
   LIKE '%x%' 本身用不了 B 树，但等值 + 前缀查询能用上，且排序可避免 */
CREATE INDEX IX_Item_Name
    ON dbo.Item (ItemName)
    INCLUDE (ItemType, Price, FactoryID);
GO

/* ---- I9 审计页按时间倒序 ---- */
CREATE INDEX IX_StockAudit_Time
    ON dbo.StockAudit (AuditTime DESC)
    INCLUDE (RecordID, ItemID, WarehouseID, ChangeQty);
CREATE INDEX IX_StockAudit_Record
    ON dbo.StockAudit (RecordID);
CREATE INDEX IX_PermAudit_Time
    ON dbo.PermissionAudit (AuditTime DESC);
GO

/* ---- I10 物品页按厂家 JOIN ---- */
CREATE INDEX IX_Item_Factory
    ON dbo.Item (FactoryID);
GO
