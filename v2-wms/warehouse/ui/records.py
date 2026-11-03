# -*- coding: utf-8 -*-
"""流水记录页。"""
from __future__ import annotations

import datetime as dt

import pandas as pd
import streamlit as st

from warehouse.repository import audit
from warehouse.ui import common, theme


def render() -> None:
    common.page_header(
        "流水记录",
        "Record 表就是不可变的历史账，一条记录对应一次库存动作；调拨会成对出现，可用组号核对",
        "📑",
    )

    with st.container(border=True):
        c1, c2, c3 = st.columns([1, 1.4, 1])
        op_type = c1.selectbox("类型", ["全部", "入库", "出库", "调拨入", "调拨出"], key="rec_type")
        keyword = c2.text_input("搜索物品或经办人", key="rec_kw", placeholder="支持模糊匹配")
        limit = c3.selectbox("显示条数", [100, 500, 2000, 0],
                             format_func=lambda x: "全部" if x == 0 else f"最近 {x} 条",
                             index=0, key="rec_limit")

        today = dt.date.today()
        rng = st.date_input(
            "时间范围（留空表示不限）",
            value=(),
            key="rec_range",
            format="YYYY-MM-DD",
            help="起止均可单独使用；结束日期当天包含在内",
        )

    start = end = None
    if isinstance(rng, (list, tuple)) and len(rng) == 2:
        start, end = rng
    elif isinstance(rng, dt.date):
        start = end = rng

    df = audit.operation_log(
        None if op_type == "全部" else op_type,
        keyword or None,
        start, end,
        limit or None,
    )

    if df.empty:
        common.empty_state("没有符合条件的记录", "放宽筛选条件，或去「库存作业」做一次出入库", "📭")
        return

    df = df.copy()
    df["时间"] = pd.to_datetime(df["时间"]).dt.strftime("%Y-%m-%d %H:%M:%S")

    # 入库/调拨入用绿、出库/调拨出用橙，扫一眼就能分出方向
    def _tint(val):
        if val in ("入库", "调拨入"):
            return "color: #059669; font-weight: 600"
        return "color: #D97706; font-weight: 600"

    left, right = st.columns([3, 1])
    left.caption(f"共 {len(df)} 条")
    with right:
        st.download_button(
            "导出 CSV",
            df.to_csv(index=False).encode("utf-8-sig"),
            file_name=f"operation_records_{today}.csv",
            mime="text/csv",
            width="stretch",
        )

    st.dataframe(
        df.style.map(_tint, subset=["类型"]),
        width="stretch", hide_index=True, height=430,
    )

    # ---------------- 调拨核对 ----------------
    st.divider()
    with st.expander("调拨核对：输入组号，还原一对流水", expanded=False):
        common.hint("调拨会把「调拨出」和「调拨入」两条流水绑在同一个组号下，"
                    "这里可以确认两端是否都成功入账。")
        group_id = st.text_input("调拨组号（UNIQUEIDENTIFIER）", key="rec_group",
                                 placeholder="例如 3F2A8C1E-...")
        if group_id:
            pair = audit.transfer_group(group_id.strip())
            if pair.empty:
                st.warning("未找到该组号的记录，请检查是否复制完整")
            else:
                common.table(pair)
