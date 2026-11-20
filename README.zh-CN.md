# cpath

**一键复制规范化绝对路径，原生兼容本地与 SSH 远程会话。**

[English](README.md) | 简体中文

`cpath` 是一个零依赖、独立的 Bash 命令行工具，用于获取文件或目录的规范化绝对路径并写入剪贴板。在本地自动适配 macOS、Linux（Wayland / X11）与 Windows WSL；在 SSH 远程会话中自动切换为 **OSC 52** 转义序列，直接穿透写入本地剪贴板，无需 X11 转发，也不绑定任何 Shell 框架。

## 特性

- **零依赖、跨 Shell**：独立可执行脚本（`~/.local/bin/cpath`），Bash、Zsh、Fish 和子脚本均可直接调用，不污染 RC 文件。
- **本地与 SSH 自动切换**：本地自动探测 `pbcopy` / `wl-copy` / `xclip` / `xsel` / `clip.exe`；SSH 远程自动通过 **OSC 52** 写入本地剪贴板。
- **主机别名感知**：支持 `host:/abs/path`（`-s`）和 `user@host:/abs/path`（`-u`），配合 `scp`/`rsync` 与团队沟通非常顺手。
- **极简交互**：无参数默认操作当前目录；支持短选项连写（如 `-sd`、`-ud`、`-dn`）、多文件换行复制及仅打印模式（`-p`）。
- **软链接控制**：默认递归解析软链接；加 `-n` 保留软链接逻辑路径。
- **内置 Shell 补全**：同时提供 Zsh（`completions/_cpath`）与 Bash（`completions/cpath.bash`）补全脚本，支持选项、路径及 `--set-host` 主机别名（含 `~/.ssh/config` 主机）自动补全。

