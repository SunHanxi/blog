# Kubernetes 源码学习路线

这份文档用于配合当前 Kubernetes 源码仓库学习。目标不是一次性读完所有代码，而是沿着一条真实工作链路，逐步建立 Kubernetes 的源码地图和调试能力。

推荐主线：

```text
kubectl apply deployment.yaml
  -> kube-apiserver 接收请求
  -> admission / validation / storage
  -> etcd 保存 Deployment
  -> deployment controller 观察到变化
  -> 创建 ReplicaSet
  -> replicaset controller 创建 Pod
  -> scheduler 发现 Pending Pod
  -> scheduler 绑定 Node
  -> kubelet 观察到本节点 Pod
  -> kubelet 通过 CRI 启动容器
```

读源码时始终把文件放回这条链路里理解。

## 0. 仓库地图

当前仓库中最重要的目录：

| 目录 | 作用 |
| --- | --- |
| `cmd/` | Kubernetes 各组件入口，例如 `kube-apiserver`、`kube-controller-manager`、`kube-scheduler`、`kubelet`、`kubectl` |
| `pkg/` | Kubernetes 核心实现代码 |
| `staging/src/k8s.io/` | 对外拆分模块，例如 `api`、`apimachinery`、`client-go`、`apiserver`、`kubectl` |
| `test/` | 集成测试、e2e 测试 |
| `hack/` | 构建、代码生成、校验脚本 |
| `vendor/` | 依赖代码 |

常用搜索命令：

```bash
rg "func New.*Command" cmd pkg staging/src/k8s.io
rg "syncHandler" pkg/controller
rg "ScheduleOne" pkg/scheduler
rg "syncPod" pkg/kubelet
rg "Run" cmd pkg staging/src/k8s.io
```

常用测试命令：

```bash
go test ./pkg/probe/...
go test ./pkg/scheduler/...
go test ./pkg/controller/deployment/...
go test ./staging/src/k8s.io/client-go/...
```

## 1. 学习节奏

建议每天 1.5 到 2 小时：

1. 30 分钟：看概念或复习上一天笔记。
2. 45 分钟：读一个核心文件，只抓主流程。
3. 30 分钟：写笔记，记录输入、输出、关键类型、调用方。
4. 15 分钟：跑测试、搜调用链或做一个小实验。

每读一个函数，回答四个问题：

1. 谁调用它？
2. 它的输入是什么？
3. 它改变了什么状态？
4. 它失败时怎么返回错误或重试？

## 2. 第 1 周：会用 Kubernetes

目标：先会使用核心资源，不急着读源码。

需要掌握：

- Pod
- Deployment
- ReplicaSet
- Service
- ConfigMap
- Secret
- Namespace
- Node
- RBAC
- PV / PVC

练习命令：

```bash
kubectl run nginx --image=nginx
kubectl get pod -o yaml
kubectl create deployment web --image=nginx --replicas=3
kubectl expose deployment web --port=80 --type=NodePort
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- sh
kubectl get deployment,rs,pod -o wide
```

本周检查点：

- 能解释 `Spec` 和 `Status` 的区别。
- 能解释 Deployment、ReplicaSet、Pod 的关系。
- 能解释 Service 为什么不是直接等于 Pod。
- 能画出一次 `kubectl apply` 后大概发生了什么。

## 3. 第 2 周：API 对象和元数据

目标：理解 Kubernetes 所有控制逻辑的对象基础。

重点文件：

```text
staging/src/k8s.io/api/core/v1/types.go
staging/src/k8s.io/api/apps/v1/types.go
staging/src/k8s.io/apimachinery/pkg/apis/meta/v1/types.go
```

重点类型：

- `Pod`
- `PodSpec`
- `PodStatus`
- `Container`
- `Deployment`
- `DeploymentSpec`
- `DeploymentStatus`
- `ObjectMeta`
- `TypeMeta`
- `OwnerReference`
- `LabelSelector`
- `ListOptions`
- `WatchEvent`

阅读任务：

1. 找到 `Pod` 结构体，区分 `TypeMeta`、`ObjectMeta`、`Spec`、`Status`。
2. 找到 `DeploymentSpec`，理解 `Replicas`、`Selector`、`Template`。
3. 找到 `OwnerReference`，理解级联删除和归属关系。
4. 找到 `ListOptions`，理解 `ResourceVersion`、`LabelSelector`、`FieldSelector`。

本周检查点：

- 能解释为什么 Kubernetes API 对象通常都有 `Spec` 和 `Status`。
- 能解释为什么 Deployment 通过 `Template` 创建 Pod。
- 能解释 `labels` 和 `selector` 的关系。
- 能解释 `resourceVersion` 大概解决什么问题。

## 4. 第 3-4 周：kube-apiserver

目标：读懂请求进入 apiserver 后的大致链路。

入口文件：

```text
cmd/kube-apiserver/apiserver.go
pkg/kubeapiserver/
staging/src/k8s.io/apiserver/
```

重点主题：

- 命令行参数如何初始化组件。
- HTTP 请求如何进入 apiserver。
- 认证 Authentication。
- 鉴权 Authorization。
- Admission。
- API 对象序列化和反序列化。
- REST storage。
- 对 etcd 的读写。

