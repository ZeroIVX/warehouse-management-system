import os

import streamlit as st
import pyodbc
import pandas as pd
import plotly.express as px


# ==========================================
# 1. 数据库连接配置
# ==========================================
# 归档版改动：连接参数改为环境变量驱动，仓库内不保存任何真实账号或密码。
# 未提供用户名时走 Windows 集成认证。
def _load_db_env() -> None:
    """读取同目录的 db.env；环境变量优先。"""
    from pathlib import Path

    env_file = Path(__file__).resolve().parent / "db.env"
    if not env_file.exists():
        return
    for raw in env_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_db_env()

DB_SERVER = os.environ.get("WAREHOUSE_DB_SERVER", "localhost")
DB_NAME = os.environ.get("WAREHOUSE_DB_NAME", "WarehouseDB_V1")
DB_USER = os.environ.get("WAREHOUSE_DB_USER", "")
DB_PASSWORD = os.environ.get("WAREHOUSE_DB_PASSWORD", "")


def get_connection():
    parts = [
        "DRIVER={ODBC Driver 17 for SQL Server}",
        f"SERVER={DB_SERVER}",
        f"DATABASE={DB_NAME}",
        "TrustServerCertificate=yes",
        "CHARSET=UTF8",
    ]
    if DB_USER:
        parts += [f"UID={DB_USER}", f"PWD={DB_PASSWORD}"]
    else:
        parts.append("Trusted_Connection=yes")
    return pyodbc.connect(";".join(parts) + ";")


# ==========================================
# 2. 核心辅助函数
# ==========================================

def get_simple_options(table_name, id_col, name_col):
    """通用下拉框函数"""
    try:
        conn = get_connection()
        query = f"SELECT {id_col}, {name_col} FROM {table_name}"
        df = pd.read_sql(query, conn)
        conn.close()
        return dict(zip(df[id_col], df[name_col]))
    except:
        return {}


def get_item_detailed_options():
    """物品专用详细选项"""
    try:
        conn = get_connection()
        sql = "SELECT i.ItemID, i.ItemName, i.ItemType, f.FactName FROM Item i JOIN Factory f ON i.FactoryID = f.FactID"
        df = pd.read_sql(sql, conn)
        conn.close()
        return {row['ItemID']: f"{row['ItemName']} [{row['ItemType']}] - {row['FactName']} (ID: {row['ItemID']})" for
                _, row in df.iterrows()}
    except:
        return {}


def get_warehouses_with_stock(item_id):
    """根据物品ID获取所有有库存的仓库列表"""
    try:
        conn = get_connection()
        # 查询 Storage 表中存储量 > 0 的仓库
        sql = """
              SELECT DISTINCT w.WarehouseID, w.WarehouseName
              FROM Storage s
                       JOIN Warehouse w ON s.WarehouseID = w.WarehouseID
              WHERE s.ItemID = ? \
                AND s.Storing > 0 \
              """
        df = pd.read_sql(sql, conn, params=(item_id,))
        conn.close()
        return dict(zip(df['WarehouseID'], df['WarehouseName']))
    except Exception as e:
        st.error(f"查询仓库失败: {e}")
        return {}


def get_specific_stock(item_id, wh_id, s_id):
    """获取特定库位的精确库存数值（适配方案3）"""
    try:
        conn = get_connection()
        # 分支逻辑：s_id 为 None 时查询仓库总库存
        if s_id is None:
            sql = "SELECT ISNULL(SUM(Storing), 0) FROM Storage WHERE ItemID = ? AND WarehouseID = ?"
            params = (item_id, wh_id)
        else:
            # 选了具体供应商，使用 ISNULL 确保 NULL 安全匹配
            sql = """
                  SELECT ISNULL(SUM(Storing), 0)
                  FROM Storage
                  WHERE ItemID = ? \
                    AND WarehouseID = ? \
                    AND ISNULL(SupplierID, 0) = ISNULL(?, 0) \
                  """
            params = (item_id, wh_id, s_id)

        df = pd.read_sql(sql, conn, params=params)
        conn.close()
        return int(df.iloc[0, 0]) if not df.empty else 0
    except Exception as e:
        st.error(f"获取余量失败: {e}")
        return 0


