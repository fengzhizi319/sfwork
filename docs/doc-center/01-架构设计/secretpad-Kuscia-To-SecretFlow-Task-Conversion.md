# Kuscia 如何把上层任务转化为对 SecretFlow 的调用

> 本文档详细描述 Kuscia 从接收到上层（如 SecretPad）的 `CreateJob` 请求开始，到最终启动 SecretFlow 容器并执行任务的全过程。重点讲解任务配置如何在不同层级之间转换、容器规格如何生成、以及 SecretFlow 如何读取配置。

---

## 1. 概述

Kuscia 作为隐私计算基础设施，本身不执行联邦学习算法，而是负责：

1. 接收上层调度请求（HTTP/gRPC `CreateJob`）
2. 把请求转化为 Kubernetes CRD（`KusciaJob`）
3. 按依赖和并发策略拆解为 `KusciaTask`
4. 为每个 Task 创建 Pod、Service、ConfigMap、TaskResourceGroup
5. 通过 **AppImage + DeployTemplate + ConfigTemplate + config-render 插件** 生成 SecretFlow 可识别的配置文件
6. 启动 SecretFlow 容器，由 SecretFlow 读取配置后连接 DataMesh 执行计算
7. 监听 Pod 状态，汇总 Task / Job 状态，通过 `WatchJob` 流回传给上层

整个过程中，Kuscia 是“任务编排器 + K8s 控制器 + 运行时注入器”，SecretFlow 是“真正的算法执行引擎”。

---

## 2. 整体架构与调用链

```text
上层系统 (SecretPad / 脚本 / 其他控制台)
    │
    │ HTTP POST /api/v1/job/create
    │ 或 gRPC JobService/CreateJob
    ▼
┌─────────────────────────────────────────┐
│  KusciaAPI                              │
│  pkg/kusciaapi/service/job_service.go   │
│  校验 → 组装 KusciaJob → 写入 CRD       │
└─────────────────────────────────────────┘
    │
    ▼
KusciaJob CRD (namespace: cross-domain)
    │
    ▼
┌─────────────────────────────────────────┐
│  KusciaJob Controller                   │
│  pkg/controllers/kusciajob/controller.go│
│  Initialized → Pending → Running        │
│  scheduler.go: 依赖解析、并发控制        │
│  running.go: 创建 KusciaTask            │
└─────────────────────────────────────────┘
    │
    ▼
KusciaTask CRD (namespace: cross-domain)
    │
    ▼
┌─────────────────────────────────────────┐
│  KusciaTask Controller                  │
│  pkg/controllers/kusciatask/controller.go│
│  PendingHandler → RunningHandler        │
│  创建 Pod/Service/ConfigMap/TRG         │
└─────────────────────────────────────────┘
    │
    ▼
Pod in party namespace (e.g., alice/bob)
    │
    ├─ ConfigMap: <task>-kuscia-gen-conf  (TASK_ID / TASK_INPUT_CONFIG / TASK_CLUSTER_DEFINE / ALLOCATED_PORTS)
    ├─ ConfigMap: <task>-configtemplate    (AppImage configTemplates 渲染源)
    ├─ VolumeMount: /work/kuscia/task-config.conf
    │
    ▼
Agent config-render plugin 渲染配置
    │
    ▼
SecretFlow 容器启动
    sh -c "python -m secretflow.kuscia.entry ./kuscia/task-config.conf"
    │
    ▼
secretflow.kuscia.entry.py
    ├─ 解析 task-config.conf → KusciaTaskConfig
    ├─ 连接 datamesh:8071
    ├─ 下载输入 DomainData
    ├─ comp_eval() 执行联邦学习组件
    └─ 上传输出到 DataMesh
    │
    ▼
Pod Succeeded / Failed
    │
    ▼
KusciaTask Controller 汇总状态
    │
    ▼
KusciaJob Controller 汇总状态
    │
    ▼
WatchJob stream → 上层系统
```

---

## 3. 第一步：KusciaAPI 接收 CreateJob 请求

### 3.1 HTTP 入口

**文件：** `kuscia/pkg/kusciaapi/bean/http_server_bean.go`

```go
groupsRouters := []*router.GroupRouters{
    {
        Group: "api/v1/job",
        Routes: []*router.Router{
            {
                HTTPMethod:   http.MethodPost,
                RelativePath: "create",
                Handlers:     []gin.HandlerFunc{protoDecorator(e, job.NewCreateJobHandler(jobService))},
            },
            // ...
        },
    },
}
```

外部 HTTP 服务器监听默认端口 `8082`，内部 HTTP 服务器监听 `8092`。

**Handler：** `kuscia/pkg/kusciaapi/handler/httphandler/job/create.go`

```go
type createJobHandler struct {
    jobService service.IJobService
}

func (c createJobHandler) Handle(context *api.BizContext, request api.ProtoRequest) api.ProtoResponse {
    createRequest, _ := request.(*kusciaapi.CreateJobRequest)
    return c.jobService.CreateJob(context.Context, createRequest)
}
```

### 3.2 gRPC 入口

**文件：** `kuscia/pkg/kusciaapi/bean/grpc_server_bean.go`

```go
kusciaapi.RegisterJobServiceServer(server, grpchandler.NewJobHandler(service.NewJobService(s.config)))
```

**Handler：** `kuscia/pkg/kusciaapi/handler/grpchandler/job_handler.go`

```go
func (h jobHandler) CreateJob(ctx context.Context, request *kusciaapi.CreateJobRequest) (*kusciaapi.CreateJobResponse, error) {
    res := h.jobService.CreateJob(ctx, request)
    return res, nil
}
```

### 3.3 请求 / 响应结构

**Proto：** `kuscia/proto/api/v1alpha1/kusciaapi/job.proto`

```protobuf
message CreateJobRequest {
  RequestHeader header = 1;
  string job_id = 2;
  string initiator = 3;
  int32 max_parallelism = 4;
  repeated Task tasks = 5;
  map<string, string> custom_fields = 6;
}

message CreateJobResponse {
  Status status = 1;
  CreateJobResponseData data = 2;
}

message CreateJobResponseData {
  string job_id = 1;
}

message Task {
  string app_image = 1;
  repeated Party parties = 2;
  string alias = 3;
  string task_id = 4;
  repeated string dependencies = 5;
  string task_input_config = 6;
  int32 priority = 7;
  ScheduleConfig schedule_config = 8;
  bool tolerable = 9;
}

message Party {
  string domain_id = 1;
  string role = 2;
  Resource resources = 3;
  // ...
}
```

`task_input_config` 是上层（SecretPad）已经准备好的 JSON 字符串，包含 SecretFlow 需要的全部信息（`sf_node_eval_param`、`sf_cluster_desc`、`sf_input_ids`、`sf_output_ids` 等）。Kuscia 基本不解析其内容，只是透传。

---

## 4. 第二步：KusciaJob CRD 的创建

### 4.1 核心服务

**文件：** `kuscia/pkg/kusciaapi/service/job_service.go`

入口函数 `CreateJob`：

