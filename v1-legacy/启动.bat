@echo off
chcp 936 >nul 2>&1
setlocal enabledelayedexpansion
title 仓库管理系统 V1 - 启动器
cd /d "%~dp0"

set "APP=%~dp0app.py"
set "VENV=%~dp0.venv"
set "PY=%VENV%\Scripts\python.exe"
set "REQ=%~dp0requirements.txt"
set "SQLDIR=%~dp0sql"
set "ENVFILE=%~dp0db.env"
set "DBNAME=WarehouseDB_V1"
set "PORT=8501"

echo ============================================================
echo        仓 库 管 理 系 统   V1  ·  原 始 版
echo ============================================================
echo.

if not exist "%APP%" (
    echo [错误] 未找到 app.py，请把本脚本放在项目根目录。
    goto :fail
)

rem ---------- 读取本地数据库配置 ----------
if exist "%ENVFILE%" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENVFILE%") do set "%%A=%%B"
)
if not defined WAREHOUSE_DB_SERVER set "WAREHOUSE_DB_SERVER=localhost"
if not defined WAREHOUSE_DB_NAME set "WAREHOUSE_DB_NAME=%DBNAME%"
if not defined WAREHOUSE_DB_USER set "WAREHOUSE_DB_USER="
if not defined WAREHOUSE_DB_PASSWORD set "WAREHOUSE_DB_PASSWORD="
set "SQLAUTH=-E"
if defined WAREHOUSE_DB_USER set "SQLAUTH=-U !WAREHOUSE_DB_USER! -P !WAREHOUSE_DB_PASSWORD!"

set "DBNAME=!WAREHOUSE_DB_NAME!"
set "TRIES=0"

:check_db
rem ---------- 检查数据库连通性 ----------
where sqlcmd >nul 2>&1
if errorlevel 1 (
    echo [错误] 未检测到 sqlcmd。请安装 SQL Server 命令行工具，
    echo        或把 SQL Server 的 Tools\Binn 目录加入 PATH。
    goto :fail
)

echo [1/5] 连接数据库 !WAREHOUSE_DB_SERVER! / !DBNAME! ...
sqlcmd -S "!WAREHOUSE_DB_SERVER!" !SQLAUTH! -C -d master -h -1 -W -Q "SET NOCOUNT ON; SELECT 1" >nul 2>&1
if errorlevel 1 (
    echo       [失败] 无法连接。请检查实例名、认证方式与服务状态。
    if not exist "%ENVFILE%" (
        set /a TRIES+=1
        if !TRIES! LEQ 1 goto :configure
    )
    echo       可复制 db.env.example 为 db.env 后修改，再重新运行本脚本。
    goto :fail
)

set "DBEXIST="
set "DBEXIST="
for /f "usebackq tokens=*" %%L in (`sqlcmd -S "!WAREHOUSE_DB_SERVER!" !SQLAUTH! -C -d master -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'!DBNAME!') IS NULL THEN 0 ELSE 1 END"`) do set "DBEXIST=%%L"

if "!DBEXIST!"=="1" (
    echo       数据库已存在，跳过初始化。
) else (
    echo       数据库不存在。
    choice /c YN /n /m "       是否立即创建并导入演示数据？[Y/N] "
    if errorlevel 2 (
        echo       已取消。程序将无法连接数据库。
        goto :fail
    )
    call :init_db
    if errorlevel 1 goto :fail
)

rem ---------- Python 环境 ----------
echo [2/5] 检查 Python ...
set "PY_CMD="
py -3.13 -c "import sys" >nul 2>&1 && set "PY_CMD=py -3.13"
if not defined PY_CMD py -3.12 -c "import sys" >nul 2>&1 && set "PY_CMD=py -3.12"
if not defined PY_CMD py -3.11 -c "import sys" >nul 2>&1 && set "PY_CMD=py -3.11"
if not defined PY_CMD python -c "import sys; assert (3,9) <= sys.version_info[:2] < (3,14)" >nul 2>&1 && set "PY_CMD=python"
if not defined PY_CMD (
    echo       [错误] 未找到 Python 3.9 ~ 3.13。
    goto :fail
)

