# -*- coding: utf-8 -*-
"""
出入库用例。

UI 只跟这一层打交道，拿到的永远是 OperationResult，不用关心底下是
存储过程还是触发器、错误码是 50004 还是 50005。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from warehouse.db import errors
from warehouse.repository import operation, stock


@dataclass
class OperationResult:
    ok: bool
    message: str
    record_id: int = 0
    group_id: str = ""
    detail: str = ""
    error: Exception | None = field(default=None, repr=False)


def _fail(exc: Exception) -> OperationResult:
    return OperationResult(ok=False, message=str(exc), detail=type(exc).__name__, error=exc)


def inbound(item_id: int | None, warehouse_id: int | None, supplier_id: int | None,
            staff_id: int | None, quantity: int, remarks: str | None = None) -> OperationResult:
    if not item_id:
        return OperationResult(False, "请选择物品")
    if not warehouse_id:
        return OperationResult(False, "请选择目标仓库")
    if not staff_id:
        return OperationResult(False, "请选择经办人（该仓库需要有在职员工）")
    if not quantity or quantity <= 0:
        return OperationResult(False, "入库数量必须大于 0")

    try:
        rid = operation.post_inbound(item_id, warehouse_id, supplier_id,
                                     staff_id, quantity, remarks)
        return OperationResult(True, f"入库成功，流水号 {rid}", record_id=rid)
    except errors.DomainError as exc:
        return _fail(exc)


def outbound(item_id: int | None, warehouse_id: int | None, supplier_id: int | None,
             staff_id: int | None, quantity: int, remarks: str | None = None) -> OperationResult:
    if not item_id:
        return OperationResult(False, "请选择物品")
    if not warehouse_id:
        return OperationResult(False, "请选择出货仓库")
    if not staff_id:
        return OperationResult(False, "请选择经办人")
    if not quantity or quantity <= 0:
        return OperationResult(False, "出库数量必须大于 0")

    # 先查一次余量，只为了让报错信息更具体（真正的并发防护在存储过程里）
    available = stock.available_qty(item_id, warehouse_id, supplier_id)
    if quantity > available:
        return OperationResult(False, f"库存不足：当前可用 {available}，本次申请 {quantity}")

    try:
        rid = operation.post_outbound(item_id, warehouse_id, supplier_id,
                                      staff_id, quantity, remarks)
        return OperationResult(True, f"出库成功，流水号 {rid}", record_id=rid)
    except errors.DomainError as exc:
        return _fail(exc)


def transfer(item_id: int | None, src_warehouse_id: int | None, dst_warehouse_id: int | None,
             supplier_id: int | None, quantity: int,
             out_staff_id: int | None, in_staff_id: int | None,
             remarks: str | None = None) -> OperationResult:
    if not item_id:
        return OperationResult(False, "请选择物品")
    if not src_warehouse_id or not dst_warehouse_id:
        return OperationResult(False, "请选择源仓库与目标仓库")
    if src_warehouse_id == dst_warehouse_id:
        return OperationResult(False, "源仓库与目标仓库不能相同")
    if not out_staff_id or not in_staff_id:
        return OperationResult(False, "发货人与收货人都必须选择")
    if not quantity or quantity <= 0:
        return OperationResult(False, "调拨数量必须大于 0")

    available = stock.available_qty(item_id, src_warehouse_id, supplier_id)
    if quantity > available:
        return OperationResult(False, f"源仓库库存不足：可用 {available}，本次申请 {quantity}")

    try:
        gid = operation.transfer(item_id, src_warehouse_id, dst_warehouse_id,
                                 supplier_id, quantity, out_staff_id, in_staff_id, remarks)
        return OperationResult(True, "调拨完成，两条流水已配对入账", group_id=gid)
    except errors.DomainError as exc:
        return _fail(exc)