```go
func (h *jobService) CreateJob(ctx context.Context, request *kusciaapi.CreateJobRequest) *kusciaapi.CreateJobResponse {
    // 1. 校验请求
    if err := validateCreateJobRequest(request, h.Initiator); err != nil { ... }
    // 2. 鉴权
    if err := h.authHandlerJobCreate(ctx, request); err != nil { ... }

    // 3. 把 request.Tasks 转成 []v1alpha1.KusciaTaskTemplate
    kusciaTasks := make([]v1alpha1.KusciaTaskTemplate, len(tasks))
    for i, task := range tasks {
        // 转换 parties
        kusciaParties := make([]v1alpha1.Party, len(task.Parties))
        for j, party := range task.Parties {
            kusciaParties[j] = v1alpha1.Party{
                DomainID:       party.DomainId,
                Role:           party.Role,
                Resources:      resource,
                BandwidthLimit: bandwidthLimits,
            }
        }

        kusciaTasks[i] = v1alpha1.KusciaTaskTemplate{
            TaskID:          task.TaskId,
            Alias:           task.Alias,
            Dependencies:    task.Dependencies,
            AppImage:        task.AppImage,
            TaskInputConfig: task.TaskInputConfig,
            Parties:         kusciaParties,
            Priority:        int(task.Priority),
            Tolerable:       &task.Tolerable,
            ScheduleConfig:  buildScheduleConfigForKusciaTask(task.ScheduleConfig),
        }
    }

    // 4. 组装 KusciaJob
    kusciaJob := &v1alpha1.KusciaJob{
        ObjectMeta: metav1.ObjectMeta{
            Name:   request.JobId,
            Labels: labels,   // custom_fields -> labels
        },
        Spec: v1alpha1.KusciaJobSpec{
            Initiator:      request.Initiator,
            MaxParallelism: utils.IntValue(request.MaxParallelism),
            ScheduleMode:   v1alpha1.KusciaJobScheduleModeBestEffort,
            Tasks:          kusciaTasks,
        },
    }

    // 5. 写入 CRD
    _, err := h.kusciaClient.KusciaV1alpha1().KusciaJobs(common.KusciaCrossDomain).Create(ctx, kusciaJob, metav1.CreateOptions{})
    // ...
}
```

### 4.2 字段映射关系

| `CreateJobRequest` | `KusciaJob` CRD |
|---|---|
| `job_id` | `metadata.name` |
| `initiator` | `Spec.Initiator` |
| `max_parallelism` | `Spec.MaxParallelism` |
| `tasks` | `Spec.Tasks []KusciaTaskTemplate` |
| `task.task_id` | `KusciaTaskTemplate.TaskID` |
| `task.alias` | `KusciaTaskTemplate.Alias` |
| `task.app_image` | `KusciaTaskTemplate.AppImage` |
| `task.task_input_config` | `KusciaTaskTemplate.TaskInputConfig` |
| `task.parties` | `KusciaTaskTemplate.Parties []Party` |
| `task.dependencies` | `KusciaTaskTemplate.Dependencies` |
| `task.schedule_config` | `KusciaTaskTemplate.ScheduleConfig` |
| `task.tolerable` | `KusciaTaskTemplate.Tolerable` |
| `custom_fields` | `metadata.Labels`（前缀 `kuscia.job.custom-fields/`） |

### 4.3 KusciaJob CRD 类型

**文件：** `kuscia/pkg/crd/apis/kuscia/v1alpha1/kusciajob_types.go`

```go
type KusciaJobSpec struct {
    FlowID         string                `json:"flowID,omitempty"`
    Initiator      string                `json:"initiator"`
    ScheduleMode   KusciaJobScheduleMode `json:"scheduleMode,omitempty"`
    MaxParallelism *int                  `json:"maxParallelism,omitempty"`
    Tasks          []KusciaTaskTemplate  `json:"tasks"`
}

type KusciaTaskTemplate struct {
    Alias           string          `json:"alias"`
    TaskID          string          `json:"taskID,omitempty"`
    Dependencies    []string        `json:"dependencies,omitempty"`
    Tolerable       *bool           `json:"tolerable,omitempty"`
    AppImage        string          `json:"appImage"`
    TaskInputConfig string          `json:"taskInputConfig"`
    ScheduleConfig  *ScheduleConfig `json:"scheduleConfig,omitempty"`
    Priority        int             `json:"priority,omitempty"`
    Parties         []Party         `json:"parties"`
}
```

此时 `TaskInputConfig` 还是上层给的原始 JSON 字符串，尚未做任何 Kuscia 侧扩展。

---

## 5. 第三步：KusciaJob Controller 的调度逻辑

### 5.1 控制器入口

**文件：** `kuscia/pkg/controllers/kusciajob/controller.go`

```go
type Controller struct {
    kusciaClient      clientset.Interface
    kusciaTaskLister  kuscialistersv1alpha1.KusciaTaskLister
    kusciaJobLister   kuscialistersv1alpha1.KusciaJobLister
    handlerFactory    *handler.KusciaJobPhaseHandlerFactory
    // ...
}

func (c *Controller) syncHandler(ctx context.Context, key string) error {
    preJob, _ := c.kusciaJobLister.KusciaJobs(common.KusciaCrossDomain).Get(name)
    curJob := preJob.DeepCopy()
    kusciaJobDefault(curJob)

    phase := curJob.Status.Phase
    needUpdate, err := c.handlerFactory.KusciaJobPhaseHandlerFor(phase).HandlePhase(curJob)

    if err = utilsres.UpdateKusciaJobStatus(c.kusciaClient, preJob, curJob); err != nil {
        return err
    }
}
```

控制器监听 `KusciaJob` 和 `KusciaTask` 事件，任何 Task 状态变化都会重新触发对应 Job 的入队。

### 5.2 状态机与 Handler 映射

**文件：** `kuscia/pkg/controllers/kusciajob/handler/factory.go`

| Phase | Handler | 文件 |
|---|---|---|
| `"" / Initialized` | `InitializedHandler` | `handler/initialized.go` |
| `Pending` | `PendingHandler` | `handler/pending.go` |
| `Running` | `RunningHandler` | `handler/running.go` |
| `Failed` | `FailedHandler` | `handler/failed.go` |
| `Succeeded` | `SucceededHandler` | `handler/succeeded.go` |

### 5.3 依赖解析与就绪任务计算

**文件：** `kuscia/pkg/controllers/kusciajob/handler/scheduler.go`

```go
func readyTasksOf(kusciaJob *kusciaapisv1alpha1.KusciaJob, currentTasks map[string]kusciaapisv1alpha1.KusciaTaskPhase) []kusciaapisv1alpha1.KusciaTaskTemplate {
    copyKusciaJob := kusciaJob.DeepCopy()

    // 去掉已经 Succeeded 的依赖
    for i, t := range copyKusciaJob.Spec.Tasks {
        copyKusciaJob.Spec.Tasks[i].Dependencies = stringFilter(t.Dependencies,
            func(t string, i int) bool {
                return !(currentTasks[t] == kusciaapisv1alpha1.TaskSucceeded)
            })
    }

    // 0 依赖且未创建的任务即 ready
    noDependenciesTasks := kusciaTaskTemplateFilter(copyKusciaJob.Spec.Tasks,
        func(t kusciaapisv1alpha1.KusciaTaskTemplate, i int) bool {
            return len(t.Dependencies) == 0 && t.TaskID != ""
        })

    readyTasks := kusciaTaskTemplateFilter(noDependenciesTasks,
        func(t kusciaapisv1alpha1.KusciaTaskTemplate, i int) bool {
            _, exist := currentTasks[t.Alias]
            return !exist
        })

    // 按优先级排序
    sort.Slice(readyTasks, func(i, j int) bool {
        return readyTasks[i].Priority > readyTasks[j].Priority
    })

    return originReadyTasks
}
```

