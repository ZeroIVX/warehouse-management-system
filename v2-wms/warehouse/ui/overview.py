# -*- coding: utf-8 -*-
"""库存总览 —— 监控大屏。

信息层次按「先看总量、再看结构、然后看趋势与异常、最后看明细」排布：

    第 1 层  KPI 条     —— 六个核心数字，一眼看完全局
    第 2 层  流量 + 结构 —— 出入库趋势（含净变动）、各仓库存占比
    第 3 层  结构细分    —— 品类金额、库存 TOP10、库区占用
    第 4 层  健康度      —— 周转天数、补货与效期待办
    第 5 层  明细        —— 最近流水、可筛选的库存明细（默认收起）

大屏约定：图表高度 ≥ 280、字号 ≥ 12、不放大段表格在首屏，
避免远距离观看时读不清。
"""
from __future__ import annotations

import colorsys

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

from warehouse import config
from warehouse.repository import audit, master, stock
from warehouse.ui import common, theme

CHART_FONT = dict(family=theme.FONT_STACK, size=12.5, color=theme.INK_2)
CHART_H = 300


# ==========================================================================
# 第 1 层：KPI
# ==========================================================================
def _kpi_row() -> None:
    m = stock.summary_metrics()
    expires = stock.expiry_alerts(90)
    expired = int((expires["剩余天数"] < 0).sum()) if not expires.empty else 0

    common.metric_row([
        ("库存总量", f"{m.get('total_stock', 0):,}"),
        ("库存金额", f"¥ {float(m.get('total_amount', 0)) / 10000:,.1f} 万"),
        ("在库品类", f"{m.get('item_count', 0)}"),
        ("仓库数", f"{m.get('warehouse_count', 0)}"),
        ("低库存预警", f"{m.get('alert_count', 0)}"),
        ("临期/过期批次", f"{expired}"),
    ])


# ==========================================================================
# 第 2 层：流量与结构
# ==========================================================================
def _trend_chart(days: int = 14) -> None:
    """出入库柱状 + 净变动折线（双轴）。柱看流量，线看资金/货量的净增减。"""
    df = audit.daily_trend(days)
    if df.empty or float(df["入库"].sum() + df["出库"].sum()) == 0:
        common.empty_state("这段时间没有出入库流水", "去「入库管理」收一次货，这里就会出趋势", "📈")
        return

    df = df.copy()
    df["净变动"] = df["入库"] - df["出库"]

    fig = go.Figure()
    fig.add_trace(go.Bar(x=df["日期"], y=df["入库"], name="入库",
                         marker=dict(color=theme.SUCCESS, line_width=0), opacity=.9))
    fig.add_trace(go.Bar(x=df["日期"], y=df["出库"], name="出库",
                         marker=dict(color=theme.WARNING, line_width=0), opacity=.9))
    fig.add_trace(go.Scatter(
        x=df["日期"], y=df["净变动"], name="净变动", yaxis="y2",
        mode="lines+markers",
        line=dict(color=theme.BRAND, width=2.5),
        marker=dict(size=6, line=dict(width=1.5, color="#fff")),
    ))
    fig.update_layout(
        height=CHART_H, barmode="group", bargap=.32,
        hovermode="x unified", font=CHART_FONT,
        margin=dict(l=8, r=8, t=8, b=44),
        xaxis=dict(tickformat="%m-%d", title=None),
        yaxis=dict(title="出入库量", rangemode="tozero", gridcolor=theme.LINE),
        # 右轴只用于画折线，不重复标注刻度：左轴已经给了量级，两套刻度反而干扰
        yaxis2=dict(overlaying="y", side="right", showgrid=False,
                    showticklabels=False, zeroline=False),
        # 图例放在坐标区下方并留足空隙，否则会压在 x 轴日期上
        legend=dict(orientation="h", y=-0.26, x=0.5, xanchor="center",
                    font=dict(size=11)),
    )
    common.chart(fig)


