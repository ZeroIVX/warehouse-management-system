# -*- coding: utf-8 -*-
"""
主数据访问：工厂、供应商、仓库、物品、员工。

这一层只负责"把 SQL 变成对象"，不含业务判断。
所有查询走参数化，所有表名/列名都是写死的常量 —— 不接收外部传入的标识符。
"""
from __future__ import annotations

import pandas as pd

from warehouse.db import engine

# --------------------------------------------------------------------------
# 通用下拉选项
# --------------------------------------------------------------------------

def options(sql: str) -> list[tuple]:
    """通用下拉数据源：返回 [(id, 显示名), ...]"""
    df = engine.fetch_df(sql)
    return list(zip(df.iloc[:, 0], df.iloc[:, 1])) if not df.empty else []


def factory_options() -> list[tuple]:
    return options("SELECT FactID, FactName FROM dbo.Factory ORDER BY FactName")


def supplier_options() -> list[tuple]:
    return options("SELECT SupID, SupName FROM dbo.Supplier ORDER BY SupName")


def warehouse_options() -> list[tuple]:
    return options("SELECT WarehouseID, WarehouseName FROM dbo.Warehouse ORDER BY WarehouseName")


def warehouse_type_options() -> list[tuple]:
    return options("SELECT TypeID, TypeName FROM dbo.WarehouseType ORDER BY TypeID")


def item_options() -> list[tuple]:
    """物品下拉：带上规格与厂家，便于区分同名物品"""
    return options("""
        SELECT i.ItemID,
               i.ItemName + N' [' + ISNULL(i.ItemType, N'—') + N'] - '
               + ISNULL(f.FactName, N'无厂家') + N' (ID:' + CAST(i.ItemID AS NVARCHAR) + N')'
        FROM dbo.Item i
                 LEFT JOIN dbo.Factory f ON i.FactoryID = f.FactID
        ORDER BY i.ItemName
    """)


def staff_options() -> list[tuple]:
    return options("SELECT StaffID, StaffName FROM dbo.Staff WHERE IsActive = 1 ORDER BY StaffName")


def staff_by_warehouse(warehouse_id: int) -> list[tuple]:
    """该仓库的在职员工 —— 出入库时的经办人候选"""
    df = engine.fetch_df("""
        SELECT s.StaffID, s.StaffName
        FROM dbo.StaffAssignment sa
                 INNER JOIN dbo.Staff s ON sa.StaffID = s.StaffID
        WHERE sa.WarehouseID = :wid AND s.IsActive = 1
        ORDER BY s.StaffName
    """, {"wid": warehouse_id})
    return list(zip(df.iloc[:, 0], df.iloc[:, 1])) if not df.empty else []


# --------------------------------------------------------------------------
# 列表查询
# --------------------------------------------------------------------------

def list_factories() -> pd.DataFrame:
    return engine.fetch_df('''
        SELECT FactID AS [编号], FactName AS [工厂名称],
               FactAddress AS [地址], FactTel AS [联系电话]
        FROM dbo.Factory ORDER BY FactID
    ''')


def list_suppliers() -> pd.DataFrame:
    return engine.fetch_df('''
        SELECT SupID AS [编号], SupName AS [供应商名称],
               SupAddress AS [地址], SupTel AS [联系电话]
        FROM dbo.Supplier ORDER BY SupID
    ''')


def list_warehouses() -> pd.DataFrame:
    return engine.fetch_df('''
        SELECT WarehouseID AS [编号], WarehouseName AS [仓库],
               WarehouseType AS [类型], WarehouseSize AS [库容],
               WarehouseUsage AS [已用], FreeSpace AS [剩余],
               CAST(UsagePercent AS DECIMAL(5,1)) AS [使用率%],
               BatchCount AS [批次数]
        FROM dbo.vw_WarehouseUtilization ORDER BY WarehouseID
    ''')