### 5.4 最大并发控制

```go
func willStartTasksOf(kusciaJob *kusciaapisv1alpha1.KusciaJob, readyTasks []kusciaapisv1alpha1.KusciaTaskTemplate, status map[string]kusciaapisv1alpha1.KusciaTaskPhase) []kusciaapisv1alpha1.KusciaTaskTemplate {
    count := 0
    for _, phase := range status {
        if phase == TaskRunning || phase == TaskPending || phase == "" {
            count++
        }
    }

    if *kusciaJob.Spec.MaxParallelism <= count {
        return nil
    }

    if len(readyTasks) > (*kusciaJob.Spec.MaxParallelism - count) {
        return readyTasks[:*kusciaJob.Spec.MaxParallelism-count]
    }

    return readyTasks
}
```

---

## 6. 第四步：KusciaTask CRD 的创建

### 6.1 RunningHandler 创建 KusciaTask

**文件：** `kuscia/pkg/controllers/kusciajob/handler/running.go`

```go
func (h *RunningHandler) handleRunning(job *kusciaapisv1alpha1.KusciaJob) (needUpdateStatus bool, err error) {
    // ...
    readyTask := readyTasksOf(job, currentSubTasksStatusWithAlias)
    willStartTask := willStartTasksOf(job, readyTask, currentSubTasksStatusWithAlias)
    willStartKusciaTasks, err := h.buildWillStartKusciaTask(job, willStartTask)

    for _, t := range willStartKusciaTasks {
        _, err = h.kusciaClient.KusciaV1alpha1().KusciaTasks(common.KusciaCrossDomain).Create(context.Background(), t, metav1.CreateOptions{})
    }
}
```

### 6.2 buildWillStartKusciaTask

**文件：** `kuscia/pkg/controllers/kusciajob/handler/scheduler.go`

```go
func (h *RunningHandler) buildWillStartKusciaTask(kusciaJob *kusciaapisv1alpha1.KusciaJob, willStartTask []kusciaapisv1alpha1.KusciaTaskTemplate) ([]*kusciaapisv1alpha1.KusciaTask, error) {
    for i, t := range willStartTask {
        taskObject := &kusciaapisv1alpha1.KusciaTask{
            ObjectMeta: metav1.ObjectMeta{
                Name: t.TaskID,
                OwnerReferences: []metav1.OwnerReference{
                    *metav1.NewControllerRef(kusciaJob, kusciaapisv1alpha1.SchemeGroupVersion.WithKind(KusciaJobKind)),
                },
                Annotations: map[string]string{
                    common.JobIDAnnotationKey:                    kusciaJob.Name,
                    common.TaskAliasAnnotationKey:                t.Alias,
                    common.SelfClusterAsParticipantAnnotationKey: strconv.FormatBool(asParticipant),
                },
                Labels: map[string]string{
                    common.LabelController: LabelControllerValueKusciaJob,
                    common.LabelJobUID:     string(kusciaJob.UID),
                },
            },
            Spec: h.createTaskSpec(kusciaJob.Spec.Initiator, t),
        }
    }
}
```

### 6.3 TaskInputConfig、Parties、AppImage 的映射

```go
func (h *RunningHandler) createTaskSpec(initiator string, t kusciaapisv1alpha1.KusciaTaskTemplate) kusciaapisv1alpha1.KusciaTaskSpec {
    return kusciaapisv1alpha1.KusciaTaskSpec{
        Initiator:       initiator,
        TaskInputConfig: t.TaskInputConfig,
        Parties:         h.buildPartiesFromTaskInputConfig(t),
        ScheduleConfig:  *t.ScheduleConfig,
    }
}

func (h *RunningHandler) buildPartiesFromTaskInputConfig(template kusciaapisv1alpha1.KusciaTaskTemplate) []kusciaapisv1alpha1.PartyInfo {
    for i, p := range template.Parties {
        tpl := h.buildPartyTemplate(p, template.AppImage)
        taskPartyInfos[i] = kusciaapisv1alpha1.PartyInfo{
            DomainID:       p.DomainID,
            AppImageRef:    template.AppImage,
            Role:           p.Role,
            Template:       tpl,
            BandwidthLimit: p.BandwidthLimit,
        }
    }
    return taskPartyInfos
}
```

### 6.4 AppImage 部署模板选择

```go
func (h *RunningHandler) findMatchedDeployTemplate(p kusciaapisv1alpha1.Party, appImageName string) (*v1alpha1.DeployTemplate, error) {
    appImage, err := h.kusciaClient.KusciaV1alpha1().AppImages().Get(context.Background(), appImageName, metav1.GetOptions{})
    return utilsres.SelectDeployTemplate(appImage.Spec.DeployTemplates, p.Role)
}
```

`SelectDeployTemplate` 按 `role` 匹配；未指定 role 的模板作为默认模板。

### 6.5 KusciaTask CRD 类型

**文件：** `kuscia/pkg/crd/apis/kuscia/v1alpha1/kusciatask_types.go`

```go
type KusciaTaskSpec struct {
    Initiator       string      `json:"initiator"`
    TaskInputConfig string      `json:"taskInputConfig"`
    Parties         []PartyInfo `json:"parties"`
    ScheduleConfig  ScheduleConfig `json:"scheduleConfig"`
}

type PartyInfo struct {
    DomainID       string         `json:"domainID"`
    AppImageRef    string         `json:"appImageRef"`
    Role           string         `json:"role,omitempty"`
    Template       PartyTemplate  `json:"template,omitempty"`
    BandwidthLimit *BandwidthLimit `json:"bandwidthLimit,omitempty"`
}
```

---

## 7. 第五步：KusciaTask Controller 创建运行资源

### 7.1 控制器入口

**文件：** `kuscia/pkg/controllers/kusciatask/controller.go`

```go
func (c *Controller) syncHandler(key string) (retErr error) {
    sharedTask, _ := c.kusciaTaskLister.KusciaTasks(common.KusciaCrossDomain).Get(name)
    kusciaTask := sharedTask.DeepCopy()

    phase := kusciaTask.Status.Phase
    if phase == "" {
        phase = kusciaapisv1alpha1.TaskPending
    }

    needUpdate, err := c.handlerFactory.GetKusciaTaskPhaseHandler(phase).Handle(kusciaTask)
    c.updateTaskStatus(sharedTask, kusciaTask)
}
```

控制器监听对象：KusciaTask、Pod、Service、TaskResourceGroup。

### 7.2 PendingHandler 主流程

**文件：** `kuscia/pkg/controllers/kusciatask/handler/pending_handler.go`

```go
func (h *PendingHandler) Handle(kusciaTask *kusciaapisv1alpha1.KusciaTask) (needUpdate bool, err error) {
    if needUpdate, err = h.prepareTaskResources(now, kusciaTask); needUpdate || err != nil {
        return needUpdate, err
    }

    h.initPartyTaskStatus(kusciaTask, curKtStatus)
    refreshKtResourcesStatus(...)

    if updated := h.taskFailed(now, kusciaTask); updated {
        return true, nil
    }

    if updated, err := h.taskRunning(now, kusciaTask); updated || err != nil {
        return updated, err
    }
}
```