def _warehouse_donut() -> None:
    """各仓库存量占比 —— 一眼看出货压在哪"""
    df = stock.warehouse_share()
    if df.empty:
        common.empty_state("还没有库存", "", "🏢")
        return

    fig = px.pie(df, values="Qty", names="WarehouseName", hole=.58,
                 color_discrete_sequence=theme.PALETTE)
    # 百分比放环内：outside 会和右侧图例抢位置，小屏或大屏都会互相压
    fig.update_traces(
        textposition="inside", textinfo="percent",
        insidetextorientation="horizontal",
        textfont=dict(size=13.5, color="#FFFFFF"),
        marker=dict(line=dict(color="#fff", width=2)),
    )
    fig.update_layout(
        height=CHART_H, font=CHART_FONT,
        margin=dict(l=24, r=8, t=8, b=8), showlegend=True,
        legend=dict(orientation="v", y=0.5, yanchor="middle", x=1.0,
                    xanchor="left", font=dict(size=10.5)),
    )
    common.chart(fig)


# ==========================================================================
# 第 3 层：结构细分
# ==========================================================================
def _category_bar() -> None:
    """品类金额分布 —— 钱压在哪类货上"""
    df = stock.category_distribution()
    if df.empty:
        common.empty_state("暂无数据", "", "🏷️")
        return

    df = df.sort_values("Amount")
    fig = go.Figure(go.Bar(
        x=df["Amount"], y=df["Category"], orientation="h",
        marker=dict(color=df["Amount"], colorscale=[[0, "#BFDBFE"], [1, theme.BRAND]],
                    line_width=0),
        text=[f"¥{v / 10000:.1f}万" for v in df["Amount"]],
        textposition="outside", textfont=dict(size=11),
    ))
    fig.update_layout(
        height=CHART_H, font=CHART_FONT,
        margin=dict(l=8, r=72, t=8, b=8),
        xaxis=dict(title=None, showgrid=True, gridcolor=theme.LINE, showticklabels=False),
        yaxis=dict(title=None),
        showlegend=False,
    )
    common.chart(fig)


def _top_items_bar() -> None:
    """库存量 TOP10"""
    df = stock.top_items(10)
    if df.empty:
        common.empty_state("暂无数据", "", "📦")
        return

    df = df.sort_values("Qty")
    fig = go.Figure(go.Bar(
        x=df["Qty"], y=df["ItemName"], orientation="h",
        marker=dict(color=theme.PALETTE[1], line_width=0),
        text=df["Qty"], textposition="outside", textfont=dict(size=11),
    ))
    fig.update_layout(
        height=CHART_H, font=CHART_FONT,
        margin=dict(l=8, r=40, t=8, b=8),
        xaxis=dict(title=None, showgrid=True, gridcolor=theme.LINE, showticklabels=False),
        yaxis=dict(title=None),
        showlegend=False,
    )
    common.chart(fig)


def _zone_occupancy() -> None:
    """
    库区货位占用 —— 看的是「用了几个货位 / 一共几个」，
    不是「件数 / 库容」。后者对 2000 容量的货位来说永远是接近 0，
    图上看不出任何差异。
    """
    df = stock.location_heat()
    if df.empty:
        common.empty_state("还没有库位数据", "", "🏗️")
        return

    agg = (df.groupby(["WarehouseName", "ZoneCode"], as_index=False)
             .agg(Total=("LocationCode", "count"),
                  Used=("UsedQty", lambda x: int((x > 0).sum()))))
    agg["Pct"] = (agg["Used"] * 100 / agg["Total"].replace(0, pd.NA)).fillna(0).round(0)
    agg["Label"] = agg["WarehouseName"] + " · " + agg["ZoneCode"]
    agg = agg.sort_values("Pct")

    def _color(v):
        if v >= 90:
            return "#DC2626"
        if v >= 60:
            return "#D97706"
        if v > 0:
            return "#059669"
        return "#CBD5E1"

    fig = go.Figure(go.Bar(
        x=agg["Pct"], y=agg["Label"], orientation="h",
        marker=dict(color=[_color(v) for v in agg["Pct"]], line_width=0),
        text=[f"{int(u)}/{int(t)} 位" for u, t in zip(agg["Used"], agg["Total"])],
        textposition="outside", textfont=dict(size=10.5),
        customdata=agg[["Used", "Total"]].values,
        hovertemplate="%{y}<br>已用 %{customdata[0]} / %{customdata[1]} 个货位<extra></extra>",
    ))
    fig.update_layout(
        height=CHART_H, font=CHART_FONT,
        margin=dict(l=8, r=64, t=8, b=8),
        xaxis=dict(title=None, range=[0, 118], showgrid=True,
                   gridcolor=theme.LINE, showticklabels=False),
        yaxis=dict(title=None, tickfont=dict(size=10.5)),
        showlegend=False,
    )
    common.chart(fig)


