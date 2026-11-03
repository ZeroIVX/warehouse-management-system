# -*- coding: utf-8 -*-
"""
视觉主题层：设计 token + 全局样式 + 图表模板。

为什么单独抽一层：
    颜色、圆角、阴影这些如果散落在各页面里，改一次要翻五个文件，而且很快
    就不一致了。这里集中定义，页面只引用语义名（BRAND / DANGER / MUTED），
    不写十六进制。

关于自定义 CSS 的边界：
    Streamlit 没有官方的样式 API，只能注入 CSS。所以这里只挑
    data-testid 这类相对稳定的选择器，不碰自动生成的 class 名 ——
    升级 Streamlit 时不容易整块失效。
"""
from __future__ import annotations

import plotly.graph_objects as go
import plotly.io as pio
import streamlit as st

# ---------------------------------------------------------------- 设计 token
BRAND = "#2563EB"          # 主色：操作、链接、选中态
BRAND_DEEP = "#1D4ED8"
SUCCESS = "#059669"
WARNING = "#D97706"
DANGER = "#DC2626"
INFO = "#0891B2"

INK = "#0F172A"            # 正文最深
INK_2 = "#334155"          # 次级文字
MUTED = "#64748B"          # 说明文字
LINE = "#E2E8F0"           # 分隔线 / 边框
SURFACE = "#FFFFFF"
CANVAS = "#F6F8FB"         # 页面底色

RADIUS = "12px"
RADIUS_SM = "8px"
SHADOW = "0 1px 2px rgba(15,23,42,.04), 0 1px 3px rgba(15,23,42,.06)"

FONT_STACK = (
    '"PingFang SC", "Microsoft YaHei UI", "Microsoft YaHei", '
    '"Segoe UI", "Helvetica Neue", Arial, sans-serif'
)

# 分类色板：给饼图/柱图用，与主色同族，避免 Streamlit 默认的彩虹配色
PALETTE = ["#2563EB", "#0891B2", "#7C3AED", "#059669", "#D97706", "#DB2777", "#64748B"]


