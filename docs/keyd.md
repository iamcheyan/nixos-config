# MINILA-R keyd 键位配置

MINILA-R Convertible 的系统级键位映射由 `modules/core.nix` 中的
`services.keyd.keyboards.minila-r-convertible` 声明。NixOS 同时负责安装 keyd、
生成 `/etc/keyd/minila-r-convertible.conf`、启用服务以及配置变化后的重启。

设备 ID 是 `0c45:22b8`。配置对导入 `modules/core.nix` 的所有 NixOS 主机生效，
但 keyd 只匹配该设备，不影响其他键盘。

## 修改和应用

不要直接编辑 `/etc/keyd`，也不要通过 chezmoi 安装映射。修改
`modules/core.nix` 后执行：

```bash
cd ~/nixos-config
nix flake check --no-build
nixos-rebuild build --flake .#hx90
sudo nixos-rebuild switch --flake .#hx90
```

检查结果：

```bash
systemctl status keyd
keyd check /etc/keyd/minila-r-convertible.conf
```

旧的 Omarchy/OMD 自动配置若仍以 `omd.conf.disabled` 留在 `/etc/keyd`，不会被
keyd 的 `*.conf` glob 加载，可在确认新配置稳定后手动清理。
