# -*- coding: utf-8 -*-
"""审计页：库存变动 + 权限变动。

原版把两类审计塞进一张 AuditLog，用 OldQuantity 存 StaffID、
NewQuantity 存 WarehouseID —— 字段语义被复用，读数据时得靠
ActionType 反推每个字段是什么意思。这里拆成两张表，字段各司其职。
"""
from __future__ import annotations

import pandas as pd
import streamlit as st

from warehouse.repository import audit
from warehouse.ui import common, theme


def _stock_tab() -> None:
    c1, c2 = st.columns([1, 1])
    action = c1.selectbox("动作", ["全部", "入库", "出库", "调拨入", "调拨出"], key="aud_stock_type")
    limit = c2.selectbox("显示条数", [100, 500, 2000, 0],
                         format_func=lambda x: "全部" if x == 0 else f"最近 {x} 条",
                         key="aud_stock_limit")

    df = audit.stock_audit(None if action == "全部" else action, limit or None)
    if df.empty:
        common.empty_state(
            "还没有库存审计记录",
            "审计由触发器自动写入 —— 去「库存作业」做一次入库或出库，这里立刻就会有数据",
            "🛡️",
        )
        return

    df = df.copy()
    df["时间"] = pd.to_datetime(df["时间"]).dt.strftime("%Y-%m-%d %H:%M:%S")

    def _color(val):
        if pd.isna(val):
            return ""
        return "color: #B42318; font-weight: 600" if val > 0 else "color: #067647; font-weight: 600"

    st.dataframe(
        df.style.map(_color, subset=["变动"]),
        width="stretch", hide_index=True, height=400,
    )
    st.caption(f"共 {len(df)} 条库存变动 · 变动为正表示入库，为负表示出库")


def _perm_tab() -> None:
    c1, c2 = st.columns([1, 1])
    action = c1.selectbox("动作", ["全部", "权限授予", "权限撤销"], key="aud_perm_type")
    limit = c2.selectbox("显示条数", [100, 500, 2000, 0],
                         format_func=lambda x: "全部" if x == 0 else f"最近 {x} 条",
                         key="aud_perm_limit")

    df = audit.permission_audit(None if action == "全部" else action, limit or None)
    if df.empty:
        common.empty_state(
            "还没有权限审计记录",
            "在「基础数据 → 员工与权限」里调整授权，这里会记录每一次变动",
            "🔑",
        )
        return

    df = df.copy()
    df["时间"] = pd.to_datetime(df["时间"]).dt.strftime("%Y-%m-%d %H:%M:%S")
    common.table(df, height=400)
    st.caption(f"共 {len(df)} 条权限变动")


def render() -> None:
    common.page_header(
        "系统审计",
        "审计由触发器写入，应用层无法绕过 —— 任何一次库存或权限变动都必然留痕",
        "🛡️",
    )

    stats = audit.audit_stats()
    common.metric_row([
        ("库存变动总数", f"{stats.get('total_stock', 0):,}"),
        ("今日变动", f"{stats.get('today_stock', 0)}"),
        ("近七日变动", f"{stats.get('week_stock', 0)}"),
        ("权限变动", f"{stats.get('total_perm', 0)}"),
    ])

    st.write("")
    tab1, tab2 = st.tabs(["库存变动", "权限变动"])
    with tab1:
        _stock_tab()
    with tab2:
        _perm_tab()
