# -*- coding: utf-8 -*-
"""
单据作业用例：建单、收货、发货、盘点。

界面只调这一层，拿到的永远是 OperationResult。
真正的业务校验在存储过程里，这里只做"明显不合法就别发请求"的前置拦截，
以及把数据库错误翻译成人话。
"""
from __future__ import annotations

from warehouse.db import errors
from warehouse.repository import orders
from warehouse.service.inventory import OperationResult


def _fail(exc: Exception) -> OperationResult:
    return OperationResult(False, str(exc), error=exc)


def _need(cond: bool, msg: str) -> OperationResult | None:
    return None if cond else OperationResult(False, msg)


# ---------------------------------------------------------------- 入库单
def create_inbound_order(order_type: str, warehouse_id, supplier_id,
                         expected, remark, lines: list[dict]) -> OperationResult:
    if not warehouse_id:
        return OperationResult(False, "请选择收货仓库")
    if not lines:
        return OperationResult(False, "至少添加一行明细")

    for i, ln in enumerate(lines, start=1):
        if not ln.get("item_id"):
            return OperationResult(False, f"第 {i} 行未选择物品")
        if not ln.get("qty") or int(ln["qty"]) <= 0:
            return OperationResult(False, f"第 {i} 行数量必须大于 0")

    try:
        oid = orders.create_inbound(order_type, warehouse_id, supplier_id,
                                    expected, remark, lines)
        return OperationResult(True, f"入库单已创建（ID {oid}），可开始收货", record_id=oid)
    except errors.DomainError as exc:
        return _fail(exc)


def receive(line_id, qty, location_id, batch_no, production_date,
            expiry_date, operator_id) -> OperationResult:
    if not line_id:
        return OperationResult(False, "请选择要收货的明细行")
    if not operator_id:
        return OperationResult(False, "请选择经办人（该仓库需要有在职员工）")
    if not qty or int(qty) <= 0:
        return OperationResult(False, "收货数量必须大于 0")
    if production_date and expiry_date and expiry_date <= production_date:
        return OperationResult(False, "失效日期必须晚于生产日期")

    try:
        rid = orders.receive_line(line_id, int(qty), location_id,
                                  batch_no or None, production_date, expiry_date, operator_id)
        return OperationResult(True, f"收货成功，流水号 {rid}", record_id=rid)
    except errors.DomainError as exc:
        return _fail(exc)


# ---------------------------------------------------------------- 出库单
def create_outbound_order(order_type: str, warehouse_id, customer_id,
                          required, remark, lines: list[dict]) -> OperationResult:
    if not warehouse_id:
        return OperationResult(False, "请选择发货仓库")
    if not lines:
        return OperationResult(False, "至少添加一行明细")
    if order_type == "销售出库" and not customer_id:
        return OperationResult(False, "销售出库需要选择客户")

    for i, ln in enumerate(lines, start=1):
        if not ln.get("item_id"):
            return OperationResult(False, f"第 {i} 行未选择物品")
        if not ln.get("qty") or int(ln["qty"]) <= 0:
            return OperationResult(False, f"第 {i} 行数量必须大于 0")

    try:
        oid = orders.create_outbound(order_type, warehouse_id, customer_id,
                                     required, remark, lines)
        return OperationResult(True, f"出库单已创建（ID {oid}），可开始发货", record_id=oid)
    except errors.DomainError as exc:
        return _fail(exc)


def ship(line_id, qty, operator_id) -> OperationResult:
    if not line_id:
        return OperationResult(False, "请选择要发货的明细行")
    if not operator_id:
        return OperationResult(False, "请选择经办人")
    if not qty or int(qty) <= 0:
        return OperationResult(False, "发货数量必须大于 0")

    try:
        rid = orders.ship_line(line_id, int(qty), operator_id)
        return OperationResult(True, f"发货成功，库存已按先到期先出扣减（流水 {rid}）", record_id=rid)
    except errors.DomainError as exc:
        return _fail(exc)


# ---------------------------------------------------------------- 盘点
def create_stocktake(warehouse_id, zone_id, remark) -> OperationResult:
    if not warehouse_id:
        return OperationResult(False, "请选择要盘点的仓库")
    try:
        sid = orders.create_stocktake(warehouse_id, zone_id, remark)
        lines = orders.stocktake_lines(sid)
        if lines.empty:
            return OperationResult(False, "该范围内没有库存，无需盘点", record_id=sid)
        return OperationResult(True, f"盘点单已生成，共 {len(lines)} 行待盘", record_id=sid)
    except errors.DomainError as exc:
        return _fail(exc)


def complete(stocktake_id, operator_id) -> OperationResult:
    if not stocktake_id:
        return OperationResult(False, "请选择盘点单")
    if not operator_id:
        return OperationResult(False, "请选择盘点人")
    try:
        n = orders.complete_stocktake(stocktake_id, operator_id)
        if n == 0:
            return OperationResult(True, "盘点结案，账实相符，未产生调整")
        return OperationResult(True, f"盘点结案，已生成 {n} 条盘盈/盘亏流水")
    except errors.DomainError as exc:
        return _fail(exc)

# ---------------------------------------------------------------- 调拨单
def create_transfer_order(src_id, dst_id, src_op, dst_op, remark,
                          lines: list[dict]) -> OperationResult:
    if not src_id or not dst_id:
        return OperationResult(False, "请选择源仓库与目标仓库")
    if src_id == dst_id:
        return OperationResult(False, "源仓库与目标仓库不能相同")
    if not src_op or not dst_op:
        return OperationResult(False, "发货人与收货人都必须选择")
    if not lines:
        return OperationResult(False, "至少添加一行明细")

    for i, ln in enumerate(lines, start=1):
        if not ln.get("item_id"):
            return OperationResult(False, f"第 {i} 行未选择物品")
        if not ln.get("qty") or int(ln["qty"]) <= 0:
            return OperationResult(False, f"第 {i} 行数量必须大于 0")

    try:
        tid = orders.create_transfer(src_id, dst_id, src_op, dst_op, remark, lines)
        return OperationResult(True, f"调拨单已创建（ID {tid}），可开始发货", record_id=tid)
    except errors.DomainError as exc:
        return _fail(exc)


def ship_transfer(line_id, qty) -> OperationResult:
    if not line_id:
        return OperationResult(False, "请选择要发货的明细行")
    if not qty or int(qty) <= 0:
        return OperationResult(False, "发货数量必须大于 0")

    try:
        gid = orders.ship_transfer_line(line_id, int(qty))
        return OperationResult(True, "调拨完成，两条流水已配对入账", group_id=gid)
    except errors.DomainError as exc:
        return _fail(exc)
