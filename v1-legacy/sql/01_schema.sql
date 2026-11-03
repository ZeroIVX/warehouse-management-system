USE WarehouseDB_V1;
GO

-- =============================================
-- 1. 基础信息表 (Master Data)
-- =============================================

-- 生产厂家表
CREATE TABLE Factory (
    FactID INT PRIMARY KEY IDENTITY(1,1),
    FactName NVARCHAR(100) NOT NULL,
    FactAddress NVARCHAR(200),
    FactTel NVARCHAR(50)
);

-- 供应商表
CREATE TABLE Supplier (
    SupID INT PRIMARY KEY IDENTITY(1,1),
    SupName NVARCHAR(100) NOT NULL,
    SupAddress NVARCHAR(200),
    SupTel NVARCHAR(50)
);

-- 仓库表
CREATE TABLE Warehouse (
    WarehouseID INT PRIMARY KEY IDENTITY(1,1),
    WarehouseName NVARCHAR(100) NOT NULL,
    WarehouseAddress NVARCHAR(200),
    WarehouseType NVARCHAR(100),
    WarehouseSize INT CHECK (WarehouseSize > 0), -- 约束：大小必须为正数
    WarehouseUsage INT DEFAULT 0 CHECK (WarehouseUsage >= 0) -- 当前占用量
);

-- 物品表
CREATE TABLE Item (
    ItemID INT PRIMARY KEY IDENTITY(1,1),
    ItemName NVARCHAR(100) NOT NULL,
    ItemType NVARCHAR(50),
    Price DECIMAL(10,2) NOT NULL CHECK (Price >= 0), -- 约束：价格非负
    FactoryID INT FOREIGN KEY REFERENCES Factory(FactID) ON UPDATE CASCADE ON DELETE SET NULL
);

-- 员工表
CREATE TABLE Staff (
    StaffID INT PRIMARY KEY IDENTITY(1,1),
    StaffName NVARCHAR(50) NOT NULL,
    StaffTel NVARCHAR(20),
    IsActive BIT DEFAULT 1 -- 添加状态，离职员工逻辑删除而非物理删除
);

-- =============================================
-- 2. 关系与库存表 (Relationships & Inventory)
-- =============================================

-- 员工与仓库的工作分配
CREATE TABLE StaffAssignment (
    StaffID INT FOREIGN KEY (StaffID) REFERENCES Staff(StaffID) NOT NULL,
    WarehouseID INT FOREIGN KEY (WarehouseID) REFERENCES Warehouse(WarehouseID) NOT NULL,
    AssignDate DATETIME DEFAULT GETDATE(),
    PRIMARY KEY (StaffID, WarehouseID)
);

-- 物品库存表 (核心表)
CREATE TABLE Storage (
    StorageID INT PRIMARY KEY IDENTITY(1,1), -- 建议添加独立主键方便引用
    ItemID INT NOT NULL FOREIGN KEY REFERENCES Item(ItemID) ON UPDATE CASCADE,
    WarehouseID INT NOT NULL FOREIGN KEY REFERENCES Warehouse(WarehouseID) ON UPDATE CASCADE,
    SupplierID INT FOREIGN KEY REFERENCES Supplier(SupID) ON UPDATE CASCADE, -- 在这里记录具体批次的供应商
    Storing INT DEFAULT 0 CHECK (Storing >= 0), -- 约束：库存不能为负
    LastUpdate DATETIME DEFAULT GETDATE(),
    
    -- 联合唯一约束：同一物品、同一仓库、同一供应商视为同一库存记录
    CONSTRAINT UK_Storage UNIQUE (ItemID, WarehouseID, SupplierID)
);

-- =============================================
-- 3. 业务记录表 (Transactions)
-- =============================================

-- 操作记录表 (流水账)
CREATE TABLE Record (
    RecordID INT PRIMARY KEY IDENTITY(1,1),
    ItemID INT NOT NULL FOREIGN KEY REFERENCES Item(ItemID) ON UPDATE CASCADE,
    WarehouseID INT NOT NULL FOREIGN KEY REFERENCES Warehouse(WarehouseID) ON UPDATE CASCADE,
    SupplierID INT FOREIGN KEY REFERENCES Supplier(SupID), -- 必须知道入库来源或出库批次
    OperatorID INT FOREIGN KEY REFERENCES Staff(StaffID) ON DELETE SET NULL, -- 员工离职不应删除历史单据
    OperationTime DATETIME DEFAULT GETDATE(),
    OperationType NVARCHAR(20) NOT NULL CHECK (OperationType IN (N'入库', N'出库')),
    OperationQuantity INT NOT NULL CHECK (OperationQuantity > 0), -- 数量必须为正
    Remarks NVARCHAR(200)
);