# ==========================================================================
# 第 3.5 层：单仓货位矩阵
# ==========================================================================
def _shade(base_hex: str, t: float) -> str:
    """
    按占用比例把基色压深：t=0 最浅，t=1 最深。

    只保留基色的**色相和饱和度**，明度统一重算。
    否则不同品类的原生明度不同（蓝本来就比紫暗），
    同样占用量的两个品类会显出深浅差，占用量就比不上来了。
    """
    r = int(base_hex[1:3], 16) / 255
    g = int(base_hex[3:5], 16) / 255
    b = int(base_hex[5:7], 16) / 255
    h, _lum, sat = colorsys.rgb_to_hls(r, g, b)
    t = max(0.0, min(1.0, t))
    lum = 0.78 - 0.40 * t
    sat = max(0.58, min(0.88, sat))
    r, g, b = colorsys.hls_to_rgb(h, lum, sat)
    return f"rgb({int(r * 255)},{int(g * 255)},{int(b * 255)})"


def _location_matrix(warehouse_id: int, mode: str) -> None:
    """
    货位矩阵：一个格子 = 一个货位。

    两种着色维度：
      品类模式 —— 色相表示品类，明度表示占用量。一眼同时看出"放的是什么"
                 和"放了多少"，这是纯占用量图做不到的。
      占用模式 —— 单色阶表示占用量，用于快速找出最满的货位。

    矩形用 add_shape 逐格画，而不是用 Heatmap：
    Heatmap 的 colorscale 是一维的，表达不了"色相=品类、明度=占用"两个维度。
    """
    df = stock.warehouse_locations(warehouse_id)
    if df.empty:
        common.empty_state("该仓库没有货位", "建库脚本会为每个仓库生成货位", "🏗️")
        return

    mix = stock.location_item_mix(warehouse_id)

    df = df.copy()
    df["Seq"] = df["LocationCode"].str.extract(r"-(\d+)$").astype(int)
    zones = list(dict.fromkeys(df["ZoneCode"]))
    max_seq = int(df["Seq"].max())

    # 每个货位：主品类（存量最多的）、总量、完整构成
    main_cat: dict[str, str] = {}
    total_qty: dict[str, int] = {}
    breakdown: dict[str, str] = {}
    if not mix.empty:
        for code, grp in mix.groupby("LocationCode"):
            grp = grp.sort_values("Qty", ascending=False)
            main_cat[code] = str(grp.iloc[0]["ItemType"])
            total_qty[code] = int(grp["Qty"].sum())
            breakdown[code] = "、".join(f"{r.ItemType} {int(r.Qty)} 件" for r in grp.itertuples())

    cats = sorted({c for c in main_cat.values() if c})
    palette = {c: theme.PALETTE[i % len(theme.PALETTE)] for i, c in enumerate(cats)}
    peak = max(1, max(total_qty.values()) if total_qty else 1)

    fig = go.Figure()
    hx, hy, htext = [], [], []

    for row, zone in enumerate(zones):
        for seq in range(1, max_seq + 1):
            hit = df[(df["ZoneCode"] == zone) & (df["Seq"] == seq)]
            if hit.empty:
                continue                      # 这个位置没有货位 -> 不画

            r = hit.iloc[0]
            code = r["LocationCode"]
            qty = total_qty.get(code, 0)

            if qty == 0:
                fill, label, font_color = "#CBD5E1", "", theme.INK_2
            else:
                cat = main_cat.get(code, "其他")
                # radio 的取值是中文文案，不要拿英文标识去比
                base = palette.get(cat, "#94A3B8") if mode.startswith("品类") else "#3B82F6"
                ratio = qty / peak
                fill = _shade(base, ratio)
                label = f"{qty}"
                # 占用少时底色很浅，白字会糊掉，改用深色字
                font_color = "#FFFFFF" if ratio > 0.30 else theme.INK

            fig.add_shape(
                type="rect",
                x0=seq - 0.46, x1=seq + 0.46,
                y0=row - 0.42, y1=row + 0.42,
                fillcolor=fill,
                line=dict(color="#FFFFFF", width=2),
                layer="below",
            )
            if label:
                fig.add_annotation(x=seq, y=row, text=label, showarrow=False,
                                   font=dict(size=13.5, color=font_color))

            hx.append(seq)
            hy.append(row)
            htext.append(
                f"<b>{code}</b>（{r['ZoneName']}）<br>"
                f"存放：{breakdown.get(code, '空')}<br>"
                f"合计 {qty} 件 · 容量 {int(r['Capacity'])} · 空余 {int(r['Capacity']) - qty}"
            )

    # 透明散点只用来承接 hover（矩形本身不带悬停信息）
    if hx:
        fig.add_trace(go.Scatter(
            x=hx, y=hy, mode="markers",
            marker=dict(size=64, color="rgba(0,0,0,0)"),
            text=htext, hovertemplate="%{text}<extra></extra>",
            showlegend=False,
        ))

    fig.update_layout(
        height=max(210, 62 * len(zones) + 74),
        font=CHART_FONT,
        margin=dict(l=8, r=8, t=8, b=8),
        xaxis=dict(
            range=[0.45, max_seq + 0.55],
            tickmode="array", tickvals=list(range(1, max_seq + 1)),
            ticktext=[f"{i:02d}" for i in range(1, max_seq + 1)],
            side="top", showgrid=False, zeroline=False, tickfont=dict(size=11),
        ),
        yaxis=dict(
            range=[len(zones) - 0.5, -0.5],   # 反向：第一个库区在最上面
            tickmode="array", tickvals=list(range(len(zones))), ticktext=zones,
            showgrid=False, zeroline=False, tickfont=dict(size=12),
        ),
        plot_bgcolor="rgba(0,0,0,0)",
        showlegend=False,
    )
    common.chart(fig)

    # 品类图例：告诉用户每种颜色代表什么
    if mode.startswith("品类") and palette:
        chips = " ".join(
            f'<span style="display:inline-flex;align-items:center;gap:5px;'
            f'margin-right:14px;font-size:.78rem;color:{theme.INK_2}">'
            f'<span style="width:11px;height:11px;border-radius:3px;background:{col};'
            f'display:inline-block"></span>{name}</span>'
            for name, col in palette.items()
        )
        st.markdown(
            f'<div style="margin-top:4px">{chips}'
            f'<span style="font-size:.72rem;color:{theme.MUTED};margin-left:8px">'
            f'（色相=品类，颜色越深占用越多；悬停看完整构成）</span></div>',
            unsafe_allow_html=True,
        )


