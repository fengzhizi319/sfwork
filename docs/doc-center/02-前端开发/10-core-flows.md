# 10 核心流程

> 本节用 Mermaid 时序图描述 SecretPad 前端最核心的跨页面业务流程。

## 10.1 登录与首页分流

```mermaid
sequenceDiagram
    actor U as 用户
    participant FE as 登录页
    participant BE as 后端

    U ->> FE: 输入账号密码
    FE ->> FE: 前端 SHA256 哈希密码
    FE ->> BE: POST /api/login
    BE -->> FE: Token + userInfo
    FE ->> FE: 缓存 Token，写入全局状态

    alt platformType === AUTONOMY
        FE ->> U: 跳转 /edge?ownerId=...
    else platformType === EDGE
        FE ->> U: 跳转 /node?ownerId=...
    else platformType === CENTER 且首次登录
        FE ->> U: 跳转 /guide
    else platformType === CENTER 非首次
        FE ->> U: 跳转 /home
    else CENTER 下的 EDGE 子账号
        FE ->> U: 跳转 /home（跳过引导）
    end
```

## 10.2 创建项目（CENTER 模式）

```mermaid
sequenceDiagram
    actor U as 项目发起方
    participant Home as 项目列表页
    participant Drawer as 创建项目抽屉
    participant BE as 后端

    U ->> Home: 点击“创建项目”
    Home ->> Drawer: 打开抽屉
    U ->> Drawer: 填写：名称、描述、计算模式、参与节点
    Drawer ->> BE: POST /project/create
    BE -->> Drawer: 创建成功
    Drawer ->> Home: 关闭抽屉，刷新列表
    Home ->> U: 显示新项目卡片
```

## 10.3 P2P 项目创建与审批

```mermaid
sequenceDiagram
    actor A as 发起方 Alice
    actor B as 参与方 Bob
    participant FE_A as Alice 前端
    participant FE_B as Bob 前端
    participant BE as 后端/P2P 同步

    A ->> FE_A: 创建项目，选择 Bob
    FE_A ->> BE: POST /p2p/project/create
    BE ->> BE: 生成 VoteRequest + VoteInvite
    BE -->> FE_A: 项目状态：审核中
    BE ->> FE_B: 推送消息（通过同步机制）

    B ->> FE_B: 进入消息中心
    FE_B ->> BE: GET /message/list
    BE -->> FE_B: 待处理项目邀约
    B ->> FE_B: 点击“同意”
    FE_B ->> BE: POST /message/reply（签名）
    BE ->> BE: 校验签名，达到阈值
    BE ->> BE: 项目状态变为 APPROVED
    BE -->> FE_A: 同步状态更新
    BE -->> FE_B: 同步状态更新
```

## 10.4 数据授权到项目

```mermaid
sequenceDiagram
    actor U as 数据提供方
    participant DM as 数据管理页
    participant Drawer as 授权管理抽屉
    participant BE as 后端
    participant K as Kuscia

    U ->> DM: 选择数据表，点击“授权管理”
    DM ->> BE: GET /project/datatable/get（查询已授权项目）
    BE -->> DM: 返回授权列表
    DM ->> Drawer: 打开授权抽屉
    U ->> Drawer: 勾选要授权的项目
    Drawer ->> BE: POST /project/datatable/add
    BE ->> K: 创建/更新 DomainDataGrant
    K -->> BE: 授权成功
    BE -->> Drawer: 返回结果
    Drawer ->> DM: 关闭抽屉，刷新列表
```

## 10.5 DAG 编排与运行

```mermaid
sequenceDiagram
    actor U as 建模工程师
    participant Dag as DAG 画布
    participant Drawer as 组件配置抽屉
    participant BE as 后端
    participant K as Kuscia

    U ->> Dag: 从组件库/数据集拖拽节点到画布
    Dag ->> Dag: 生成节点，自动分配 ID
    U ->> Dag: 连接节点端口
    Dag ->> Dag: 校验输入输出类型
    U ->> Dag: 选中节点，打开配置抽屉
    U ->> Drawer: 填写组件参数
    Drawer ->> Dag: 保存节点配置
    U ->> Dag: 点击“运行”
    Dag ->> BE: POST /graph/start
    BE ->> BE: 拓扑排序生成 Job
    BE ->> K: 创建 Job
    K -->> BE: JobId
    BE -->> Dag: 返回提交成功
    K ->> BE: watchJob 事件流
    BE ->> BE: 更新 ProjectTask 状态
    BE -->> Dag: 轮询/SSE 状态更新
    Dag ->> U: 节点颜色随状态变化
```

## 10.6 模型提交与发布

```mermaid
sequenceDiagram
    actor U as 建模工程师
    participant Dag as DAG 画布
    participant Sub as 模型提交抽屉
    participant Model as 模型管理页
    participant BE as 后端
    participant K as Kuscia Serving

    U ->> Dag: 训练完成，点击“模型提交”
    Dag ->> Sub: 打开提交抽屉
    U ->> Sub: 选择模型组件
    Sub ->> BE: POST /model/pack
    BE -->> Sub: 提交成功
    Sub ->> Model: 跳转或刷新模型列表
    U ->> Model: 点击“发布”
    Model ->> BE: POST /model/serving/create
    BE ->> K: 创建 Serving 服务
    K -->> BE: 服务创建成功
    BE -->> Model: 状态：已发布
```

## 10.7 TEE 结果下载审批

```mermaid
sequenceDiagram
    actor U as 下载请求方
    actor O as 数据/节点 owner
    participant Result as 结果管理页
    participant Msg as 消息中心
    participant BE as 后端

    U ->> Result: 点击 TEE 结果“下载”
    Result ->> BE: POST /approval/create（TEE_DOWNLOAD）
    BE ->> BE: 生成 VoteRequest
    BE -->> Result: 已进入审批
    BE ->> Msg: 推送给 owner

    O ->> Msg: 查看待处理消息
    O ->> Msg: 同意下载
    Msg ->> BE: POST /message/reply
    BE ->> BE: 达到阈值，允许下载
    BE -->> Result: 状态更新为可下载
    U ->> Result: 重新点击下载
```