def list_items() -> pd.DataFrame:
    return engine.fetch_df("""
        SELECT i.ItemID AS [编号], i.ItemName AS [物品名称],
               i.ItemType AS [规格], i.Price AS [单价],
               ISNULL(f.FactName, N'（无厂家）') AS [生产厂家]
        FROM dbo.Item i
                 LEFT JOIN dbo.Factory f ON i.FactoryID = f.FactID
        ORDER BY i.ItemID
    """)


def list_staff_with_permission() -> pd.DataFrame:
    """一行一个（员工, 仓库）授权；未分配仓库的员工也会出现一行"""
    return engine.fetch_df("""
        SELECT StaffName AS [姓名], StaffTel AS [电话], StatusText AS [状态],
               ISNULL(WarehouseName, N'未分配') AS [授权仓库]
        FROM dbo.vw_StaffPermission
        ORDER BY StaffName, WarehouseName
    """)


def get_factory(fact_id: int) -> dict | None:
    df = engine.fetch_df("SELECT * FROM dbo.Factory WHERE FactID = :id", {"id": fact_id})
    return None if df.empty else df.iloc[0].to_dict()


def get_supplier(sup_id: int) -> dict | None:
    df = engine.fetch_df("SELECT * FROM dbo.Supplier WHERE SupID = :id", {"id": sup_id})
    return None if df.empty else df.iloc[0].to_dict()


def get_warehouse(warehouse_id: int) -> dict | None:
    df = engine.fetch_df("""
        SELECT WarehouseID, WarehouseName, WarehouseAddress, WarehouseTypeID,
               WarehouseSize, WarehouseUsage
        FROM dbo.Warehouse WHERE WarehouseID = :id
    """, {"id": warehouse_id})
    return None if df.empty else df.iloc[0].to_dict()


def get_item(item_id: int) -> dict | None:
    df = engine.fetch_df("SELECT * FROM dbo.Item WHERE ItemID = :id", {"id": item_id})
    return None if df.empty else df.iloc[0].to_dict()


def get_staff(staff_id: int) -> dict | None:
    df = engine.fetch_df("SELECT * FROM dbo.Staff WHERE StaffID = :id", {"id": staff_id})
    return None if df.empty else df.iloc[0].to_dict()


def staff_assigned_warehouses(staff_id: int) -> list[int]:
    df = engine.fetch_df(
        "SELECT WarehouseID FROM dbo.StaffAssignment WHERE StaffID = :id",
        {"id": staff_id},
    )
    return [int(x) for x in df["WarehouseID"].tolist()] if not df.empty else []


# --------------------------------------------------------------------------
# 写操作
# --------------------------------------------------------------------------

def insert_factory(name: str, address: str | None, tel: str | None) -> int:
    return engine.fetch_scalar("""
        INSERT INTO dbo.Factory (FactName, FactAddress, FactTel)
        OUTPUT INSERTED.FactID
        VALUES (:n, :a, :t)
    """, {"n": name, "a": address, "t": tel})


def update_factory(fact_id: int, name: str, address: str | None, tel: str | None) -> None:
    engine.execute("""
        UPDATE dbo.Factory SET FactName = :n, FactAddress = :a, FactTel = :t
        WHERE FactID = :id
    """, {"n": name, "a": address, "t": tel, "id": fact_id})


def delete_factory(fact_id: int) -> None:
    engine.execute("DELETE FROM dbo.Factory WHERE FactID = :id", {"id": fact_id})


def insert_supplier(name: str, address: str | None, tel: str | None) -> int:
    return engine.fetch_scalar("""
        INSERT INTO dbo.Supplier (SupName, SupAddress, SupTel)
        OUTPUT INSERTED.SupID
        VALUES (:n, :a, :t)
    """, {"n": name, "a": address, "t": tel})


def update_supplier(sup_id: int, name: str, address: str | None, tel: str | None) -> None:
    engine.execute("""
        UPDATE dbo.Supplier SET SupName = :n, SupAddress = :a, SupTel = :t
        WHERE SupID = :id
    """, {"n": name, "a": address, "t": tel, "id": sup_id})