def inject_css() -> None:
    """在页面最开始调用一次。"""
    st.markdown(
        f"""
<style>
:root {{
  --brand: {BRAND};
  --ink: {INK};
  --ink-2: {INK_2};
  --muted: {MUTED};
  --line: {LINE};
  --radius: {RADIUS};
  --radius-sm: {RADIUS_SM};
  --shadow: {SHADOW};
}}

/* ---------- 基础排版 ---------- */
html, body, [data-testid="stAppViewContainer"] {{
  font-family: {FONT_STACK};
  color: var(--ink);
}}
[data-testid="stAppViewContainer"] {{ background: {CANVAS}; }}

.block-container {{
  padding-top: 2.4rem;
  padding-bottom: 3.5rem;
  max-width: 1440px;
}}

h1, h2, h3, h4 {{ color: var(--ink); letter-spacing: -.01em; }}
h1 {{ font-size: 1.65rem !important; font-weight: 650; }}
h2 {{ font-size: 1.3rem !important; font-weight: 600; }}
h3 {{ font-size: 1.05rem !important; font-weight: 600; }}

/* 顶部工具条：保留功能但去掉那条实色横杠 */
[data-testid="stHeader"] {{
  background: transparent;
  height: 0;
}}
[data-testid="stToolbar"] {{ right: 1rem; }}

/* Streamlit 1.66 的「安装 skills」开发提示浮层：会盖住右上角的内容区，
   对最终用户没有意义，直接隐藏（不影响任何功能） */
[data-testid="stSkillsNudgeAnchor"],
[data-testid="stSkillsNudge"] {{ display: none !important; }}

/* ---------- 侧边栏：深色，与浅色主体拉开层次 ---------- */
[data-testid="stSidebar"] {{
  background: linear-gradient(180deg, #0F172A 0%, #16233B 100%);
  border-right: none;
}}
[data-testid="stSidebar"] > div:first-child {{ padding-top: .6rem; }}

/* 侧边栏里的文字统一走浅色 */
[data-testid="stSidebar"] p,
[data-testid="stSidebar"] span,
[data-testid="stSidebar"] label,
[data-testid="stSidebar"] h1,
[data-testid="stSidebar"] h2,
[data-testid="stSidebar"] h3 {{ color: #E2E8F0 !important; }}

/* 导航项：把 radio 做成菜单 */
[data-testid="stSidebar"] [role="radiogroup"] {{ gap: 2px; }}
[data-testid="stSidebar"] [role="radiogroup"] label {{
  padding: 9px 12px;
  border-radius: var(--radius-sm);
  transition: background .15s ease, color .15s ease;
  cursor: pointer;
}}
[data-testid="stSidebar"] [role="radiogroup"] label:hover {{
  background: rgba(148,163,184,.14);
}}
/* 选中项：左侧主色竖条 + 淡底 */
[data-testid="stSidebar"] [role="radiogroup"] label:has(input:checked) {{
  background: rgba(37,99,235,.22);
  box-shadow: inset 3px 0 0 var(--brand);
}}
/* 隐藏原生圆点，只留文字 */
[data-testid="stSidebar"] [role="radiogroup"] label > div:first-child {{ display: none; }}
[data-testid="stSidebar"] [role="radiogroup"] label p {{
  font-size: .93rem;
  font-weight: 500;
}}

/* ---------- 指标卡 ---------- */
[data-testid="stMetric"] {{
  background: {SURFACE};
  border: 1px solid var(--line);
  border-radius: var(--radius);
  padding: 14px 18px;
  box-shadow: var(--shadow);
  transition: transform .15s ease, box-shadow .15s ease;
}}
[data-testid="stMetric"]:hover {{
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(15,23,42,.08);
}}
[data-testid="stMetricLabel"] p {{
  font-size: .78rem !important;
  color: var(--muted) !important;
  font-weight: 500;
  letter-spacing: .02em;
}}
[data-testid="stMetricValue"] {{
  font-size: 1.55rem !important;
  font-weight: 650;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
}}

/* ---------- 表格 ---------- */
[data-testid="stDataFrame"] {{
  border: 1px solid var(--line);
  border-radius: var(--radius);
  overflow: hidden;
  box-shadow: var(--shadow);
}}
[data-testid="stDataFrame"] [role="columnheader"] {{
  background: #F1F5F9 !important;
  font-weight: 600 !important;
  color: var(--ink-2) !important;
}}

/* ---------- 按钮 ---------- */
.stButton > button, .stDownloadButton > button {{
  border-radius: var(--radius-sm);
  font-weight: 500;
  border: 1px solid var(--line);
  transition: all .15s ease;
}}
.stButton > button:hover, .stDownloadButton > button:hover {{
  border-color: var(--brand);
  color: var(--brand);
}}
.stButton > button[kind="primary"] {{
  background: var(--brand);
  border-color: var(--brand);
  color: #fff;
  box-shadow: 0 1px 2px rgba(37,99,235,.25);
}}
.stButton > button[kind="primary"]:hover {{
  background: {BRAND_DEEP};
  border-color: {BRAND_DEEP};
  color: #fff;
}}

/* ---------- 输入控件：统一圆角与聚焦色 ---------- */
[data-testid="stTextInput"] input,
[data-testid="stNumberInput"] input,
[data-testid="stDateInput"] input {{
  border-radius: var(--radius-sm);
}}
[data-baseweb="select"] > div {{
  border-radius: var(--radius-sm) !important;
}}

/* ---------- 标签页 ---------- */
[data-testid="stTabs"] [data-baseweb="tab-list"] {{
  gap: 4px;
  border-bottom: 1px solid var(--line);
}}
[data-testid="stTabs"] [data-baseweb="tab"] {{
  border-radius: var(--radius-sm) var(--radius-sm) 0 0;
  padding: 8px 16px;
  font-weight: 500;
}}
[data-testid="stTabs"] [aria-selected="true"] {{
  color: var(--brand) !important;
}}

/* ---------- 提示条：换成更轻的左边框样式 ---------- */
[data-testid="stAlert"] {{
  border-radius: var(--radius-sm);
  border-left-width: 3px;
  box-shadow: none;
}}

/* ---------- 分隔线 ---------- */
hr {{ border-color: var(--line); margin: 1.2rem 0; }}

/* ---------- 自定义组件 ---------- */
.wb-brand {{
  display: flex; align-items: center; gap: 10px;
  padding: 4px 8px 14px 8px;
}}
.wb-brand-mark {{
  width: 34px; height: 34px; border-radius: 9px;
  background: linear-gradient(135deg, {BRAND} 0%, #7C3AED 100%);
  display: flex; align-items: center; justify-content: center;
  font-size: 17px; box-shadow: 0 2px 8px rgba(37,99,235,.35);
}}
.wb-brand-title {{ font-size: .98rem; font-weight: 650; color: #F8FAFC; line-height: 1.2; }}
.wb-brand-sub {{ font-size: .72rem; color: #94A3B8; letter-spacing: .04em; }}

.wb-side-label {{
  font-size: .68rem; text-transform: uppercase; letter-spacing: .09em;
  color: #64748B; margin: 18px 8px 6px 8px; font-weight: 600;
}}

.wb-status {{
  display: flex; align-items: center; gap: 8px;
  padding: 9px 12px; border-radius: var(--radius-sm);
  background: rgba(148,163,184,.10);
  font-size: .8rem; color: #CBD5E1;
}}
.wb-dot {{
  width: 7px; height: 7px; border-radius: 50%; flex: 0 0 auto;
}}
.wb-dot.on {{ background: #22C55E; box-shadow: 0 0 0 3px rgba(34,197,94,.18); }}
.wb-dot.off {{ background: #EF4444; box-shadow: 0 0 0 3px rgba(239,68,68,.18); }}

.wb-page-head {{ margin-bottom: 1.1rem; }}
.wb-page-title {{
  font-size: 1.5rem; font-weight: 650; color: var(--ink);
  display: flex; align-items: center; gap: 10px; line-height: 1.3;
}}
.wb-page-desc {{ font-size: .85rem; color: var(--muted); margin-top: 4px; }}

.wb-empty {{
  text-align: center; padding: 38px 20px;
  border: 1px dashed var(--line); border-radius: var(--radius);
  background: {SURFACE};
}}
.wb-empty-icon {{ font-size: 28px; opacity: .55; }}
.wb-empty-title {{ font-size: .95rem; font-weight: 600; color: var(--ink-2); margin-top: 8px; }}
.wb-empty-hint {{ font-size: .82rem; color: var(--muted); margin-top: 4px; }}

.wb-kbd {{
  display: inline-block; padding: 1px 6px; font-size: .72rem;
  border: 1px solid var(--line); border-radius: 5px;
  background: #F8FAFC; color: var(--ink-2);
}}
</style>
        """,
        unsafe_allow_html=True,
    )


