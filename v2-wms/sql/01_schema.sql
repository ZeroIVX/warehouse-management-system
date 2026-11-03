/* ============================================================================
   智能仓库管理系统 V2  ——  01 数据库与表结构
   ----------------------------------------------------------------------------
   目标平台：Microsoft SQL Server 2016+（实测 SQL Server 2025 / 兼容级别 170）
   设计原则：
     1. 每张表只描述一个实体，非主属性完全依赖主键 —— 满足 3NF
     2. 业务不变式优先交给数据库约束（CHECK / UNIQUE / FK），不依赖应用层自觉
     3. 审计表按「库存变动」与「权限变动」拆开，一个字段只表达一个语义
   ----------------------------------------------------------------------------
   与原版（打包版）的差异说明：
     [D1] AuditLog 一表两用（OldQuantity 存 StaffID、NewQuantity 存 WarehouseID）
          -> 拆成 StockAudit / PermissionAudit，字段语义各自成立。
     [D2] Record.OperationType 只有 入库/出库，调拨靠 Remarks 里的中文字符串
          区分 -> 增加 调拨出/调拨入 两个受约束的取值，并引入 TransferGroupID
          把一对调拨记录绑定在一起，可成组追溯。
     [D3] Warehouse.WarehouseUsage 从来没有代码维护（永远等于建库时的初值）
          -> 改为由触发器随库存变动同步，并加 CHECK 约束使其不可能超过库容。
   ============================================================================ */

USE master;
GO

IF DB_ID(N'WarehouseDB_V2') IS NOT NULL
BEGIN
    ALTER DATABASE WarehouseDB_V2 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WarehouseDB_V2;
END
GO

CREATE DATABASE WarehouseDB_V2;
GO

ALTER DATABASE WarehouseDB_V2 SET COMPATIBILITY_LEVEL = 170;
GO

USE WarehouseDB_V2;
GO


/* ---------------------------------------------------------------------------
   1. 基础数据（主数据实体）
   --------------------------------------------------------------------------- */

CREATE TABLE dbo.Factory
(
    FactID      INT IDENTITY (1,1) NOT NULL,
    FactName    NVARCHAR(100) NOT NULL,
    FactAddress NVARCHAR(200) NULL,
    FactTel     NVARCHAR(50)  NULL,
    CONSTRAINT PK_Factory PRIMARY KEY (FactID),
    CONSTRAINT UQ_Factory_Name UNIQUE (FactName)
);
GO

CREATE TABLE dbo.Supplier
(
    SupID      INT IDENTITY (1,1) NOT NULL,
    SupName    NVARCHAR(100) NOT NULL,
    SupAddress NVARCHAR(200) NULL,
    SupTel     NVARCHAR(50)  NULL,
    CONSTRAINT PK_Supplier PRIMARY KEY (SupID),
    CONSTRAINT UQ_Supplier_Name UNIQUE (SupName)
);
GO

/* 仓库类型的受控词汇表。
   原版把类型写成 Warehouse.WarehouseType NVARCHAR + 前端硬编码三个选项，
   而库里实际存的是「常温库/冷链库/恒温库/危化库/特种库」五类 —— 前端选项
   与数据对不上，一旦新增类型还要改代码。
   抽成字典表后：类型可增删、名称只存一份、仓库表只存外键。 */
CREATE TABLE dbo.WarehouseType
(
    TypeID   INT IDENTITY (1,1) NOT NULL,
    TypeName NVARCHAR(20)  NOT NULL,
    Remark   NVARCHAR(100) NULL,
    CONSTRAINT PK_WarehouseType PRIMARY KEY (TypeID),
    CONSTRAINT UQ_WarehouseType_Name UNIQUE (TypeName)
);
GO

INSERT INTO dbo.WarehouseType (TypeName, Remark)
VALUES (N'常温库', N'常温存储，适用于普通货物'),
       (N'冷链库', N'低温存储，适用于生鲜、医药'),
       (N'恒温库', N'恒温恒湿，适用于精密电子'),
       (N'危化库', N'危险化学品专用，需相应资质'),
       (N'特种库', N'超尺寸、超重货物');
GO