def delete_supplier(sup_id: int) -> None:
    engine.execute("DELETE FROM dbo.Supplier WHERE SupID = :id", {"id": sup_id})


def insert_warehouse(name: str, type_id: int, size: int, address: str | None) -> int:
    return engine.fetch_scalar("""
        INSERT INTO dbo.Warehouse (WarehouseName, WarehouseTypeID, WarehouseSize, WarehouseAddress)
        OUTPUT INSERTED.WarehouseID
        VALUES (:n, :tid, :s, :a)
    """, {"n": name, "tid": type_id, "s": size, "a": address})


def update_warehouse(warehouse_id: int, name: str, type_id: int, size: int, address: str | None) -> None:
    engine.execute("""
        UPDATE dbo.Warehouse
        SET WarehouseName = :n, WarehouseTypeID = :tid, WarehouseSize = :s, WarehouseAddress = :a
        WHERE WarehouseID = :id
    """, {"n": name, "tid": type_id, "s": size, "a": address, "id": warehouse_id})


def delete_warehouse(warehouse_id: int) -> None:
    engine.execute("DELETE FROM dbo.Warehouse WHERE WarehouseID = :id", {"id": warehouse_id})


def insert_item(name: str, item_type: str | None, price: float, factory_id: int | None) -> int:
    return engine.fetch_scalar("""
        INSERT INTO dbo.Item (ItemName, ItemType, Price, FactoryID)
        OUTPUT INSERTED.ItemID
        VALUES (:n, :t, :p, :f)
    """, {"n": name, "t": item_type, "p": price, "f": factory_id})


def update_item(item_id: int, name: str, item_type: str | None, price: float, factory_id: int | None) -> None:
    engine.execute("""
        UPDATE dbo.Item SET ItemName = :n, ItemType = :t, Price = :p, FactoryID = :f
        WHERE ItemID = :id
    """, {"n": name, "t": item_type, "p": price, "f": factory_id, "id": item_id})


def delete_item(item_id: int) -> None:
    engine.execute("DELETE FROM dbo.Item WHERE ItemID = :id", {"id": item_id})


def insert_staff(name: str, tel: str | None, is_active: bool) -> int:
    return engine.fetch_scalar("""
        INSERT INTO dbo.Staff (StaffName, StaffTel, IsActive)
        OUTPUT INSERTED.StaffID
        VALUES (:n, :t, :a)
    """, {"n": name, "t": tel, "a": 1 if is_active else 0})


def update_staff(staff_id: int, name: str, tel: str | None, is_active: bool) -> None:
    engine.execute("""
        UPDATE dbo.Staff SET StaffName = :n, StaffTel = :t, IsActive = :a
        WHERE StaffID = :id
    """, {"n": name, "t": tel, "a": 1 if is_active else 0, "id": staff_id})


def replace_assignments(staff_id: int, warehouse_ids: list[int]) -> None:
    """
    覆盖式更新员工权限：先删旧授权再写新授权。

    两条语句必须同一事务 —— 原版是两次独立 commit，中间失败会导致
    员工权限全部丢失。这里用 SQLAlchemy 的 begin() 包住。
    """
    from sqlalchemy import text

    with engine.get_engine().begin() as conn:
        conn.execute(text("DELETE FROM dbo.StaffAssignment WHERE StaffID = :id"),
                     {"id": staff_id})
        for wid in warehouse_ids:
            conn.execute(
                text("INSERT INTO dbo.StaffAssignment (StaffID, WarehouseID) VALUES (:s, :w)"),
                {"s": staff_id, "w": wid},
            )


def warehouse_type_name(type_id: int) -> str | None:
    return engine.fetch_scalar(
        "SELECT TypeName FROM dbo.WarehouseType WHERE TypeID = :id", {"id": type_id}
    )