## 安装

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Arcadiastra/cpath/main/install.sh | bash
```

交互式终端下，安装脚本会一步询问本机的持久化主机别名（直接回车即不写死，走动态默认）；在无终端的自动化/容器/CI 环境中会自动静默跳过。

### Debian / Ubuntu（`.deb` 安装包）

从 [GitHub Releases](https://github.com/Arcadiastra/cpath/releases) 下载 `.deb` 包并使用 `apt` 安装（自动安装 `/usr/bin/cpath`、Bash/Zsh 系统补全以及 `man cpath` 手册页）：

```bash
curl -fsSLO https://github.com/Arcadiastra/cpath/releases/download/v0.1.0/cpath_0.1.0_all.deb
sudo apt install ./cpath_0.1.0_all.deb
```

### Homebrew（macOS / Linux）

通过 [Homebrew Tap](https://github.com/Arcadiastra/homebrew-tap) 安装 `cpath`、Bash 和 Zsh 补全，以及 `man cpath` 手册页。

```bash
brew install arcadiastra/tap/cpath
```

### 本地仓库安装

```bash
git clone https://github.com/Arcadiastra/cpath.git
cd cpath
./install.sh
```

### 自定义安装路径

| 环境变量 | 默认值 |
| --- | --- |
| `CPATH_INSTALL_DIR` | `~/.local/bin` |
| `CPATH_ZSH_COMPLETION_DIR` | `${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions` |
| `CPATH_BASH_COMPLETION_DIR` | `${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions` |
| `CPATH_NONINTERACTIVE` | *（未设置；设为 `1` 可跳过交互提示）* |

## 使用说明

```text
cpath [OPTIONS] [PATH...]
```

### 命令行选项

| 选项 | 作用 | 示例输出 |
| --- | --- | --- |
| （无参数） | 复制当前目录（`.`）规范化绝对路径 | `/var/www/app` |
| `-d` | 若目标为文件，仅取其所在父目录 | `/var/www` |
| `-s` | 附加主机名（`host:/abs/path`） | `prod-api:/var/www/app` |
| `-u` | 附加用户名与主机名（`user@host:/abs/path`） | `alice@prod-api:/var/www/app` |
| `-n` | 不解析软链接（对应 `realpath -s`） | `/var/www/current` |
| `-p` | 仅打印到标准输出，不写入剪贴板 | `/var/www/app` |
| `--set-host [ALIAS]` | 设置或更新本机持久化主机别名（不带参数时进入交互输入） | — |
| `--clear-host` | 清除持久化别名，恢复动态解析 | — |
| `-h`, `--help` | 显示帮助信息 | — |
| `-v`, `--version` | 显示版本号 | — |

### 常用示例

```bash
# 复制当前目录绝对路径
cpath

# 复制指定文件的绝对路径
cpath ./config/app.yaml

# 传入文件但只复制其所在目录
cpath -d ./config/app.yaml

# 复制 host:path，直接贴给 scp / rsync 使用
cpath -s ./build/release.tar.gz

# 短选项连写：复制 user@host:父目录
cpath -ud ./logs/error.log

# 不解析软链接，保留逻辑路径
cpath -n /var/www/current/index.html

# 多文件换行复制
cpath src/main.go src/server.go

# 仅打印模式，用于脚本或命令替换
scp "$(cpath -sp ./artifact.tar.gz)" ./
```

## 主机名解析优先级

使用 `-s` 或 `-u` 时，按从高到低依次回退：

1. **`$CPATH_HOST`**：单次命令临时环境变量覆盖：
   ```bash
   CPATH_HOST=bastion cpath -s ./dump.sql
   ```
2. **`~/.config/cpath/host`**：安装时或通过 `cpath --set-host prod-api` 保存的本机持久化别名。
3. **`$LC_SSH_HOST`**：本地 `~/.ssh/config` 通过 `SetEnv` 透传的主机别名。
4. **`$(hostname)`**：系统当前主机名动态兜底。

### 技巧：通过 SSH `SetEnv` 自动透传本地别名

主流 Linux 发行版的 `/etc/ssh/sshd_config` 默认放行 `AcceptEnv LANG LC_*`。在**本地** `~/.ssh/config` 中配置 `SetEnv LC_SSH_HOST=...`，即可免去在每台远端服务器单独配置别名的麻烦：

```sshconfig
# 本地 ~/.ssh/config
Host prod-api
  HostName 10.0.1.42
  User alice
  SetEnv LC_SSH_HOST=prod-api
```

登录后在远端运行 `cpath -s app.log`，即使机器本身的主机名是 `ip-10-0-1-42`，也能直接输出 `prod-api:/path/to/app.log`。

## 剪贴板与 OSC 52 兼容性

### 本地剪贴板探测顺序

| 平台 | 后端工具 | 探测条件 |
| --- | --- | --- |
| macOS | `pbcopy` | 存在 `pbcopy` |
| Linux (Wayland) | `wl-copy` | 已设置 `$WAYLAND_DISPLAY` 且存在 `wl-copy` |
| Linux (X11) | `xclip` / `xsel` | 已设置 `$DISPLAY` 且存在 `xclip` 或 `xsel` |
| Windows WSL | `clip.exe` | 存在 `clip.exe` |

### SSH 远程剪贴板（OSC 52）终端支持矩阵

检测到 `$SSH_CONNECTION`、`$SSH_TTY` 或 `$SSH_CLIENT` 时，`cpath` 会输出标准 OSC 52 转义序列（`\033]52;c;<base64>\a`）。

| 终端 | OSC 52 支持 | 说明 |
| --- | --- | --- |
| **WezTerm** | 原生支持 | 开箱即用 |
| **Ghostty** | 原生支持 | 开箱即用 |
| **Kitty** | 原生支持 | 开箱即用（`clipboard_control write-clipboard`） |
| **Alacritty** | 原生支持 | 开箱即用 |
| **Foot** | 原生支持 | 开箱即用 |
| **Windows Terminal** | 原生支持 | v1.15+ 开箱即用 |
| **VS Code 内置终端** | 原生支持 | 开箱即用 |
| **iTerm2** | 支持 | 需开启 *Preferences → General → Selection → Applications in terminal may access clipboard* |
| **macOS Terminal.app** | 不支持 | 建议使用上述现代终端 |

### 在 `tmux` 中使用

现代 `tmux`（3.2+）只需在 `~/.tmux.conf` 中添加一行即可让标准 OSC 52 生效：

```tmux
set -s set-clipboard on
```

保存后执行 `tmux source-file ~/.tmux.conf` 使其生效。

## Shell 自动补全

`install.sh` 会在检测到对应 Shell 时自动安装 Zsh 与 Bash 补全脚本：

### Zsh

默认安装至 `${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions/_cpath`。请确保在 `~/.zshrc` 调用 `compinit` 之前将该目录加入 `fpath`：

```zsh
fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
```

如果使用 **Oh My Zsh**，也可以直接指定补全目录安装：

```bash
CPATH_ZSH_COMPLETION_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions" ./install.sh
```

### Bash

默认安装至 `${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/cpath`，配合 `bash-completion` v2+ 会按需自动加载，无需额外配置。

如未安装 `bash-completion`，可在 `~/.bashrc` 中手动引入：

```bash
source "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/cpath"
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/Arcadiastra/cpath/main/uninstall.sh | bash
```

或在本地仓库中运行：

```bash
./uninstall.sh
```

## 测试与检查

```bash
./tests/test_cpath.sh
shellcheck bin/cpath install.sh uninstall.sh completions/cpath.bash tests/test_cpath.sh
```

## 开源协议

[MIT](LICENSE)