CREATE TABLE dbo.Warehouse
(
    WarehouseID      INT IDENTITY (1,1) NOT NULL,
    WarehouseName    NVARCHAR(100) NOT NULL,
    WarehouseAddress NVARCHAR(200) NULL,
    WarehouseTypeID  INT           NOT NULL CONSTRAINT DF_Warehouse_Type DEFAULT 1,
    WarehouseSize    INT           NOT NULL CONSTRAINT DF_Warehouse_Size DEFAULT 1000,
    WarehouseUsage   INT           NOT NULL CONSTRAINT DF_Warehouse_Usage DEFAULT 0,
    CONSTRAINT PK_Warehouse PRIMARY KEY (WarehouseID),
    CONSTRAINT FK_Warehouse_Type FOREIGN KEY (WarehouseTypeID)
        REFERENCES dbo.WarehouseType (TypeID),
    CONSTRAINT UQ_Warehouse_Name UNIQUE (WarehouseName),
    CONSTRAINT CK_Warehouse_Size  CHECK (WarehouseSize > 0),
    CONSTRAINT CK_Warehouse_Usage CHECK (WarehouseUsage >= 0 AND WarehouseUsage <= WarehouseSize)
);
GO

CREATE TABLE dbo.Item
(
    ItemID    INT IDENTITY (1,1) NOT NULL,
    ItemName  NVARCHAR(100)  NOT NULL,
    ItemType  NVARCHAR(50)   NULL,
    Price     DECIMAL(10, 2) NOT NULL CONSTRAINT DF_Item_Price DEFAULT 0,
    FactoryID INT            NULL,
    CONSTRAINT PK_Item PRIMARY KEY (ItemID),
    CONSTRAINT FK_Item_Factory FOREIGN KEY (FactoryID)
        REFERENCES dbo.Factory (FactID) ON UPDATE CASCADE ON DELETE SET NULL,
    -- 同一厂家下同名同规格只允许一条，从根上避免重复建档
    CONSTRAINT UQ_Item_Ident UNIQUE (ItemName, ItemType, FactoryID),
    CONSTRAINT CK_Item_Price CHECK (Price >= 0)
);
GO

CREATE TABLE dbo.Staff
(
    StaffID   INT IDENTITY (1,1) NOT NULL,
    StaffName NVARCHAR(50) NOT NULL,
    StaffTel  NVARCHAR(20) NULL,
    IsActive  BIT          NOT NULL CONSTRAINT DF_Staff_Active DEFAULT 1,
    CONSTRAINT PK_Staff PRIMARY KEY (StaffID)
);
GO


/* ---------------------------------------------------------------------------
   2. 客户与库位 —— 现实仓储的作业基础
   --------------------------------------------------------------------------- */

/* 出库收货方。销售出库要知道货发给谁；调拨出库不需要客户。 */
CREATE TABLE dbo.Customer
(
    CustomerID   INT IDENTITY (1,1) NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL,
    Contact      NVARCHAR(50)  NULL,
    Phone        NVARCHAR(30)  NULL,
    Address      NVARCHAR(200) NULL,
    CONSTRAINT PK_Customer PRIMARY KEY (CustomerID),
    CONSTRAINT UQ_Customer_Name UNIQUE (CustomerName)
);
GO

/* 库区：一个仓库按功能分区。
   现实流程里货不是直接进存储区的 —— 先进待检区，质检合格才转入存储区。 */
CREATE TABLE dbo.WarehouseZone
(
    ZoneID      INT IDENTITY (1,1) NOT NULL,
    WarehouseID INT          NOT NULL,
    ZoneCode    NVARCHAR(20) NOT NULL,
    ZoneName    NVARCHAR(50) NOT NULL,
    ZoneType    NVARCHAR(20) NOT NULL,
    CONSTRAINT PK_WarehouseZone PRIMARY KEY (ZoneID),
    CONSTRAINT FK_Zone_Warehouse FOREIGN KEY (WarehouseID)
        REFERENCES dbo.Warehouse (WarehouseID) ON UPDATE CASCADE,
    CONSTRAINT UQ_Zone_Code UNIQUE (WarehouseID, ZoneCode),
    CONSTRAINT CK_Zone_Type CHECK (ZoneType IN (N'存储区', N'拣选区', N'待检区', N'退货区', N'冻结区'))
);
GO

