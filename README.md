# hfut-campus-auth

用于合肥工业大学宣城校区（Dr.COM 门户）的 Windows 开机自动认证工具。

## 功能概览

- 开机登录后自动执行（任务计划 `CampusAuthAtLogon`，延迟 30 秒）
- 仅在有线网卡场景触发（避免干扰 Wi-Fi）
- 从 Windows 凭据管理器读取账号密码（目标名：`CampusPortalAuth`）
- 自动读取 `0.htm + a41.js` 参数并按 Dr.COM 规则加密提交
- 失败自动重试（默认 5 次，每次间隔 10 秒）
- 结构化日志输出到 `C:\ProgramData\CampusAuth\auth.log`

## 目录结构

- `scripts/campus-auth.ps1`：核心认证脚本
- `scripts/install-task.ps1`：安装/更新开机任务
- `scripts/uninstall-task.ps1`：卸载开机任务
- `config/config.example.json`：配置模板
- `docs/troubleshooting.md`：故障排查

## 环境要求

- Windows 10/11
- PowerShell 5.1 或 PowerShell 7+
- 可访问校园网认证门户（如 `http://172.18.3.3/0.htm`）

## 快速开始

1. 复制本地配置：

```powershell
Copy-Item .\config\config.example.json .\config\config.local.json
```

2. 写入凭据（仅本机执行，不要提交到仓库）：

```powershell
cmdkey /generic:CampusPortalAuth /user:你的学号 /pass:你的密码
```

3. 安装开机任务：

```powershell
.\scripts\install-task.ps1
```

4. 手动试跑一次：

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\CampusAuth\campus-auth.ps1
```

5. 查看日志：

```powershell
Get-Content C:\ProgramData\CampusAuth\auth.log -Tail 50
```

## 成功判定

满足以下两项可认为认证成功：

- 脚本退出码为 `0`
- 日志包含 `Campus auth succeeded`

可选再做外网连通性确认：

```powershell
Invoke-WebRequest http://www.msftconnecttest.com/connecttest.txt -UseBasicParsing
```

## 配置说明（`config.local.json`）

默认推荐：

- `auth_mode`: `drcom_hfut`
- `portal_page_url`: `http://172.18.3.3/0.htm`
- `interface_mode`: `ethernet_only`
- `max_retries`: `5`
- `retry_interval_sec`: `10`

说明：

- `drcom_hfut` 模式下会自动从登录页与 JS 提取 `ps/pid/calg/0MKKey/para/v6ip`，无需手工抓包字段。
- `portal_url/payload_template` 主要用于保留的模板模式兼容，不是当前推荐路径。

## 常见命令

- 更新任务（脚本变更后建议执行一次）：

```powershell
.\scripts\install-task.ps1
```

- 卸载任务：

```powershell
.\scripts\uninstall-task.ps1
```

- 卸载任务并清理运行目录：

```powershell
.\scripts\uninstall-task.ps1 -RemoveRuntime
```

## 近期修复记录

- 修复了变量名冲突问题：脚本内部 `pid` 与 PowerShell 内置只读变量 `$PID` 冲突，现已改为独立变量名，避免认证阶段报错。

## 安全说明

- 不要提交 `config/config.local.json`
- 不要提交账号、密码、Cookie、抓包原始文件或其他密钥材料
- 凭据仅通过 Windows Credential Manager 管理（`CampusPortalAuth`）

## 许可证

MIT
