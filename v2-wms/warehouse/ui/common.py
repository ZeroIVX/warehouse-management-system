# -*- coding: utf-8 -*-
"""UI 公共组件：页头、空状态、结果提示、表格、指标卡。"""
from __future__ import annotations

import pandas as pd
import streamlit as st

from warehouse.service.inventory import OperationResult
from warehouse.ui import theme


# ---------------------------------------------------------------- 页头
def page_header(title: str, desc: str = "", icon: str = "") -> None:
    """
    统一页面头部：标题 + 一句话说明。

    说明文字不是装饰 —— 每个页面写清楚"这里能做什么、规则是什么"，
    用户不用去翻文档。
    """
    mark = f"<span>{icon}</span>" if icon else ""
    html = f'<div class="wb-page-head"><div class="wb-page-title">{mark}{title}</div>'
    if desc:
        html += f'<div class="wb-page-desc">{desc}</div>'
    html += "</div>"
    st.markdown(html, unsafe_allow_html=True)


# ---------------------------------------------------------------- 空状态
def empty_state(title: str, hint: str = "", icon: str = "📭") -> None:
    """
    空状态。

    比 st.info("暂无数据") 多给一步"接下来该干什么"，
    新用户第一次打开时不至于停在空白页面上。
    """
    st.markdown(
        f"""<div class="wb-empty">
              <div class="wb-empty-icon">{icon}</div>
              <div class="wb-empty-title">{title}</div>
              {f'<div class="wb-empty-hint">{hint}</div>' if hint else ''}
            </div>""",
        unsafe_allow_html=True,
    )


# ---------------------------------------------------------------- 结果提示
def show_result(result: OperationResult, toast: bool = True) -> None:
    """
    统一展示用例结果。

    成功时同时给一个右下角 toast —— 它不占版面，操作后
    页面不会因为多出一条 success 条而整体下移。
    """
    if result.ok:
        if toast:
            st.toast(result.message, icon="✅")
        st.success(result.message)
        return

    st.error(result.message)
    if result.error is not None:
        with st.expander("技术细节", expanded=False):
            st.caption(f"异常类型：{type(result.error).__name__}")
            st.code(str(result.error), language="text")


# ---------------------------------------------------------------- 表格
def table(df: pd.DataFrame, height: int | None = None, hide_index: bool = True) -> None:
    """统一表格。空数据走空状态，不渲染一张空表。"""
    if df is None or df.empty:
        empty_state("暂无数据", "先执行一次相关操作，这里就会有内容")
        return
    st.dataframe(df, width="stretch", hide_index=hide_index, height=height)


# ---------------------------------------------------------------- 图表
# 关掉 Plotly 右上角的工具栏（下载/缩放那排按钮）：
# 它默认悬停就出现，直接压住图形右上区域，大屏上尤其碍事。
PLOTLY_CONFIG = {"displayModeBar": False, "scrollZoom": False, "responsive": True}


def chart(fig) -> None:
    st.plotly_chart(fig, width="stretch", config=PLOTLY_CONFIG)


# ---------------------------------------------------------------- 指标
def metric_row(items: list[tuple[str, str]], delta: list[str] | None = None) -> None:
    """一行指标卡：[(标题, 值), ...]"""
    cols = st.columns(len(items))
    for i, (col, (label, value)) in enumerate(zip(cols, items)):
        kwargs = {}
        if delta and i < len(delta) and delta[i]:
            kwargs["delta"] = delta[i]
        col.metric(label, value, **kwargs)


# ---------------------------------------------------------------- 小工具
def section(title: str, caption: str = "") -> None:
    st.subheader(title)
    if caption:
        st.caption(caption)


def spacer(h: int = 8) -> None:
    st.markdown(f'<div style="height:{h}px"></div>', unsafe_allow_html=True)


def badge(text: str, color: str = theme.BRAND) -> str:
    """行内小徽章，返回 HTML 片段（用于拼进 markdown）"""
    return (
        f'<span style="display:inline-block;padding:2px 8px;border-radius:999px;'
        f'font-size:.72rem;font-weight:600;background:{color}18;color:{color};'
        f'border:1px solid {color}33">{text}</span>'
    )


def hint(text: str) -> None:
    """轻量提示：比 st.caption 更弱，用于补充说明"""
    st.markdown(
        f'<div style="font-size:.78rem;color:{theme.MUTED};line-height:1.5">{text}</div>',
        unsafe_allow_html=True,
    )


def choice_map(pairs: list[tuple]) -> dict:
    return {k: v for k, v in pairs}


def pick(label: str, pairs: list[tuple], key: str, allow_none: bool = False,
         none_label: str = "— 请选择 —", index: int = 0):
    """下拉框：把 (id, 名称) 列表包装成选择器，返回值是 id"""
    if not pairs:
        st.warning(f"{label}：没有可选项，请先在「基础数据」里维护")
        return None

    options = [None] + [k for k, _ in pairs] if allow_none else [k for k, _ in pairs]
    labels = {k: v for k, v in pairs}
    if allow_none:
        labels[None] = none_label

    return st.selectbox(label, options, key=key,
                        index=index if options else 0,
                        format_func=lambda x: labels.get(x, str(x)))


def delete_guard(selected, key: str) -> bool:
    """
    删除二次确认。

    流程：勾选"确认删除" -> 按钮才可用 -> 点击后执行并把勾选复位。
    原版是点一下直接删，误触就没有回头路。
    """
    if selected is None:
        return False

    ok = st.checkbox("我确认删除这条数据", key=f"del_confirm_{key}")
    clicked = st.form_submit_button("确认删除", disabled=not ok, width="stretch")
    if clicked and ok:
        st.session_state[f"del_confirm_{key}"] = False
        return True
    return False