### 7.3 prepareTaskResources：端口分配 + 资源创建

```go
func (h *PendingHandler) prepareTaskResources(now metav1.Time, kusciaTask *kusciaapisv1alpha1.KusciaTask) (needUpdate bool, err error) {
    // 1. 分配端口
    cond, found := utilsres.GetKusciaTaskCondition(&kusciaTask.Status, KusciaTaskCondPortsAllocated, true)
    if !found {
        needUpdate, err = h.allocatePorts(kusciaTask)
    }

    // 2. 创建资源
    cond, found = utilsres.GetKusciaTaskCondition(&kusciaTask.Status, KusciaTaskCondResourceCreated, true)
    if !found {
        if err = h.createTaskResources(kusciaTask); err != nil {
            // ...
        }
    }
}
```

### 7.4 createTaskResources：为每个本域 party 创建资源

```go
func (h *PendingHandler) createTaskResources(kusciaTask *kusciaapisv1alpha1.KusciaTask) error {
    partyKitInfos, selfPartyKitInfos, err := h.buildPartyKitInfos(kusciaTask)
    buildPodAllocatePorts(kusciaTask, selfPartyKitInfos)

    parties := generateParties(partyKitInfos)
    for _, partyKitInfo := range partyKitInfos {
        fillPartyClusterDefine(partyKitInfo, parties)
    }

    for _, partyKitInfo := range selfPartyKitInfos {
        permit, errors := h.pluginManager.Permit(context.Background(), *partyKitInfo)
        ps, ss, err := h.createResourceForParty(partyKitInfo)
    }

    return h.createTaskResourceGroup(kusciaTask, partyKitInfos)
}
```

### 7.5 buildPartyKitInfo：把 AppImage 部署模板落到 party

```go
func (h *PendingHandler) buildPartyKitInfo(kusciaTask *kusciaapisv1alpha1.KusciaTask, party *kusciaapisv1alpha1.PartyInfo) (*PartyKitInfo, error) {
    appImage, _ := h.appImagesLister.Get(party.AppImageRef)
    baseDeployTemplate, _ := utilsres.SelectDeployTemplate(appImage.Spec.DeployTemplates, party.Role)
    deployTemplate := mergeDeployTemplate(baseDeployTemplate, &party.Template)

    kit.Image = fmt.Sprintf("%s:%s", appImage.Spec.Image.Name, appImage.Spec.Image.Tag)
    kit.ImageID = appImage.Spec.Image.ID
    kit.DeployTemplate = deployTemplate
    kit.ConfigTemplates = appImage.Spec.ConfigTemplates
    // ...
}
```

### 7.6 createResourceForParty：创建 ConfigMap、Pod、Service

```go
func (h *PendingHandler) createResourceForParty(partyKit *PartyKitInfo) (map[string]*PodStatus, map[string]*ServiceStatus, error) {
    // 如果 AppImage 有 configTemplates，先创建 config-template ConfigMap
    if len(partyKit.ConfigTemplates) > 0 {
        configMap := generateConfigMap(partyKit)
        h.submitConfigMap(configMap)
    }

    // 创建 Kuscia 生成的 values ConfigMap
    // ... generateKusciaConfigMap ...

    // 为每个 pod 创建 Pod 和 Service
    for _, podKit := range partyKit.Pods {
        pod, _ := h.generatePod(partyKit, podKit)
        pod, _ = h.submitPod(pod)

        for portName, serviceName := range podKit.PortService {
            service, _ := generateServices(partyKit, pod, serviceName, ctrPort)
            h.submitService(service, pod)
        }
    }
}
```

### 7.7 generatePod 关键片段

```go
pod := &v1.Pod{
    ObjectMeta: metav1.ObjectMeta{
        Name:        podKit.PodName,
        Namespace:   partyKit.DomainID,
        Labels:      labels,
        Annotations: annotations,
    },
    Spec: v1.PodSpec{
        RestartPolicy:                restartPolicy,
        NodeSelector:                 map[string]string{common.LabelNodeNamespace: partyKit.DomainID},
        SchedulerName:                schedulerName,
        AutomountServiceAccountToken: &automountServiceAccountToken,
        Tolerations: []v1.Toleration{{
            Key: common.KusciaTaintTolerationKey, Operator: v1.TolerationOpExists, Effect: v1.TaintEffectNoSchedule,
        }},
    },
}

for _, ctr := range partyKit.DeployTemplate.Spec.Containers {
    resCtr := v1.Container{
        Name:            ctr.Name,
        Image:           partyKit.Image,
        Command:         ctr.Command,
        Args:            ctr.Args,
        WorkingDir:      ctr.WorkingDir,
        Env:             ctr.Env,
        Resources:       ctr.Resources,
        // ...
    }
    for _, port := range ctr.Ports { ... }
}
```

Pod 名规则：

```go
func generatePodName(taskName string, role string, index int) string {
    return fmt.Sprintf("%s-%s-%d", taskName, role, index)
}
```

---

## 8. 第六步：ConfigMap 与 TaskInputConfig

### 8.1 两个 ConfigMap

KusciaTask PendingHandler 会创建两类 ConfigMap：

| ConfigMap | 名称格式 | 来源 | 用途 |
|---|---|---|---|
| **config-template CM** | `<task>-configtemplate` | AppImage.Spec.ConfigTemplates | 存储待渲染的模板文件 |
| **values CM** | `<task>-kuscia-gen-conf` | Kuscia 生成 | 存储运行时变量：TASK_ID、TASK_INPUT_CONFIG、TASK_CLUSTER_DEFINE、ALLOCATED_PORTS 等 |

### 8.2 values CM 的生成

**文件：** `kuscia/pkg/controllers/kusciatask/handler/pending_handler.go`

```go
func generateKusciaConfigMap(partyKit *PartyKitInfo, podKit *PodKitInfo) *v1.ConfigMap {
    confMap := make(map[string]string)
    confMap[common.EnvDomainID] = partyKit.DomainID          // KUSCIA_DOMAIN_ID
    confMap[common.EnvTaskID] = partyKit.KusciaTask.Name     // TASK_ID
    confMap[common.EnvTaskClusterDefine] = string(clusterDefine)
    confMap[common.EnvAllocatedPorts] = string(allocatedPorts)

    confMapBinaryData := make(map[string][]byte)

    // 压缩 task_input_config
    if compressInputConf, err := utilcom.CompressString(partyKit.KusciaTask.Spec.TaskInputConfig); err != nil {
        confMap[common.EnvTaskInputConfig] = partyKit.KusciaTask.Spec.TaskInputConfig
    } else {
        confMapBinaryData[common.EnvTaskInputConfig] = compressInputConf
        annotations[common.ConfigValueCompressFieldsNameAnnotationKey] =
            utilcom.SliceToAnnotationString([]string{common.EnvTaskInputConfig})
    }

    confMapName := fmt.Sprintf(common.KusciaGenerateConfigMapFormat, partyKit.KusciaTask.Name)
    return &v1.ConfigMap{
        ObjectMeta: metav1.ObjectMeta{
            Name:        confMapName,
            Namespace:   partyKit.DomainID,
            Annotations: annotations,
        },
        Data:       confMap,
        BinaryData: confMapBinaryData,
    }
}
```

