# -*- coding: utf-8 -*-
"""
主数据维护用例。

把"保存 / 删除"统一成 OperationResult，UI 不用写 try/except，
也不会像原版那样用裸 `except:` 把真实错误吞掉、只弹一句「外键约束」。
"""
from __future__ import annotations

from warehouse.db import errors
from warehouse.repository import master
from warehouse.service.inventory import OperationResult


def _fail(exc: Exception) -> OperationResult:
    return OperationResult(False, str(exc), error=exc)


# ---------------------------------------------------------------- 工厂
def save_factory(fact_id: int | None, name: str, address: str | None, tel: str | None) -> OperationResult:
    if not name or not name.strip():
        return OperationResult(False, "工厂名称不能为空")
    try:
        if fact_id:
            master.update_factory(fact_id, name.strip(), address, tel)
            return OperationResult(True, "工厂信息已更新")
        new_id = master.insert_factory(name.strip(), address, tel)
        return OperationResult(True, "工厂已新增", record_id=int(new_id))

    except errors.DuplicateError:
        return OperationResult(False, "已存在同名工厂")
    except errors.DomainError as exc:
        return _fail(exc)


def delete_factory(fact_id: int | None) -> OperationResult:
    if not fact_id:
        return OperationResult(False, "请先选择要删除的工厂")
    try:
        master.delete_factory(fact_id)
        return OperationResult(True, "工厂已删除（其下物品的厂家置空）")
    except errors.ReferenceError_:
        return OperationResult(False, "该工厂仍被物品引用，无法删除")
    except errors.DomainError as exc:
        return _fail(exc)


# ---------------------------------------------------------------- 供应商
def save_supplier(sup_id: int | None, name: str, address: str | None, tel: str | None) -> OperationResult:
    if not name or not name.strip():
        return OperationResult(False, "供应商名称不能为空")
    try:
        if sup_id:
            master.update_supplier(sup_id, name.strip(), address, tel)
            return OperationResult(True, "供应商信息已更新")
        new_id = master.insert_supplier(name.strip(), address, tel)
        return OperationResult(True, "供应商已新增", record_id=int(new_id))
    except errors.DuplicateError:
        return OperationResult(False, "已存在同名供应商")
    except errors.DomainError as exc:
        return _fail(exc)


def delete_supplier(sup_id: int | None) -> OperationResult:
    if not sup_id:
        return OperationResult(False, "请先选择要删除的供应商")
    try:
        master.delete_supplier(sup_id)
        return OperationResult(True, "供应商已删除")
    except errors.ReferenceError_:
        return OperationResult(False, "该供应商仍有库存或流水引用，无法删除")
    except errors.DomainError as exc:
        return _fail(exc)


# ---------------------------------------------------------------- 仓库
def save_warehouse(warehouse_id: int | None, name: str, type_id: int | None,
                   size: int, address: str | None) -> OperationResult:
    if not name or not name.strip():
        return OperationResult(False, "仓库名称不能为空")
    if not type_id:
        return OperationResult(False, "请选择仓库类型")
    if not size or size <= 0:
        return OperationResult(False, "库容必须大于 0")
    try:
        if warehouse_id:
            master.update_warehouse(warehouse_id, name.strip(), type_id, size, address)
            return OperationResult(True, "仓库信息已更新")
        new_id = master.insert_warehouse(name.strip(), type_id, size, address)
        return OperationResult(True, "仓库已新增", record_id=int(new_id))
    except errors.DuplicateError:
        return OperationResult(False, "已存在同名仓库")
    except errors.DomainError as exc:
        return _fail(exc)


def delete_warehouse(warehouse_id: int | None) -> OperationResult:
    if not warehouse_id:
        return OperationResult(False, "请先选择要删除的仓库")
    try:
        master.delete_warehouse(warehouse_id)
        return OperationResult(True, "仓库已删除")
    except errors.ReferenceError_:
        return OperationResult(False, "仓库内仍有库存或流水，无法删除")
    except errors.DomainError as exc:
        return _fail(exc)


# ---------------------------------------------------------------- 物品
def save_item(item_id: int | None, name: str, item_type: str | None,
              price: float, factory_id: int | None) -> OperationResult:
    if not name or not name.strip():
        return OperationResult(False, "物品名称不能为空")
    if price is None or price < 0:
        return OperationResult(False, "单价不能为负数")
    try:
        if item_id:
            master.update_item(item_id, name.strip(), item_type, price, factory_id)
            return OperationResult(True, "物品信息已更新")
        new_id = master.insert_item(name.strip(), item_type, price, factory_id)
        return OperationResult(True, "物品已新增", record_id=int(new_id))
    except errors.DuplicateError:
        # 唯一约束 UQ_Item_Ident 拦下的重复建档
        return OperationResult(False, "同一厂家下已存在同名同规格物品")
    except errors.DomainError as exc:
        return _fail(exc)


def delete_item(item_id: int | None) -> OperationResult:
    if not item_id:
        return OperationResult(False, "请先选择要删除的物品")
    try:
        master.delete_item(item_id)
        return OperationResult(True, "物品已删除")
    except errors.ReferenceError_:
        return OperationResult(False, "该物品已有库存或出入库流水，无法删除")
    except errors.DomainError as exc:
        return _fail(exc)


# ---------------------------------------------------------------- 员工
def save_staff(staff_id: int | None, name: str, tel: str | None,
               is_active: bool, warehouse_ids: list[int]) -> OperationResult:
    if not name or not name.strip():
        return OperationResult(False, "员工姓名不能为空")
    try:
        if staff_id:
            master.update_staff(staff_id, name.strip(), tel, is_active)
            master.replace_assignments(staff_id, warehouse_ids)
            return OperationResult(True, "员工信息与权限已同步")
        new_id = master.insert_staff(name.strip(), tel, is_active)
        master.replace_assignments(int(new_id), warehouse_ids)
        return OperationResult(True, "员工已新增并完成授权", record_id=int(new_id))
    except errors.DomainError as exc:
        return _fail(exc)
