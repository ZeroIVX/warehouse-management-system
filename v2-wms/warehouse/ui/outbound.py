# -*- coding: utf-8 -*-
"""出库管理：建发货单 → 按行发货（自动 FEFO 选批）。"""
from __future__ import annotations

import datetime as dt

import pandas as pd
import streamlit as st

from warehouse.repository import master, orders, stock
from warehouse.service import orders as svc
from warehouse.ui import common, theme


def _new_order_panel() -> None:
    items = master.item_options()
    whs = master.warehouse_options()
    cuss = orders.customer_options()

    if not items or not whs:
        common.empty_state("缺少基础数据", "先在「基础数据」里维护物品与仓库", "🗂️")
        return

    if "out_draft" not in st.session_state:
        st.session_state.out_draft = []

    c1, c2, c3 = st.columns(3)
    order_type = c1.selectbox("单据类型", ["销售出库", "调拨出库", "报损出库", "退供出库"], key="out_type")
    wh_id = c2.selectbox("发货仓库", [k for k, _ in whs], key="out_wh_new",
                         format_func=lambda x: dict(whs)[x])
    customer_id = c3.selectbox(
        "客户（销售出库必选）", [None] + [k for k, _ in cuss], key="out_cus",
        format_func=lambda x: "— 不需要客户 —" if x is None else dict(cuss)[x],
        disabled=(order_type != "销售出库"),
    )

    c4, c5 = st.columns([1, 2])
    required = c4.date_input("要求发货日", value=dt.date.today() + dt.timedelta(days=2), key="out_required")
    remark = c5.text_input("备注", key="out_remark", placeholder="例如：华东区一月订单")

    st.divider()
    st.markdown("**① 添加明细行**")

    label_by_id = dict(items)
    ca, cb, cc = st.columns([3, 1, 1])
    with ca:
        add_item = st.selectbox("物品", [k for k, _ in items], key="out_add_item",
                                format_func=lambda x: label_by_id[x])
    with cb:
        add_qty = st.number_input("计划数量", min_value=1, value=10, step=1, key="out_add_qty")
    with cc:
        st.write("")
        st.write("")
        if st.button("＋ 添加到明细", key="out_add_btn", width="stretch"):
            st.session_state.out_draft.append({
                "item_id": int(add_item),
                "item_name": label_by_id[add_item],
                "qty": int(add_qty),
            })
            st.rerun()

    st.markdown("**② 明细清单**")
    draft = st.session_state.out_draft

    if not draft:
        common.hint("还没有明细行。选好物品和数量后点「添加到明细」。")
        return

    show = pd.DataFrame([
        {"序号": i, "物品": d["item_name"], "计划数量": d["qty"]}
        for i, d in enumerate(draft, start=1)
    ])
    st.dataframe(show, width="stretch", hide_index=True)

    cd1, cd2 = st.columns([1, 3])
    if cd1.button("清空明细", key="out_clear", width="stretch"):
        st.session_state.out_draft = []
        st.rerun()
    cd2.caption(f"共 {len(draft)} 行，计划总量 {sum(d['qty'] for d in draft)}")

    if st.button("创建出库单", type="primary", key="btn_create_out", width="stretch"):
        lines = [{"item_id": d["item_id"], "qty": d["qty"]} for d in draft]
        result = svc.create_outbound_order(order_type, wh_id,
                                           customer_id if order_type == "销售出库" else None,
                                           required, remark or None, lines)
        common.show_result(result)
        if result.ok:
            st.session_state.out_draft = []
            st.rerun()


def _ship_panel() -> None:
    df = orders.list_outbound_orders()
    pending = df[df["状态"].isin(["待拣货", "拣货中"])] if not df.empty else df

    if pending.empty:
        common.empty_state("没有待发货的单据", "先在上方创建一张出库单", "📤")
        return

    labels = {int(r.OrderID): f"{r.单号} · {r.仓库} · {r.状态} · 待发 {int(r.待发)}"
              for r in pending.itertuples()}
    order_id = st.selectbox("选择单据", list(labels), key="out_pick_order",
                            format_func=lambda x: labels[x])

    row = pending[pending["OrderID"] == order_id].iloc[0]
    warehouse_id = int(row["WarehouseID"])

    lines = orders.outbound_lines(order_id)
    if lines.empty:
        common.empty_state("该单据没有明细", "", "📄")
        return

    st.dataframe(lines.drop(columns=["LineID", "ItemID"]), width="stretch", hide_index=True)

    open_lines = lines[lines["待发"] > 0]
    if open_lines.empty:
        st.success("该单据已全部发货")
        return

    st.divider()
    st.markdown("**发货登记**")

    line_labels = {int(r.LineID): f"#{int(r.行号)} {r.物品} · 待发 {int(r.待发)}"
                   for r in open_lines.itertuples()}
    line_id = st.selectbox("发货行", list(line_labels), key="out_pick_line",
                           format_func=lambda x: line_labels[x])

    sel = open_lines[open_lines["LineID"] == line_id].iloc[0]
    item_id = int(sel["ItemID"])
    max_qty = int(sel["待发"])

    # 实时显示可用量，让用户提前知道能不能发
    available = stock.available_qty(item_id, warehouse_id)

    c1, c2, c3 = st.columns(3)
    c1.metric("该物品可用量", f"{available}")
    c2.metric("本行待发", f"{max_qty}")
    if available < max_qty:
        c3.warning("库存不足，无法整行发货")

    qty = st.number_input("本次发货数量", min_value=1,
                          max_value=max(1, min(max_qty, available or 1)),
                          value=max(1, min(max_qty, available or 1)), key="out_qty")

    staffs = master.staff_by_warehouse(warehouse_id)
    if not staffs:
        st.warning("该仓库没有在职员工，无法发货。请先在「基础数据 → 员工」里授权")

    staff = st.selectbox("经办人", [k for k, _ in staffs], key="out_staff_ship",
                         format_func=lambda x: dict(staffs).get(x, str(x))) if staffs else None

    if st.button("确认发货", type="primary", key="btn_ship", width="stretch"):
        common.show_result(svc.ship(line_id, qty, staff))
        st.rerun()


def _history_panel() -> None:
    df = orders.list_outbound_orders()
    if df.empty:
        common.empty_state("还没有出库单", "", "📋")
        return
    show = df.drop(columns=["OrderID", "WarehouseID"]).copy()
    show["创建时间"] = pd.to_datetime(show["创建时间"]).dt.strftime("%Y-%m-%d %H:%M")

    def _status(v):
        return {"已完成": "color:#059669;font-weight:600",
                "拣货中": "color:#D97706;font-weight:600",
                "已取消": "color:#94A3B8"}.get(v, "")

    st.dataframe(show.style.map(_status, subset=["状态"]), width="stretch", hide_index=True)


def render() -> None:
    common.page_header(
        "出库管理",
        "销售/调拨/报损/退供出库都以单据驱动；发货时系统按「先到期先出」自动选批，避免临期货压库",
        "📤",
    )
    tab1, tab2, tab3 = st.tabs(["新建出库单", "发货作业", "单据查询"])
    with tab1:
        with st.container(border=True):
            _new_order_panel()
    with tab2:
        with st.container(border=True):
            _ship_panel()
    with tab3:
        _history_panel()