### 8.3 关键常量

**文件：** `kuscia/pkg/common/constants.go`

```go
const (
    EnvTaskID              = "TASK_ID"
    EnvTaskInputConfig     = "TASK_INPUT_CONFIG"
    EnvTaskClusterDefine   = "TASK_CLUSTER_DEFINE"
    EnvAllocatedPorts      = "ALLOCATED_PORTS"
    EnvDomainID            = "KUSCIA_DOMAIN_ID"
)

const KusciaGenerateConfigMapFormat = "%s-kuscia-gen-conf"
```

### 8.4 TaskInputConfig 压缩

`TASK_INPUT_CONFIG` 可能很大（包含完整的组件参数、输入输出 ID、集群描述等），所以 Kuscia 用 `CompressString` 把它压缩后放到 `ConfigMap.BinaryData` 中，并在 annotations 里记录压缩字段名，由 config-render 插件解压。

---

## 9. 第七步：config-render 插件渲染配置

### 9.1 触发时机

**文件：** `kuscia/pkg/agent/middleware/plugins/hook/configrender/config_render.go`

config-render 是 Kuscia Agent 的一个 hook 插件，在容器启动前执行：

```go
func (cr *configRender) CanExec(ctx hook.Context) bool {
    switch ctx.Point() {
    case hook.PointMakeMounts:
        return mCtx.Mount.Name == mCtx.Pod.Annotations[common.ConfigTemplateVolumesAnnotationKey]
    case hook.PointK8sProviderSyncPod:
        return syncPodCtx.BkPod.Annotations[common.ConfigTemplateVolumesAnnotationKey] != ""
    }
}
```

触发条件：

1. Pod 挂载了名为 `config-template` 的 volume；
2. Pod 带有注解 `kuscia.secretflow/config-template-volumes`。

### 9.2 渲染数据准备

```go
func (cr *configRender) handleMakeMountsContext(ctx *hook.MakeMountsContext) error {
    envs := map[string]string{}
    for _, env := range ctx.Envs {
        envs[env.Name] = env.Value
    }

    data, err := cr.makeDataMap(ctx.Pod.Annotations, envs)
    if err = fillTemplateValueFromConfigMap(ctx.Pod, ctx.ResourceManager, data); err != nil { ... }

    // 渲染模板目录/文件
    if info.IsDir() {
        cr.renderConfigDirectory(hostPath, configPath, data)
    } else {
        cr.renderConfigFile(hostPath, configPath, data)
    }

    *ctx.HostPath = configPath
}
```

### 9.3 从 values CM 读取并解压

```go
func fillTemplateValueFromConfigMap(pod *v1.Pod, resourceManager *resource.KubeResourceManager, templateValues map[string]string) error {
    cmName := pod.Annotations[common.ConfigTemplateValueAnnotationKey]
    cm, _ := resourceManager.GetConfigMap(cmName)

    for k, v := range cm.Data {
        templateValues[k] = v
    }

    // 解压被压缩的字段
    if strCompressFields, ok := cm.Annotations[common.ConfigValueCompressFieldsNameAnnotationKey]; ok {
        for _, field := range utilcom.AnnotationStringToSlice(strCompressFields) {
            valString, _ := utilcom.DecompressString(cm.BinaryData[field])
            templateValues[field] = valString
        }
    }
}
```

### 9.4 渲染语法

```go
func (cr *configRender) renderConfig(templateContent string, data map[string]string) (string, error) {
    configReg := regexp.MustCompile(`\{\{?\{\.([^{}]+)\}\}?\}`)
    // ...
    tmpl, err := template.New("config-template").Option(defaultTemplateRenderOption).
        Funcs(template.FuncMap{"kuscia": kusciaQueryValue}).Parse(configResult)
    // ...
    for k, v := range data {
        quoteData[k] = strings.Trim(strconv.Quote(v), "\"")
    }
    tmpl.Execute(&buf, quoteData)
}
```

支持：

- `{{.TASK_ID}}` / `{{.TASK_INPUT_CONFIG}}` 等普通占位符；
- `{{{kuscia "xxx.yyy"}}}` 复杂查询；
- 缺失 key 按 `missingkey=zero` 处理。

### 9.5 渲染结果示例

AppImage 里的模板：

```yaml
configTemplates:
  task-config.conf: |
    {
      "task_id": "{{.TASK_ID}}",
      "task_input_config": "{{.TASK_INPUT_CONFIG}}",
      "task_cluster_def": "{{.TASK_CLUSTER_DEFINE}}",
      "task_progress_url":"http://reporter.master.svc/report/progress?task_id={{.TASK_ID}}",
      "allocated_ports": "{{.ALLOCATED_PORTS}}"
    }
```

渲染后变成容器内的 `/work/kuscia/task-config.conf`：

```json
{
  "task_id": "job-abc-task-1",
  "task_input_config": "{\"sf_node_eval_param\": {...}, ...}",
  "task_cluster_def": "{\"parties\": [...], ...}",
  "task_progress_url": "http://reporter.master.svc/report/progress?task_id=job-abc-task-1",
  "allocated_ports": "{\"spu\": 30001, \"fed\": 30002, ...}"
}
```

SecretFlow 入口读取的正是这个文件。

---

## 10. 第八步：AppImage、DeployTemplate 与 SecretFlow 启动命令

### 10.1 AppImage CRD 类型

**文件：** `kuscia/pkg/crd/apis/kuscia/v1alpha1/appimage_types.go`

```go
type AppImageSpec struct {
    Image           AppImageInfo          `json:"image"`
    ConfigTemplates map[string]string     `json:"configTemplates,omitempty"`
    DeployTemplates []DeployTemplate      `json:"deployTemplates"`
}

type AppImageInfo struct {
    Name string `json:"name"`
    Tag  string `json:"tag"`
    ID   string `json:"id,omitempty"`
    Sign string `json:"sign,omitempty"`
}

type DeployTemplate struct {
    Name          string         `json:"name"`
    Role          string         `json:"role,omitempty"`
    Replicas      *int32         `json:"replicas,omitempty"`
    NetworkPolicy *NetworkPolicy `json:"networkPolicy,omitempty"`
    Spec          PodSpec        `json:"spec"`
}
```

### 10.2 PodSpec / Container 类型

**文件：** `kuscia/pkg/crd/apis/kuscia/v1alpha1/common.go`

```go
type PodSpec struct {
    RestartPolicy corev1.RestartPolicy `json:"restartPolicy,omitempty"`
    Containers    []Container          `json:"containers,omitempty"`
    Affinity      *corev1.Affinity     `json:"affinity,omitempty"`
}

type Container struct {
    Name               string                `json:"name"`
    Command            []string              `json:"command,omitempty"`
    Args               []string              `json:"args,omitempty"`
    WorkingDir         string                `json:"workingDir"`
    ConfigVolumeMounts []ConfigVolumeMount   `json:"configVolumeMounts,omitempty"`
    Ports              []ContainerPort       `json:"ports"`
    EnvFrom            []corev1.EnvFromSource `json:"envFrom,omitempty"`
    Env                []corev1.EnvVar       `json:"env,omitempty"`
    Resources          corev1.ResourceRequirements `json:"resources,omitempty"`
    // ...
}

type ConfigVolumeMount struct {
    MountPath string `json:"mountPath"`
    SubPath   string `json:"subPath"`
}

type ContainerPort struct {
    Name     string       `json:"name"`
    Port     int32        `json:"port,omitempty"`
    Protocol PortProtocol `json:"protocol,omitempty"`  // HTTP / GRPC
    Scope    PortScope    `json:"scope,omitempty"`     // Cluster / Domain / Local
}
```

