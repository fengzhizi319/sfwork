``` mermaid
flowchart LR
    %% 阶段1
    subgraph S1 ["阶段1: 任务创建 Task Creation"]
        direction TB
        A[前端: 创建任务] -->|选择算法| B[配置参与方<br/>Alice + Bob]
        B -->|上传配置| C[设置超参数<br/>lr, epochs]
        C -->|提交任务| D[secretpad-web<br/>Controller]
        D -->|验证参数| E[secretpad-service<br/>Service]
        E -->|生成TaskID| F[(本地DB<br/>保存任务)]
    end
    
    %% 阶段2
    subgraph S2 ["阶段2: 任务调度 Task Scheduling"]
        direction TB
        G[secretpad-scheduled<br/>Quartz定时器] -->|查询可用节点| H[Kuscia API Client]
        H -->|gRPC调用| I[Kuscia Master<br/>Scheduler]
        I -->|资源分配| J[Alice Node<br/>Initiator]
        I -->|资源分配| K[Bob Node<br/>Participant]
    end
    
    %% 阶段3
    subgraph S3 ["阶段3: 数据准备 Data Preparation"]
        direction TB
        L[Alice DataMesh<br/>获取本地数据] -->|数据预处理| N[特征工程<br/>归一化/缺失值]
        M[Bob DataMesh<br/>获取本地数据] -->|数据预处理| O[特征工程<br/>归一化/缺失值]
    end
    
    %% 阶段4
    subgraph S4 ["阶段4: SecretFlow组件启动"]
        direction TB
        P[SF Runtime<br/>Alice侧Worker] -->|建立安全通道| R[SPU安全计算引擎<br/>基于MPC协议]
        Q[SF Runtime<br/>Bob侧Worker] -->|建立安全通道| R
    end
    
    %% 阶段5
    subgraph S5 ["阶段5: 联邦训练 Federated Training"]
        direction TB
        S[纵向LR模型<br/>initiator端] -->|前向传播| T[加密梯度计算<br/>Paillier同态加密]
        T -->|交换加密梯度| U[跨域梯度聚合<br/>Alice ↔ Bob]
        U -->|反向传播| V[参数更新<br/>SGD优化器]
        V -->|检查收敛| W{达到<br/>epochs?}
        W -->|否| T
        W -->|是| X[训练完成]
    end
    
    %% 阶段6
    subgraph S6 ["阶段6: 模型评估 Model Evaluation"]
        direction TB
        Y[生成预测结果<br/>加密密文] -->|解密评估| Z[计算评估指标<br/>AUC/Acc/F1]
        Z -->|保存模型| AA[模型持久化<br/>OSS/本地存储]
    end
    
    %% 阶段7
    subgraph S7 ["阶段7: 结果返回 Result Delivery"]
        direction TB
        AB[secretpad-service<br/>更新任务状态] -->|写入数据库| AC[(SecretPad DB)]
        AC -->|WebSocket| AD[前端实时通知]
        AD -->|刷新页面| AE[展示训练结果<br/>模型+指标]
    end

    %% 跨阶段的横向连接线
    S1 -->|异步调度| S2
    S2 -->|读取DataRef| S3
    S3-->|读取DataRef| S4
    S4 -->|启动Ray集群| S5
    S5 -->|启动Ray集群| S6
    S6 -->|初始化模型| S7
    S7 -->|预测测试集| S8
    S8 -->|更新任务状态| S9

    %% 节点样式保留
    style A fill:#e3f2fd,stroke:#1976d2,stroke-width:3px
    style D fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style E fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style G fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    style I fill:#e8f5e9,stroke:#388e3c,stroke-width:3px
    style J fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style K fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style L fill:#e0f2f1,stroke:#00796b,stroke-width:2px
    style M fill:#e0f2f1,stroke:#00796b,stroke-width:2px
    style P fill:#f1f8e9,stroke:#689f38,stroke-width:2px
    style Q fill:#f1f8e9,stroke:#689f38,stroke-width:2px
    style R fill:#fff9c4,stroke:#fbc02d,stroke-width:3px
    style T fill:#ffebee,stroke:#c62828,stroke-width:2px
    style U fill:#ffebee,stroke:#c62828,stroke-width:3px
    style W fill:#e1bee7,stroke:#8e24aa,stroke-width:2px
    style AA fill:#e8eaf6,stroke:#3949ab,stroke-width:2px
    style AC fill:#fff9c4,stroke:#fbc02d,stroke-width:2px
    style AE fill:#e3f2fd,stroke:#1976d2,stroke-width:3px
```

