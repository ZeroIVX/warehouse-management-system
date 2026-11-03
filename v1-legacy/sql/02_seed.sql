/* ============================================================================
   V1 初始化演示数据
   ----------------------------------------------------------------------------
   用途：为原版（单文件 pyodbc 直连）准备一套可直接查看的演示数据。
   数据为构造的示例数据，不含任何真实企业或个人信息。

   注意：Record 上有两个触发器（Updating / RecordAudit），
        直接灌流水会再扣一次库存并重复写审计，所以导入期间禁用、灌完恢复。
   ============================================================================ */
USE WarehouseDB_V1;
GO
SET NOCOUNT ON;
GO

DISABLE TRIGGER dbo.Updating ON dbo.Record;
GO

DISABLE TRIGGER dbo.RecordAudit ON dbo.Record;
GO

DISABLE TRIGGER dbo.StaffAssignmentUpdating ON dbo.StaffAssignment;
GO

/* ---- Factory：6 行 ---- */
SET IDENTITY_INSERT dbo.Factory ON;
GO
INSERT INTO dbo.Factory ([FactID], [FactName], [FactAddress], [FactTel]) VALUES (1, N'华东制造厂', N'上海市浦东新区张江路100号', N'021-12347788');
INSERT INTO dbo.Factory ([FactID], [FactName], [FactAddress], [FactTel]) VALUES (2, N'华南精密厂', N'深圳市南山区科技园88号', N'0755-87654321');
INSERT INTO dbo.Factory ([FactID], [FactName], [FactAddress], [FactTel]) VALUES (3, N'北方重工厂', N'北京市朝阳区工业园66号', N'010-11223344');
INSERT INTO dbo.Factory ([FactID], [FactName], [FactAddress], [FactTel]) VALUES (4, N'西部电子厂', N'成都市高新区天府五街200号', N'028-55667788');
INSERT INTO dbo.Factory ([FactID], [FactName], [FactAddress], [FactTel]) VALUES (5, N'东方化工厂', N'南京市江宁区化工园99号', N'025-33445566');
INSERT INTO dbo.Factory ([FactID], [FactName], [FactAddress], [FactTel]) VALUES (1001, N'江南皮革厂', N'浙江省温州市龙湾区瑶溪街道机场大道618号', N'0577-11451419');
SET IDENTITY_INSERT dbo.Factory OFF;
GO
GO

/* ---- Supplier：5 行 ---- */
SET IDENTITY_INSERT dbo.Supplier ON;
GO
INSERT INTO dbo.Supplier ([SupID], [SupName], [SupAddress], [SupTel]) VALUES (1, N'上海供应有限公司', N'上海市徐汇区漕宝路120号', N'021-22334455');
INSERT INTO dbo.Supplier ([SupID], [SupName], [SupAddress], [SupTel]) VALUES (2, N'深圳科技供应', N'深圳市福田区深南大道500号', N'0755-66778899');
INSERT INTO dbo.Supplier ([SupID], [SupName], [SupAddress], [SupTel]) VALUES (3, N'北京物资集团', N'北京市海淀区中关村88号', N'010-99887766');
INSERT INTO dbo.Supplier ([SupID], [SupName], [SupAddress], [SupTel]) VALUES (4, N'成都物流供应', N'成都市武侯区人民南路200号', N'028-55443322');
INSERT INTO dbo.Supplier ([SupID], [SupName], [SupAddress], [SupTel]) VALUES (5, N'南京化工供应', N'南京市鼓楼区中山路300号', N'025-44332211');
SET IDENTITY_INSERT dbo.Supplier OFF;
GO
GO

/* ---- Warehouse：5 行 ---- */
SET IDENTITY_INSERT dbo.Warehouse ON;
GO
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseType], [WarehouseSize], [WarehouseUsage]) VALUES (1, N'中央仓库', N'上海市宝山区宝杨路1000号', N'特种库', 8000, 3200);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseType], [WarehouseSize], [WarehouseUsage]) VALUES (2, N'冷藏仓库', N'上海市浦东新区冷链物流园', N'冷链库', 3000, 1800);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseType], [WarehouseSize], [WarehouseUsage]) VALUES (3, N'危险品仓库', N'上海市金山区化工园区', N'危化库', 2000, 800);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseType], [WarehouseSize], [WarehouseUsage]) VALUES (4, N'电子元器件库', N'深圳市南山区科技园', N'恒温库', 4000, 2500);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseType], [WarehouseSize], [WarehouseUsage]) VALUES (5, N'成品仓库', N'北京市通州区物流基地', N'常温库', 6000, 4200);
SET IDENTITY_INSERT dbo.Warehouse OFF;
GO
GO