建议阅读顺序：

1. `cmd/kube-apiserver/apiserver.go`
2. `pkg/kubeapiserver/`
3. `staging/src/k8s.io/apiserver/pkg/server/`
4. `staging/src/k8s.io/apiserver/pkg/endpoints/`
5. `staging/src/k8s.io/apiserver/pkg/registry/generic/`
6. `staging/src/k8s.io/apiserver/pkg/storage/`

阅读任务：

```bash
rg "NewAPIServerCommand" cmd pkg staging/src/k8s.io
rg "Create" staging/src/k8s.io/apiserver/pkg
rg "Admission" pkg staging/src/k8s.io/apiserver
rg "Authorize" pkg staging/src/k8s.io/apiserver
rg "etcd" pkg staging/src/k8s.io/apiserver
```

本阶段检查点：

- 能描述一次 `POST /api/v1/namespaces/default/pods` 的大概流程。
- 能区分认证、鉴权、准入控制。
- 能解释 apiserver 为什么不是直接操作 Go 结构体，而要经过序列化、版本转换、storage。
- 能知道资源最终会进入 etcd。

## 5. 第 5-6 周：controller-manager 和调谐模型

目标：理解 Kubernetes 最核心的控制循环。

入口文件：

```text
cmd/kube-controller-manager/controller-manager.go
pkg/controller/
```

推荐先读 Deployment Controller：

```text
pkg/controller/deployment/deployment_controller.go
pkg/controller/deployment/sync.go
pkg/controller/deployment/rolling.go
pkg/controller/replicaset/
```

核心概念：

- informer
- lister
- workqueue
- sync handler
- reconcile
- owner reference
- expectations

阅读任务：

1. 找到 Deployment Controller 如何创建。
2. 找到它监听哪些资源。
3. 找到 Deployment 如何入队。
4. 找到 `syncDeployment` 这样的核心调谐函数。
5. 观察它如何创建或更新 ReplicaSet。
6. 继续追 ReplicaSet 如何创建 Pod。

搜索命令：

```bash
rg "NewDeploymentController" pkg/controller/deployment
rg "syncDeployment" pkg/controller/deployment
rg "enqueue" pkg/controller/deployment
rg "workqueue" pkg/controller
rg "OwnerReference" pkg/controller
```

本阶段检查点：

- 能解释 informer 不是简单的 HTTP 轮询。
- 能解释为什么 controller 使用 workqueue。
- 能解释 Deployment Controller 如何把期望副本数变成 ReplicaSet。
- 能解释 ReplicaSet Controller 如何把 ReplicaSet 变成 Pod。
- 能解释 controller 的核心模式：观察、入队、对比、修正。

## 6. 第 7 周：kube-scheduler

目标：理解调度器如何把 Pending Pod 绑定到 Node。

入口文件：

```text
cmd/kube-scheduler/scheduler.go
pkg/scheduler/scheduler.go
pkg/scheduler/schedule_one.go
pkg/scheduler/framework/
```

核心概念：

- scheduling queue
- pending pod
- filtering
- scoring
- binding
- scheduling framework
- plugin

建议阅读顺序：

1. `cmd/kube-scheduler/scheduler.go`
2. `pkg/scheduler/scheduler.go`
3. `pkg/scheduler/schedule_one.go`
4. `pkg/scheduler/framework/interface.go`
5. `pkg/scheduler/framework/types.go`

搜索命令：

```bash
rg "ScheduleOne" pkg/scheduler
rg "Filter" pkg/scheduler
rg "Score" pkg/scheduler
rg "Bind" pkg/scheduler
rg "SchedulingQueue" pkg/scheduler
```

本周检查点：

- 能解释 scheduler 只负责绑定，不负责启动容器。
- 能解释 Filter 和 Score 的区别。
- 能解释 Pod 为什么会处于 Pending 状态。
- 能描述一个 Pod 从 Pending 到被绑定 Node 的流程。

## 7. 第 8-9 周：kubelet

目标：理解 kubelet 如何在节点上真正运行 Pod。

入口文件：

```text
cmd/kubelet/kubelet.go
pkg/kubelet/
pkg/kubelet/kuberuntime/
pkg/kubelet/prober/
pkg/kubelet/config/
pkg/kubelet/container/
```

核心概念：

- node agent
- pod source
- sync loop
- syncPod
- CRI
- container runtime
- probe
- volume
- secret / configmap mount

建议阅读顺序：

1. `cmd/kubelet/kubelet.go`
2. `pkg/kubelet/kubelet.go`
3. `pkg/kubelet/kubelet_pods.go`
4. `pkg/kubelet/kuberuntime/`
5. `pkg/kubelet/prober/`

搜索命令：

```bash
rg "syncPod" pkg/kubelet
rg "SyncPod" pkg/kubelet
rg "PLEG" pkg/kubelet
rg "RunPodSandbox" pkg/kubelet
rg "CreateContainer" pkg/kubelet
rg "probe" pkg/kubelet/prober pkg/probe
```

本阶段检查点：