-- 历史/审计表 (原 History 表优化)
-- 建议：通常不需要单独的 History 表复制 Record 表的所有内容。
-- Record 表本身就是历史流水。如果需要审计“修改操作”，则使用 History。
-- 此处保留您的设计，但用途改为“审计日志”，记录被修改或删除的记录。
CREATE TABLE AuditLog (
    LogID INT PRIMARY KEY IDENTITY(1,1),
    RecordID INT,
    ActionType NVARCHAR(20), -- INSERT, UPDATE, DELETE
    ChangeTime DATETIME DEFAULT GETDATE(),
    OldQuantity INT,
    NewQuantity INT,
    OperatorID INT
);

-- =============================================
-- 4. 索引优化 (Performance)
-- =============================================
-- 为外键创建索引以加速 JOIN 查询
CREATE INDEX IX_Item_Factory ON Item(FactoryID);
CREATE INDEX IX_Storage_Item ON Storage(ItemID);
CREATE INDEX IX_Storage_Warehouse ON Storage(WarehouseID);
CREATE INDEX IX_Record_Time ON Record(OperationTime); -- 加速按时间查询报表
CREATE INDEX IX_Record_Item ON Record(ItemID);

GO

-- =============================================
-- 5. 核心业务触发器 (Business Logic)
-- =============================================

-- 触发器 1: 自动更新库存
-- 当插入 Record 记录时，自动增减 Storage 表的库存
CREATE TRIGGER Updating
ON Record
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ItemID INT, @WarehouseID INT, @SupplierID INT, @Qty INT, @OpType NVARCHAR(10);
    SELECT @ItemID=ItemID, @WarehouseID=WarehouseID, @SupplierID=SupplierID, @Qty=OperationQuantity, @OpType=OperationType FROM inserted;

    IF @OpType = N'入库'
    BEGIN
        -- 入库逻辑保持不变：精确匹配或新增
        IF EXISTS (SELECT 1 FROM Storage WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND ISNULL(SupplierID,0)=ISNULL(@SupplierID,0))
            UPDATE Storage SET Storing = Storing + @Qty, LastUpdate = GETDATE()
            WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND ISNULL(SupplierID,0)=ISNULL(@SupplierID,0);
        ELSE
            INSERT INTO Storage (ItemID, WarehouseID, SupplierID, Storing, LastUpdate)
            VALUES (@ItemID, @WarehouseID, @SupplierID, @Qty, GETDATE());
    END
    ELSE IF @OpType = N'出库'
    BEGIN
        -- 核心改动：出库逻辑
        IF @SupplierID IS NOT NULL
        BEGIN
            -- 1. 指定了供应商：精确扣减
            IF (SELECT ISNULL(Storing,0) FROM Storage WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND SupplierID=@SupplierID) >= @Qty
                UPDATE Storage SET Storing = Storing - @Qty, LastUpdate = GETDATE()
                WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND SupplierID=@SupplierID;
            ELSE
            BEGIN
                RAISERROR(N'该指定供应商的库存不足。', 16, 1); ROLLBACK;
            END
        END
        ELSE
        BEGIN
            -- 2. 不指定供应商：从该仓库该物品的“总库存”里扣减
            DECLARE @TotalStock INT = (SELECT SUM(Storing) FROM Storage WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID);
            IF @TotalStock < @Qty
            BEGIN
                RAISERROR(N'该仓库总库存不足。', 16, 1); ROLLBACK;
            END
            ELSE
            BEGIN
                -- 自动扣减逻辑：按供应商记录顺序依次扣减，直到扣完 @Qty
                DECLARE @RemainingQty INT = @Qty;
                DECLARE @CurrentSID INT, @CurrentStock INT;

                DECLARE stock_cursor CURSOR FOR 
                SELECT SupplierID, Storing FROM Storage WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND Storing > 0;
                
                OPEN stock_cursor;
                FETCH NEXT FROM stock_cursor INTO @CurrentSID, @CurrentStock;
                WHILE @@FETCH_STATUS = 0 AND @RemainingQty > 0
                BEGIN
                    IF @CurrentStock >= @RemainingQty
                    BEGIN
                        UPDATE Storage SET Storing = Storing - @RemainingQty WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND ISNULL(SupplierID,0) = ISNULL(@CurrentSID,0);
                        SET @RemainingQty = 0;
                    END
                    ELSE
                    BEGIN
                        UPDATE Storage SET Storing = 0 WHERE ItemID=@ItemID AND WarehouseID=@WarehouseID AND ISNULL(SupplierID,0) = ISNULL(@CurrentSID,0);
                        SET @RemainingQty = @RemainingQty - @CurrentStock;
                    END
                    FETCH NEXT FROM stock_cursor INTO @CurrentSID, @CurrentStock;
                END
                CLOSE stock_cursor; DEALLOCATE stock_cursor;
            END
        END
    END