/* ---- Item：11 行 ---- */
SET IDENTITY_INSERT dbo.Item ON;
GO
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (1, N'笔记本电脑', N'电子产品', 4399.00, 1);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (2, N'智能手机', N'电子产品', 3000.00, 1);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (3, N'工业电机', N'机械设备', 2800.00, 2);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (4, N'化工原料A', N'化工产品', 1200.00, 5);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (5, N'包装材料', N'包装材料', 80.00, 3);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (6, N'传感器', N'电子元件', 350.00, 4);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (7, N'冷冻食品', N'食品', 150.00, 2);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (8, N'润滑油', N'化工产品', 200.00, 5);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (9, N'办公桌椅', N'办公用品', 800.00, 3);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (10, N'LED显示屏', N'电子产品', 2500.00, 4);
INSERT INTO dbo.Item ([ItemID], [ItemName], [ItemType], [Price], [FactoryID]) VALUES (1001, N'乙醇', N'易燃易爆品', 50.00, 3);
SET IDENTITY_INSERT dbo.Item OFF;
GO
GO

/* ---- Staff：6 行 ---- */
SET IDENTITY_INSERT dbo.Staff ON;
GO
INSERT INTO dbo.Staff ([StaffID], [StaffName], [StaffTel], [IsActive]) VALUES (1, N'张三', N'13800138001', 1);
INSERT INTO dbo.Staff ([StaffID], [StaffName], [StaffTel], [IsActive]) VALUES (2, N'李四', N'13800138002', 1);
INSERT INTO dbo.Staff ([StaffID], [StaffName], [StaffTel], [IsActive]) VALUES (3, N'王五', N'13800138003', 0);
INSERT INTO dbo.Staff ([StaffID], [StaffName], [StaffTel], [IsActive]) VALUES (4, N'赵六', N'13800138004', 1);
INSERT INTO dbo.Staff ([StaffID], [StaffName], [StaffTel], [IsActive]) VALUES (5, N'孙七', N'13800138005', 1);
INSERT INTO dbo.Staff ([StaffID], [StaffName], [StaffTel], [IsActive]) VALUES (1001, N'演示员工01', N'000-00000000', 1);
SET IDENTITY_INSERT dbo.Staff OFF;
GO
GO

/* ---- StaffAssignment：17 行 ---- */
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1, 1, '2025-12-23T17:06:33');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1, 2, '2025-12-23T17:06:33');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1, 3, '2025-12-23T17:06:33');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1, 4, '2025-12-23T17:06:33');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1, 5, '2025-12-23T17:06:33');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (2, 2, '2025-12-23T17:06:45');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (2, 3, '2026-01-11T14:39:14');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (2, 5, '2026-01-11T14:39:14');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (4, 1, '2025-12-24T01:52:44');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (4, 3, '2026-01-11T17:00:04');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (5, 1, '2025-12-23T17:07:34');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (5, 5, '2025-12-23T17:07:34');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1001, 1, '2026-01-11T14:35:07');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1001, 2, '2026-01-11T14:35:07');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1001, 3, '2026-01-11T14:35:07');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1001, 4, '2026-01-11T14:35:07');
INSERT INTO dbo.StaffAssignment ([StaffID], [WarehouseID], [AssignDate]) VALUES (1001, 5, '2026-01-11T14:35:07');
GO

/* ---- Storage：28 行 ---- */
SET IDENTITY_INSERT dbo.Storage ON;
GO
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (12, 1, 1, 1, 34, '2025-12-24T02:21:44');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (13, 2, 1, 1, 0, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (14, 3, 2, 2, 10, '2026-01-11T17:55:00');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (15, 4, 3, 5, 139, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (16, 5, 4, 3, 323, '2025-12-24T02:05:16');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (17, 6, 4, 4, 271, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (18, 7, 2, 2, 150, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (19, 8, 3, 5, 10, '2025-12-23T15:14:14');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (20, 9, 5, 3, 110, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (21, 10, 5, 4, 45, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (22, 3, 4, 2, 45, '2026-01-03T17:07:03');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1002, 6, 4, 3, 68, '2025-12-23T14:37:43');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1003, 1001, 3, 5, 295, '2025-12-23T14:58:26');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1004, 7, 2, 4, 9, '2026-01-11T16:22:35');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1005, 5, 1, NULL, 14, '2025-12-23T16:12:06');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1006, 1, 1, 3, 12, '2026-01-11T16:07:33');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1007, 6, 1, NULL, 10, '2025-12-23T16:12:49');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1008, 2, 5, NULL, 75, '2026-01-11T16:23:18');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1009, 1, 5, 1, 83, '2025-12-23T17:13:09');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1010, 6, 1, 3, 33, '2025-12-24T02:00:13');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1011, 1, 1, 4, 0, '2025-12-24T02:20:19');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1012, 1, 1, NULL, 4, '2026-01-11T16:27:18');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1014, 2, 4, 3, 50, '2026-01-11T16:00:33');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1015, 7, 1, 4, 1, '2026-01-11T16:22:35');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1016, 6, 4, 2, 11, '2026-01-11T19:56:48');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1017, 8, 2, 2, 10, '2026-01-11T17:10:22');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1018, 2, 1, 3, 310, '2026-01-11T17:40:34');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [Storing], [LastUpdate]) VALUES (1019, 5, 5, NULL, 1, '2026-01-11T17:55:44');
SET IDENTITY_INSERT dbo.Storage OFF;
GO
GO