/* 库位：拣货要走到具体货位。编码形如 A-01-03（巷道-层-位）。 */
CREATE TABLE dbo.StorageLocation
(
    LocationID   INT IDENTITY (1,1) NOT NULL,
    ZoneID       INT          NOT NULL,
    LocationCode NVARCHAR(30) NOT NULL,
    Capacity     INT          NOT NULL CONSTRAINT DF_Location_Cap DEFAULT 1000,
    IsLocked     BIT          NOT NULL CONSTRAINT DF_Location_Lock DEFAULT 0,
    CONSTRAINT PK_StorageLocation PRIMARY KEY (LocationID),
    CONSTRAINT FK_Location_Zone FOREIGN KEY (ZoneID)
        REFERENCES dbo.WarehouseZone (ZoneID) ON UPDATE CASCADE,
    CONSTRAINT UQ_Location_Code UNIQUE (ZoneID, LocationCode),
    CONSTRAINT CK_Location_Cap CHECK (Capacity > 0)
);
GO


/* ---------------------------------------------------------------------------
   3. 关系与库存
   --------------------------------------------------------------------------- */

CREATE TABLE dbo.StaffAssignment
(
    StaffID     INT      NOT NULL,
    WarehouseID INT      NOT NULL,
    AssignDate  DATETIME NOT NULL CONSTRAINT DF_Assign_Date DEFAULT GETDATE(),
    CONSTRAINT PK_StaffAssignment PRIMARY KEY (StaffID, WarehouseID),
    CONSTRAINT FK_Assign_Staff FOREIGN KEY (StaffID)
        REFERENCES dbo.Staff (StaffID) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT FK_Assign_Warehouse FOREIGN KEY (WarehouseID)
        REFERENCES dbo.Warehouse (WarehouseID) ON UPDATE CASCADE ON DELETE CASCADE
);
GO

/* 库存按「物品 × 仓库 × 供应商」三元组聚合。
   SupplierID 允许为 NULL，表示"未指定供应商"的混装库存；
   SQL Server 的 UNIQUE 约束把 NULL 视为相等，因此同一三元组只可能有一行，
   正好实现"未指定供应商的批次自动合并"。 */
CREATE TABLE dbo.Storage
(
    StorageID      INT      IDENTITY (1,1) NOT NULL,
    ItemID         INT      NOT NULL,
    WarehouseID    INT      NOT NULL,
    SupplierID     INT      NULL,
    LocationID     INT      NULL,   -- 库位；旧数据可为空（未上架）
    BatchNo        NVARCHAR(40) NULL,
    ProductionDate DATE     NULL,
    ExpiryDate     DATE     NULL,   -- 效期，决定 FEFO 出库顺序
    Storing        INT      NOT NULL CONSTRAINT DF_Storage_Qty DEFAULT 0,
    LastUpdate     DATETIME NOT NULL CONSTRAINT DF_Storage_Update DEFAULT GETDATE(),
    CONSTRAINT PK_Storage PRIMARY KEY (StorageID),
    CONSTRAINT FK_Storage_Item FOREIGN KEY (ItemID)
        REFERENCES dbo.Item (ItemID) ON UPDATE CASCADE,
    CONSTRAINT FK_Storage_Warehouse FOREIGN KEY (WarehouseID)
        REFERENCES dbo.Warehouse (WarehouseID) ON UPDATE CASCADE,
    CONSTRAINT FK_Storage_Supplier FOREIGN KEY (SupplierID)
        REFERENCES dbo.Supplier (SupID) ON UPDATE CASCADE,
    CONSTRAINT FK_Storage_Location FOREIGN KEY (LocationID)
        REFERENCES dbo.StorageLocation (LocationID),
    -- 同一 物品+仓库+供应商+批次+库位 视为同一库存单元，自动合并
    CONSTRAINT UQ_Storage_Unit UNIQUE (ItemID, WarehouseID, SupplierID, BatchNo, LocationID),
    CONSTRAINT CK_Storage_Qty CHECK (Storing >= 0),
    CONSTRAINT CK_Storage_Expiry CHECK (
        ExpiryDate IS NULL OR ProductionDate IS NULL OR ExpiryDate > ProductionDate)
);
GO


/* ---------------------------------------------------------------------------
   4. 业务流水与审计
   --------------------------------------------------------------------------- */

/* 流水表即历史表：一条 Record 代表一次不可变的库存动作。
   调拨会产生两条记录（调拨出 / 调拨入），通过 TransferGroupID 绑定成组。 */
