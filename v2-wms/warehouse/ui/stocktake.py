# -*- coding: utf-8 -*-
"""盘点管理：生成盘点单 → 录入实盘数 → 结案生成盘盈/盘亏。"""
from __future__ import annotations

import pandas as pd
import streamlit as st

from warehouse.repository import master, orders
from warehouse.service import orders as svc
from warehouse.ui import common, theme


def _create_panel() -> None:
    whs = master.warehouse_options()
    if not whs:
        common.empty_state("还没有仓库", "先在「基础数据」里维护仓库", "🏢")
        return

    c1, c2 = st.columns([1, 1])
    wh_id = c1.selectbox("盘点仓库", [k for k, _ in whs], key="st_wh",
                         format_func=lambda x: dict(whs)[x])

    zones = orders.zone_options(wh_id)
    zone_labels = {zid: label for zid, label in zones}
    zone_id = c2.selectbox("盘点范围", [None] + list(zone_labels), key="st_zone",
                           format_func=lambda x: "全仓" if x is None else zone_labels[x])

    remark = st.text_input("备注", key="st_remark", placeholder="例如：月末全仓盘点 / 冷链区循环盘点")

    common.hint("生成时会自动带出该范围内所有有库存的批次作为账面数；"
                "账面为 0 的空货位不需要盘。未录入实盘数的行按「未盘」处理，不产生调整。")

    if st.button("生成盘点单", type="primary", key="btn_create_st", width="stretch"):
        common.show_result(svc.create_stocktake(wh_id, zone_id, remark or None))


def _count_panel() -> None:
    df = orders.list_stocktakes()
    if df.empty:
        common.empty_state("还没有盘点单", "先在上方生成一张", "📋")
        return

    open_orders = df[df["状态"] == "盘点中"]
    if open_orders.empty:
        common.empty_state("没有进行中的盘点单", "全部已结案", "✅")
        return

    labels = {int(r.StocktakeID): f"{r.盘点单号} · {r.仓库} · {r.范围} · 已盘 {int(r.已盘)}/{int(r.行数)}"
              for r in open_orders.itertuples()}
    st_id = st.selectbox("选择盘点单", list(labels), key="st_pick",
                         format_func=lambda x: labels[x])

    lines = orders.stocktake_lines(st_id)
    if lines.empty:
        common.empty_state("该盘点单没有明细", "", "📄")
        return

    st.caption("在「实盘」列填数字：显示 None 表示尚未录入；填 0 表示实物为空（结案时会产生盘亏）；留空的行不参与调整")

    editable = lines.drop(columns=["LineID"]).copy()
    # 转成数值型：object 列里的 None 在表格里会显示成字符串 "None"，
    # 转成 float 后空值才是真正的空白
    for col in ("实盘", "差异"):
        editable[col] = pd.to_numeric(editable[col], errors="coerce")

    edited = st.data_editor(
        editable,
        width="stretch",
        hide_index=True,
        key=f"st_editor_{st_id}",
        disabled=["物品", "规格", "货位", "批次", "账面", "差异"],
        column_config={
            "实盘": st.column_config.NumberColumn("实盘", min_value=0, step=1),
            "差异": st.column_config.NumberColumn("差异", help="实盘 - 账面；结案时据此生成盘盈/盘亏"),
        },
    )

    c1, c2 = st.columns([1, 1])
    if c1.button("保存实盘数", key="btn_save_count", width="stretch"):
        saved = 0
        for idx, r in edited.iterrows():
            if pd.notna(r["实盘"]):
                orders.set_counted(int(lines.iloc[idx]["LineID"]), int(r["实盘"]))
                saved += 1
        st.toast(f"已保存 {saved} 行实盘数", icon="💾")
        st.rerun()

    # 结案需要盘点人（要有该仓库权限）。仓库 ID 直接从单据带出来，
    # 不要再靠仓库名反查 —— 名字有重名或前后空格就会拿不到人。
    row = open_orders[open_orders["StocktakeID"] == st_id].iloc[0]
    warehouse_id = int(row["WarehouseID"])
    staffs = master.staff_by_warehouse(warehouse_id)

    with c2:
        staff = st.selectbox("盘点人", [k for k, _ in staffs], key="st_staff",
                             format_func=lambda x: dict(staffs).get(x, str(x))) if staffs else None

    counted = int((edited["实盘"].notna()).sum())
    diff_rows = int((edited["实盘"].notna() & (edited["差异"] != 0)).sum())
    m1, m2, m3 = st.columns(3)
    m1.metric("待盘行数", f"{len(edited)}")
    m2.metric("已录实盘", f"{counted}")
    m3.metric("有差异行", f"{diff_rows}")

    if st.button("结案并生成调整", type="primary", key="btn_complete", width="stretch"):
        common.show_result(svc.complete(st_id, staff))
        st.rerun()


def _history_panel() -> None:
    df = orders.list_stocktakes()
    if df.empty:
        common.empty_state("还没有盘点记录", "", "📋")
        return

    show = df.drop(columns=["StocktakeID", "WarehouseID"]).copy()
    for col in ("开始时间", "结案时间"):
        show[col] = pd.to_datetime(show[col]).dt.strftime("%Y-%m-%d %H:%M")

    def _status(v):
        return {"盘点中": "color:#D97706;font-weight:600",
                "已完成": "color:#059669;font-weight:600"}.get(v, "")

    st.dataframe(show.style.map(_status, subset=["状态"]), width="stretch", hide_index=True)


def render() -> None:
    common.page_header(
        "盘点管理",
        "账面数自动带出，实盘数人工录入，差异在结案时转成盘盈/盘亏流水并留痕",
        "📋",
    )
    tab1, tab2, tab3 = st.tabs(["生成盘点单", "录入实盘", "盘点记录"])
    with tab1:
        with st.container(border=True):
            _create_panel()
    with tab2:
        with st.container(border=True):
            _count_panel()
    with tab3:
        _history_panel()