END;

-- 触发器 2：记录员工权限变更
GO
CREATE TRIGGER StaffAssignmentUpdating
ON StaffAssignment
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. 处理新增权限记录
    IF EXISTS (SELECT * FROM inserted)
    BEGIN
        INSERT INTO [dbo].[AuditLog] (
            [ActionType], 
            [ChangeTime], 
            [OldQuantity], -- 权限表无数量，此处存入 StaffID 作为标识
            [NewQuantity], -- 权限表无数量，此处存入 WarehouseID 作为标识
            [OperatorID]   -- 记录被操作的员工ID
        )
        SELECT 
            N'权限授予', 
            GETDATE(), 
            i.StaffID, 
            i.WarehouseID, 
            i.StaffID
        FROM inserted i;
    END

    -- 2. 处理删除权限记录
    IF EXISTS (SELECT * FROM deleted) AND NOT EXISTS (SELECT * FROM inserted)
    BEGIN
        INSERT INTO [dbo].[AuditLog] (
            [ActionType], 
            [ChangeTime], 
            [OldQuantity], 
            [NewQuantity], 
            [OperatorID]
        )
        SELECT 
            N'权限撤销', 
            GETDATE(), 
            d.StaffID, 
            d.WarehouseID, 
            d.StaffID
        FROM deleted d;
    END
END

GO
--触发器 3：记录入库出库
CREATE TRIGGER RecordAudit
ON Record
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- 声明变量用于暂存计算过程
    DECLARE @OldQty INT;
    DECLARE @NewQty INT;
    DECLARE @RecordID INT;
    DECLARE @ItemID INT;
    DECLARE @WHID INT;
    DECLARE @SupID INT;
    DECLARE @OpType NVARCHAR(20);
    DECLARE @OpQty INT;
    DECLARE @OpID INT;

    -- 使用游标处理可能存在的批量插入（通常Streamlit是单条，但触发器应保证健壮性）
    DECLARE audit_cursor CURSOR FOR 
    SELECT RecordID, ItemID, WarehouseID, SupplierID, OperationType, OperationQuantity, OperatorID 
    FROM inserted;

    OPEN audit_cursor;
    FETCH NEXT FROM audit_cursor INTO @RecordID, @ItemID, @WHID, @SupID, @OpType, @OpQty, @OpID;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- 1. 获取操作前的库存 (处理NULL供应商匹配)
        SELECT @OldQty = ISNULL(Storing, 0)
        FROM Storage
        WHERE ItemID = @ItemID 
          AND WarehouseID = @WHID 
          AND ISNULL(SupplierID, 0) = ISNULL(@SupID, 0);

        -- 如果Storage中还没这条记录，初值为0
        SET @OldQty = ISNULL(@OldQty, 0);

        -- 2. 根据操作类型计算操作后库存
        IF @OpType = N'入库'
            SET @NewQty = @OldQty + @OpQty;
        ELSE -- 出库
            SET @NewQty = @OldQty - @OpQty;

        -- 3. 写入 AuditLog 表
        INSERT INTO [dbo].[AuditLog] (
            [RecordID],
            [ActionType],
            [ChangeTime],
            [OldQuantity], -- 操作前库存
            [NewQuantity], -- 操作后库存
            [OperatorID]
        )
        VALUES (
            @RecordID,
            @OpType,
            GETDATE(),
            @OldQty,
            @NewQty,
            @OpID
        );

        FETCH NEXT FROM audit_cursor INTO @RecordID, @ItemID, @WHID, @SupID, @OpType, @OpQty, @OpID;
    END

    CLOSE audit_cursor;
    DEALLOCATE audit_cursor;
END
GO