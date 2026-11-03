/* ============================================================================
   06 初始化数据（自包含）
   ----------------------------------------------------------------------------
   提供主数据、库区货位与库存批次，保证从零建库后即可进入作业页面。
   全部为构造的示例数据，不含任何真实企业或个人信息。

   说明：
     1. StaffAssignment 上的 TR_Assignment_Audit 会为每条授权写审计，
        初始化阶段禁用，避免把建库动作混进业务审计。
     2. Storage 上的 TR_Storage_SyncUsage 保留启用 —— 仓库使用量由触发器
        按实际库存重算，正好完成初始化的一部分。
     3. 单据与历史流水分别由 07_demo_data.sql / 08_demo_orders.sql 生成。
   ============================================================================ */
USE WarehouseDB_V2;
GO
SET NOCOUNT ON;
GO

DISABLE TRIGGER dbo.TR_Assignment_Audit ON dbo.StaffAssignment;
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

GO

/* ---- Warehouse：5 行 ---- */
SET IDENTITY_INSERT dbo.Warehouse ON;
GO
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseTypeID], [WarehouseSize], [WarehouseUsage]) VALUES (1, N'中央仓库', N'上海市宝山区宝杨路1000号', 5, 8000, 708);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseTypeID], [WarehouseSize], [WarehouseUsage]) VALUES (2, N'冷藏仓库', N'上海市浦东新区冷链物流园', 2, 3000, 309);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseTypeID], [WarehouseSize], [WarehouseUsage]) VALUES (3, N'危险品仓库', N'上海市金山区化工园区', 4, 2000, 683);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseTypeID], [WarehouseSize], [WarehouseUsage]) VALUES (4, N'电子元器件库', N'深圳市南山区科技园', 3, 4000, 868);
INSERT INTO dbo.Warehouse ([WarehouseID], [WarehouseName], [WarehouseAddress], [WarehouseTypeID], [WarehouseSize], [WarehouseUsage]) VALUES (5, N'成品仓库', N'北京市通州区物流基地', 1, 6000, 581);
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

/* ---- Customer：4 行 ---- */
SET IDENTITY_INSERT dbo.Customer ON;
GO
INSERT INTO dbo.Customer ([CustomerID], [CustomerName], [Contact], [Phone], [Address]) VALUES (1, N'华联超市', N'王经理', N'021-58881234', N'上海市浦东新区世纪大道 100 号');
INSERT INTO dbo.Customer ([CustomerID], [CustomerName], [Contact], [Phone], [Address]) VALUES (2, N'京东物流华东仓', N'李主管', N'021-67890123', N'上海市青浦区华徐公路 888 号');
INSERT INTO dbo.Customer ([CustomerID], [CustomerName], [Contact], [Phone], [Address]) VALUES (3, N'永辉超市', N'张采购', N'0591-88886666', N'福建省福州市鼓楼区五四路 1 号');
INSERT INTO dbo.Customer ([CustomerID], [CustomerName], [Contact], [Phone], [Address]) VALUES (4, N'盒马鲜生', N'陈店长', N'021-55667788', N'上海市杨浦区淞沪路 77 号');
SET IDENTITY_INSERT dbo.Customer OFF;
GO
GO

