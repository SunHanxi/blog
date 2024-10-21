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
pacman -s	gnome gnome-tweaks	
systemctl enable --now gdm
```

### 2.2 输入法

```bash
sudo pacman -S fcitx5-im
sudo pacman -S fcitx5-chinese-addons  fcitx5-rime
```