# ==========================================================================
# 第 4 层：健康度
# ==========================================================================
def _turnover_chart() -> None:
    """周转天数：>90 天视为呆滞，超过 180 天标红"""
    df = stock.turnover(90)
    if df.empty:
        common.empty_state("暂无周转数据", "", "🔄")
        return

    df = df.dropna(subset=["TurnoverDays"]).sort_values("TurnoverDays")
    if df.empty:
        common.empty_state("近 90 天没有出库记录", "没有出库就算不出周转天数", "🔄")
        return

    def _color(v):
        if v >= 180:
            return theme.DANGER
        if v >= 90:
            return theme.WARNING
        return theme.SUCCESS

    fig = go.Figure(go.Bar(
        x=df["TurnoverDays"], y=df["WarehouseName"], orientation="h",
        marker=dict(color=[_color(v) for v in df["TurnoverDays"]], line_width=0),
        text=[f"{v:.0f} 天" for v in df["TurnoverDays"]],
        textposition="outside", textfont=dict(size=11),
    ))
    fig.add_vline(x=90, line_dash="dash", line_color=theme.WARNING, line_width=1,
                  annotation_text="90 天呆滞线", annotation_font_size=10,
                  annotation_position="top")
    fig.update_layout(
        height=CHART_H, font=CHART_FONT,
        margin=dict(l=8, r=48, t=24, b=8),
        xaxis=dict(title=None, showgrid=True, gridcolor=theme.LINE, showticklabels=False),
        yaxis=dict(title=None),
        showlegend=False,
    )
    common.chart(fig)


