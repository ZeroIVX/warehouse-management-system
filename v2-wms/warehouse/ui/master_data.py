# -*- coding: utf-8 -*-
"""基础数据维护页：工厂、仓库、物品、供应商、员工。

两个稳定性的细节：
  1. 表单 key 里带上"当前选中记录的 ID"，切换下拉框时输入框才会重新取值。
     否则切记录后表单仍显示上一条内容，很容易改错数据。
  2. 删除需要先勾选确认。原版点一下直接删，误触没有回头路。
"""
from __future__ import annotations

import pandas as pd
import streamlit as st

from warehouse.repository import master, orders
from warehouse.service import master_data as svc
from warehouse.ui import common, theme


def _picker(label: str, pairs: list[tuple], key: str):
    if not pairs:
        st.info(f"暂无{label}，可直接新增")
        return st.selectbox(label, [None], key=key, format_func=lambda x: "＋ 新增")
    return st.selectbox(
        label, [None] + [k for k, _ in pairs],
        format_func=lambda x: "＋ 新增" if x is None else dict(pairs)[x],
        key=key,
    )


def _save_delete(selected, key: str) -> tuple[bool, bool]:
    """保存 / 删除两个按钮。删除需先勾选确认，未选中记录时置灰。"""
    b1, b2 = st.columns(2)
    do_save = b1.form_submit_button("保存", type="primary", width="stretch")

    if selected is None:
        b2.form_submit_button("删除", disabled=True, width="stretch")
        return do_save, False

    confirmed = st.checkbox("确认删除这条记录", key=f"delok_{key}_{selected}")
    do_del = b2.form_submit_button("删除", disabled=not confirmed, width="stretch")
    return do_save, do_del


# ---------------------------------------------------------------- 工厂
def _tab_factory() -> None:
    left, right = st.columns([1, 1.7])
    pairs = master.factory_options()

    with left:
        with st.container(border=True):
            sel = _picker("选择工厂", pairs, "fac_sel")
            cur = master.get_factory(sel) if sel else None

            with st.form(f"fac_form_{sel}"):
                name = st.text_input("工厂名称", value=cur["FactName"] if cur else "")
                address = st.text_input("地址", value=(cur["FactAddress"] or "") if cur else "")
                tel = st.text_input("联系电话", value=(cur["FactTel"] or "") if cur else "")
                do_save, do_del = _save_delete(sel, "fac")

            if do_save:
                common.show_result(svc.save_factory(sel, name, address or None, tel or None))
            if do_del:
                common.show_result(svc.delete_factory(sel))

    with right:
        st.markdown("##### 工厂清单")
        common.table(master.list_factories(), height=400)


# ---------------------------------------------------------------- 仓库
def _tab_warehouse() -> None:
    left, right = st.columns([1, 1.7])
    pairs = master.warehouse_options()
    type_pairs = master.warehouse_type_options()

    with left:
        with st.container(border=True):
            sel = _picker("选择仓库", pairs, "wh_sel")
            cur = master.get_warehouse(sel) if sel else None
            cur_type = int(cur["WarehouseTypeID"]) if cur else None

            with st.form(f"wh_form_{sel}"):
                name = st.text_input("仓库名称", value=cur["WarehouseName"] if cur else "")
                address = st.text_input("仓库地址", value=(cur["WarehouseAddress"] or "") if cur else "")

                type_ids = [k for k, _ in type_pairs]
                type_id = st.selectbox(
                    "仓库类型", type_ids,
                    index=type_ids.index(cur_type) if cur_type in type_ids else 0,
                    format_func=lambda x: dict(type_pairs).get(x, str(x)),
                    help="类型维护在 WarehouseType 字典表中，新增类型不需要改代码",
                )
                size = st.number_input("库容", min_value=1,
                                       value=int(cur["WarehouseSize"]) if cur else 1000)

                if cur:
                    usage = int(cur["WarehouseUsage"])
                    pct = usage * 100 / max(1, int(cur["WarehouseSize"]))
                    st.progress(min(1.0, pct / 100),
                                text=f"当前已用 {usage} / {int(cur['WarehouseSize'])}（由触发器自动同步）")

                do_save, do_del = _save_delete(sel, "wh")

            if do_save:
                common.show_result(svc.save_warehouse(sel, name, type_id, size, address or None))
            if do_del:
                common.show_result(svc.delete_warehouse(sel))

    with right:
        st.markdown("##### 仓库与容量")
        common.table(master.list_warehouses(), height=400)


# ---------------------------------------------------------------- 物品
def _tab_item() -> None:
    left, right = st.columns([1, 1.7])
    pairs = master.item_options()
    factories = master.factory_options()

    with left:
        with st.container(border=True):
            sel = _picker("选择物品", pairs, "item_sel")
            cur = master.get_item(sel) if sel else None

            with st.form(f"item_form_{sel}"):
                name = st.text_input("物品名称", value=cur["ItemName"] if cur else "")
                item_type = st.text_input("规格", value=(cur["ItemType"] or "") if cur else "")
                price = st.number_input("单价", min_value=0.0, step=0.01,
                                        value=float(cur["Price"]) if cur else 0.0, format="%.2f")

                fac_ids = [None] + [k for k, _ in factories]
                fac_labels = {None: "（无厂家）"}
                fac_labels.update(dict(factories))
                cur_fac = int(cur["FactoryID"]) if cur and cur["FactoryID"] is not None else None
                factory_id = st.selectbox("所属厂家", fac_ids,
                                          index=fac_ids.index(cur_fac) if cur_fac in fac_ids else 0,
                                          format_func=lambda x: fac_labels.get(x, str(x)),
                                          help="同一厂家下「同名 + 同规格」视为重复建档，会被唯一约束拦下")

                do_save, do_del = _save_delete(sel, "item")

            if do_save:
                common.show_result(svc.save_item(sel, name, item_type or None, price, factory_id))
            if do_del:
                common.show_result(svc.delete_item(sel))

    with right:
        st.markdown("##### 物品清单")
        common.table(master.list_items(), height=400)