### 10.3 SecretFlow 的 AppImage 实例

**文件：** `kuscia/scripts/templates/app_image.secretflow.yaml`

```yaml
apiVersion: kuscia.secretflow/v1alpha1
kind: AppImage
metadata:
  name: secretflow-image
spec:
  configTemplates:
    task-config.conf: |
      {
        "task_id": "{{.TASK_ID}}",
        "task_input_config": "{{.TASK_INPUT_CONFIG}}",
        "task_cluster_def": "{{.TASK_CLUSTER_DEFINE}}",
        "task_progress_url":"http://reporter.master.svc/report/progress?task_id={{.TASK_ID}}",
        "allocated_ports": "{{.ALLOCATED_PORTS}}"
      }
  deployTemplates:
    - name: secretflow
      replicas: 1
      spec:
        containers:
          - command:
              - sh
            args:
              - -c
              - "python -m secretflow.kuscia.entry ./kuscia/task-config.conf"
            configVolumeMounts:
              - mountPath: /work/kuscia/task-config.conf
                subPath: task-config.conf
            name: secretflow
            ports:
              - name: spu
                protocol: GRPC
                scope: Cluster
              - name: fed
                protocol: GRPC
                scope: Cluster
              - name: global
                protocol: GRPC
                scope: Domain
              - name: node-manager
                protocol: GRPC
                scope: Local
              - name: object-manager
                protocol: GRPC
                scope: Local
              - name: client-server
                protocol: GRPC
                scope: Local
              - name: inference
                protocol: HTTP
                scope: Cluster
            workingDir: /work
        restartPolicy: Never
  image:
    name: secretflow/secretflow-lite-anolis8
    tag: latest
```

### 10.4 Kuscia 生成的容器 Spec

在 `generatePod` 中，Kuscia 把 AppImage 的 `DeployTemplate` 复制为 K8s Container：

```go
resCtr := v1.Container{
    Name:       ctr.Name,         // "secretflow"
    Image:      partyKit.Image,   // "secretflow/secretflow-lite-anolis8:latest"
    Command:    ctr.Command,      // ["sh"]
    Args:       ctr.Args,         // ["-c", "python -m secretflow.kuscia.entry ./kuscia/task-config.conf"]
    WorkingDir: ctr.WorkingDir,   // "/work"
    Env:        ctr.Env,
    Resources:  ctr.Resources,
    // ...
}
```

同时根据 `configVolumeMounts` 生成 VolumeMount：

```go
VolumeMount{
    Name:      "config-template",
    MountPath: "/work/kuscia/task-config.conf",
    SubPath:   "task-config.conf",
}
```

### 10.5 SecretFlow 实际启动命令

容器真正执行的进程等价于：

```bash
cd /work
sh -c "python -m secretflow.kuscia.entry ./kuscia/task-config.conf"
```

这行命令由 AppImage 模板决定，Kuscia 只是原样透传到 K8s Container 的 `Command` + `Args`。

---

## 11. 第九步：SecretFlow 读取配置、连接 DataMesh、执行任务

### 11.1 SecretFlow 入口

**文件：** `secretflow/secretflow/kuscia/entry.py`

```python
DEFAULT_DATAMESH_ADDRESS = "datamesh:8071"

@click.command()
@click.argument("task_config_path", type=click.Path(exists=True))
@click.option("--datamesh_addr", required=False, default=DEFAULT_DATAMESH_ADDRESS)
def main(task_config_path, datamesh_addr, enable_plugins: bool):
    os.environ["DATAMESH_ADDRESS"] = datamesh_addr
    # ...
```

由于 AppImage 启动命令没有传 `--datamesh_addr`，所以使用默认 `datamesh:8071`。

### 11.2 解析 task-config.conf

```python
kuscia_config = KusciaTaskConfig.from_file(task_config_path)
```

`KusciaTaskConfig` 字段包含：

- `task_id`
- `task_cluster_def`
- `task_allocated_ports`
- `task_progress_url`
- `sf_node_eval_param`
- `sf_cluster_desc`
- `sf_storage_config`
- `sf_input_ids`
- `sf_input_partitions_spec`
- `sf_output_ids`
- `sf_output_uris`
- `sf_output_partitions_spec`
- `sf_datasource_config`
- `table_attrs`

### 11.3 DataMesh 地址与 mTLS

SecretFlow 通过 `datamesh:8071` 连接本域 DataMesh gRPC/Flight 服务。

TLS 证书由 Kuscia Agent 的 `certissuance` hook 注入：

**文件：** `kuscia/pkg/agent/middleware/plugins/hook/certissuance/cert_issuance.go`

在 `generatePod` 中，Pod 被打上标签：

```go
common.LabelCommunicationRoleServer: "true"
common.LabelCommunicationRoleClient: "true"
```

agent 的 `certIssuance` hook 据此为容器签发证书，并注入环境变量：

- `SERVER_CERT_FILE`
- `SERVER_PRIVATE_KEY_FILE`
- `CLIENT_CERT_FILE`
- `CLIENT_PRIVATE_KEY_FILE`
- `TRUSTED_CA_FILE`

SecretFlow 的 `create_channel(address)` 会读取这些环境变量来建立到 DataMesh 的 mTLS 连接。

### 11.4 任务执行

```text
secretflow/kuscia/entry.py::main()
    ├─ load_plugins()                       # 加载组件插件
    ├─ KusciaTaskConfig.from_file(path)     # 解析配置
    ├─ create_channel(datamesh_addr)        # 连接 DataMesh
    ├─ get_domain_data_source(...)          # 查询数据源
    ├─ get_storage_config(...)              # 构建 StorageConfig
    ├─ preprocess_sf_node_eval_param(...)   # DomainData -> DistData
    ├─ get_sf_cluster_config(...)           # Kuscia -> SFClusterConfig
    ├─ comp_eval(...)                       # 执行组件
    │   ├─ setup_sf_cluster()
    │   ├─ Context()
    │   ├─ Component.evaluate(ctx)
    │   └─ NodeEvalResult(outputs=[...])
    └─ postprocess_sf_node_eval_result(...) # DistData -> DataMesh
        ├─ create_domain_data_in_dm()
        └─ upload_dist_data_to_dp()
```

---

## 12. 第十步：任务执行完成后状态回传

### 12.1 Pod 状态被 KusciaTask Controller 监听

**文件：** `kuscia/pkg/controllers/kusciatask/controller.go`

```go
_, _ = podInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
    UpdateFunc: func(oldObj, newObj interface{}) {
        // ...
        controller.handlePodObject(newObj)
    },
    DeleteFunc: controller.handlePodObject,
})
```

`handlePodObject` 通过 Pod 注解 `kuscia.secretflow/task-id` 找到所属 KusciaTask，重新入队。

