---
title: "一次 kubectl 异常耗时的排查"
description: "kubectl get pod 卡顿 6 秒，真正的根因不在 apiserver，而在 API Discovery 阶段的 custom metrics 高基数 metric。"
date: 2024-09-01T00:00:00+08:00
image: 
categories:
    - Linux
tags:
    - Kubernetes
    - 故障排查
license: 
hidden: false
comments: true
draft: false
---

## 问题现象

某个 Kubernetes 集群执行 `kubectl get pod` 需要等待约 6 秒才返回，但实际返回的数据量很小，集群规模也正常：

```text
$ time kubectl get pod
real    0m6.0s
```

而加上 `-v=9` 看真正的 LIST 请求，仅耗时约 104ms：

```text
$ kubectl get pod -v=9
GET /api/v1/pods   104ms
```

真正的请求并不慢，慢在别处。

## 环境信息

```text
Client Version: v1.17.5
Server Version: v1.24.2
```

集群中存在大量 CRD、Prometheus、Rancher、custom metrics。

## 初步怀疑

最初怀疑包括：apiserver 性能问题、etcd 性能问题、APIService 超时、kubectl 版本过老、discovery cache 损坏。

## 验证 apiserver

`kubectl get pod -v=9` 显示 `GET /api/v1/pods` 仅 104ms，说明网络、apiserver、etcd 都正常，真正的请求并不慢。

## 验证 discovery

```text
$ time kubectl api-resources
real    0m6.137s
```

> 慢发生在 API Discovery 阶段。

## 检查 kubectl 缓存

```text
$ du -sh ~/.kube/*
154M    ~/.kube/cache
332M    ~/.kube/http-cache
```

明显异常。进一步定位：

```text
$ du -sh ~/.kube/cache/discovery/*/*/*
142M  /root/.kube/cache/discovery/<api-server-ip>_6443/custom.metrics.k8s.io/v1beta1/serverresources.json
```

142MB 集中在 `custom.metrics.k8s.io/v1beta1` 这一个文件上。

## 定位 custom metrics

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq '.resources | length'
```

结果：**546833**。

| 场景 | 数量 |
|-----|-----:|
| metrics-server | 2~10 |
| 普通 custom metrics | 10~100 |
| 大型平台 | 数百 |
| 超大平台 | 数千 |

本集群 546833，已经严重异常。

## 查看具体 metric

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 \
  | jq -r '.resources[].name' \
  | grep alluxio
```

```text
Master_GetSpace_User:...
Master_UfsSessionCount_Ufs:...
```

metric name 中包含了用户名、UFS、文件路径、日期目录，例如 `/xxx/daytime_20240821`，全部进了 metric name。

## 根因分析

Alluxio 导出的 metric 存在极高基数，每一个路径都会生成一个新的 metric：

```text
Master_GetSpace_User::/path1
Master_GetSpace_User::/path2
Master_GetSpace_User::/path3
```

连锁反应如下：

```text
几十万个目录
    ↓
几十万个 metric
    ↓
Prometheus Adapter 暴露全部 metric
    ↓
custom.metrics.k8s.io 暴露 546833 resources
    ↓
142MB discovery 文件
    ↓
kubectl 解析耗时 6 秒
```

## 为什么 kubectl get pod 会受影响

kubectl 启动时需要执行 Discovery，会请求 `GET /api`、`GET /apis`、`GET /apis/apps/v1`、`GET /apis/custom.metrics.k8s.io/v1beta1` 等接口。其中 custom metrics 返回了 546833 resources、142MB JSON，kubectl 本地需要：

1. 下载 JSON
2. 解析 JSON
3. 构建 RESTMapper
4. 写入 discovery cache

最终导致：

```text
kubectl get pod
    ↓
真正 LIST pod：104ms
    ↓
Discovery：5~6秒
    ↓
返回结果
```

## 修复过程

Alluxio 已经下线，删除对应的 ServiceMonitor 停止采集。一段时间后再次查看：

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq '.resources | length'
```

结果：**9983**，从 546833 降到了 9983。

## 清理客户端缓存

```bash
rm -rf ~/.kube/cache
rm -rf ~/.kube/http-cache
```

## 修复结果

```text
$ time kubectl get pod
real    0m5s   →   0.5s
```

问题解决。

## 排查流程总结

1. **判断是否是 apiserver**：`kubectl get pod -v=9`，看真正的 LIST 请求耗时。
2. **判断是否是 discovery**：`time kubectl api-resources`。
3. **查看 discovery cache**：`du -sh ~/.kube/cache`。
4. **找超大资源文件**：`du -sh ~/.kube/cache/discovery/*/*/*`。
5. **检查 custom metrics 数量**：`kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq '.resources | length'`。

## 经验总结

如果出现「kubectl get 很慢、apiserver 很快、LIST 请求只有几十毫秒」，优先检查：

```bash
time kubectl api-resources
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq '.resources | length'
```

特别留意 Prometheus Adapter、custom metrics、高基数 metric、失效的监控系统——它们可能导致 kubectl discovery 变慢，而不是 Kubernetes 本身变慢。

## 最终根因

```text
Alluxio 高基数 metric
        ↓
ServiceMonitor 持续采集
        ↓
Prometheus 存储
        ↓
Prometheus Adapter 全量暴露
        ↓
custom.metrics.k8s.io 暴露 546833 resources
        ↓
142MB discovery 文件
        ↓
kubectl discovery 6 秒
        ↓
kubectl get pod 卡顿
```
