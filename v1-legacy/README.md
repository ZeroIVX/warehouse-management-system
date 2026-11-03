# 仓库管理系统 V1 · 原始版

> 课程设计原始提交版，单文件 Streamlit 应用 ｜ 9 表 · 3 触发器
>
> 保留此版用于对照与追溯，**不建议用于真实业务**。

---

## 一、这是什么

V1 是项目起点：一个约 750 行的单文件程序，用 `pyodbc` 直连 SQL Server，把界面、SQL、业务判断写在同一层。功能覆盖主数据维护、手工出入库、跨仓调拨、流水查询、库存审计与员工授权，能够完整演示一套库存台账的日常操作。

它解决的问题很明确：**把纸质台账搬到数据库里，让每次出入库留下记录。** 但它没有回答"这笔变动属于哪张单、货在哪个货位、哪批先到期"——这些是 V2 才补上的作业层能力。

---

## 二、为什么保留

1. **可追溯**：能看到重构前的真实写法与真实问题，而不是事后编一个"反面教材"
2. **可对比**：同一套业务，V1 与 V2 的数据库对象、代码组织、错误处理方式差异明显
3. **可运行**：配套建库与演示数据脚本，双击即可启动，便于对照界面与行为

V1 的具体问题清单与 V2 的逐项处理见 [`../docs/04-版本差异与迁移说明.md`](../docs/04-版本差异与迁移说明.md)。

---

## 三、功能

| 模块 | 内容 |
|---|---|
| 库存概览 | 库存总量、低库存提醒、仓库使用率、物品分布 |
| 库存作业 | 手工入库、手工出库、跨仓调拨 |
| 流水记录 | 按类型与关键字查询出入库流水 |
| 基础数据 | 工厂、供应商、仓库、物品、员工与仓库授权 |
| 系统审计 | 库存变动审计、权限变更审计 |

---

## 四、目录

```
v1-legacy/
├── README.md
├── app.py                    原始单文件应用（约 750 行）
├── requirements.txt
├── 启动.bat                  一键启动
├── db.env.example            连接配置模板
├── docs/
│   └── ER图.drawio           9 张表 + 10 条关系的 ER 图
└── sql/
    ├── 01_schema.sql         9 张表 + 3 个触发器
    └── 02_seed.sql           演示数据（构造数据）
```

---

## 五、数据库

| 表 | 作用 |
|---|---|
| `Factory` | 生产厂家 |
| `Supplier` | 供应商 |
| `Warehouse` | 仓库（含库容与已用量） |
| `Item` | 物品 |
| `Staff` | 员工（逻辑删除） |
| `StaffAssignment` | 员工 × 仓库授权 |
| `Storage` | 库存（物品 + 仓库 + 供应商） |
| `Record` | 出入库流水 |
| `AuditLog` | 审计（库存与权限共用一张表） |

触发器：

| 触发器 | 作用 |
|---|---|
| `Updating` | 流水写入后扣减 / 增加库存 |
| `RecordAudit` | 流水写入后写审计 |
| `StaffAssignmentUpdating` | 授权变更写审计 |

ER 图见 [`docs/ER图.drawio`](docs/ER图.drawio)。

---

## 六、运行

### 6.1 前置条件

- Windows 10 / 11
- SQL Server 2016 及以上
- Python 3.9 ~ 3.13
- `sqlcmd`、ODBC Driver 17 for SQL Server

### 6.2 配置

复制 `db.env.example` 为 `db.env`：

```ini
WAREHOUSE_DB_SERVER=localhost
WAREHOUSE_DB_NAME=WarehouseDB_V1
WAREHOUSE_DB_USER=
WAREHOUSE_DB_PASSWORD=
```

`WAREHOUSE_DB_USER` 留空时走 Windows 集成认证。

### 6.3 启动

双击 `启动.bat`，默认访问 <http://localhost:8501>。

脚本会检测 `WarehouseDB_V1`，不存在时询问是否创建并导入演示数据；随后创建虚拟环境、安装依赖并启动。

手动方式：

```bash
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt

sqlcmd -S "localhost" -E -C -b -Q "IF DB_ID(N'WarehouseDB_V1') IS NULL CREATE DATABASE WarehouseDB_V1;"
sqlcmd -S "localhost" -E -C -b -I -f 65001 -d WarehouseDB_V1 -i "sql\01_schema.sql"
sqlcmd -S "localhost" -E -C -b -I -f 65001 -d WarehouseDB_V1 -i "sql\02_seed.sql"

.venv\Scripts\python.exe -m streamlit run app.py --server.port 8501
```

---

## 七、已知问题（V2 已处理）

| 类别 | 问题 |
|---|---|
| 正确性 | 触发器用 `SELECT @var = ... FROM inserted`，批量写入时只处理第一行 |
| 正确性 | 出库按 `SupplierID` 排序扣减，与先进先出无关 |
| 并发 | 库存校验与扣减分离，无锁保护，存在超卖窗口 |
| 一致性 | `WarehouseUsage` 没有维护逻辑，建库后一直是假值 |
| 查询口径 | 库存页 `INNER JOIN Supplier` 会丢掉供应商为空的批次 |
| 数据建模 | `AuditLog` 一表两用，`OldQuantity` / `NewQuantity` 承载过不同语义 |
| 数据建模 | 调拨靠 `Remarks` 中的中文文本区分，无法成组追溯 |
| 安全 | 多处 f-string 拼接 SQL；连接凭据直接写在代码里（归档版已改为环境变量） |
| 可维护 | 单文件混写、裸 `except` 吞异常、每次查询新建连接 |
| 可测试 | 无自动化测试 |

归档改动只有三处，均为可运行性与脱敏需要：

1. 连接参数从硬编码改为 `WAREHOUSE_DB_*` 环境变量，默认 Windows 集成认证
2. 建库脚本的库名由 `WarehouseDB` 改为 `WarehouseDB_V1`，避免与 V2 冲突
3. `Styler.applymap` 增加兼容分支：pandas 3 已移除该方法，改为优先 `Styler.map`，
   旧版本回退到 `applymap`，不改变展示效果

业务逻辑保持原样，未做"顺手重构"。

---

## 八、说明

- 演示数据为构造数据，企业名称、联系人、电话、地址不对应任何真实主体。
- 仓库不包含任何真实服务器名、账号或密码。
- 本版仅用于对照，若需要单据、库位、批次效期、盘点等能力，请使用 [`../v2-wms/`](../v2-wms/)。

---

**作者 / 维护者：Zero**
