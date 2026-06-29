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

某个 Kubernetes 集群执行：

```bash
kubectl get pod
```

需要等待约 6 秒才返回。

但实际返回的数据量很小，集群规模正常。

表现：

```text
kubectl get pod

real    0m6.0s
```

而：

```bash
kubectl get pod -v=9
```

显示真正的 Pod LIST 请求仅耗时约：

```text
104ms
```

---

## 环境信息

```text
Client Version: v1.17.5
Server Version: v1.24.2
```

集群中存在大量：

- CRD
- Prometheus
- Rancher
- custom metrics

---

## 初步怀疑

最初怀疑包括：

1. apiserver 性能问题
2. etcd 性能问题
3. APIService 超时
4. kubectl 版本过老
5. discovery cache 损坏

---

## 验证 apiserver

开启调试：

```bash
kubectl get pod -v=9
```

发现：

```text
GET /api/v1/pods

104ms
```

说明：

- 网络正常
- apiserver 正常
- etcd 正常

真正的请求并不慢。

---

## 验证 discovery

执行：

```bash
time kubectl api-resources
```

结果：

```text
real    0m6.137s
```

说明：

> 慢发生在 API Discovery 阶段。

---

## 检查 kubectl 缓存

查看缓存目录：

```bash
du -sh ~/.kube/*
```

结果：

```text
154M    ~/.kube/cache
332M    ~/.kube/http-cache
```

明显异常。

进一步定位：

```bash
du -sh ~/.kube/cache/discovery/*/*/*
```

发现：

```text
142M

/root/.kube/cache/discovery/10.72.104.137_6443/custom.metrics.k8s.io/v1beta1/serverresources.json
```

---

## 定位 custom metrics

查看资源数量：

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 \
    | jq '.resources | length'
```

结果：

```text
546833
```

正常情况下：

| 场景 | 数量 |
|-----|-----:|
| metrics-server | 2~10 |
| 普通 custom metrics | 10~100 |
| 大型平台 | 数百 |
| 超大平台 | 数千 |

本集群：

```text
546833
```

已经严重异常。

---

## 查看具体 metric

执行：

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 \
| jq -r '.resources[].name' \
| grep alluxio
```

发现：

```text
Master_GetSpace_User:presto_UFS:dgs:_2F_2Fheng_2Fuser...
Master_UfsSessionCount_Ufs:dgs:_2F_2Fheng_2Fuser...
```

metric 中包含：

- 用户名
- UFS
- 文件路径
- 日期目录

例如：

```text
/heng/user/g_fsg_fdw/xxx/daytime_20240821
```

全部进入了 metric name。

---

## 根因分析

Alluxio 导出的 metric 存在极高基数。

类似：

```text
Master_GetSpace_User:presto_UFS:/path1
Master_GetSpace_User:presto_UFS:/path2
Master_GetSpace_User:presto_UFS:/path3
```

每一个路径都会生成新的 metric。

导致：

```text
几十万个目录
↓

几十万个 metric

↓

Prometheus Adapter 暴露全部 metric

↓

custom.metrics.k8s.io

↓

546833 resources

↓

142MB discovery 文件

↓

kubectl 解析耗时 6 秒
```

---

## 为什么 kubectl get pod 会受影响

kubectl 启动时需要执行 Discovery：

```text
GET /api
GET /apis
GET /apis/apps/v1
GET /apis/custom.metrics.k8s.io/v1beta1
...
```

custom metrics 返回：

```text
546833 resources
142MB JSON
```

kubectl 本地需要：

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

---

## 修复过程

发现 Alluxio 已经下线。

删除对应：

```text
ServiceMonitor
```

停止采集。

一段时间后再次查看：

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 \
    | jq '.resources | length'
```

结果：

```text
9983
```

资源数量下降：

```text
546833

↓

9983
```

---

## 清理客户端缓存

```bash
rm -rf ~/.kube/cache
rm -rf ~/.kube/http-cache
```

---

## 修复结果

测试：

```bash
time kubectl get pod
```

结果：

```text
0.5s
```

问题解决。

---

## 排查流程总结

### 1. 判断是否是 apiserver

```bash
kubectl get pod -v=9
```

看真正的 LIST 请求耗时。

---

### 2. 判断是否是 discovery

```bash
time kubectl api-resources
```

---

### 3. 查看 discovery cache

```bash
du -sh ~/.kube/cache
```

---

### 4. 找超大资源文件

```bash
du -sh ~/.kube/cache/discovery/*/*/*
```

---

### 5. 检查 custom metrics 数量

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 \
    | jq '.resources | length'
```

---

## 经验总结

如果出现：

```text
kubectl get 很慢
apiserver 很快
LIST 请求只有几十毫秒
```

优先检查：

```bash
time kubectl api-resources

kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 \
    | jq '.resources | length'
```

特别是：

- Prometheus Adapter
- custom metrics
- 高基数 metric
- 失效监控系统

因为它们可能导致：

```text
kubectl discovery 变慢

而不是 Kubernetes 本身变慢。
```

---

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
custom.metrics.k8s.io 546833 resources
        ↓
142MB discovery 文件
        ↓
kubectl discovery 6 秒
        ↓
kubectl get pod 卡顿
```