def get_sups_for_item_in_wh(item_id, wh_id):
    """获取某物品在特定仓库下的所属供应商，并始终强制添加‘不指定供应商’选项"""
    try:
        conn = get_connection()
        # 查找该库位下现有的供应商
        sql = """
              SELECT DISTINCT st.SupplierID, s.SupName
              FROM Storage st
                       LEFT JOIN Supplier s ON st.SupplierID = s.SupID
              WHERE st.ItemID = ? \
                AND st.WarehouseID = ? \
                AND st.Storing > 0 \
              """
        df = pd.read_sql(sql, conn, params=(item_id, wh_id))
        conn.close()

        # 1. 初始化选项字典，首先强行加入 None (不指定供应商)
        options = {None: "⚪ 不指定供应商 (NULL)"}

        # 2. 将数据库中查到的其他供应商加入字典
        for _, row in df.iterrows():
            sid = row['SupplierID']
            # 如果 sid 本身就是 None，上面的初始化已经覆盖了；如果是具体 ID，则添加
            if pd.notnull(sid):
                options[int(sid)] = row['SupName']

        return options
    except Exception as e:
        st.error(f"查询供应商失败: {e}")
        return {None: "⚪ 不指定供应商 (NULL)"}


def check_potential_duplicate(name, item_type, factory_id):
    conn = get_connection()
    df = pd.read_sql("SELECT ItemID FROM Item WHERE ItemName=? AND ItemType=? AND FactoryID=?",
                     conn, params=(name, item_type, factory_id))
    conn.close()
    return df


def get_staffs_by_warehouse(wh_id):
    """根据 StaffAssignment 表获取特定仓库的在职员工"""
    try:
        conn = get_connection()
        # 通过 JOIN 关联表来筛选员工
        sql = """
            SELECT s.StaffID, s.StaffName 
            FROM Staff s
            JOIN StaffAssignment sa ON s.StaffID = sa.StaffID
            WHERE sa.WarehouseID = ? AND s.IsActive = 1
        """
        df = pd.read_sql(sql, conn, params=(wh_id,))
        conn.close()
        return dict(zip(df['StaffID'], df['StaffName']))
    except Exception as e:
        st.error(f"查询员工权限失败: {e}")
        return {}

# ==========================================
# 3. 页面布局
# ==========================================
st.set_page_config(page_title="仓库管理系统", layout="wide")
st.title("📦 智能仓库管理系统")

menu = st.sidebar.selectbox("功能导航", ["📊 库存概览", "📝 入库/出库操作", "📑 流水账记录", "⚙️ 基础数据录入","🛠️ 系统审计"])

# ------------------------------------------------------------------
# 模块 A: 库存概览 (带预警与饼图)
# ------------------------------------------------------------------
if menu == "📊 库存概览":
    st.header("📊 实时库存监控与分析")

    # 1. 筛选控制
    c1, c2, c3 = st.columns(3)
    with c1:
        search_name = st.text_input("🔍 搜索物品")
    with c2:
        whs = get_simple_options("Warehouse", "WarehouseID", "WarehouseName")
        sel_wh = st.selectbox("🏢 选择仓库", [None] + list(whs.keys()),
                              format_func=lambda x: "全部仓库" if x is None else whs[x])
    with c3:
        search_type = st.text_input("🏷️ 规格筛选")

    # 2. 构建查询
    sql = """
          SELECT i.ItemName AS [物品], i.ItemType AS [规格], 
               w.WarehouseName AS [仓库], s.SupName AS [供应商],
               st.Storing AS [当前库存], st.LastUpdate AS [更新时间]
          FROM Storage st
              JOIN Item i \
          ON st.ItemID = i.ItemID
              JOIN Warehouse w ON st.WarehouseID = w.WarehouseID
              JOIN Supplier s ON st.SupplierID = s.SupID
          WHERE 1=1 \
          """
    params = []
    if search_name: sql += " AND i.ItemName LIKE N'%' + ? + '%'"; params.append(search_name)
    if sel_wh: sql += " AND w.WarehouseID = ?"; params.append(sel_wh)
    if search_type: sql += " AND i.ItemType LIKE N'%' + ? + '%'"; params.append(search_type)

    try:
        conn = get_connection();
        df = pd.read_sql(sql, conn, params=params);
        conn.close()

        if not df.empty:
            # 库存预警函数：库存 <= [预警数量] 标红
            def alert_low_stock(val):
                color = '#FF4B4B' if val <= 20 else ''  # 阈值可根据需要调整
                return f'background-color: {color}; color: white' if color else ''


            st.write("### 库存明细 (红色表示库存紧张)")
            # pandas 2.1+ 用 Styler.map，2.0 用 applymap；pandas 3 已移除后者。
            _styler = df.style
            _styled = (_styler.map(alert_low_stock, subset=['当前库存'])
                       if hasattr(_styler, "map")
                       else _styler.applymap(alert_low_stock, subset=['当前库存']))
            st.dataframe(_styled, use_container_width=True)

            # 3. 可视化分析
            st.divider()
            v1, v2 = st.columns(2)
            with v1:
                st.write("**仓库储量占比 (条形图)**")
                st.bar_chart(df.groupby("仓库")["当前库存"].sum())
            with v2:
                st.write("**规格类型分布 (饼状图)**")
                # 使用 Plotly 绘制饼图
                fig = px.pie(df, values='当前库存', names='规格', hole=0.3,
                             color_discrete_sequence=px.colors.qualitative.Pastel)
                st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("未找到符合条件的库存。")
    except Exception as e:
        st.error(f"查询出错: {e}")