CREATE TABLE dbo.Record
(
    RecordID         INT IDENTITY (1,1) NOT NULL,
    ItemID           INT           NOT NULL,
    WarehouseID      INT           NOT NULL,
    SupplierID       INT           NULL,
    BatchNo          NVARCHAR(40)  NULL,
    LocationID       INT           NULL,
    OperatorID       INT           NULL,
    OperationTime    DATETIME      NOT NULL CONSTRAINT DF_Record_Time DEFAULT GETDATE(),
    OperationType    NVARCHAR(10)  NOT NULL,
    OperationQuantity INT          NOT NULL,
    Remarks          NVARCHAR(200) NULL,
    TransferGroupID  UNIQUEIDENTIFIER NULL,
    -- 作业来源：这批货是哪张单、哪一行产生的，用于单据-流水双向追溯
    SourceType       NVARCHAR(20) NULL,
    SourceOrderID    INT          NULL,
    SourceLineID     INT          NULL,
    CONSTRAINT PK_Record PRIMARY KEY (RecordID),
    CONSTRAINT FK_Record_Item FOREIGN KEY (ItemID)
        REFERENCES dbo.Item (ItemID) ON UPDATE CASCADE,
    CONSTRAINT FK_Record_Warehouse FOREIGN KEY (WarehouseID)
        REFERENCES dbo.Warehouse (WarehouseID) ON UPDATE CASCADE,
    CONSTRAINT FK_Record_Supplier FOREIGN KEY (SupplierID)
        REFERENCES dbo.Supplier (SupID),
    CONSTRAINT FK_Record_Staff FOREIGN KEY (OperatorID)
        REFERENCES dbo.Staff (StaffID) ON DELETE SET NULL,
    CONSTRAINT FK_Record_Location FOREIGN KEY (LocationID)
        REFERENCES dbo.StorageLocation (LocationID),
    CONSTRAINT CK_Record_Type CHECK (
        OperationType IN (N'入库', N'出库', N'调拨入', N'调拨出', N'盘盈', N'盘亏', N'报损')),
    CONSTRAINT CK_Record_Qty  CHECK (OperationQuantity > 0),
    -- 调拨记录必须成组，普通出入库不得带组号
    CONSTRAINT CK_Record_Transfer CHECK (
        (OperationType IN (N'调拨入', N'调拨出') AND TransferGroupID IS NOT NULL)
        OR (OperationType NOT IN (N'调拨入', N'调拨出') AND TransferGroupID IS NULL)
    ),
    CONSTRAINT CK_Record_Source CHECK (
        SourceType IS NULL OR SourceType IN (N'入库单', N'出库单', N'盘点单', N'调拨单', N'调拨', N'手工'))
);
GO

/* 库存审计：一条记录对应一次批次级的库存变动。
   与原版 AuditLog 的区别是每个字段只表达一个含义，不再复用。 */
CREATE TABLE dbo.StockAudit
(
    AuditID     BIGINT IDENTITY (1,1) NOT NULL,
    RecordID    INT      NOT NULL,
    ItemID      INT      NOT NULL,
    WarehouseID INT      NOT NULL,
    SupplierID  INT      NULL,
    BatchNo     NVARCHAR(40) NULL,
    LocationID  INT      NULL,
    ActionType  NVARCHAR(10) NOT NULL,
    ChangeQty   INT      NOT NULL,   -- 带符号：入库为正、出库为负
    BeforeQty   INT      NOT NULL,   -- 该批次变动前数量
    AfterQty    INT      NOT NULL,   -- 该批次变动后数量
    AuditTime   DATETIME NOT NULL CONSTRAINT DF_StockAudit_Time DEFAULT GETDATE(),
    CONSTRAINT PK_StockAudit PRIMARY KEY (AuditID),
    CONSTRAINT FK_StockAudit_Record FOREIGN KEY (RecordID)
        REFERENCES dbo.Record (RecordID),
    -- 变动前后值必须自洽，避免审计表被写入手工构造的脏数据
    CONSTRAINT CK_StockAudit_Balance CHECK (AfterQty = BeforeQty + ChangeQty)
);
GO