/* ---- WarehouseZone：15 行 ---- */
SET IDENTITY_INSERT dbo.WarehouseZone ON;
GO
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (1, 5, N'A', N'存储区A', N'存储区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (2, 5, N'B', N'拣选区B', N'拣选区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (3, 5, N'QC', N'待检区', N'待检区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (4, 4, N'A', N'存储区A', N'存储区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (5, 4, N'B', N'拣选区B', N'拣选区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (6, 4, N'QC', N'待检区', N'待检区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (7, 2, N'A', N'存储区A', N'存储区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (8, 2, N'B', N'拣选区B', N'拣选区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (9, 2, N'QC', N'待检区', N'待检区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (10, 3, N'A', N'存储区A', N'存储区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (11, 3, N'B', N'拣选区B', N'拣选区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (12, 3, N'QC', N'待检区', N'待检区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (13, 1, N'A', N'存储区A', N'存储区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (14, 1, N'B', N'拣选区B', N'拣选区');
INSERT INTO dbo.WarehouseZone ([ZoneID], [WarehouseID], [ZoneCode], [ZoneName], [ZoneType]) VALUES (15, 1, N'QC', N'待检区', N'待检区');
SET IDENTITY_INSERT dbo.WarehouseZone OFF;
GO
GO

/* ---- StorageLocation：70 行 ---- */
SET IDENTITY_INSERT dbo.StorageLocation ON;
GO
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (1, 1, N'A-01', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (2, 1, N'A-02', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (3, 1, N'A-03', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (4, 1, N'A-04', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (5, 1, N'A-05', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (6, 1, N'A-06', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (7, 1, N'A-07', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (8, 1, N'A-08', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (9, 2, N'B-01', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (10, 2, N'B-02', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (11, 2, N'B-03', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (12, 2, N'B-04', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (13, 3, N'QC-01', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (14, 3, N'QC-02', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (15, 4, N'A-01', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (16, 4, N'A-02', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (17, 4, N'A-03', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (18, 4, N'A-04', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (19, 4, N'A-05', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (20, 4, N'A-06', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (21, 4, N'A-07', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (22, 4, N'A-08', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (23, 5, N'B-01', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (24, 5, N'B-02', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (25, 5, N'B-03', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (26, 5, N'B-04', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (27, 6, N'QC-01', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (28, 6, N'QC-02', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (29, 7, N'A-01', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (30, 7, N'A-02', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (31, 7, N'A-03', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (32, 7, N'A-04', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (33, 7, N'A-05', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (34, 7, N'A-06', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (35, 7, N'A-07', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (36, 7, N'A-08', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (37, 8, N'B-01', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (38, 8, N'B-02', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (39, 8, N'B-03', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (40, 8, N'B-04', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (41, 9, N'QC-01', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (42, 9, N'QC-02', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (43, 10, N'A-01', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (44, 10, N'A-02', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (45, 10, N'A-03', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (46, 10, N'A-04', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (47, 10, N'A-05', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (48, 10, N'A-06', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (49, 10, N'A-07', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (50, 10, N'A-08', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (51, 11, N'B-01', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (52, 11, N'B-02', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (53, 11, N'B-03', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (54, 11, N'B-04', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (55, 12, N'QC-01', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (56, 12, N'QC-02', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (57, 13, N'A-01', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (58, 13, N'A-02', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (59, 13, N'A-03', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (60, 13, N'A-04', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (61, 13, N'A-05', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (62, 13, N'A-06', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (63, 13, N'A-07', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (64, 13, N'A-08', 2000, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (65, 14, N'B-01', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (66, 14, N'B-02', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (67, 14, N'B-03', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (68, 14, N'B-04', 500, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (69, 15, N'QC-01', 200, 0);
INSERT INTO dbo.StorageLocation ([LocationID], [ZoneID], [LocationCode], [Capacity], [IsLocked]) VALUES (70, 15, N'QC-02', 200, 0);
SET IDENTITY_INSERT dbo.StorageLocation OFF;
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

/* ---- Storage：137 行 ---- */
SET IDENTITY_INSERT dbo.Storage ON;
GO
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (12, 1, 1, 1, 57, N'B20251224-012', NULL, NULL, 3, '2026-10-28T13:28:03');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (13, 2, 1, 1, 58, N'B20251222-013', NULL, NULL, 0, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (14, 3, 2, 2, 29, N'B20260111-014', NULL, NULL, 10, '2026-01-11T17:55:00');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (15, 4, 3, 5, 43, N'B20251222-015', '2025-10-23', '2026-06-20', 139, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (16, 5, 4, 3, 15, N'B20251224-016', NULL, NULL, 323, '2025-12-24T02:05:16');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (17, 6, 4, 4, 16, N'B20251222-017', NULL, NULL, 271, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (18, 7, 2, 2, 30, N'B20251222-018', '2025-10-23', '2026-06-20', 141, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (19, 8, 3, 5, 44, N'B20251223-019', '2025-10-24', '2026-06-21', 10, '2025-12-23T15:14:14');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (20, 9, 5, 3, 1, N'B20251222-020', NULL, NULL, 110, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (21, 10, 5, 4, 2, N'B20251222-021', NULL, NULL, 45, '2025-12-22T23:45:47');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (22, 3, 4, 2, 17, N'B20260103-022', NULL, NULL, 45, '2026-01-03T17:07:03');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1002, 6, 4, 3, 18, N'B20251223-002', NULL, NULL, 68, '2025-12-23T14:37:43');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1003, 1001, 3, 5, 45, N'B20251223-003', '2025-10-24', '2026-06-21', 295, '2025-12-23T14:58:26');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1004, 7, 2, 4, 31, N'B20260111-004', '2025-11-12', '2026-07-10', 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1005, 5, 1, NULL, 59, N'B20251223-005', NULL, NULL, 14, '2025-12-23T16:12:06');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1006, 1, 1, 3, 60, N'B20260111-006', NULL, NULL, 7, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1007, 6, 1, NULL, 61, N'B20251223-007', NULL, NULL, 10, '2025-12-23T16:12:49');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1008, 2, 5, NULL, 3, N'B20260111-008', NULL, NULL, 75, '2026-01-11T16:23:18');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1009, 1, 5, 1, 4, N'B20251223-009', NULL, NULL, 74, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1010, 6, 1, 3, 62, N'B20251224-010', NULL, NULL, 33, '2025-12-24T02:00:13');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1011, 1, 1, 4, 63, N'B20251224-011', NULL, NULL, 0, '2025-12-24T02:20:19');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1012, 1, 1, NULL, 64, N'B20260111-012', NULL, NULL, 4, '2026-01-11T16:27:18');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1014, 2, 4, 3, 19, N'B20260111-014', NULL, NULL, 50, '2026-01-11T16:00:33');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1015, 7, 1, 4, 57, N'B20260111-015', '2025-11-12', '2026-07-10', 1, '2026-01-11T16:22:35');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1016, 6, 4, 2, 20, N'B20260111-016', NULL, NULL, 11, '2026-01-11T19:56:48');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1017, 8, 2, 2, 32, N'B20260111-017', '2025-11-12', '2026-07-10', 10, '2026-01-11T17:10:22');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1018, 2, 1, 3, 58, N'B20260111-018', NULL, NULL, 310, '2026-01-11T17:40:34');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1019, 5, 5, NULL, 5, N'B20260111-019', NULL, NULL, 1, '2026-01-11T17:55:44');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1020, 4, 1, 3, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:01');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1021, 6, 4, 4, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1022, 5, 5, 4, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1023, 1, 2, 1, NULL, NULL, NULL, NULL, 15, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1024, 1, 3, 1, NULL, NULL, NULL, NULL, 19, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1025, 1001, 5, 1, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1026, 6, 1, 5, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1027, 6, 3, 2, NULL, NULL, NULL, NULL, 21, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1028, 1001, 5, 2, NULL, NULL, NULL, NULL, 13, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1029, 7, 4, 4, NULL, NULL, NULL, NULL, 15, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1030, 1001, 1, 1, NULL, NULL, NULL, NULL, 42, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1031, 1, 2, 3, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1032, 10, 4, 2, NULL, NULL, NULL, NULL, 4, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1033, 5, 2, 3, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1034, 9, 5, 1, NULL, NULL, NULL, NULL, 13, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1035, 10, 1, 1, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1036, 3, 3, 4, NULL, NULL, NULL, NULL, 15, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1037, 7, 5, 1, NULL, NULL, NULL, NULL, 4, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1038, 1, 1, 5, NULL, NULL, NULL, NULL, 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1039, 6, 2, 5, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1040, 10, 4, 4, NULL, NULL, NULL, NULL, 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1041, 2, 5, 3, NULL, NULL, NULL, NULL, 3, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1042, 2, 5, 5, NULL, NULL, NULL, NULL, 15, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1043, 4, 3, 4, NULL, NULL, NULL, NULL, 9, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1044, 9, 1, 3, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1045, 1001, 3, 2, NULL, NULL, NULL, NULL, 23, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1046, 1001, 5, 5, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1047, 4, 4, 4, NULL, NULL, NULL, NULL, 7, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1048, 3, 2, 2, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1049, 9, 3, 5, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1050, 7, 2, 1, NULL, NULL, NULL, NULL, 7, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1051, 3, 5, 1, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1052, 10, 3, 3, NULL, NULL, NULL, NULL, 14, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1053, 9, 1, 1, NULL, NULL, NULL, NULL, 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1054, 7, 1, 1, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1055, 6, 4, 5, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1056, 10, 5, 2, NULL, NULL, NULL, NULL, 14, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1057, 1, 2, 4, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1058, 2, 3, 3, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1059, 4, 1, 1, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1060, 3, 1, 5, NULL, NULL, NULL, NULL, 22, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1061, 4, 5, 2, NULL, NULL, NULL, NULL, 9, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1062, 8, 1, 4, NULL, NULL, NULL, NULL, 25, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1063, 9, 3, 2, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1064, 1001, 4, 5, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1065, 8, 2, 2, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1066, 8, 3, 4, NULL, NULL, NULL, NULL, 23, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1067, 1, 3, 4, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1068, 9, 1, 2, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1069, 2, 1, 3, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1070, 1001, 2, 4, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1071, 1, 4, 3, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1072, 9, 5, 4, NULL, NULL, NULL, NULL, 3, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1073, 10, 3, 2, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1074, 4, 4, 1, NULL, NULL, NULL, NULL, 3, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1075, 7, 5, 5, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1076, 1001, 1, 4, NULL, NULL, NULL, NULL, 4, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1077, 10, 3, 4, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1078, 6, 1, 1, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1079, 5, 1, 5, NULL, NULL, NULL, NULL, 3, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1080, 10, 2, 2, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1081, 4, 4, 2, NULL, NULL, NULL, NULL, 6, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1082, 2, 5, 4, NULL, NULL, NULL, NULL, 9, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1083, 8, 1, 3, NULL, NULL, NULL, NULL, 14, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1084, 6, 3, 3, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1085, 10, 2, 1, NULL, NULL, NULL, NULL, 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1086, 1, 3, 5, NULL, NULL, NULL, NULL, 4, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1087, 6, 5, 2, NULL, NULL, NULL, NULL, 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1088, 1001, 2, 2, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1089, 9, 4, 4, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1090, 10, 2, 4, NULL, NULL, NULL, NULL, 7, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1091, 1, 4, 2, NULL, NULL, NULL, NULL, 3, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1092, 3, 5, 4, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1093, 8, 3, 5, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1094, 1001, 1, 3, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1095, 9, 4, 2, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1096, 5, 3, 3, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1097, 8, 5, 5, NULL, NULL, NULL, NULL, 21, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1098, 8, 2, 3, NULL, NULL, NULL, NULL, 7, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1099, 2, 3, 5, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1100, 2, 3, 1, NULL, NULL, NULL, NULL, 4, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1101, 1001, 2, 5, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1102, 6, 3, 5, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1103, 4, 4, 3, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1104, 5, 1, 1, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1105, 2, 5, 2, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1106, 1, 2, 2, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1107, 5, 5, 3, NULL, NULL, NULL, NULL, 3, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1108, 8, 3, 2, NULL, NULL, NULL, NULL, 9, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1109, 4, 4, 5, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1110, 5, 2, 2, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1111, 2, 2, 1, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1112, 3, 4, 3, NULL, NULL, NULL, NULL, 8, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1113, 3, 5, 3, NULL, NULL, NULL, NULL, 9, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1114, 10, 1, 4, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1115, 1001, 3, 3, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1116, 2, 1, 4, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1117, 8, 5, 3, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1118, 5, 1, 2, NULL, NULL, NULL, NULL, 1, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1119, 7, 5, 4, NULL, NULL, NULL, NULL, 5, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1120, 2, 5, 1, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1121, 7, 1, 4, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1122, 10, 1, 5, NULL, NULL, NULL, NULL, 2, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1123, 3, 1, 2, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1124, 8, 2, 1, NULL, NULL, NULL, NULL, 11, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1125, 2, 3, 4, NULL, NULL, NULL, NULL, 12, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1126, 1, 1, 1, NULL, NULL, NULL, NULL, 80, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1127, 1, 5, 5, NULL, NULL, NULL, NULL, 70, '2026-10-28T13:28:02');
INSERT INTO dbo.Storage ([StorageID], [ItemID], [WarehouseID], [SupplierID], [LocationID], [BatchNo], [ProductionDate], [ExpiryDate], [Storing], [LastUpdate]) VALUES (1128, 1, 5, NULL, NULL, NULL, NULL, NULL, 10, '2026-10-28T13:28:03');
SET IDENTITY_INSERT dbo.Storage OFF;
GO
GO


/* ----------------------------------------------------------------------------
   上架：把没有库位的批次摊到各仓库的存储区货位
   初始化数据保留的是库存数量，库位属于作业结果，这里按顺序补一次。
   ---------------------------------------------------------------------------- */
WITH locs AS (
    SELECT l.LocationID,
           z.WarehouseID,
           ROW_NUMBER() OVER (PARTITION BY z.WarehouseID ORDER BY l.LocationID) AS rn,
           COUNT(*) OVER (PARTITION BY z.WarehouseID)                          AS cnt
    FROM dbo.StorageLocation l
             INNER JOIN dbo.WarehouseZone z ON l.ZoneID = z.ZoneID
    WHERE z.ZoneType = N'存储区'
),
ranked AS (
    SELECT StorageID, WarehouseID,
           ROW_NUMBER() OVER (PARTITION BY WarehouseID ORDER BY StorageID) AS rn
    FROM dbo.Storage
)
UPDATE s
SET s.LocationID = l.LocationID
FROM dbo.Storage s
         INNER JOIN ranked r ON s.StorageID = r.StorageID
         INNER JOIN locs l ON l.WarehouseID = r.WarehouseID AND l.rn = ((r.rn - 1) % l.cnt) + 1
WHERE s.LocationID IS NULL;
GO

/* 批次号：B + 入库日期 + 三位流水，便于人工核对 */
UPDATE dbo.Storage
SET BatchNo = CONCAT('B', FORMAT(LastUpdate, 'yyyyMMdd'), '-', RIGHT('000' + CAST(StorageID AS VARCHAR(10)), 3))
WHERE BatchNo IS NULL;
GO

/* 有保质期概念的品类补上生产/失效日期，其余品类留空（不适用效期管理） */
UPDATE s
SET ProductionDate = DATEADD(day, -60, CAST(s.LastUpdate AS DATE)),
    ExpiryDate     = DATEADD(day, 180, CAST(s.LastUpdate AS DATE))
FROM dbo.Storage s
         INNER JOIN dbo.Item i ON s.ItemID = i.ItemID
WHERE s.ExpiryDate IS NULL
  AND (i.ItemType LIKE N'%食品%' OR i.ItemType LIKE N'%化工%'
    OR i.ItemType LIKE N'%易燃%' OR i.ItemType LIKE N'%医药%');
GO

/* 兜底重算：仓库使用量恒等于库存之和 */
EXEC dbo.sp_RecalcWarehouseUsage;
GO

ENABLE TRIGGER dbo.TR_Assignment_Audit ON dbo.StaffAssignment;
GO