# ------------------------------------------------------------------
# 模块 B: 入库/出库操作
# ------------------------------------------------------------------
elif menu == "📝 入库/出库操作":
    st.header("🛒 库存作业中心")
    tab_in, tab_out, tab_move = st.tabs(["➕ 货物入库", "➖ 货物出库", "🔄 库存转移"])

    detailed_items = get_item_detailed_options()
    warehouses = get_simple_options("Warehouse", "WarehouseID", "WarehouseName")

    # --- 1. 入库模块 ---
    with tab_in:
        with st.form("in_form_pro"):
            c1, c2 = st.columns(2)
            i_id = c1.selectbox("物品", list(detailed_items.keys()), format_func=lambda x: detailed_items[x])
            w_id = c1.selectbox("目标仓库", list(warehouses.keys()), format_func=lambda x: warehouses[x])

            # 动态获取员工
            in_allowed_staffs = get_staffs_by_warehouse(w_id)
            stf = c1.selectbox("经办人 (仅限该库员工)", list(in_allowed_staffs.keys()),
                               format_func=lambda x: in_allowed_staffs[x] if in_allowed_staffs else "⚠️ 无授权员工")

            # 供应商 (可选不指定)
            all_sups = get_simple_options("Supplier", "SupID", "SupName")
            s_id = c2.selectbox("供应商", [None] + list(all_sups.keys()),
                                format_func=lambda x: "⚪ 不指定供应商" if x is None else all_sups[x])
            qty = c2.number_input("入库数量", min_value=1)

            if st.form_submit_button("确认入库"):
                if not in_allowed_staffs:
                    st.error("无法操作：该仓库未分配员工。")
                else:
                    try:
                        conn = get_connection();
                        cur = conn.cursor()
                        cur.execute(
                            "INSERT INTO Record (ItemID, WarehouseID, SupplierID, OperatorID, OperationType, OperationQuantity) VALUES (?,?,?,?,N'入库',?)",
                            (i_id, w_id, s_id, stf, qty))
                        conn.commit();
                        st.success("入库成功");
                        import time
                        time.sleep(1)
                        st.rerun()
                    except Exception as e:
                        st.error(f"失败: {e}")

    # --- 2. 出库模块 ---
    with tab_out:
        selected_item = st.selectbox("1. 选择物品", [None] + list(detailed_items.keys()),
                                     format_func=lambda x: "--- 请选择 ---" if x is None else detailed_items[x],
                                     key="out_item")
        if selected_item:
            available_whs = get_warehouses_with_stock(selected_item)
            if not available_whs:
                st.warning("全线无货")
            else:
                # 仓库选择放在 Form 外以触发经办人联动
                out_w_id = st.selectbox("2. 选择仓库", list(available_whs.keys()),
                                        format_func=lambda x: available_whs[x])

                with st.form("out_form_pro"):
                    col1, col2 = st.columns(2)
                    # 动态获取员工
                    out_allowed_staffs = get_staffs_by_warehouse(out_w_id)
                    stf = col1.selectbox("3. 经办人", list(out_allowed_staffs.keys()),
                                         format_func=lambda x: out_allowed_staffs[x])

                    # 供应商与库存 (方案3逻辑)
                    out_sups = get_sups_for_item_in_wh(selected_item, out_w_id)
                    s_id = col1.selectbox("4. 供应商", list(out_sups.keys()), format_func=lambda x: out_sups[x])

                    max_qty = get_specific_stock(selected_item, out_w_id, s_id)
                    col2.metric("当前余量", f"{max_qty} 件")
                    qty = col2.number_input("5. 出库数量", min_value=1, max_value=max(1, max_qty))

                    if st.form_submit_button("确认出库"):
                        if not out_allowed_staffs:
                            st.error("无权限员工")
                        else:
                            try:
                                conn = get_connection();
                                cur = conn.cursor()
                                cur.execute(
                                    "INSERT INTO Record (ItemID, WarehouseID, SupplierID, OperatorID, OperationType, OperationQuantity) VALUES (?,?,?,?,N'出库',?)",
                                    (selected_item, out_w_id, s_id, stf, qty))
                                conn.commit();
                                st.success("成功");
                                import time
                                time.sleep(1)
                                st.rerun()
                            except Exception as e:
                                st.error(str(e))

    # --- 3. 转移模块 ---
    with tab_move:
        st.subheader("🔄 跨仓库库存调拨")
        st.info("规则：发货人需拥有源仓库权限，接收人需拥有目标仓库权限。")

        # 1. 选择物品
        move_item = st.selectbox("1. 选择转移物品", [None] + list(detailed_items.keys()),
                                 format_func=lambda x: "--- 请选择 ---" if x is None else detailed_items[x],
                                 key="move_item_dual")

        if move_item:
            # 2. 获取有货的源仓库
            src_whs = get_warehouses_with_stock(move_item)

            if not src_whs:
                st.warning("该物品目前无库存可供转移。")
            else:
                # 来源选择 (表单外以实时触发余量刷新)
                c_top1, c_top2 = st.columns(2)
                with c_top1:
                    src_w_id = st.selectbox("2. 来源仓库 (从哪转出)", list(src_whs.keys()),
                                            format_func=lambda x: src_whs[x], key="move_src_wh")
                with c_top2:
                    move_sups = get_sups_for_item_in_wh(move_item, src_w_id)
                    move_s_id = st.selectbox("3. 选择所属供应商", list(move_sups.keys()),
                                             format_func=lambda x: move_sups[x], key="move_src_sup")

                # 获取源仓库当前余量
                max_move = get_specific_stock(move_item, src_w_id, move_s_id)
                st.metric(f"📍 {src_whs[src_w_id]} 可用余量", f"{max_move} 件")

                st.divider()

                # --- 调拨核心表单 ---
                with st.form("dual_staff_transfer_form"):
                    col1, col2 = st.columns(2)

                    with col1:
                        # 目标仓库选择
                        dst_wh_options = {k: v for k, v in warehouses.items() if k != src_w_id}
                        dst_w_id = st.selectbox("4. 目标仓库 (转入到哪)", list(dst_wh_options.keys()),
                                                format_func=lambda x: dst_wh_options[x])

                        # 权限校验：获取源仓库在职员工 (发货人)
                        src_allowed_staff = get_staffs_by_warehouse(src_w_id)
                        out_staff = st.selectbox("5. 发货经办人 (需源库权限)", list(src_allowed_staff.keys()),
                                                 format_func=lambda x: src_allowed_staff[
                                                     x] if src_allowed_staff else "🚫 无权限员工")

                    with col2:
                        move_qty = st.number_input("6. 转移数量", min_value=1, max_value=max(1, max_move), step=1)

                        # 权限校验：获取目标仓库在职员工 (接收人)
                        dst_allowed_staff = get_staffs_by_warehouse(dst_w_id)
                        in_staff = st.selectbox("7. 接收经办人 (需目标库权限)", list(dst_allowed_staff.keys()),
                                                format_func=lambda x: dst_allowed_staff[
                                                    x] if dst_allowed_staff else "🚫 无权限员工")

                    if st.form_submit_button("🚀 确认调拨对接"):
                        if not src_allowed_staff or not dst_allowed_staff:
                            st.error("❌ 无法操作：源仓库或目标仓库未配置在职员工。")
                        elif max_move < move_qty:
                            st.error("❌ 提交瞬间源仓库库存不足。")
                        else:
                            try:
                                conn = get_connection()
                                cur = conn.cursor()
                                # 1. 插入源仓库出库记录 (由发货人操作)
                                cur.execute("""
                                            INSERT INTO Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                                                OperationType, OperationQuantity, Remarks)
                                            VALUES (?, ?, ?, ?, N'出库', ?, N'调拨-发货')
                                            """, (move_item, src_w_id, move_s_id, out_staff, move_qty))

                                # 2. 插入目标仓库入库记录 (由接收人操作)
                                cur.execute("""
                                            INSERT INTO Record (ItemID, WarehouseID, SupplierID, OperatorID,
                                                                OperationType, OperationQuantity, Remarks)
                                            VALUES (?, ?, ?, ?, N'入库', ?, N'调拨-接收')
                                            """, (move_item, dst_w_id, move_s_id, in_staff, move_qty))

                                conn.commit()
                                st.success(
                                    f"✅ 调拨成功！{move_qty}件物品已在 {src_allowed_staff[out_staff]} 与 {dst_allowed_staff[in_staff]} 之间完成对接。")
                                import time

                                time.sleep(1)
                                st.rerun()
                            except Exception as e:
                                st.error(f"❌ 调拨失败: {e}")

