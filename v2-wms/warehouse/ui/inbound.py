# -*- coding: utf-8 -*-
"""入库管理：建收货单 → 分批收货 → 自动推进单据状态。"""
from __future__ import annotations

import datetime as dt

import pandas as pd
import streamlit as st

from warehouse.repository import master, orders
from warehouse.service import orders as svc
from warehouse.ui import common, theme


def _new_order_panel() -> None:
    items = master.item_options()
    whs = master.warehouse_options()
    sups = master.supplier_options()

    if not items or not whs:
        common.empty_state("缺少基础数据", "先在「基础数据」里维护物品与仓库", "🗂️")
        return

    if "in_draft" not in st.session_state:
        st.session_state.in_draft = []

    c1, c2, c3 = st.columns(3)
    order_type = c1.selectbox("单据类型", ["采购入库", "退货入库", "调拨入库"], key="in_type")
    wh_id = c2.selectbox("收货仓库", [k for k, _ in whs], key="in_wh",
                         format_func=lambda x: dict(whs)[x])
    sup_id = c3.selectbox("供应商（可不指定）", [None] + [k for k, _ in sups], key="in_sup",
                          format_func=lambda x: "— 不指定 —" if x is None else dict(sups)[x])

    c4, c5 = st.columns([1, 2])
    expected = c4.date_input("预计到货", value=dt.date.today() + dt.timedelta(days=3), key="in_expected")
    remark = c5.text_input("备注", key="in_remark", placeholder="例如：华东区一月补货")

    st.divider()
    st.markdown("**① 添加明细行**")

    # 逐行添加，不用 data_editor —— 后者在空表 + SelectboxColumn 的组合下
    # 会把选项渲染成内码（显示成 10/9/5 这样的数字），用户根本认不出是哪个物品。
    label_by_id = dict(items)
    ca, cb, cc = st.columns([3, 1, 1])
    with ca:
        add_item = st.selectbox("物品", [k for k, _ in items], key="in_add_item",
                                format_func=lambda x: label_by_id[x])
    with cb:
        add_qty = st.number_input("计划数量", min_value=1, value=10, step=1, key="in_add_qty")
    with cc:
        st.write("")
        st.write("")
        if st.button("＋ 添加到明细", key="in_add_btn", width="stretch"):
            st.session_state.in_draft.append({
                "item_id": int(add_item),
                "item_name": label_by_id[add_item],
                "qty": int(add_qty),
            })
            st.rerun()

    st.markdown("**② 明细清单**")
    draft = st.session_state.in_draft

    if not draft:
        common.hint("还没有明细行。选好物品和数量后点「添加到明细」。")
    else:
        show = pd.DataFrame([
            {"序号": i, "物品": d["item_name"], "计划数量": d["qty"]}
            for i, d in enumerate(draft, start=1)
        ])
        st.dataframe(show, width="stretch", hide_index=True)

        cd1, cd2 = st.columns([1, 3])
        if cd1.button("清空明细", key="in_clear", width="stretch"):
            st.session_state.in_draft = []
            st.rerun()
        cd2.caption(f"共 {len(draft)} 行，计划总量 {sum(d['qty'] for d in draft)}")

        if st.button("创建入库单", type="primary", key="btn_create_in", width="stretch"):
            lines = [{"item_id": d["item_id"], "qty": d["qty"]} for d in draft]
            result = svc.create_inbound_order(order_type, wh_id, sup_id,
                                              expected, remark or None, lines)
            common.show_result(result)
            if result.ok:
                st.session_state.in_draft = []
                st.rerun()


def _receive_panel() -> None:
    df = orders.list_inbound_orders()
    pending = df[df["状态"].isin(["待收货", "部分收货"])] if not df.empty else df

    if pending.empty:
        common.empty_state("没有待收货的单据", "先在上方创建一张入库单", "📥")
        return

    labels = {int(r.OrderID): f"{r.单号} · {r.仓库} · {r.状态} · 待收 {int(r.待收)}"
              for r in pending.itertuples()}
    order_id = st.selectbox("选择单据", list(labels), key="in_pick_order",
                            format_func=lambda x: labels[x])

    row = pending[pending["OrderID"] == order_id].iloc[0]
    warehouse_id = int(row["WarehouseID"])

    lines = orders.inbound_lines(order_id)
    if lines.empty:
        common.empty_state("该单据没有明细", "", "📄")
        return

    st.dataframe(lines.drop(columns=["LineID"]), width="stretch", hide_index=True)

    open_lines = lines[lines["待收"] > 0]
    if open_lines.empty:
        st.success("该单据已全部收货")
        return

    st.divider()
    st.markdown("**收货登记**")

    line_labels = {int(r.LineID): f"#{int(r.行号)} {r.物品} · 待收 {int(r.待收)}"
                   for r in open_lines.itertuples()}
    line_id = st.selectbox("收货行", list(line_labels), key="in_pick_line",
                           format_func=lambda x: line_labels[x])
    max_qty = int(open_lines[open_lines["LineID"] == line_id]["待收"].iloc[0])

    staffs = master.staff_by_warehouse(warehouse_id)
    if not staffs:
        st.warning("该仓库没有在职员工，无法收货。请先在「基础数据 → 员工」里授权")

    locs = orders.location_options(warehouse_id, "存储区")
    loc_labels = {lid: label for lid, label in locs}

    c1, c2, c3 = st.columns(3)
    qty = c1.number_input("实收数量", min_value=1, max_value=max_qty, value=max_qty, key="in_qty")
    location_id = c2.selectbox("上架货位", [None] + list(loc_labels), key="in_loc",
                               format_func=lambda x: "— 暂不上架 —" if x is None else loc_labels[x])
    batch = c3.text_input("批次号", key="in_batch", placeholder="留空自动生成")

    c4, c5, c6 = st.columns(3)
    prod = c4.date_input("生产日期（可选）", value=None, key="in_prod")
    exp = c5.date_input("失效日期（可选）", value=None, key="in_exp")
    staff = c6.selectbox("经办人", [k for k, _ in staffs], key="in_staff",
                         format_func=lambda x: dict(staffs).get(x, str(x))) if staffs else None

    if st.button("确认收货", type="primary", key="btn_receive", width="stretch"):
        if not batch:
            batch = f"B{dt.date.today():%Y%m%d}-{line_id:03d}"
        common.show_result(svc.receive(line_id, qty, location_id, batch, prod, exp, staff))
        st.rerun()


def _history_panel() -> None:
    df = orders.list_inbound_orders()
    if df.empty:
        common.empty_state("还没有入库单", "", "📋")
        return
    show = df.drop(columns=["OrderID", "WarehouseID"]).copy()
    show["创建时间"] = pd.to_datetime(show["创建时间"]).dt.strftime("%Y-%m-%d %H:%M")

    def _status(v):
        return {"已完成": "color:#059669;font-weight:600",
                "部分收货": "color:#D97706;font-weight:600",
                "已取消": "color:#94A3B8"}.get(v, "")

    st.dataframe(show.style.map(_status, subset=["状态"]), width="stretch", hide_index=True)


def render() -> None:
    common.page_header(
        "入库管理",
        "采购/退货/调拨入库都以单据驱动：先建单，再分批收货，收完自动结单",
        "📥",
    )
    tab1, tab2, tab3 = st.tabs(["新建入库单", "收货作业", "单据查询"])
    with tab1:
        with st.container(border=True):
            _new_order_panel()
    with tab2:
        with st.container(border=True):
            _receive_panel()
    with tab3:
        _history_panel()