if exist "%PY%" (
    echo [3/5] 虚拟环境已存在。
) else (
    echo [3/5] 创建虚拟环境 .venv ...
    %PY_CMD% -m venv "%VENV%"
    if not exist "%PY%" (
        echo       [错误] 虚拟环境创建失败。
        goto :fail
    )
)

if exist "%VENV%\.deps_ok" (
    echo [4/5] 依赖已安装。
) else (
    echo [4/5] 安装依赖（首次运行需要几分钟）...
    rem 国内网络默认走清华镜像；已设置 PIP_INDEX_URL 时以用户配置为准
    if not defined PIP_INDEX_URL set "PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/"
    "%PY%" -m pip install --upgrade pip -q --disable-pip-version-check
    "%PY%" -m pip install -r "%REQ%" -q --disable-pip-version-check
    if errorlevel 1 (
        echo       [错误] 依赖安装失败。
        goto :fail
    )
    type nul > "%VENV%\.deps_ok"
)

rem ---------- 交给应用 ----------
set "WAREHOUSE_DB_SERVER=!WAREHOUSE_DB_SERVER!"
set "WAREHOUSE_DB_NAME=!DBNAME!"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

echo [5/5] 启动 Streamlit（端口 !PORT!）...
echo       浏览器将自动打开 http://localhost:!PORT!
echo       关闭本窗口或按 Ctrl+C 即可停止。
echo.
"%PY%" -m streamlit run "%APP%" --server.port !PORT! --server.address localhost --server.headless false --browser.gatherUsageStats false
goto :eof


:configure
echo.
echo ---------- 首次配置数据库连接 ----------
echo 提示：密码会保存在本地 db.env（已被 .gitignore 排除），请勿提交到仓库。
set "INPUT="
set /p "INPUT=SQL Server 实例（例如 localhost\SQLEXPRESS）[localhost]: "
if not "!INPUT!"=="" set "WAREHOUSE_DB_SERVER=!INPUT!"
set "INPUT="
set /p "INPUT=使用 Windows 集成认证？[Y/n]: "
if /i "!INPUT!"=="n" (
    set /p "WAREHOUSE_DB_USER=SQL 登录名: "
    set /p "WAREHOUSE_DB_PASSWORD=密码: "
    set "SQLAUTH=-U !WAREHOUSE_DB_USER! -P !WAREHOUSE_DB_PASSWORD!"
) else (
    set "WAREHOUSE_DB_USER="
    set "WAREHOUSE_DB_PASSWORD="
    set "SQLAUTH=-E"
)
> "%ENVFILE%" (
    echo # 本地数据库连接配置，请勿提交到版本库
    echo WAREHOUSE_DB_SERVER=!WAREHOUSE_DB_SERVER!
    echo WAREHOUSE_DB_NAME=!DBNAME!
    echo WAREHOUSE_DB_USER=!WAREHOUSE_DB_USER!
    echo WAREHOUSE_DB_PASSWORD=!WAREHOUSE_DB_PASSWORD!
)
echo       已写入 db.env。
goto :check_db


:init_db
echo       正在建库 ...
sqlcmd -S "!WAREHOUSE_DB_SERVER!" !SQLAUTH! -C -d master -b -Q "IF DB_ID(N'!DBNAME!') IS NULL CREATE DATABASE [!DBNAME!];" >nul
if errorlevel 1 (
    echo       [错误] 创建数据库失败。
    exit /b 1
)
for %%F in (01_schema 02_seed) do (
    echo         - %%F.sql
    sqlcmd -S "!WAREHOUSE_DB_SERVER!" !SQLAUTH! -C -b -I -f 65001 -d "!DBNAME!" -i "%SQLDIR%\%%F.sql" >nul
    if errorlevel 1 (
        echo       [错误] %%F.sql 执行失败。
        exit /b 1
    )
)
echo       建库完成。
exit /b 0


:fail
echo.
echo 启动中止。请根据上面的提示处理后重试。
pause
exit /b 1