# ------------------------------------------------------------------
# 模块 C: 流水记录
# ------------------------------------------------------------------
elif menu == "📑 流水账记录":
    st.header("📑 历史流水账记录")

    # 增加筛选功能，方便排查
    col1, col2 = st.columns(2)
    with col1:
        type_filter = st.selectbox("过滤类型", ["全部", "入库", "出库"])

    # 使用 LEFT JOIN 避免因为某个 ID 为 NULL 导致整行记录不显示
    sql = """
          SELECT r.RecordID AS [编号],
            r.OperationTime AS [操作时间],
            r.OperationType AS [类型],
            i.ItemName AS [物品名称],
            r.OperationQuantity AS [数量],
            w.WarehouseName AS [仓库],
            ISNULL(s.SupName, N'---') AS [供应商],
            ISNULL(st.StaffName, N'未知') AS [经办人]
          FROM Record r
              LEFT JOIN Item i \
          ON r.ItemID = i.ItemID
              LEFT JOIN Warehouse w ON r.WarehouseID = w.WarehouseID
              LEFT JOIN Supplier s ON r.SupplierID = s.SupID
              LEFT JOIN Staff st ON r.OperatorID = st.StaffID
          WHERE 1=1 \
          """

    if type_filter != "全部":
        sql += f" AND r.OperationType = N'{type_filter}'"

    sql += " ORDER BY r.OperationTime DESC"

    try:
        conn = get_connection()
        df = pd.read_sql(sql, conn)
        conn.close()

        if not df.empty:
            # 格式化时间显示
            df['操作时间'] = pd.to_datetime(df['操作时间']).dt.strftime('%Y-%m-%d %H:%M:%S')
            st.dataframe(df, use_container_width=True, hide_index=True)

            # 下载功能
            csv = df.to_csv(index=False).encode('utf-8-sig')
            st.download_button("📥 导出流水账 (CSV)", csv, "inventory_records.csv", "text/csv")
        else:
            st.info("暂无操作记录。")
    except Exception as e:
        st.error(f"查询流水账失败: {e}")