def _todo_panel() -> None:
    tab_stock, tab_expiry = st.tabs(["补货提醒", "效期预警"])

    with tab_stock:
        alerts = stock.stock_alerts(config.LOW_STOCK_THRESHOLD)
        if alerts.empty:
            st.markdown(
                f'<div class="wb-empty" style="padding:22px 14px">'
                f'<div class="wb-empty-icon">✅</div>'
                f'<div class="wb-empty-title">库存健康</div>'
                f'<div class="wb-empty-hint">都在安全线 {config.LOW_STOCK_THRESHOLD} 以上</div>'
                f'</div>', unsafe_allow_html=True)
        else:
            st.markdown(
                f'<div style="font-size:.82rem;color:{theme.DANGER};font-weight:600;'
                f'margin-bottom:6px">⚠️ {len(alerts)} 组低于安全库存</div>',
                unsafe_allow_html=True)
            st.dataframe(alerts[["物品", "仓库", "库存", "缺口"]].head(7),
                         width="stretch", hide_index=True, height=238)

    with tab_expiry:
        exp = stock.expiry_alerts(90)
        if exp.empty:
            common.hint("90 天内没有临期批次（未登记效期的品类不参与预警）")
        else:
            expired = int((exp["剩余天数"] < 0).sum())
            soon = int(exp["剩余天数"].between(0, 30).sum())
            st.markdown(
                f'<div style="font-size:.82rem;font-weight:600;margin-bottom:6px">'
                f'<span style="color:{theme.DANGER}">已过期 {expired}</span>&nbsp;·&nbsp;'
                f'<span style="color:{theme.WARNING}">30 天内临期 {soon}</span></div>',
                unsafe_allow_html=True)
            st.dataframe(exp[["物品", "货位", "效期", "剩余天数", "库存"]].head(7),
                         width="stretch", hide_index=True, height=238)


# ==========================================================================
# 第 5 层：明细
# ==========================================================================
def _activity_feed() -> None:
    df = audit.recent_activity(10)
    if df.empty:
        common.empty_state("还没有流水", "", "📑")
        return

    df = df.copy()
    df["时间"] = pd.to_datetime(df["OperationTime"]).dt.strftime("%m-%d %H:%M")
    show = df[["时间", "OperationType", "ItemName", "OperationQuantity",
               "WarehouseName", "OperatorName"]].copy()
    show.columns = ["时间", "类型", "物品", "数量", "仓库", "经办人"]

    def _tint(v):
        return ("color:#059669;font-weight:600" if v in ("入库", "调拨入", "盘盈")
                else "color:#D97706;font-weight:600")

    st.dataframe(show.style.map(_tint, subset=["类型"]),
                 width="stretch", hide_index=True, height=300)


def _detail_table() -> None:
    c1, c2, c3 = st.columns([1.4, 1, 1])
    keyword = c1.text_input("搜索物品名称", key="ov_kw", placeholder="支持模糊匹配")
    wh_pairs = master.warehouse_options()
    wh_id = c2.selectbox("仓库", [None] + [k for k, _ in wh_pairs],
                         format_func=lambda x: "全部仓库" if x is None else dict(wh_pairs)[x],
                         key="ov_wh")
    item_type = c3.text_input("规格筛选", key="ov_type")

    df = stock.stock_overview(keyword or None, wh_id, item_type or None)
    if df.empty:
        common.empty_state("没有符合条件的库存", "换个关键词，或清空筛选条件", "🔍")
        return

    st.caption(f"共 {len(df)} 条批次记录 · 该批次库存低于 {config.LOW_STOCK_THRESHOLD} 的行标红"
               "（右上预警按「物品 × 仓库」汇总，两者口径不同属正常）")

    def _highlight_low(row: pd.Series) -> list[str]:
        style = "background-color: #FDECEA; color: #B42318"
        return [style if row["当前库存"] < config.LOW_STOCK_THRESHOLD else "" for _ in row]

    styled = df.style.apply(_highlight_low, axis=1).format({
        "库存金额": "¥ {:,.2f}",
        "更新时间": lambda v: v.strftime("%Y-%m-%d %H:%M") if pd.notna(v) else "",
    })
    st.dataframe(styled, width="stretch", hide_index=True, height=380)


