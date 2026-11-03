# -*- coding: utf-8 -*-
"""调拨管理：建调拨单 → 发货（一次生成两条配对流水）→ 单据查询。

手工裸调拨（不经单据）降级为页面底部的应急入口 ——
正规流程必须挂单，否则事后无法回答"这批货是哪张调拨单动的"。
"""
from __future__ import annotations

import pandas as pd
import streamlit as st

from warehouse.repository import master, orders, stock
from warehouse.service import orders as svc
from warehouse.ui import common, theme


# ---------------------------------------------------------------- 新建
def _new_panel() -> None:
    whs = master.warehouse_options()
    if len(whs) < 2:
        common.empty_state("至少需要两个仓库", "先在「基础数据 → 仓库」里建好", "🏢")
        return

    if "tr_draft" not in st.session_state:
        st.session_state.tr_draft = []

    items = master.item_options()
    if not items:
        common.empty_state("还没有物品", "先在「基础数据 → 物品」里建档", "📦")
        return
    label_by_id = dict(items)

    c1, c2 = st.columns(2)
    src_id = c1.selectbox("源仓库（从哪转出）", [k for k, _ in whs], key="trd_src",
                          format_func=lambda x: dict(whs)[x])
    dst_options = [(k, v) for k, v in whs if k != src_id]
    if not dst_options:
        common.empty_state("没有其他仓库可选", "", "🏢")
        return
    dst_id = c2.selectbox("目标仓库（转入到哪）", [k for k, _ in dst_options], key="trd_dst",
                          format_func=lambda x: dict(dst_options)[x])

    c3, c4 = st.columns(2)
    src_staffs = master.staff_by_warehouse(src_id)
    dst_staffs = master.staff_by_warehouse(dst_id)

    src_op = c3.selectbox("发货人（需源仓库权限）", [k for k, _ in src_staffs], key="trd_sop",
                          format_func=lambda x: dict(src_staffs).get(x, str(x))) if src_staffs else None
    dst_op = c4.selectbox("收货人（需目标仓库权限）", [k for k, _ in dst_staffs], key="trd_dop",
                          format_func=lambda x: dict(dst_staffs).get(x, str(x))) if dst_staffs else None

    if not src_staffs:
        st.warning("源仓库没有在职员工，请先在「基础数据 → 员工」里授权")
    if not dst_staffs:
        st.warning("目标仓库没有在职员工，请先在「基础数据 → 员工」里授权")

    remark = st.text_input("备注", key="trd_remark", placeholder="例如：华东调拨补货")

    st.divider()
    st.markdown("**① 添加明细行**")
    ca, cb, cc = st.columns([3, 1, 1])
    with ca:
        add_item = st.selectbox("物品", [k for k, _ in items], key="trd_add_item",
                                format_func=lambda x: label_by_id[x])
    with cb:
        add_qty = st.number_input("调拨数量", min_value=1, value=10, step=1, key="trd_add_qty")
    with cc:
        st.write("")
        st.write("")
        if st.button("＋ 添加到明细", key="trd_add_btn", width="stretch"):
            st.session_state.tr_draft.append({
                "item_id": int(add_item),
                "item_name": label_by_id[add_item],
                "qty": int(add_qty),
            })
            st.rerun()

    st.markdown("**② 明细清单**")
    draft = st.session_state.tr_draft
    if not draft:
        common.hint("还没有明细行。选好物品和数量后点「添加到明细」。")
        return

    show = pd.DataFrame([{"序号": i, "物品": d["item_name"], "调拨数量": d["qty"]}
                         for i, d in enumerate(draft, start=1)])
    st.dataframe(show, width="stretch", hide_index=True)

    cd1, cd2 = st.columns([1, 3])
    if cd1.button("清空明细", key="trd_clear", width="stretch"):
        st.session_state.tr_draft = []
        st.rerun()
    cd2.caption(f"共 {len(draft)} 行，计划总量 {sum(d['qty'] for d in draft)}")

    if st.button("创建调拨单", type="primary", key="btn_create_tr", width="stretch"):
        lines = [{"item_id": d["item_id"], "qty": d["qty"]} for d in draft]
        result = svc.create_transfer_order(src_id, dst_id, src_op, dst_op,
                                           remark or None, lines)
        common.show_result(result)
        if result.ok:
            st.session_state.tr_draft = []
            st.rerun()