/* 权限审计：员工与仓库的授权关系变化 */
CREATE TABLE dbo.PermissionAudit
(
    AuditID     BIGINT IDENTITY (1,1) NOT NULL,
    StaffID     INT          NOT NULL,
    WarehouseID INT          NOT NULL,
    ActionType  NVARCHAR(10) NOT NULL,  -- 权限授予 / 权限撤销
    OperatorNote NVARCHAR(100) NULL,
    AuditTime   DATETIME     NOT NULL CONSTRAINT DF_PermAudit_Time DEFAULT GETDATE(),
    CONSTRAINT PK_PermissionAudit PRIMARY KEY (AuditID),
    CONSTRAINT CK_PermAudit_Type CHECK (ActionType IN (N'权限授予', N'权限撤销'))
);
GO


/* ---------------------------------------------------------------------------
   5. 作业单据 —— 库存变动必须挂在单据上
   ---------------------------------------------------------------------------
   库存流水记录的是"发生了什么"，单据记录的是"该发生什么"。
   没有单据层，系统只能事后记账，没法回答"这批货是哪张采购单收的"
   "客户订的 100 件还差多少没发"。
   --------------------------------------------------------------------------- */

/* 入库单：支持分次到货 —— 计划 100 件，先到 60 就是"部分收货" */
CREATE TABLE dbo.InboundOrder
(
    OrderID      INT IDENTITY (1,1) NOT NULL,
    OrderNo      NVARCHAR(30)  NOT NULL,
    OrderType    NVARCHAR(20)  NOT NULL,
    WarehouseID  INT           NOT NULL,
    SupplierID   INT           NULL,
    Status       NVARCHAR(10)  NOT NULL CONSTRAINT DF_In_Status DEFAULT N'草稿',
    ExpectedDate DATE          NULL,
    CreatedAt    DATETIME      NOT NULL CONSTRAINT DF_In_Created DEFAULT GETDATE(),
    CompletedAt  DATETIME      NULL,
    Remark       NVARCHAR(200) NULL,
    CONSTRAINT PK_InboundOrder PRIMARY KEY (OrderID),
    CONSTRAINT UQ_InboundOrder_No UNIQUE (OrderNo),
    CONSTRAINT FK_In_Wh FOREIGN KEY (WarehouseID) REFERENCES dbo.Warehouse (WarehouseID),
    CONSTRAINT FK_In_Sup FOREIGN KEY (SupplierID) REFERENCES dbo.Supplier (SupID),
    CONSTRAINT CK_In_Type CHECK (OrderType IN (N'采购入库', N'退货入库', N'调拨入库')),
    CONSTRAINT CK_In_Status CHECK (Status IN (N'草稿', N'待收货', N'部分收货', N'已完成', N'已取消'))
);
GO

CREATE TABLE dbo.InboundOrderLine
(
    LineID         INT IDENTITY (1,1) NOT NULL,
    OrderID        INT           NOT NULL,
    LineNumber         INT           NOT NULL,
    ItemID         INT           NOT NULL,
    PlannedQty     INT           NOT NULL,
    ReceivedQty    INT           NOT NULL CONSTRAINT DF_InLine_Recv DEFAULT 0,
    LocationID     INT           NULL,
    BatchNo        NVARCHAR(40)  NULL,
    ProductionDate DATE          NULL,
    ExpiryDate     DATE          NULL,
    CONSTRAINT PK_InboundOrderLine PRIMARY KEY (LineID),
    CONSTRAINT FK_InLine_Order FOREIGN KEY (OrderID)
        REFERENCES dbo.InboundOrder (OrderID) ON DELETE CASCADE,
    CONSTRAINT FK_InLine_Item FOREIGN KEY (ItemID) REFERENCES dbo.Item (ItemID),
    CONSTRAINT FK_InLine_Loc FOREIGN KEY (LocationID) REFERENCES dbo.StorageLocation (LocationID),
    CONSTRAINT UQ_InLine_No UNIQUE (OrderID, LineNumber),
    CONSTRAINT CK_InLine_Qty CHECK (PlannedQty > 0 AND ReceivedQty >= 0 AND ReceivedQty <= PlannedQty),
    CONSTRAINT CK_InLine_Expiry CHECK (
        ExpiryDate IS NULL OR ProductionDate IS NULL OR ExpiryDate > ProductionDate)
);
GO

