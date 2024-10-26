---
title: "ArchLinux配置"
description: 
date: 2024-10-17T15:15:51+08:00
image: 
math: 
license: 
hidden: false
comments: true
draft: false
---

## 1 安装

- ventory制作启动盘
- archinstall安装
    - 选择一个单独的硬盘，自动分区，不区分home目录。
    - copy iso网络配置
- 完成



## 2 配置

### 2.1 gnome桌面

```bash
# 新建用户
useradd bringwater

# 安装 Noto 字体	
pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji	
# 桌面环境
pacman -S gnome gnome-tweaks	
systemctl enable --now gdm
```

### 2.2 输入法

```bash
sudo pacman -S fcitx5-im
sudo pacman -S fcitx5-chinese-addons  fcitx5-rime
```

### 2.3 安装开发环境

安装软件的列表：
- JetBrains Toolbox App
- QQ
- Chrome

```bash
yay -S 
```

### 2.4 配置v2raya

```bash
# 安装
sudo pacman -S v2raya v2ray

# 启动
sudo systemctl enable v2raya
```

### 2.5 声卡

```bash

sudo pacman -S pavucontrol alsa-utils alsa-plugins pulseaudio-alsa pavucontrol-qt

# 禁用声卡省电模式

echo 0 > /sys/module/snd_hda_intel/parameters/power_save

sudo cat > /etc/modprobe.d/audio_disable_powersave.conf <<EOF
options snd_hda_intel power_save=0

EOF
```

### 2.6 配置git

```bash
yay git vscode
git config --global user.name ***
git config --global user.email ***
```


### 2.7 美化桌面

```bash
yay -S chrome-gnome-shell


```