# ---------------------------------------------------------------- 供应商
def _tab_supplier() -> None:
    left, right = st.columns([1, 1.7])
    pairs = master.supplier_options()

    with left:
        with st.container(border=True):
            sel = _picker("选择供应商", pairs, "sup_sel")
            cur = master.get_supplier(sel) if sel else None

            with st.form(f"sup_form_{sel}"):
                name = st.text_input("供应商名称", value=cur["SupName"] if cur else "")
                address = st.text_input("地址", value=(cur["SupAddress"] or "") if cur else "")
                tel = st.text_input("联系电话", value=(cur["SupTel"] or "") if cur else "")
                do_save, do_del = _save_delete(sel, "sup")

            if do_save:
                common.show_result(svc.save_supplier(sel, name, address or None, tel or None))
            if do_del:
                common.show_result(svc.delete_supplier(sel))

    with right:
        st.markdown("##### 供应商清单")
        common.table(master.list_suppliers(), height=400)


# ---------------------------------------------------------------- 员工
def _tab_staff() -> None:
    left, right = st.columns([1, 1.7])
    pairs = master.staff_options()
    whs = master.warehouse_options()

    with left:
        with st.container(border=True):
            sel = _picker("选择员工", pairs, "staff_sel")
            cur = master.get_staff(sel) if sel else None
            assigned = master.staff_assigned_warehouses(sel) if sel else []

            with st.form(f"staff_form_{sel}"):
                name = st.text_input("姓名", value=cur["StaffName"] if cur else "")
                tel = st.text_input("联系电话", value=(cur["StaffTel"] or "") if cur else "")
                is_active = st.checkbox("在职", value=bool(cur["IsActive"]) if cur else True)
                chosen = st.multiselect(
                    "授权仓库（可多选）", [k for k, _ in whs],
                    default=[w for w in assigned if w in [k for k, _ in whs]],
                    format_func=lambda x: dict(whs).get(x, str(x)),
                    help="只有被授权的仓库，该员工才能办理出入库与调拨",
                )

                if not is_active:
                    st.caption("离职员工保留历史流水，但不再出现在经办人候选中")

                do_save, _ = _save_delete(sel, "staff")

            if do_save:
                common.show_result(svc.save_staff(sel, name, tel or None, is_active, chosen))

    with right:
        st.markdown("##### 员工与授权")
        st.caption("一行一个授权关系；未分配仓库的员工也会显示一行")
        common.table(master.list_staff_with_permission(), height=400)


def _tab_location() -> None:
    """库位利用：哪个货位满了、哪个还空着"""
    whs = master.warehouse_options()
    c1, c2 = st.columns([1, 2])
    wh_id = c1.selectbox("筛选仓库", [None] + [k for k, _ in whs], key="loc_wh",
                         format_func=lambda x: "全部仓库" if x is None else dict(whs)[x])

    df = orders.location_utilization(wh_id)
    if df.empty:
        common.empty_state("没有库位数据", "建库脚本 06_seed 会自动生成库区与货位", "🏗️")
        return

    total = len(df)
    used = int((df["已用"] > 0).sum())
    locked = int((df["状态"] == "锁定").sum())
    c1, c2, c3 = st.columns(3)
    c1.metric("货位总数", f"{total}")
    c2.metric("已占用", f"{used}")
    c3.metric("锁定", f"{locked}")

    def _usage_color(val):
        if pd.isna(val):
            return ""
        if val >= 90:
            return "background-color: #FEE4E2; color: #B42318"
        if val >= 70:
            return "background-color: #FEF0C7; color: #B54708"
        if val > 0:
            return "background-color: #EFF6FF; color: #1D4ED8"
        return ""

    st.dataframe(
        df.style.format({"使用率%": "{:.1f}"}).map(_usage_color, subset=["使用率%"]),
        width="stretch", hide_index=True, height=430,
    )
    common.hint("使用率按「该货位库存量 / 容量」计算；一张货位可以放多个批次，"
                "因为不同批次必须分开记账才能做先到期先出。")


TABS = {
    "工厂": _tab_factory,
    "仓库": _tab_warehouse,
    "库位": _tab_location,
    "物品": _tab_item,
    "供应商": _tab_supplier,
    "员工与权限": _tab_staff,
}


def render() -> None:
    common.page_header(
        "基础数据",
        "工厂、仓库、物品、供应商与员工授权。主数据变化会立刻影响作业页的可选项",
        "🗂️",
    )
    tabs = st.tabs(list(TABS.keys()))
    for tab, fn in zip(tabs, TABS.values()):
        with tab:
            fn()