def register_chart_template() -> None:
    """注册统一的 Plotly 模板，让所有图表配色与页面一致。"""
    pio.templates["warehouse"] = go.layout.Template(
        layout=go.Layout(
            colorway=PALETTE,
            font=dict(family=FONT_STACK, size=12, color=INK_2),
            paper_bgcolor="rgba(0,0,0,0)",
            plot_bgcolor="rgba(0,0,0,0)",
            margin=dict(l=10, r=10, t=34, b=10),
            title=dict(font=dict(size=13, color=INK_2), x=0, xanchor="left"),
            xaxis=dict(
                gridcolor=LINE, zeroline=False,
                linecolor=LINE, tickfont=dict(size=11),
                title=dict(font=dict(size=11, color=MUTED)),
            ),
            yaxis=dict(
                gridcolor=LINE, zeroline=False,
                linecolor=LINE, tickfont=dict(size=11),
                title=dict(font=dict(size=11, color=MUTED)),
            ),
            legend=dict(
                orientation="h", yanchor="bottom", y=-0.22,
                xanchor="center", x=0.5, font=dict(size=11),
            ),
            hoverlabel=dict(bgcolor="#0F172A", font_size=12, font_color="#F8FAFC"),
        )
    )
    pio.templates.default = "warehouse"


def setup() -> None:
    """页面开头调用一次即可。"""
    inject_css()
    register_chart_template()
