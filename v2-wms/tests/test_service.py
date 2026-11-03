# -*- coding: utf-8 -*-
"""
service 层单元测试 —— 只测参数校验与错误转换，不连数据库。

这些用例之所以写得出来，是因为校验逻辑放在了调用存储过程之前：
拿到非法参数时直接返回，不产生任何数据库往返。

用法：python tests/test_service.py
"""
import sys
from pathlib import Path

# 允许在 tests/ 目录下直接运行：把项目根加入模块搜索路径
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from warehouse.service import inventory  # noqa: E402

results = []


def expect(name, result, ok: bool, keyword: str = ""):
    passed = (result.ok is ok) and (keyword in result.message if keyword else True)
    results.append(passed)
    mark = "PASS" if passed else "FAIL"
    print(f"  [{mark}] {name} -> {result.message}")


def main():
    print("inventory.inbound 参数校验")
    expect("未选物品", inventory.inbound(None, 1, None, 1, 5), False, "物品")
    expect("未选仓库", inventory.inbound(1, None, None, 1, 5), False, "仓库")
    expect("未选经办人", inventory.inbound(1, 1, None, None, 5), False, "经办人")
    expect("数量为 0", inventory.inbound(1, 1, None, 1, 0), False, "大于 0")
    expect("数量为负", inventory.inbound(1, 1, None, 1, -3), False, "大于 0")

    print("\ninventory.outbound 参数校验")
    expect("未选物品", inventory.outbound(None, 1, None, 1, 5), False, "物品")
    expect("未选仓库", inventory.outbound(1, None, None, 1, 5), False, "仓库")
    expect("未选经办人", inventory.outbound(1, 1, None, None, 5), False, "经办人")
    expect("数量为 0", inventory.outbound(1, 1, None, 1, 0), False, "大于 0")

    print("\ninventory.transfer 参数校验")
    expect("未选物品", inventory.transfer(None, 1, 2, None, 5, 1, 1), False, "物品")
    expect("仓库相同", inventory.transfer(1, 1, 1, None, 5, 1, 1), False, "不能相同")
    expect("缺少发货人", inventory.transfer(1, 1, 2, None, 5, None, 1), False, "发货人")
    expect("缺少收货人", inventory.transfer(1, 1, 2, None, 5, 1, None), False, "收货人")
    expect("数量为 0", inventory.transfer(1, 1, 2, None, 0, 1, 1), False, "大于 0")

    total = len(results)
    ok = sum(results)
    print(f"\n{'=' * 40}\n通过 {ok}/{total}")
    return 0 if ok == total else 1


if __name__ == "__main__":
    sys.exit(main())