### 12.2 KusciaTask RunningHandler 汇总状态

**文件：** `kuscia/pkg/controllers/kusciatask/handler/running_handler.go`

```go
func (h *RunningHandler) Handle(kusciaTask *kusciaapisv1alpha1.KusciaTask) (bool, error) {
    trg, _ := getTaskResourceGroup(...)
    h.reconcileTaskStatus(taskStatus, trg)
    refreshKtResourcesStatus(...)
    kusciaTask.Status = *taskStatus
}
```

`reconcileTaskStatus` 根据各 party 的 pod 状态决定 `KusciaTask.Phase`：

```go
if successfulPartyCount >= minReservedMembers {
    taskStatus.Phase = kusciaapisv1alpha1.TaskSucceeded
    return
}
if runningPartyCount > 0 {
    taskStatus.Phase = kusciaapisv1alpha1.TaskRunning
    return
}
// ...
```

### 12.3 KusciaJob Controller 汇总 Task 状态

**文件：** `kuscia/pkg/controllers/kusciajob/controller.go`

```go
func (c *Controller) handleTaskObject(obj interface{}) {
    if ownerRef := metav1.GetControllerOf(object); ownerRef != nil {
        if ownerRef.Kind != handler.KusciaJobKind {
            return
        }
        kusciaJob, _ := c.kusciaJobLister.KusciaJobs(common.KusciaCrossDomain).Get(ownerRef.Name)
        c.enqueueKusciaJob(kusciaJob)
    }
}
```

**文件：** `kuscia/pkg/controllers/kusciajob/handler/running.go`

```go
subTasks, _ := h.kusciaTaskLister.List(selector)
currentSubTasksStatusWithAlias, _ := buildJobSubTaskStatus(subTasks, job)
currentJobPhase := jobStatusPhaseFrom(job, currentSubTasksStatusWithAlias)
updateJobSubTaskStatus(&job.Status, currentSubTasksStatusWithID)
buildJobStatus(now, &job.Status, currentJobPhase)
```

### 12.4 WatchJob 流回传给上层

**文件：** `kuscia/pkg/kusciaapi/service/job_service.go`

```go
func (h *jobService) WatchJob(ctx context.Context, request *kusciaapi.WatchJobRequest, eventCh chan<- *kusciaapi.WatchJobEventResponse) error {
    wJob, _ := h.kusciaClient.KusciaV1alpha1().KusciaJobs(common.KusciaCrossDomain).Watch(ctx, ...)
    wTask, _ := h.kusciaClient.KusciaV1alpha1().KusciaTasks(common.KusciaCrossDomain).Watch(ctx, ...)

    for {
        select {
        case event := <-wJob.ResultChan():
            job, _ := event.Object.(*v1alpha1.KusciaJob)
            jobStatus, _ := h.buildJobStatus(ctx, job)
            eventCh <- &kusciaapi.WatchJobEventResponse{Type: ..., Object: jobStatus}

        case event := <-wTask.ResultChan():
            task, _ := event.Object.(*v1alpha1.KusciaTask)
            if task.Status.Phase == TaskRunning && task.Status.Progress > 0 {
                job, _ := h.kusciaClient.KusciaV1alpha1().KusciaJobs(...).Get(ctx, ownerRef.Name, ...)
                jobStatus, _ := h.buildJobStatus(ctx, job)
                eventCh <- &kusciaapi.WatchJobEventResponse{Type: EventType_MODIFIED, Object: jobStatus}
            }
        }
    }
}
```

上层通过 gRPC stream `JobService/WatchJob` 或 HTTP `/api/v1/job/watch` 持续收到 `JobStatus` 事件。

---

## 13. 不同任务类型在 Kuscia 侧的差异

### 13.1 MPC / TEE 任务

Kuscia 对 MPC 和 TEE **没有独立的控制器分支**，两者的差异主要体现在上层生成的配置和 AppImage 模板：

| 差异点 | MPC | TEE |
|---|---|---|
| `app_image` | `secretflow-image` | 对应的 TEE AppImage |
| `task_input_config` | 普通 SecretFlow 组件参数 | 可能包含 TEE 证书、CapsuleManager 地址、签名等 |
| `ScheduleConfig` / 资源 | 普通资源 | 可能需要 TEE 节点亲和性 |
| AppImage 模板 | SecretFlow 标准模板 | TEE 运行时模板 |

Kuscia 只负责“把任务当成一个带 AppImage 的任务”去调度，不区分算法类型。

### 13.2 Serving 任务

Serving 走的是另一条独立链路：

| 项 | Job 任务 | Serving |
|---|---|---|
| API | `CreateJob` | `CreateServing` |
| CRD | `KusciaJob` / `KusciaTask` | `KusciaDeployment` |
| 控制器 | `kusciajob` / `kusciatask` | `kusciadeployment` |
| 运行时资源 | Pod + Service + TaskResourceGroup | K8s Deployment + Service |
| 生命周期 | 批式：完成即结束 | 长服务：持续运行 |
| 输入配置 | `TaskInputConfig` | `ServingInputConfig` |

**文件：** `kuscia/pkg/kusciaapi/service/serving_service.go`

```go
func (s *servingService) CreateServing(ctx context.Context, request *kusciaapi.CreateServingRequest) *kusciaapi.CreateServingResponse {
    kd, err := s.buildKusciaDeployment(ctx, request)
    s.kusciaClient.KusciaV1alpha1().KusciaDeployments(common.KusciaCrossDomain).Create(ctx, kd, metav1.CreateOptions{})
}
```

### 13.3 BFIA 互联互通任务

在 `KusciaJob` 调度器里有专门分支处理 BFIA 协议：

**文件：** `kuscia/pkg/controllers/kusciajob/handler/pending.go`

```go
if isBFIAInterConnJob(h.namespaceLister, job) {
    if isInitatior {
        if AllJobPartiesHaveStage(job, JobCreateStageSucceeded) { ... }
        if AllJobPartiesHaveStage(job, JobStartStageSucceeded) {
            job.Status.Phase = KusciaJobRunning
        }
    } else {
        job.Status.Phase = KusciaJobRunning
    }
}
```

BFIA 任务需要等待所有参与方都完成创建阶段、并且启动阶段握手成功后，才真正进入 Running。

---

## 14. 关键配置转换示例

### 14.1 上层 CreateJobRequest.Task 示例

```json
{
  "job_id": "project-123-graph-1-job-1",
  "initiator": "alice",
  "max_parallelism": 1,
  "tasks": [
    {
      "app_image": "secretflow-image",
      "task_id": "task-psi-001",
      "alias": "psi",
      "dependencies": [],
      "parties": [
        {"domain_id": "alice", "role": "server"},
        {"domain_id": "bob", "role": "client"}
      ],
      "task_input_config": "{\"sf_node_eval_param\":{...},\"sf_cluster_desc\":{...},\"sf_input_ids\":[\"alice-table-1\",\"bob-table-1\"],\"sf_output_ids\":[\"psi-output-1\"]}"
    }
  ]
}
```

### 14.2 生成的 KusciaJob Spec 片段

