# -*- coding: utf-8 -*-
"""
出入库与调拨 —— 唯一写流水的地方。

业务规则不在这里实现，而是调用数据库里的存储过程：
校验、加锁、写流水、触发器同步库存、审计落库，全部在一个事务里完成。
Python 侧只负责把参数递进去、把错误翻译成人话。
"""
from __future__ import annotations

from warehouse.db import engine


def post_inbound(item_id: int, warehouse_id: int, supplier_id: int | None,
                 staff_id: int, quantity: int, remarks: str | None = None) -> int:
    """入库。返回新流水的 RecordID。"""
    result = engine.call_procedure("sp_PostOperation", [
        ("ItemID", item_id),
        ("WarehouseID", warehouse_id),
        ("SupplierID", supplier_id),
        ("OperatorID", staff_id),
        ("OperationType", "入库"),
        ("Quantity", quantity),
        ("Remarks", remarks),
    ])
    return int(result.get("RecordID") or 0)


def post_outbound(item_id: int, warehouse_id: int, supplier_id: int | None,
                  staff_id: int, quantity: int, remarks: str | None = None) -> int:
    """出库。库存不足时由存储过程抛 50004，调用方捕获后提示用户。"""
    result = engine.call_procedure("sp_PostOperation", [
        ("ItemID", item_id),
        ("WarehouseID", warehouse_id),
        ("SupplierID", supplier_id),
        ("OperatorID", staff_id),
        ("OperationType", "出库"),
        ("Quantity", quantity),
        ("Remarks", remarks),
    ])
    return int(result.get("RecordID") or 0)


def transfer(item_id: int, src_warehouse_id: int, dst_warehouse_id: int,
             supplier_id: int | None, quantity: int,
             out_staff_id: int, in_staff_id: int,
             remarks: str | None = None) -> str:
    """
    跨仓库调拨。返回调拨组号。

    两条流水（调拨出 / 调拨入）共用同一个 GroupID，
    任一环节失败整体回滚，不会出现"货扣了但没到账"。
    """
    result = engine.call_procedure("sp_TransferStock", [
        ("ItemID", item_id),
        ("SrcWarehouseID", src_warehouse_id),
        ("DstWarehouseID", dst_warehouse_id),
        ("SupplierID", supplier_id),
        ("Quantity", quantity),
        ("OutOperatorID", out_staff_id),
        ("InOperatorID", in_staff_id),
        ("Remarks", remarks),
    ])
    return str(result.get("TransferGroupID") or "")