/* ---- Record：75 行 ---- */
SET IDENTITY_INSERT dbo.Record ON;
GO
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (0, 1, 1, 1, 1, '2025-12-12T23:45:47', N'入库', 100, N'新采购批次');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1, 1, 1, NULL, 2, '2025-12-17T23:45:47', N'出库', 50, N'客户订单001');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (2, 2, 1, 1, 1, '2025-12-14T23:45:47', N'入库', 150, N'新到货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3, 3, 2, 2, 3, '2025-12-07T23:45:47', N'入库', 40, N'工厂直送');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (4, 4, 3, 5, 4, '2025-12-02T23:45:47', N'入库', 250, N'化工原料');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (5, 4, 3, NULL, 4, '2025-12-19T23:45:47', N'出库', 50, N'生产线使用');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (6, 5, 4, 3, 5, '2025-12-10T23:45:47', N'入库', 600, N'包装材料');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (7, 6, 4, 4, 2, '2025-12-15T23:45:47', N'入库', 400, N'电子元件');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (8, 7, 2, 2, 3, '2025-12-13T23:45:47', N'入库', 200, N'冷冻食品');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (9, 9, 5, 3, 5, '2025-12-16T23:45:47', N'入库', 150, N'办公用品');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (10, 3, 4, 2, 2, '2025-12-22T23:49:08', N'入库', 30, N'加急物品');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1001, 6, 4, 3, 5, '2025-12-23T14:37:43', N'入库', 68, N'');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1002, 1001, 3, 5, 1, '2025-12-23T14:58:26', N'入库', 300, N'');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1006, 7, 2, 4, 1, '2025-12-23T15:08:13', N'入库', 50, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1008, 8, 3, 5, 1, '2025-12-23T15:14:14', N'出库', 70, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1011, 7, 2, 4, 1, '2025-12-23T15:22:55', N'出库', 20, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1013, 3, 2, NULL, 1, '2025-12-23T15:51:31', N'出库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1014, 3, 2, NULL, 1, '2025-12-23T15:51:37', N'出库', 2, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1015, 3, 2, 2, 1, '2025-12-23T15:51:54', N'出库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1016, 9, 5, NULL, 3, '2025-12-23T15:54:37', N'出库', 10, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1017, 4, 3, NULL, 1, '2025-12-23T15:55:18', N'出库', 50, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1018, 4, 3, NULL, 1, '2025-12-23T15:55:30', N'出库', 10, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1019, 10, 5, NULL, 1, '2025-12-23T15:55:54', N'出库', 15, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1020, 6, 4, NULL, 4, '2025-12-23T15:56:53', N'出库', 19, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1021, 5, 4, NULL, 1, '2025-12-23T16:12:06', N'出库', 30, N'库存转移-拨出');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1022, 5, 1, NULL, 1, '2025-12-23T16:12:06', N'入库', 30, N'库存转移-拨入');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1023, 1, 1, 3, 1, '2025-12-23T16:12:33', N'入库', 10, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1024, 6, 4, NULL, 1, '2025-12-23T16:12:49', N'出库', 10, N'库存转移-拨出');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1025, 6, 1, NULL, 1, '2025-12-23T16:12:49', N'入库', 10, N'库存转移-拨入');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1026, 2, 1, NULL, 1, '2025-12-23T16:13:37', N'出库', 10, N'库存转移-拨出');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1027, 2, 5, NULL, 1, '2025-12-23T16:13:37', N'入库', 10, N'库存转移-拨入');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1028, 1, 1, 1, 1, '2025-12-23T17:12:34', N'出库', 70, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1029, 1, 5, 1, 1, '2025-12-23T17:12:34', N'入库', 70, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1030, 1, 1, 1, 1, '2025-12-23T17:13:09', N'出库', 13, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1031, 1, 5, 1, 5, '2025-12-23T17:13:09', N'入库', 13, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1032, 1, 1, 1, 1, '2025-12-24T01:58:09', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1033, 1, 1, 1, 1, '2025-12-24T01:58:14', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1034, 2, 1, NULL, 1, '2025-12-24T01:58:41', N'出库', 5, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1035, 6, 1, 3, 1, '2025-12-24T02:00:13', N'入库', 33, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1036, 5, 4, 3, 1, '2025-12-24T02:05:06', N'出库', 50, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1037, 5, 4, 3, 1, '2025-12-24T02:05:08', N'出库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1038, 5, 4, 3, 1, '2025-12-24T02:05:16', N'出库', 96, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1039, 2, 1, NULL, 1, '2025-12-24T02:06:18', N'出库', 35, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1040, 2, 5, NULL, 1, '2025-12-24T02:06:18', N'入库', 35, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1041, 5, 1, NULL, 1, '2025-12-24T02:16:59', N'出库', 15, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1042, 1, 1, 4, 1, '2025-12-24T02:20:19', N'入库', 15, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1043, 1, 1, NULL, 1, '2025-12-24T02:20:53', N'出库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1044, 1, 1, NULL, 1, '2025-12-24T02:21:19', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1045, 1, 1, 1, 1, '2025-12-24T02:21:44', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (1046, 1, 1, NULL, 1, '2025-12-24T14:29:25', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (2046, 3, 2, 2, 1, '2026-01-03T17:06:47', N'出库', 10, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (2047, 3, 4, 2, 1, '2026-01-03T17:06:47', N'入库', 10, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (2048, 3, 2, 2, 1, '2026-01-03T17:07:03', N'出库', 5, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (2049, 3, 4, 2, 1001, '2026-01-03T17:07:03', N'入库', 5, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3049, 1, 1, NULL, 1, '2026-01-11T15:38:05', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3050, 2, 4, 3, 1, '2026-01-11T16:00:33', N'入库', 50, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3051, 1, 1, 3, 1, '2026-01-11T16:07:30', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3052, 1, 1, 3, 1, '2026-01-11T16:07:33', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3053, 7, 2, 4, 1001, '2026-01-11T16:22:35', N'出库', 1, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3054, 7, 1, 4, 1001, '2026-01-11T16:22:35', N'入库', 1, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3055, 2, 1, NULL, 1001, '2026-01-11T16:23:17', N'出库', 30, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3056, 2, 5, NULL, 1, '2026-01-11T16:23:18', N'入库', 30, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3057, 1, 1, NULL, 1, '2026-01-11T16:27:18', N'入库', 1, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3058, 6, 4, 2, 1, '2026-01-11T17:09:56', N'入库', 10, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3059, 8, 2, 2, 1, '2026-01-11T17:10:22', N'入库', 10, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3061, 1, 1, NULL, 4, '2026-01-11T17:22:54', N'出库', 50, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3062, 4, 3, NULL, NULL, '2026-01-11T17:25:55', N'出库', 1, N'常规出库');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3063, 1001, 3, NULL, 1001, '2026-01-11T17:37:45', N'出库', 5, N'出库登记');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3064, 2, 1, 3, 1001, '2026-01-11T17:40:34', N'入库', 600, NULL);
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3065, 2, 1, NULL, 1001, '2026-01-11T17:40:59', N'出库', 300, N'常规出库');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3066, 2, 1, NULL, 1, '2026-01-11T17:43:33', N'出库', 10, N'常规出库');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3067, 3, 2, 2, 5, '2026-01-11T17:55:00', N'出库', 1, N'常规出库(分摊)');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3068, 5, 1, NULL, 1, '2026-01-11T17:55:44', N'出库', 1, N'调拨-发货');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3069, 5, 5, NULL, 1, '2026-01-11T17:55:44', N'入库', 1, N'调拨-接收');
INSERT INTO dbo.Record ([RecordID], [ItemID], [WarehouseID], [SupplierID], [OperatorID], [OperationTime], [OperationType], [OperationQuantity], [Remarks]) VALUES (3070, 6, 4, 2, 1001, '2026-01-11T19:56:48', N'入库', 1, N'常规入库');
SET IDENTITY_INSERT dbo.Record OFF;
GO
GO

ENABLE TRIGGER dbo.Updating ON dbo.Record;
GO

ENABLE TRIGGER dbo.RecordAudit ON dbo.Record;
GO

ENABLE TRIGGER dbo.StaffAssignmentUpdating ON dbo.StaffAssignment;
GO
