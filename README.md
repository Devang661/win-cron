# Windows Claude JSON Cron

这是一个可复制到另一台 Windows PC 的 Claude Code 定时任务小包。它用 Windows 计划任务每隔几分钟唤醒一次，然后读取 `tasks.json`，只运行已经到期的任务。



## 安装办法

｛

https://github.com/Devang661/win-cron
给我安装这个东西，看一下那个 read me 的部分，然后帮我配置一个简单的（每天早上 6 点钟向我问候的作为例子）

｝

括号中的可以替换掉成自己的， 把大括号的东西喂给 Claude Code 或者是 codex

## 文件说明

- `tasks.json`：你真正需要编辑的任务配置。
- `claude_cron.ps1`：调度器，读取 `tasks.json`、判断任务是否到期、记录状态。
- `claude_task.ps1`：执行单个 Claude Code 任务。
- `register_claude_cron_task.ps1`：注册 Windows 计划任务。
- `update_dashboard.ps1`：生成 `dashboard.html`。
- `dashboard.bat`：刷新并打开 dashboard。
- `claude_cron.bat`：手动启动调度器。
- `claude_task.bat`：手动强制运行所有 enabled 任务。
- `run_hidden.vbs`：让计划任务后台静默运行。
- `install-check.ps1`：迁移后的检查脚本。

运行后会自动生成：

- `cron.state.json`：记录每个任务上次成功运行时间。
- `cron.log`：英文调度日志，dashboard 的 Recent Log 只显示它。
- `task-output/`：Claude 任务完整输出，可能包含中文内容。
- `dashboard.html`：任务状态页面。

## 复制到新电脑

1. 把整个 `win-cron` 文件夹复制到新电脑任意位置。

可以放桌面、D 盘、文档目录、项目目录旁边，都可以。脚本会用自身所在目录作为根目录，不要求固定放在 C 盘。

例如：

```text
C:\Users\<你的用户名>\Documents\AutoHotkey\bat\win-cron
D:\tools\win-cron
C:\Users\<你的用户名>\Desktop\win-cron
```

2. 在新电脑安装并登录 Claude Code，确保命令可用：

```powershell
claude --version
```

3. 确认 Git Bash 路径。常见路径是：

```text
C:\Program Files\Git\bin\bash.exe
```

如果新电脑不是这个路径，修改 `tasks.json` 里的 `gitBashPath`。

4. 修改 `tasks.json`：

- 把 `workDir` 改成新电脑上的项目路径。
- 把要启用的任务设为 `"enabled": true`。
- 保持 `name` 唯一。
- 不要在 JSON 里写注释或尾逗号。

5. 运行检查：

```powershell
cd C:\Users\<你的用户名>\Documents\AutoHotkey\bat\win-cron
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-check.ps1
```

6. 注册 Windows 计划任务：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_claude_cron_task.ps1
```

默认会创建任务：

```text
Claude JSON Cron
```

它每 5 分钟检查一次 `tasks.json`。

注意：移动 `win-cron` 文件夹以后，需要在新位置重新运行 `register_claude_cron_task.ps1`，因为 Windows 计划任务里保存的是注册时的脚本路径。

## 新增或修改任务

只需要编辑 `tasks.json`，保存后下一次 5 分钟轮询会自动读取新配置。

任务示例：

```json
{
  "name": "my-daily-task",
  "enabled": true,
  "everyMinutes": 1440,
  "workDir": "C:\\Path\\To\\Workspace",
  "allowedTools": "Read,Write,Edit,Glob,Grep",
  "prompt": [
    "Today is {date}.",
    "Do the task here.",
    "Write outputs in Chinese."
  ]
}
```

字段说明：

- `name`：任务唯一 ID，也是 `cron.state.json` 的状态键。
- `enabled`：`true` 才会执行，`false` 表示暂停。
- `everyMinutes`：执行间隔，`60` 每小时，`1440` 每天，`10080` 每周。
- `workDir`：Claude Code 执行时所在目录。
- `allowedTools`：该任务允许使用的工具。
- `prompt`：交给 Claude Code 的任务说明。

支持占位符：

- `{date}`：当天日期。
- `{datetime}`：当前时间戳。

## 验证配置

```powershell
powershell.exe -NoProfile -Command "Get-Content -Raw .\tasks.json | ConvertFrom-Json | Out-Null; 'tasks json ok'"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\update_dashboard.ps1
```

打开 dashboard：

```powershell
.\dashboard.bat
```

## 手动执行

只检查一次到期任务：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude_cron.ps1 -Once
```

立刻运行某个任务：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude_cron.ps1 -Once -Only obsidian-daily-summary
```

强制运行所有 enabled 任务：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude_cron.ps1 -Once -RunAll
```

谨慎使用 `-RunAll`，它会真的触发所有 enabled 任务。

## 检查计划任务

```powershell
Get-ScheduledTask -TaskName "Claude JSON Cron"
Get-ScheduledTaskInfo -TaskName "Claude JSON Cron"
```

修改检查频率：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_claude_cron_task.ps1 -EveryMinutes 10
```

## 常见问题

如果 dashboard 显示 `Due now`，通常表示任务从未成功运行，或间隔已到。

如果任务反复运行但失败，看 `cron.log`。失败不会更新 `cron.state.json`，所以下一次轮询还会继续尝试。

如果要看 Claude 任务的完整输出，看 `task-output/<task-name>-latest.log`。`cron.log` 会尽量保持英文，避免 dashboard 里出现中文乱码。

如果 `claude` 找不到，把 Claude Code 加到 PATH，或重新打开终端。

如果 Git Bash 路径不存在，修改 `tasks.json` 的 `gitBashPath`。

如果 Claude 报模型或 token plan 不支持，这是 Claude CLI/账号配置问题，不是 Windows 计划任务没生效。