- 能解释 kubelet 如何知道哪些 Pod 属于自己。
- 能解释 kubelet 和 container runtime 的关系。
- 能解释 `syncPod` 大概做什么。
- 能解释 liveness/readiness/startup probe 的执行位置。
- 能解释 kubelet 为什么是节点侧最复杂的组件之一。

## 8. 第 10 周：kubectl 和 client-go

目标：理解客户端如何访问 apiserver，理解 informer/clientset 的使用模型。

入口文件：

```text
cmd/kubectl/kubectl.go
staging/src/k8s.io/kubectl/pkg/cmd/
staging/src/k8s.io/client-go/
```

重点目录：

```text
staging/src/k8s.io/client-go/kubernetes/
staging/src/k8s.io/client-go/rest/
staging/src/k8s.io/client-go/tools/cache/
staging/src/k8s.io/client-go/informers/
staging/src/k8s.io/client-go/listers/
staging/src/k8s.io/kubectl/pkg/cmd/apply/
```

搜索命令：

```bash
rg "NewDefaultKubectlCommand" cmd staging/src/k8s.io/kubectl
rg "RESTClient" staging/src/k8s.io/client-go
rg "SharedInformer" staging/src/k8s.io/client-go
rg "ListWatch" staging/src/k8s.io/client-go
rg "apply" staging/src/k8s.io/kubectl/pkg/cmd/apply
```

本周检查点：

- 能解释 kubeconfig 如何影响 kubectl 连接哪个集群。
- 能解释 clientset、dynamic client、RESTClient 的区别。
- 能解释 informer 为什么适合写 controller。
- 能描述 `kubectl apply` 和普通 `create/update` 的区别。

## 9. 第 11 周：做一个小改动

目标：真正改一次 Kubernetes 代码，并跑对应测试。

推荐从小模块开始：

```text
pkg/probe/
pkg/credentialprovider/
pkg/controller/ttlafterfinished/
pkg/controller/podgc/
pkg/scheduler/framework/
```

推荐任务：

1. 给 `pkg/probe` 某个错误路径补一个测试。
2. 给某个 controller 的边界条件补单元测试。
3. 改进一个错误信息。
4. 给 scheduler 某个小工具函数补测试。
5. 阅读一个已有测试，照着风格添加新 case。

示例命令：

```bash
go test ./pkg/probe/...
go test ./pkg/controller/ttlafterfinished/...
go test ./pkg/scheduler/framework/...
```

本周检查点：

- 能找到一个函数的测试文件。
- 能添加 table-driven test。
- 能只跑相关 package 的测试。
- 能用 `rg` 找到调用方和错误路径。

## 10. 第 12 周：总结和画图

目标：把散乱源码知识整理成自己的 Kubernetes 心智模型。

需要输出三份笔记：

1. `kubectl apply Deployment` 全链路图。
2. Deployment Controller 阅读笔记。
3. kubelet 启动 Pod 阅读笔记。

建议图示：

```text
User
  |
  v
kubectl
  |
  v
kube-apiserver
  |
  v
etcd
  |
  v
controller-manager
  |
  v
scheduler
  |
  v
kubelet
  |
  v
container runtime
```

最终检查点：

- 能解释 Kubernetes 为什么是声明式系统。
- 能解释 controller 的调谐循环。
- 能解释 apiserver 在整个系统里的中心地位。
- 能解释 scheduler 和 kubelet 的边界。
- 能独立定位一个资源状态异常大概应该看哪个组件。

## 11. 推荐的第一条源码精读路线

第一条精读路线选择 Deployment，不建议一开始读 kubelet 全部逻辑。

阅读顺序：

```text
staging/src/k8s.io/api/apps/v1/types.go
pkg/controller/deployment/deployment_controller.go
pkg/controller/deployment/sync.go
pkg/controller/deployment/rolling.go
pkg/controller/replicaset/
pkg/scheduler/schedule_one.go
pkg/kubelet/
```

每读完一个文件，记录：

```text
文件：
核心类型：
核心函数：
它监听什么：
它创建或更新什么：
失败后如何重试：
下一步应该读哪里：
```

## 12. 学习时不要做的事

- 不要从 kubelet 全量开始读，容易陷进去。
- 不要一开始读所有 generated 代码。
- 不要试图一次搞懂所有 admission/plugin/storage 细节。
- 不要只看源码不跑命令。
- 不要只看概念不画调用链。
- 不要追每一个接口实现，先抓主流程。

## 13. 一个判断标准

当你能用自己的话说清楚下面这段话，就说明已经入门：

```text
Kubernetes 不是直接执行用户命令的系统，而是一个围绕 API 对象工作的声明式控制系统。
用户通过 kubectl 或 client-go 把期望状态提交给 apiserver，apiserver 负责认证、鉴权、准入和持久化。
各类 controller 通过 informer 观察对象变化，把对象放入 workqueue，然后不断调谐实际状态。
scheduler 负责为 Pending Pod 选择 Node。
kubelet 负责在节点上观察属于自己的 Pod，并通过 CRI 让容器运行起来。
```

这条线理解了，后面再学习网络、存储、安全、扩展机制、CRD、Operator，都会有清晰的落点。
