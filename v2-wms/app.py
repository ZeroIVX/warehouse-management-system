# -*- coding: utf-8 -*-
"""
智能仓库管理系统 —— 应用入口。

只做三件事：初始化主题、渲染侧边栏、把请求分发给对应页面。
业务逻辑一律不写在这个文件里。
"""
from __future__ import annotations

import streamlit as st

from warehouse import config
from warehouse.db import engine, errors
from warehouse.ui import (audit, inbound, master_data, operations, outbound,
                          overview, records, stocktake, theme)

# 分成两组：日常作业 / 台账与配置。八项平铺在侧边栏里太长，也分不清主次。
PAGES = {
    "库存概览": ("📊", overview.render),
    "入库管理": ("📥", inbound.render),
    "出库管理": ("📤", outbound.render),
    "盘点管理": ("📋", stocktake.render),
    "调拨管理": ("🔄", operations.render),
    "流水记录": ("📑", records.render),
    "基础数据": ("🗂️", master_data.render),
    "系统审计": ("🛡️", audit.render),
}


def _sidebar() -> str:
    with st.sidebar:
        st.markdown(
            """
            <div class="wb-brand">
              <div class="wb-brand-mark">📦</div>
              <div>
                <div class="wb-brand-title">智能仓库管理系统</div>
                <div class="wb-brand-sub">WAREHOUSE CONSOLE</div>
              </div>
            </div>
            """,
            unsafe_allow_html=True,
        )

        st.markdown('<div class="wb-side-label">功能导航</div>', unsafe_allow_html=True)

        page = st.radio(
            "功能导航",
            list(PAGES.keys()),
            format_func=lambda k: f"{PAGES[k][0]}  {k}",
            label_visibility="collapsed",
        )

        st.markdown('<div class="wb-side-label">数据库</div>', unsafe_allow_html=True)
        _db_status()

        st.markdown('<div class="wb-side-label">关于</div>', unsafe_allow_html=True)
        st.markdown(
            """
            <div style="font-size:.75rem;color:#94A3B8;line-height:1.7;padding:0 8px">
              <b style="color:#CBD5E1">数据库综合设计</b><br>
              SQL Server 2025 · Streamlit<br>
              视图 / 存储过程 / 触发器<br>
              事务与并发控制
            </div>
            """,
            unsafe_allow_html=True,
        )

    return page


def _db_status() -> None:
    """
    连接状态。连不上时给出可操作的排查路径，而不是抛一屏红字 ——
    这类错误几乎都出在服务没起、账号密码、建库脚本没跑这三件事上。
    """
    try:
        engine.fetch_scalar("SELECT 1")
    except errors.DomainError as exc:
        st.markdown(
            '<div class="wb-status"><span class="wb-dot off"></span>数据库未连接</div>',
            unsafe_allow_html=True,
        )
        with st.expander("查看原因与排查", expanded=True):
            st.caption(str(exc))
            st.markdown(
                "1. 确认 SQL Server 服务已启动\n"
                "2. 确认实例名与账号密码（可用环境变量 `WAREHOUSE_DB_*` 覆盖）\n"
                "3. 确认已执行 `sql/01~06` 建库脚本"
            )
        st.stop()

    st.markdown(
        f"""<div class="wb-status">
              <span class="wb-dot on"></span>
              <span>已连接 · {config.DB_NAME}</span>
            </div>""",
        unsafe_allow_html=True,
    )
    st.markdown(
        f'<div style="font-size:.7rem;color:#64748B;padding:6px 10px;'
        f'font-family:ui-monospace,Consolas,monospace">{config.DB_SERVER}</div>',
        unsafe_allow_html=True,
    )


def main() -> None:
    st.set_page_config(
        page_title="智能仓库管理系统",
        page_icon="📦",
        layout="wide",
        initial_sidebar_state="expanded",
    )

    theme.setup()

    page = _sidebar()
    PAGES[page][1]()

    st.divider()
    st.markdown(
        f'<div style="text-align:center;font-size:.72rem;color:{theme.MUTED};padding:6px 0 24px">'
        "智能仓库管理系统 V2 &nbsp;|&nbsp; "
        "SQL Server 2025 + Streamlit &nbsp;|&nbsp; Zero</div>",
        unsafe_allow_html=True,
    )


if __name__ == "__main__":
    main()