```yaml
apiVersion: kuscia.secretflow/v1alpha1
kind: KusciaJob
metadata:
  name: project-123-graph-1-job-1
spec:
  initiator: alice
  maxParallelism: 1
  tasks:
    - alias: psi
      taskID: task-psi-001
      appImage: secretflow-image
      taskInputConfig: '{"sf_node_eval_param":{...},...}'
      parties:
        - domainID: alice
          role: server
        - domainID: bob
          role: client
```

### 14.3 生成的 KusciaTask Spec 片段

```yaml
apiVersion: kuscia.secretflow/v1alpha1
kind: KusciaTask
metadata:
  name: task-psi-001
  ownerReferences:
    - kind: KusciaJob
      name: project-123-graph-1-job-1
spec:
  initiator: alice
  taskInputConfig: '{"sf_node_eval_param":{...},...}'
  parties:
    - domainID: alice
      appImageRef: secretflow-image
      role: server
      template: { ... }
    - domainID: bob
      appImageRef: secretflow-image
      role: client
      template: { ... }
```

### 14.4 生成的 Pod 容器片段

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: task-psi-001-server-0
  namespace: alice
spec:
  containers:
    - name: secretflow
      image: secretflow/secretflow-lite-anolis8:latest
      command: ["sh"]
      args: ["-c", "python -m secretflow.kuscia.entry ./kuscia/task-config.conf"]
      workingDir: /work
      volumeMounts:
        - name: config-template
          mountPath: /work/kuscia/task-config.conf
          subPath: task-config.conf
      ports:
        - name: spu
          containerPort: 30001
        - name: fed
          containerPort: 30002
        # ...
```

### 14.5 渲染后的 task-config.conf 示例

```json
{
  "task_id": "task-psi-001",
  "task_input_config": "{\"sf_node_eval_param\":{\"domain\":\"data_prep\",\"name\":\"psi\",\"version\":\"1.0.0\",...},\"sf_input_ids\":[\"alice-table-1\",\"bob-table-1\"],\"sf_output_ids\":[\"psi-output-1\"],\"sf_cluster_desc\":{...}}",
  "task_cluster_def": "{\"parties\":[{\"name\":\"alice\",\"role\":\"server\",\"services\":[{\"portName\":\"fed\",\"endpoint\":\"task-psi-001-server-0.alice.svc:30002\"}]},{\"name\":\"bob\",\"role\":\"client\",\"services\":[{\"portName\":\"fed\",\"endpoint\":\"task-psi-001-client-0.bob.svc:30002\"}]}],\"selfPartyIdx\":0}",
  "task_progress_url": "http://reporter.master.svc/report/progress?task_id=task-psi-001",
  "allocated_ports": "{\"spu\":30001,\"fed\":30002,\"global\":30003,\"node-manager\":30004,\"object-manager\":30005,\"client-server\":30006}"
}
```

---

## 15. 关键文件索引

| 环节 | 文件 |
|---|---|
| HTTP/gRPC 入口注册 | `kuscia/pkg/kusciaapi/bean/http_server_bean.go` |
| gRPC Server 注册 | `kuscia/pkg/kusciaapi/bean/grpc_server_bean.go` |
| CreateJob 业务逻辑 | `kuscia/pkg/kusciaapi/service/job_service.go` |
| WatchJob 业务逻辑 | `kuscia/pkg/kusciaapi/service/job_service.go` |
| KusciaJob CRD 类型 | `kuscia/pkg/crd/apis/kuscia/v1alpha1/kusciajob_types.go` |
| KusciaTask CRD 类型 | `kuscia/pkg/crd/apis/kuscia/v1alpha1/kusciatask_types.go` |
| AppImage CRD 类型 | `kuscia/pkg/crd/apis/kuscia/v1alpha1/appimage_types.go` |
| Pod/Container 类型 | `kuscia/pkg/crd/apis/kuscia/v1alpha1/common.go` |
| Job Controller | `kuscia/pkg/controllers/kusciajob/controller.go` |
| Job 状态机工厂 | `kuscia/pkg/controllers/kusciajob/handler/factory.go` |
| Job 调度器 | `kuscia/pkg/controllers/kusciajob/handler/scheduler.go` |
| Job InitializedHandler | `kuscia/pkg/controllers/kusciajob/handler/initialized.go` |
| Job PendingHandler | `kuscia/pkg/controllers/kusciajob/handler/pending.go` |
| Job RunningHandler | `kuscia/pkg/controllers/kusciajob/handler/running.go` |
| Task Controller | `kuscia/pkg/controllers/kusciatask/controller.go` |
| Task PendingHandler | `kuscia/pkg/controllers/kusciatask/handler/pending_handler.go` |
| Task RunningHandler | `kuscia/pkg/controllers/kusciatask/handler/running_handler.go` |
| TaskResourceGroup 控制器 | `kuscia/pkg/controllers/taskresourcegroup/controller.go` |
| ConfigRender 插件 | `kuscia/pkg/agent/middleware/plugins/hook/configrender/config_render.go` |
| 证书注入插件 | `kuscia/pkg/agent/middleware/plugins/hook/certissuance/cert_issuance.go` |
| 公共常量 | `kuscia/pkg/common/constants.go` |
| SecretFlow AppImage 模板 | `kuscia/scripts/templates/app_image.secretflow.yaml` |
| Job Proto 定义 | `kuscia/proto/api/v1alpha1/kusciaapi/job.proto` |
| SecretFlow 入口 | `secretflow/secretflow/kuscia/entry.py` |
| SecretFlow 任务配置 | `secretflow/secretflow/kuscia/task_config.py` |
| SecretFlow 集群配置 | `secretflow/secretflow/kuscia/sf_config.py` |
| SecretFlow DataMesh 客户端 | `secretflow/secretflow/kuscia/datamesh.py` |
| SecretFlow 组件执行入口 | `secretflow/secretflow/component/core/entry.py` |

---

## 16. 总结

Kuscia 把上层任务转化为 SecretFlow 调用的核心机制可以概括为：

1. **接收**：KusciaAPI 通过 HTTP/gRPC `CreateJob` 接收上层请求。
2. **持久化**：把请求转换为 `KusciaJob` CRD，任务配置原样保存在 `TaskInputConfig` 中。
3. **调度**：KusciaJob Controller 解析任务依赖、控制并发，把就绪任务创建为 `KusciaTask` CRD。
4. **资源创建**：KusciaTask Controller 为每个参与方创建 Pod、Service、两个 ConfigMap 和 TaskResourceGroup。
5. **网络注入**：为每个 Pod 分配端口、生成 `TASK_CLUSTER_DEFINE`（参与方网络拓扑）。
6. **配置渲染**：config-render 插件把 `TASK_INPUT_CONFIG` 等运行时变量解压并渲染到 AppImage 的 `task-config.conf` 模板中。
7. **容器启动**：Pod 内执行 `python -m secretflow.kuscia.entry ./kuscia/task-config.conf`。
8. **执行**：SecretFlow 读取配置，连接 `datamesh:8071`，下载输入、执行组件、上传输出。
9. **状态回传**：KusciaTask Controller 监听 Pod 状态，汇总到 KusciaJob，通过 `WatchJob` 流回传给上层。

Kuscia 本身不解析也不修改 `TaskInputConfig` 中的算法语义，只负责把“算法配置 + AppImage 模板 + 运行时网络信息”组合成可运行的容器环境。SecretFlow 才是真正的算法执行者。
