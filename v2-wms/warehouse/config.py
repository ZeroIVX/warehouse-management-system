# -*- coding: utf-8 -*-
r"""
集中配置。所有连接参数只在这里出现一次，其他模块一律 import 本模块。

优先级：环境变量 > 默认值。
默认值保持通用：本机实例 + Windows 集成认证。
需要 SQL 身份验证时，通过环境变量或项目根目录的 db.env 提供账号，
仓库内不保存任何真实服务器名、账号或密码。
"""
import os


def _load_db_env() -> None:
    """读取项目根目录的 db.env（本地配置，已被 .gitignore 排除）。

    bat 启动时会把变量注入环境；手动运行或跑测试时则由这里补上，
    保证两条路径行为一致。已存在的环境变量优先，不被文件覆盖。
    """
    from pathlib import Path

    env_file = Path(__file__).resolve().parent.parent / "db.env"
    if not env_file.exists():
        return
    for raw in env_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_db_env()


# ---- 数据库 ----
DB_SERVER = os.environ.get("WAREHOUSE_DB_SERVER", "localhost")
DB_NAME = os.environ.get("WAREHOUSE_DB_NAME", "WarehouseDB_V2")
DB_USER = os.environ.get("WAREHOUSE_DB_USER", "")       # 留空 -> Trusted_Connection
DB_PASSWORD = os.environ.get("WAREHOUSE_DB_PASSWORD", "")
DB_DRIVER = os.environ.get("WAREHOUSE_DB_DRIVER", "ODBC Driver 17 for SQL Server")

# ---- 连接池 ----
POOL_SIZE = int(os.environ.get("WAREHOUSE_POOL_SIZE", "10"))
POOL_MAX_OVERFLOW = int(os.environ.get("WAREHOUSE_POOL_OVERFLOW", "20"))
POOL_RECYCLE = 3600          # 每小时回收连接，避免被服务端断开
POOL_PRE_PING = True         # 取连接前先探活

# ---- 业务参数 ----
SAFETY_STOCK = int(os.environ.get("WAREHOUSE_SAFETY_STOCK", "20"))
LOW_STOCK_THRESHOLD = SAFETY_STOCK
ALERT_PAGE_SIZE = 20


def odbc_connection_string(database: str | None = None) -> str:
    """拼接 pyodbc 连接串。database 传 None 时用默认库。"""
    parts = [
        f"DRIVER={{{DB_DRIVER}}}",
        f"SERVER={DB_SERVER}",
        f"DATABASE={database or DB_NAME}",
        # Express 版用自签证书，不跳过校验会报 SSL 错误
        "TrustServerCertificate=yes",
    ]
    if DB_USER:
        parts += [f"UID={DB_USER}", f"PWD={DB_PASSWORD}"]
    else:
        parts.append("Trusted_Connection=yes")
    return ";".join(parts) + ";"