# ------------------------------------------------------------------
# 模块 D: 基础数据录入
# ------------------------------------------------------------------
elif menu == "⚙️ 基础数据录入":
    st.header("🏢 基础信息维护中心")
    t_fact, t_wh, t_item, t_sup, t_staff = st.tabs(["工厂", "仓库", "物品", "供应商", "员工"])

    # --- 1. 工厂管理 ---
    with t_fact:
        col_e, col_l = st.columns([1, 2])
        with col_e:
            facts = get_simple_options("Factory", "FactID", "FactName")
            f_id = st.selectbox("选择工厂", [None] + list(facts.keys()), format_func=lambda x: "➕ 新增" if x is None else facts[x])
            with st.form("f_form"):
                old = {"FactName":"", "FactAddress":"", "FactTel":""}
                if f_id:
                    df = pd.read_sql(f"SELECT * FROM Factory WHERE FactID={f_id}", get_connection())
                    if not df.empty: old = df.iloc[0].to_dict()
                fn = st.text_input("工厂名", value=old["FactName"])
                fa = st.text_input("地址", value=old["FactAddress"])
                ft = st.text_input("电话", value=old["FactTel"])
                b1, b2 = st.columns(2)
                if b1.form_submit_button("保存"):
                    conn = get_connection(); cur = conn.cursor()
                    if f_id: cur.execute("UPDATE Factory SET FactName=?, FactAddress=?, FactTel=? WHERE FactID=?", (fn, fa, ft, f_id))
                    else: cur.execute("INSERT INTO Factory (FactName, FactAddress, FactTel) VALUES (?,?,?)", (fn, fa, ft))
                    conn.commit(); st.rerun()
                if b2.form_submit_button("🗑️ 删除"):
                    try:
                        conn = get_connection(); cur = conn.cursor()
                        cur.execute(f"DELETE FROM Factory WHERE FactID={f_id}"); conn.commit(); st.rerun()
                    except: st.error("外键约束：该工厂下有物品记录")
        with col_l: st.dataframe(pd.read_sql("SELECT * FROM Factory", get_connection()))

    # --- 2. 仓库管理 ---
    with t_wh:
        col_e, col_l = st.columns([1, 2])
        with col_e:
            whs = get_simple_options("Warehouse", "WarehouseID", "WarehouseName")
            w_id = st.selectbox("选择仓库", [None] + list(whs.keys()), format_func=lambda x: "➕ 新增" if x is None else whs[x])
            with st.form("w_form"):
                old = {"WarehouseName":"", "WarehouseAddress":"", "WarehouseType":"常温", "WarehouseSize":100}
                if w_id:
                    df = pd.read_sql(f"SELECT * FROM Warehouse WHERE WarehouseID={w_id}", get_connection())
                    if not df.empty: old = df.iloc[0].to_dict()
                wn = st.text_input("仓库名", value=old["WarehouseName"])
                wt = st.selectbox("类型", ["常温", "冷藏", "特种"], index=0)
                ws = st.number_input("库容", min_value=1, value=int(old["WarehouseSize"]))
                b1, b2 = st.columns(2)
                if b1.form_submit_button("保存"):
                    conn = get_connection(); cur = conn.cursor()
                    if w_id: cur.execute("UPDATE Warehouse SET WarehouseName=?, WarehouseType=?, WarehouseSize=? WHERE WarehouseID=?", (wn, wt, ws, w_id))
                    else: cur.execute("INSERT INTO Warehouse (WarehouseName, WarehouseType, WarehouseSize) VALUES (?,?,?)", (wn, wt, ws))
                    conn.commit(); st.rerun()
                if b2.form_submit_button("🗑️ 删除"):
                    try:
                        conn = get_connection(); cur = conn.cursor()
                        cur.execute(f"DELETE FROM Warehouse WHERE WarehouseID={w_id}"); conn.commit(); st.rerun()
                    except: st.error("仓库内仍有库存或记录")
        with col_l: st.dataframe(pd.read_sql("SELECT * FROM Warehouse", get_connection()))

    # --- 3. 物品管理 (审核制) ---
    with t_item:
        if 'pending_item' not in st.session_state: st.session_state.pending_item = None
        col_e, col_l = st.columns([1, 2])
        with col_e:
            items_list = get_simple_options("Item", "ItemID", "ItemName")
            i_id = st.selectbox("选择物品", [None] + list(items_list.keys()), format_func=lambda x: "➕ 新增" if x is None else f"{items_list[x]} (ID:{x})")
            factories = get_simple_options("Factory", "FactID", "FactName")
            with st.form("i_form", clear_on_submit=True):
                old = {"ItemName":"", "ItemType":"", "Price":0.0, "FactoryID": None}
                if i_id:
                    df_o = pd.read_sql(f"SELECT * FROM Item WHERE ItemID={i_id}", get_connection())
                    if not df_o.empty: old = df_o.iloc[0].to_dict()
                inm = st.text_input("物品名", value=old["ItemName"])
                itp = st.text_input("规格", value=old["ItemType"])
                ipr = st.number_input("单价", value=float(old["Price"]))
                f_keys = list(factories.keys())
                f_idx = f_keys.index(old["FactoryID"]) if old["FactoryID"] in f_keys else 0
                ifid = st.selectbox("所属工厂", f_keys, index=f_idx, format_func=lambda x: factories[x])
                b1, b2 = st.columns(2)
                if b1.form_submit_button("保存"):
                    if i_id:
                        conn = get_connection(); cur = conn.cursor()
                        cur.execute("UPDATE Item SET ItemName=?, ItemType=?, Price=?, FactoryID=? WHERE ItemID=?", (inm, itp, ipr, ifid, i_id))
                        conn.commit(); st.rerun()
                    else:
                        dupes = check_potential_duplicate(inm, itp, ifid)
                        if not dupes.empty: st.session_state.pending_item = (inm, itp, ipr, ifid)
                        else:
                            conn = get_connection(); cur = conn.cursor()
                            cur.execute("INSERT INTO Item (ItemName, ItemType, Price, FactoryID) VALUES (?,?,?,?)", (inm, itp, ipr, ifid))
                            conn.commit(); st.rerun()
                if b2.form_submit_button("🗑️ 删除"):
                    try:
                        conn = get_connection(); cur = conn.cursor()
                        cur.execute(f"DELETE FROM Item WHERE ItemID={i_id}"); conn.commit(); st.rerun()
                    except: st.error("已有出入库流水记录")
            if st.session_state.pending_item:
                st.warning("⚠️ 检测到重复规格物品")
                if st.button("确认是新物品，强制添加"):
                    p = st.session_state.pending_item
                    conn = get_connection(); cur = conn.cursor()
                    cur.execute("INSERT INTO Item (ItemName, ItemType, Price, FactoryID) VALUES (?,?,?,?)", (p[0], p[1], p[2], p[3]))
                    conn.commit(); st.session_state.pending_item = None; st.rerun()
        with col_l: st.dataframe(pd.read_sql("SELECT i.ItemID, i.ItemName, i.ItemType, f.FactName FROM Item i JOIN Factory f ON i.FactoryID=f.FactID", get_connection()))

    # --- 4. 供应商管理 ---
    with t_sup:
        col_e, col_l = st.columns([1, 2])
        with col_e:
            sups = get_simple_options("Supplier", "SupID", "SupName")
            s_id = st.selectbox("选择供应商", [None] + list(sups.keys()), format_func=lambda x: "➕ 新增" if x is None else sups[x])
            with st.form("s_form"):
                old = {"SupName":"", "SupAddress":"", "SupTel":""}
                if s_id:
                    df = pd.read_sql(f"SELECT * FROM Supplier WHERE SupID={s_id}", get_connection())
                    if not df.empty: old = df.iloc[0].to_dict()
                sn = st.text_input("供应商名", value=old["SupName"])
                sa = st.text_input("地址", value=old["SupAddress"])
                st_ = st.text_input("电话", value=old["SupTel"])
                b1, b2 = st.columns(2)
                if b1.form_submit_button("保存"):
                    conn = get_connection(); cur = conn.cursor()
                    if s_id: cur.execute("UPDATE Supplier SET SupName=?, SupAddress=?, SupTel=? WHERE SupID=?", (sn, sa, st_, s_id))
                    else: cur.execute("INSERT INTO Supplier (SupName, SupAddress, SupTel) VALUES (?,?,?)", (sn, sa, st_))
                    conn.commit(); st.rerun()
                if b2.form_submit_button("🗑️ 删除"):
                    try:
                        conn = get_connection(); cur = conn.cursor()
                        cur.execute(f"DELETE FROM Supplier WHERE SupID={s_id}"); conn.commit(); st.rerun()
                    except: st.error("该供应商有供应记录在库")
        with col_l: st.dataframe(pd.read_sql("SELECT * FROM Supplier", get_connection()))

    # --- 5. 员工管理 ---
    with t_staff:
        col_e, col_l = st.columns([1, 2])
        with col_e:
            stfs = get_simple_options("Staff", "StaffID", "StaffName")
            st_id = st.selectbox("选择员工", [None] + list(stfs.keys()),
                                 format_func=lambda x: "➕ 新增员工" if x is None else stfs[x])

            # 获取所有仓库选项
            all_wh_opts = get_simple_options("Warehouse", "WarehouseID", "WarehouseName")

            with st.form("st_form_assignment"):
                old = {"StaffName": "", "StaffTel": "", "IsActive": 1}
                current_assignments = []

                if st_id:
                    # 获取基本信息
                    df_s = pd.read_sql(f"SELECT * FROM Staff WHERE StaffID={st_id}", get_connection())
                    if not df_s.empty: old = df_s.iloc[0].to_dict()
                    # 获取已分配的仓库
                    df_sa = pd.read_sql(f"SELECT WarehouseID FROM StaffAssignment WHERE StaffID={st_id}",
                                        get_connection())
                    current_assignments = df_sa['WarehouseID'].tolist()

                stn = st.text_input("姓名", value=old["StaffName"])
                stt = st.text_input("电话", value=old["StaffTel"])
                sta = st.checkbox("在职状态", value=True if old["IsActive"] else False)

                # 关键：多选仓库分配
                assigned_whs = st.multiselect("分配在职仓库 (多选)", options=list(all_wh_opts.keys()),
                                              default=current_assignments,
                                              format_func=lambda x: all_wh_opts[x])

                if st.form_submit_button("保存员工及其权限"):
                    conn = get_connection();
                    cur = conn.cursor()
                    if st_id:
                        cur.execute("UPDATE Staff SET StaffName=?, StaffTel=?, IsActive=? WHERE StaffID=?",
                                    (stn, stt, 1 if sta else 0, st_id))
                        # 清除旧权限
                        cur.execute("DELETE FROM StaffAssignment WHERE StaffID=?", (st_id,))
                    else:
                        cur.execute("INSERT INTO Staff (StaffName, StaffTel, IsActive) VALUES (?,?,?)",
                                    (stn, stt, 1 if sta else 0))
                        cur.execute("SELECT @@IDENTITY");
                        st_id = cur.fetchone()[0]

                    # 插入新权限
                    for w_id in assigned_whs:
                        cur.execute("INSERT INTO StaffAssignment (StaffID, WarehouseID) VALUES (?,?)", (st_id, w_id))

                    conn.commit();
                    st.success("信息及权限已同步更新");
                    st.rerun()

        with col_l:
            st.write("### 员工权限清单")
            # 联表查询显示员工负责的仓库
            staff_list_sql = """
                             SELECT s.StaffName AS [姓名], s.StaffTel AS [电话],
                       CASE WHEN s.IsActive=1 THEN N'在职' ELSE N'离职' \
                             END AS [状态],
                       ISNULL(STRING_AGG(w.WarehouseName, '、'), N'未分配') AS [所属仓库]
                FROM Staff s
                LEFT JOIN StaffAssignment sa ON s.StaffID = sa.StaffID
                LEFT JOIN Warehouse w ON sa.WarehouseID = w.WarehouseID
                GROUP BY s.StaffName, s.StaffTel, s.IsActive \
                             """
            st.dataframe(pd.read_sql(staff_list_sql, get_connection()), use_container_width=True)

