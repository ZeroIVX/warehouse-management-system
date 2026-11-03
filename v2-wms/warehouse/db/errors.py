# -*- coding: utf-8 -*-
"""
领域异常。

为什么不直接把 pyodbc 的原始异常抛给界面：
  1. 数据库错误信息是给 DBA 看的，用户看不懂「50004」
  2. UI 层需要按类别给不同反馈（红色错误 / 黄色警告 / 引导操作）
  3. 业务异常是领域概念，不该泄漏"底层用的是 SQL Server"这个实现细节

存储过程的错误号在这里做一次映射，是应用与数据库之间唯一的耦合点。
"""


class DomainError(Exception):
    """所有业务异常的基类"""

    code = 0
    default_message = "操作失败"

    def __init__(self, message: str | None = None):
        self.message = message or self.default_message
        super().__init__(self.message)

    def __str__(self) -> str:
        return self.message


class ValidationError(DomainError):
    """入参不合法：数量为 0、必填项为空等"""
    code = 50006
    default_message = "输入参数不合法"


class NotFoundError(DomainError):
    """被引用的实体不存在"""
    code = 50001
    default_message = "对象不存在"


class PermissionDeniedError(DomainError):
    """操作人没有该仓库的授权，或已离职"""
    code = 50003
    default_message = "没有操作该仓库的权限"


class StockShortageError(DomainError):
    """可用库存不足"""
    code = 50004
    default_message = "库存不足"


class CapacityExceededError(DomainError):
    """仓库剩余库容不足"""
    code = 50005
    default_message = "仓库库容不足"


class DuplicateError(DomainError):
    """违反唯一约束"""
    code = 2627
    default_message = "数据已存在，不能重复"


class ReferenceError_(DomainError):
    """违反外键约束（删除仍被引用的数据）"""
    code = 547
    default_message = "该数据仍被其他记录引用，无法删除"


# 存储过程错误号 -> 异常类
_CODE_MAP = {
    50001: NotFoundError,
    50003: PermissionDeniedError,
    50004: StockShortageError,
    50005: CapacityExceededError,
    50006: ValidationError,
    2627: DuplicateError,
    2601: DuplicateError,
    547: ReferenceError_,
}


def translate(exc: BaseException) -> DomainError:
    """
    把 pyodbc / SQLAlchemy 抛出的底层异常翻译成领域异常。

    只做映射，不改原始信息 —— 把数据库原文拼在括号里，
    出问题时仍能定位到具体是哪条约束。
    """
    text = str(exc)

    for code, cls in _CODE_MAP.items():
        if str(code) in text:
            return cls(_clean(str(exc)))

    return DomainError(_clean(text))


def _clean(raw: str) -> str:
    """去掉 pyodbc 那串冗长的驱动前缀，只留人话"""
    for marker in ("] ", ")"):
        pos = raw.rfind(marker)
        if pos != -1 and pos + len(marker) < len(raw):
            tail = raw[pos + len(marker):].strip()
            if tail:
                return tail
    return raw