CREATE TABLE dbo.OutboundOrder
(
    OrderID      INT IDENTITY (1,1) NOT NULL,
    OrderNo      NVARCHAR(30)  NOT NULL,
    OrderType    NVARCHAR(20)  NOT NULL,
    WarehouseID  INT           NOT NULL,
    CustomerID   INT           NULL,
    Status       NVARCHAR(10)  NOT NULL CONSTRAINT DF_Out_Status DEFAULT N'草稿',
    RequiredDate DATE          NULL,
    CreatedAt    DATETIME      NOT NULL CONSTRAINT DF_Out_Created DEFAULT GETDATE(),
    ShippedAt    DATETIME      NULL,
    Remark       NVARCHAR(200) NULL,
    CONSTRAINT PK_OutboundOrder PRIMARY KEY (OrderID),
    CONSTRAINT UQ_OutboundOrder_No UNIQUE (OrderNo),
    CONSTRAINT FK_Out_Wh FOREIGN KEY (WarehouseID) REFERENCES dbo.Warehouse (WarehouseID),
    CONSTRAINT FK_Out_Cus FOREIGN KEY (CustomerID) REFERENCES dbo.Customer (CustomerID),
    CONSTRAINT CK_Out_Type CHECK (OrderType IN (N'销售出库', N'调拨出库', N'报损出库', N'退供出库')),
    CONSTRAINT CK_Out_Status CHECK (Status IN (N'草稿', N'待拣货', N'拣货中', N'已发货', N'已完成', N'已取消'))
);
GO

CREATE TABLE dbo.OutboundOrderLine
(
    LineID     INT IDENTITY (1,1) NOT NULL,
    OrderID    INT NOT NULL,
    LineNumber     INT NOT NULL,
    ItemID     INT NOT NULL,
    PlannedQty INT NOT NULL,
    PickedQty  INT NOT NULL CONSTRAINT DF_OutLine_Pick DEFAULT 0,
    CONSTRAINT PK_OutboundOrderLine PRIMARY KEY (LineID),
    CONSTRAINT FK_OutLine_Order FOREIGN KEY (OrderID)
        REFERENCES dbo.OutboundOrder (OrderID) ON DELETE CASCADE,
    CONSTRAINT FK_OutLine_Item FOREIGN KEY (ItemID) REFERENCES dbo.Item (ItemID),
    CONSTRAINT UQ_OutLine_No UNIQUE (OrderID, LineNumber),
    CONSTRAINT CK_OutLine_Qty CHECK (PlannedQty > 0 AND PickedQty >= 0 AND PickedQty <= PlannedQty)
);
GO

/* 盘点单：账面数 vs 实盘数，差异转成盘盈/盘亏流水。
   Variance 是计算列，差异口径只有一处定义，不会前后端各算一套。 */
CREATE TABLE dbo.StocktakeOrder
(
    StocktakeID INT IDENTITY (1,1) NOT NULL,
    StocktakeNo NVARCHAR(30)  NOT NULL,
    WarehouseID INT           NOT NULL,
    ZoneID      INT           NULL,
    Status      NVARCHAR(10)  NOT NULL CONSTRAINT DF_St_Status DEFAULT N'草稿',
    StartedAt   DATETIME      NULL,
    CompletedAt DATETIME      NULL,
    CreatedAt   DATETIME      NOT NULL CONSTRAINT DF_St_Created DEFAULT GETDATE(),
    Remark      NVARCHAR(200) NULL,
    CONSTRAINT PK_StocktakeOrder PRIMARY KEY (StocktakeID),
    CONSTRAINT UQ_Stocktake_No UNIQUE (StocktakeNo),
    CONSTRAINT FK_St_Wh FOREIGN KEY (WarehouseID) REFERENCES dbo.Warehouse (WarehouseID),
    CONSTRAINT FK_St_Zone FOREIGN KEY (ZoneID) REFERENCES dbo.WarehouseZone (ZoneID),
    CONSTRAINT CK_St_Status CHECK (Status IN (N'草稿', N'盘点中', N'已完成', N'已取消'))
);
GO