# --- 🛠️ 系统审计模块 ---
elif menu == "🛠️ 系统审计":
    st.header("🛠️ 系统安全审计日志")
    st.info("说明：本日志详细记录了权限变更(员工/仓库)及库存变动(操作前/操作后)的数值。")

    # 1. 筛选器
    search_type = st.selectbox("过滤操作类型", ["全部", "权限授予", "权限撤销", "入库", "出库"])

    # 2. 核心 SQL 逻辑
    sql = """
          SELECT a.LogID AS [编号],
            a.ChangeTime AS [操作时间],
            a.ActionType AS [动作类型],
            CASE 
                -- 权限审计显示员工姓名，库存审计显示物品名称
                WHEN a.ActionType IN (N'权限授予', N'权限撤销') 
                    THEN (SELECT StaffName FROM Staff WHERE StaffID = a.OldQuantity)
                WHEN a.ActionType IN (N'入库', N'出库')
                    THEN (SELECT i.ItemName FROM Record r JOIN Item i ON r.ItemID = i.ItemID WHERE r.RecordID = a.RecordID)
                ELSE N'--'
          END \
          AS [审计对象],
            CASE 
                -- 权限场景显示无数值，库存场景显示原库存
                WHEN a.ActionType IN (N'权限授予', N'权限撤销') THEN N'权限变更'
                WHEN a.ActionType IN (N'入库', N'出库') THEN CAST(ISNULL(a.OldQuantity, 0) AS NVARCHAR)
                ELSE N'--'
          END \
          AS [变更前数据],
            CASE 
                -- 权限场景显示所属仓库，库存场景显示新库存
                WHEN a.ActionType IN (N'权限授予', N'权限撤销') 
                    THEN (SELECT WarehouseName FROM Warehouse WHERE WarehouseID = a.NewQuantity)
                WHEN a.ActionType IN (N'入库', N'出库') THEN CAST(ISNULL(a.NewQuantity, 0) AS NVARCHAR)
                ELSE N'--'
          END \
          AS [变更后数据],
            ISNULL(s.StaffName, N'系统执行') AS [执行人]
        FROM AuditLog a
        LEFT JOIN Staff s ON a.OperatorID = s.StaffID
        WHERE 1=1 \
          """

    # 拼接过滤条件
    if search_type != "全部":
        sql += f" AND a.ActionType = N'{search_type}'"

    # 确保排序在最后
    sql += " ORDER BY a.ChangeTime DESC"

    try:
        conn = get_connection()
        df_audit = pd.read_sql(sql, conn)
        conn.close()

        if not df_audit.empty:
            # 3. 使用 st.dataframe 配合列配置，使对比更直观
            st.dataframe(
                df_audit,
                use_container_width=True,
                hide_index=True,
                column_config={
                    "变更前数据": st.column_config.TextColumn("⬅️ 原数据 / 状态"),
                    "变更后数据": st.column_config.TextColumn("➡️ 修改后数据 / 目标")
                }
            )
        else:
            st.info("📅 当前暂无符合条件的审计记录。")
    except Exception as e:
        st.error(f"读取审计日志出错，请检查 SQL 语法或数据库表结构。详情: {e}")