# ---------------------------------------------------------------- 发货
def _ship_panel() -> None:
    df = orders.list_transfer_orders()
    pending = df[df["状态"].isin(["待发货", "部分发货"])] if not df.empty else df

    if pending.empty:
        common.empty_state("没有待发货的调拨单", "先在上方创建一张", "🚚")
        return

    labels = {int(r.TransferID):
              f"{r.单号} · {r.源仓库}→{r.目标仓库} · {r.状态} · 待发 {int(r.待发)}"
              for r in pending.itertuples()}
    tid = st.selectbox("选择调拨单", list(labels), key="trd_pick",
                       format_func=lambda x: labels[x])

    lines = orders.transfer_lines(tid)
    if lines.empty:
        common.empty_state("该单据没有明细", "", "📄")
        return

    st.dataframe(lines.drop(columns=["LineID", "ItemID"]), width="stretch", hide_index=True)

    open_lines = lines[lines["待发"] > 0]
    if open_lines.empty:
        st.success("该调拨单已全部发货")
        return

    st.divider()
    st.markdown("**发货登记**")

    line_labels = {int(r.LineID): f"#{int(r.行号)} {r.物品} · 待发 {int(r.待发)}"
                   for r in open_lines.itertuples()}
    line_id = st.selectbox("发货行", list(line_labels), key="trd_line",
                           format_func=lambda x: line_labels[x])

    sel = open_lines[open_lines["LineID"] == line_id].iloc[0]
    max_qty = int(sel["待发"])
    item_id = int(sel["ItemID"])

    row = pending[pending["TransferID"] == tid].iloc[0]
    wh_pairs = master.warehouse_options()
    wh_map = {v: k for k, v in wh_pairs}
    src_wh = wh_map.get(row["源仓库"])

    available = stock.available_qty(item_id, src_wh) if src_wh else 0

    m1, m2 = st.columns(2)
    m1.metric("源仓库可用量", f"{available}")
    m2.metric("本行待发", f"{max_qty}")

    if available < max_qty:
        st.warning("源仓库库存不足，无法整行发货")

    qty = st.number_input("本次发货数量", min_value=1,
                          max_value=max(1, min(max_qty, available or 1)),
                          value=max(1, min(max_qty, available or 1)), key="trd_qty")

    if st.button("确认发货", type="primary", key="btn_ship_tr", width="stretch"):
        result = svc.ship_transfer(line_id, qty)
        common.show_result(result)
        if result.ok:
            if result.group_id:
                st.toast(f"调拨组号 {result.group_id[:8]}…", icon="🔗")
            st.rerun()


# ---------------------------------------------------------------- 查询
def _history_panel() -> None:
    df = orders.list_transfer_orders()
    if df.empty:
        common.empty_state("还没有调拨单", "", "📋")
        return

    show = df.drop(columns=["TransferID"]).copy()
    show["创建时间"] = pd.to_datetime(show["创建时间"]).dt.strftime("%Y-%m-%d %H:%M")

    def _status(v):
        return {"已完成": "color:#059669;font-weight:600",
                "部分发货": "color:#D97706;font-weight:600",
                "已取消": "color:#94A3B8"}.get(v, "")

    st.dataframe(show.style.map(_status, subset=["状态"]), width="stretch", hide_index=True)


# ---------------------------------------------------------------- 应急裸调拨
def _manual_transfer() -> None:
    """保留原有的一次性调拨：同时插两条流水，不产生单据。"""
    items = master.item_options()
    if not items:
        return

    item_id = common.pick("物品", items, "tr_item", allow_none=True, none_label="— 请选择 —")
    if not item_id:
        common.hint("选择物品后，系统会列出有货的源仓库与批次供应商。")
        return

    src_list = stock.warehouses_with_stock(item_id)
    if not src_list:
        common.empty_state("该物品无库存", "", "🚫")
        return

    c1, c2 = st.columns(2)
    src_id = c1.selectbox("源仓库", [k for k, _ in src_list], key="tr_src",
                          format_func=lambda x: dict(src_list)[x])
    all_whs = master.warehouse_options()
    dst_candidates = [(k, v) for k, v in all_whs if k != src_id]
    if not dst_candidates:
        return
    dst_id = c2.selectbox("目标仓库", [k for k, _ in dst_candidates], key="tr_dst",
                          format_func=lambda x: dict(dst_candidates)[x])

    sups = stock.suppliers_of_item_in_warehouse(item_id, src_id)
    supplier_id = st.selectbox("批次供应商", [k for k, _ in sups], key="tr_sup",
                               format_func=lambda x: dict(sups)[x])

    available = stock.available_qty(item_id, src_id, supplier_id)
    st.metric("源仓库可用量", f"{available}")

    src_staffs = master.staff_by_warehouse(src_id)
    dst_staffs = master.staff_by_warehouse(dst_id)
    c3, c4 = st.columns(2)
    out_staff = c3.selectbox("发货人", [k for k, _ in src_staffs], key="tr_out_staff",
                             format_func=lambda x: dict(src_staffs).get(x, str(x))) if src_staffs else None
    in_staff = c4.selectbox("收货人", [k for k, _ in dst_staffs], key="tr_in_staff",
                            format_func=lambda x: dict(dst_staffs).get(x, str(x))) if dst_staffs else None

    qty = st.number_input("调拨数量", min_value=1, max_value=max(1, available),
                          value=1, step=1, key="tr_qty")

    if st.button("确认调拨", type="primary", key="btn_tr", width="stretch"):
        from warehouse.service import inventory as inv
        common.show_result(inv.transfer(item_id, src_id, dst_id, supplier_id,
                                        qty, out_staff, in_staff, "应急手工调拨"))


def render() -> None:
    common.page_header(
        "调拨管理",
        "调拨单一次生成两条配对流水（调拨出 / 调拨入），共用组号；任一环节失败整体回滚",
        "🔄",
    )

    tab1, tab2, tab3 = st.tabs(["新建调拨单", "发货作业", "单据查询"])
    with tab1:
        with st.container(border=True):
            _new_panel()
    with tab2:
        with st.container(border=True):
            _ship_panel()
    with tab3:
        _history_panel()

    st.divider()
    with st.expander("应急手工调拨（不经单据，仅用于补录或纠错）", expanded=False):
        common.hint(
            "正式业务请用上方调拨单。这里的操作不会产生单据号，"
            "流水上的来源会留空，盘点与对账时无法归到具体单据。"
        )
        _manual_transfer()