# ==========================================================================
# 页面
# ==========================================================================
def render() -> None:
    common.page_header(
        "库存总览",
        "监控视图：总量 → 结构 → 趋势与异常 → 明细，按大屏阅读顺序排布",
        "📊",
    )

    # 第 1 层
    _kpi_row()

    st.write("")

    # 第 2 层：流量 + 结构
    c_left, c_right = st.columns([2, 1], gap="medium")
    with c_left:
        with st.container(border=True):
            st.markdown("##### 出入库趋势（近 14 天）")
            _trend_chart(14)
    with c_right:
        with st.container(border=True):
            st.markdown("##### 各仓库存占比")
            _warehouse_donut()

    # 第 3 层：结构细分
    c1, c2, c3 = st.columns(3, gap="medium")
    with c1:
        with st.container(border=True):
            st.markdown("##### 品类库存金额")
            _category_bar()
    with c2:
        with st.container(border=True):
            st.markdown("##### 库存量 TOP 10")
            _top_items_bar()
    with c3:
        with st.container(border=True):
            st.markdown("##### 库区占用率")
            _zone_occupancy()

    # 第 3.5 层：单仓货位矩阵
    with st.container(border=True):
        hc1, hc2 = st.columns([3, 1.2])
        hc1.markdown("##### 货位占用矩阵")
        hc1.caption("一个格子一个货位 · 颜色越红占用越多 · 深灰为空货位 · 无色块表示该位置没有货位")
        wh_pairs = master.warehouse_options()
        sel_wh = hc2.selectbox("查看仓库", [k for k, _ in wh_pairs], key="ov_matrix_wh",
                               label_visibility="collapsed",
                               format_func=lambda x: dict(wh_pairs)[x])
        # 一行小统计，让"用了几个 / 空几个"不需要数格子
        _loc = stock.warehouse_locations(sel_wh)
        if not _loc.empty:
            _total = len(_loc)
            _used = int((_loc["UsedQty"] > 0).sum())
            _qty = int(_loc["UsedQty"].sum())
            st.markdown(
                f'<div style="font-size:.82rem;color:{theme.MUTED};margin:2px 0 6px 0">'
                f'本仓 <b style="color:{theme.INK}">{_total}</b> 个货位 · '
                f'已占用 <b style="color:{theme.BRAND}">{_used}</b> 个 · '
                f'空余 <b style="color:{theme.SUCCESS}">{_total - _used}</b> 个 · '
                f'在库 <b style="color:{theme.INK}">{_qty}</b> 件</div>',
                unsafe_allow_html=True)
        _mode = st.radio("着色维度", ["品类 + 占用量", "仅占用量"],
                         horizontal=True, key="mtx_mode")
        _location_matrix(sel_wh, _mode)

    # 第 4 层：健康度
    c4, c5 = st.columns([1.35, 1], gap="medium")
    with c4:
        with st.container(border=True):
            st.markdown("##### 周转天数（近 90 天出库口径）")
            _turnover_chart()
    with c5:
        with st.container(border=True):
            st.markdown("##### 待办提醒")
            _todo_panel()

    # 第 5 层：明细
    c6, c7 = st.columns([1, 1.1], gap="medium")
    with c6:
        with st.container(border=True):
            st.markdown("##### 最近操作")
            _activity_feed()
    with c7:
        with st.container(border=True):
            st.markdown("##### 仓库容量")
            util = stock.warehouse_utilization()
            if util.empty:
                common.empty_state("还没有仓库", "", "🏢")
            else:
                show = util[["WarehouseName", "WarehouseType", "WarehouseSize",
                             "WarehouseUsage", "FreeSpace", "UsagePercent"]].copy()
                show.columns = ["仓库", "类型", "库容", "已用", "剩余", "使用率%"]

                def _u(val):
                    if pd.isna(val):
                        return ""
                    if val >= 90:
                        return "background-color: #FEE4E2; color: #B42318"
                    if val >= 70:
                        return "background-color: #FEF0C7; color: #B54708"
                    return "background-color: #D1FADF; color: #067647"

                st.dataframe(
                    show.style.format({"使用率%": "{:.1f}"}).map(_u, subset=["使用率%"]),
                    width="stretch", hide_index=True, height=300)

    st.divider()
    with st.expander("库存明细（按批次，含货位与效期）", expanded=False):
        _detail_table()