CREATE TABLE dbo.StocktakeLine
(
    LineID      INT IDENTITY (1,1) NOT NULL,
    StocktakeID INT           NOT NULL,
    StorageID   INT           NULL,
    ItemID      INT           NOT NULL,
    LocationID  INT           NULL,
    BatchNo     NVARCHAR(40)  NULL,
    BookQty     INT           NOT NULL,
    CountedQty  INT           NULL,
    -- 未录实盘数时差异应为 NULL（未盘），不能算成 -账面数，否则整张单看起来像全仓盘亏
    Variance    AS (CountedQty - BookQty) PERSISTED,
    CONSTRAINT PK_StocktakeLine PRIMARY KEY (LineID),
    CONSTRAINT FK_StLine_Order FOREIGN KEY (StocktakeID)
        REFERENCES dbo.StocktakeOrder (StocktakeID) ON DELETE CASCADE,
    CONSTRAINT FK_StLine_Storage FOREIGN KEY (StorageID) REFERENCES dbo.Storage (StorageID),
    CONSTRAINT FK_StLine_Item FOREIGN KEY (ItemID) REFERENCES dbo.Item (ItemID),
    CONSTRAINT CK_StLine_Qty CHECK (BookQty >= 0 AND (CountedQty IS NULL OR CountedQty >= 0))
);
GO

/* 调拨单：一张单同时约束源仓与目标仓，发货即生成配对流水。
   和入库/出库单一样，库存变动必须挂单，不再有"裸调拨"。 */
CREATE TABLE dbo.TransferOrder
(
    TransferID     INT IDENTITY (1,1) NOT NULL,
    TransferNo     NVARCHAR(30)  NOT NULL,
    SrcWarehouseID INT           NOT NULL,
    DstWarehouseID INT           NOT NULL,
    SrcOperatorID  INT           NULL,   -- 发货人，需源仓库权限
    DstOperatorID  INT           NULL,   -- 收货人，需目标仓库权限
    Status         NVARCHAR(10)  NOT NULL CONSTRAINT DF_Tr_Status DEFAULT N'待发货',
    CreatedAt      DATETIME      NOT NULL CONSTRAINT DF_Tr_Created DEFAULT GETDATE(),
    ShippedAt      DATETIME      NULL,
    CompletedAt    DATETIME      NULL,
    Remark         NVARCHAR(200) NULL,
    CONSTRAINT PK_TransferOrder PRIMARY KEY (TransferID),
    CONSTRAINT UQ_TransferOrder_No UNIQUE (TransferNo),
    CONSTRAINT FK_Tr_Src FOREIGN KEY (SrcWarehouseID) REFERENCES dbo.Warehouse (WarehouseID),
    CONSTRAINT FK_Tr_Dst FOREIGN KEY (DstWarehouseID) REFERENCES dbo.Warehouse (WarehouseID),
    CONSTRAINT FK_Tr_SrcOp FOREIGN KEY (SrcOperatorID) REFERENCES dbo.Staff (StaffID),
    CONSTRAINT FK_Tr_DstOp FOREIGN KEY (DstOperatorID) REFERENCES dbo.Staff (StaffID),
    -- 自己调给自己没有意义，从约束上直接禁掉
    CONSTRAINT CK_Tr_Diff CHECK (SrcWarehouseID <> DstWarehouseID),
    CONSTRAINT CK_Tr_Status CHECK (Status IN (N'待发货', N'部分发货', N'已完成', N'已取消'))
);
GO

CREATE TABLE dbo.TransferOrderLine
(
    LineID     INT IDENTITY (1,1) NOT NULL,
    TransferID INT NOT NULL,
    LineNumber INT NOT NULL,
    ItemID     INT NOT NULL,
    SupplierID INT NULL,
    PlannedQty INT NOT NULL,
    ShippedQty INT NOT NULL CONSTRAINT DF_TrLine_Ship DEFAULT 0,
    CONSTRAINT PK_TransferOrderLine PRIMARY KEY (LineID),
    CONSTRAINT FK_TrLine_Order FOREIGN KEY (TransferID)
        REFERENCES dbo.TransferOrder (TransferID) ON DELETE CASCADE,
    CONSTRAINT FK_TrLine_Item FOREIGN KEY (ItemID) REFERENCES dbo.Item (ItemID),
    CONSTRAINT FK_TrLine_Sup FOREIGN KEY (SupplierID) REFERENCES dbo.Supplier (SupID),
    CONSTRAINT UQ_TrLine_No UNIQUE (TransferID, LineNumber),
    CONSTRAINT CK_TrLine_Qty CHECK (PlannedQty > 0 AND ShippedQty >= 0 AND ShippedQty <= PlannedQty)
);
GO
