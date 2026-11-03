# -*- coding: utf-8 -*-
r"""
数据库访问底座：连接池 + 参数化执行 + 异常翻译。

这一层不依赖 Streamlit，可以被单元测试直接调用。

为什么要连接池：
    原版每个辅助函数内部都 get_connection() / close()，一次页面刷新会
    建立十几个物理连接。SQL Server Express 默认连接数有限，并发稍高就
    开始报连接超时。这里交给 SQLAlchemy 的连接池复用，
    并用 pool_pre_ping 处理被服务端闲置断开的死连接。
"""
from __future__ import annotations

import functools
import urllib.parse
from typing import Any, Sequence

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from warehouse import config
from warehouse.db import errors

# 允许被调用的存储过程白名单。
# 过程名无法用占位符参数化，只能靠白名单挡住"把注入点挪到标识符上"。
ALLOWED_PROCEDURES = {
    "sp_PostOperation": (("RecordID", "INT"),),
    "sp_TransferStock": (("TransferGroupID", "UNIQUEIDENTIFIER"),),
    "sp_RecalcWarehouseUsage": (),
    "sp_ReceiveInbound": (("RecordID", "INT"),),
    "sp_ShipOutbound": (("RecordID", "INT"),),
    "sp_CompleteStocktake": (("Adjusted", "INT"),),
    "sp_ShipTransfer": (("TransferGroupID", "UNIQUEIDENTIFIER"),),
}


@functools.lru_cache(maxsize=1)
def get_engine() -> Engine:
    """进程内单例。第一次调用时建池，之后复用。"""
    conn_str = "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(
        config.odbc_connection_string()
    )
    return create_engine(
        conn_str,
        pool_size=config.POOL_SIZE,
        max_overflow=config.POOL_MAX_OVERFLOW,
        pool_recycle=config.POOL_RECYCLE,
        pool_pre_ping=config.POOL_PRE_PING,
        future=True,
    )


def _p(params: dict | None) -> dict:
    return params or {}


def fetch_df(sql: str, params: dict | None = None) -> pd.DataFrame:
    """
    查询并返回 DataFrame。

    sql 必须用 :name 占位符，禁止 f-string 拼接 —— 这是防 SQL 注入的
    唯一可靠做法。原版有 6 处 f-string 拼 SQL，虽然当时取值来自下拉框
    而"暂时"安全，但一旦有人把它改成文本框就是现成的漏洞。
    """
    try:
        with get_engine().connect() as conn:
            return pd.read_sql(text(sql), conn, params=_p(params))
    except Exception as exc:                 # noqa: BLE001 统一翻译成领域异常
        raise errors.translate(exc) from exc


def fetch_one(sql: str, params: dict | None = None):
    try:
        with get_engine().connect() as conn:
            return conn.execute(text(sql), _p(params)).fetchone()
    except Exception as exc:
        raise errors.translate(exc) from exc


def fetch_scalar(sql: str, params: dict | None = None) -> Any:
    row = fetch_one(sql, params)
    return row[0] if row else None


def execute(sql: str, params: dict | None = None) -> int:
    """执行写操作，返回受影响行数。with begin() 自带提交/回滚。"""
    try:
        with get_engine().begin() as conn:
            return conn.execute(text(sql), _p(params)).rowcount
    except Exception as exc:
        raise errors.translate(exc) from exc


def call_procedure(name: str, args: Sequence[tuple[str, Any]] = ()) -> dict:
    """
    调用存储过程。

    args 是 [(参数名, 值), ...]，按名绑定，避免位置错乱。

    输出参数的处理：先 DECLARE 局部变量，执行时以 OUTPUT 回填，
    最后 SELECT 出来取走。比依赖 pyodbc 的 output binding 稳定得多。
    """
    if name not in ALLOWED_PROCEDURES:
        raise ValueError(f"未注册的存储过程: {name}")

    out_specs = ALLOWED_PROCEDURES[name]

    decl = " ".join(f"DECLARE @{n} {t};" for n, t in out_specs)
    bindings = [f"@{n} = ?" for n, _ in args]
    bindings += [f"@{n} = @{n} OUTPUT" for n, _ in out_specs]
    select_out = ("; SELECT " + ", ".join(f"@{n} AS [{n}]" for n, _ in out_specs)) if out_specs else ""

    sql = f"{decl} EXEC dbo.{name} {', '.join(bindings)}{select_out}"

    try:
        import pyodbc

        with pyodbc.connect(config.odbc_connection_string(), autocommit=False) as raw:
            cur = raw.cursor()
            cur.execute(sql, [v for _, v in args])
            result: dict[str, Any] = {}

            while True:
                if cur.description is not None:
                    row = cur.fetchone()
                    if row is not None:
                        cols = [d[0] for d in cur.description]
                        result.update(dict(zip(cols, row)))
                if not cur.nextset():
                    break

            raw.commit()
            return result
    except Exception as exc:
        raise errors.translate(exc) from exc
