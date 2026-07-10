// 侧边栏切换
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    item.classList.add('active');
    const target = item.getAttribute('data-target');
    const section = document.getElementById(target);
    if (section) section.classList.add('active');
  });
});

// 抽屉开关
function openDrawer(id) {
  const overlay = document.getElementById(id);
  if (overlay) overlay.classList.add('active');
  const drawer = document.getElementById(id + '-el');
  if (drawer) drawer.style.transform = 'translateX(0)';
}

function closeDrawer(id) {
  const overlay = document.getElementById(id);
  if (overlay) overlay.classList.remove('active');
  const drawer = document.getElementById(id + '-el');
  if (drawer) drawer.style.transform = 'translateX(100%)';
}

// Tab 切换（简单示例）
document.querySelectorAll('.tabs').forEach(tabs => {
  const items = tabs.querySelectorAll('.tab');
  items.forEach(tab => {
    tab.addEventListener('click', () => {
      items.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
    });
  });
});

// 统计卡片点击提示
document.querySelectorAll('.stat-card').forEach(card => {
  card.addEventListener('click', () => {
    const label = card.querySelector('.stat-label').innerText;
    alert(`跳转至 ${label} 列表页`);
  });
});

// DAG 场景切换
const scenarioMap = {
  fraud: {
    title: '反欺诈联邦建模',
    nodes: [
      { title: '读数据', sub: 'user' },
      { title: '特征工程', sub: 'FeatureFilter' },
      { title: '联邦训练', sub: 'SSGLM' },
      { title: '模型评估', sub: 'Evaluation' },
    ],
  },
  dp: {
    title: '差分隐私统计',
    nodes: [
      { title: '读数据', sub: 'user' },
      { title: '差分隐私', sub: 'DPNoise' },
      { title: '安全统计', sub: 'SecureCount' },
      { title: '结果报告', sub: 'Report' },
    ],
  },
  'k anonymity': {
    title: 'K-匿名脱敏',
    nodes: [
      { title: '读数据', sub: 'raw_data' },
      { title: 'K-匿名', sub: 'KAnonymity' },
      { title: 'L-多样性', sub: 'LDiversity' },
      { title: '脱敏输出', sub: 'AnonOutput' },
    ],
  },
  classification: {
    title: '分类分级识别',
    nodes: [
      { title: '读数据', sub: 'table' },
      { title: '字段识别', sub: 'ColumnDetect' },
      { title: '敏感分级', sub: 'Sensitivity' },
      { title: '分级报告', sub: 'ClassReport' },
    ],
  },
  psi: {
    title: '隐私求交（PSI）',
    nodes: [
      { title: '读数据 A', sub: 'alice_data' },
      { title: '读数据 B', sub: 'bob_data' },
      { title: '隐私求交', sub: 'PSI' },
      { title: '交集分析', sub: 'JoinAnalysis' },
    ],
  },
  secureAggregation: {
    title: '安全聚合',
    nodes: [
      { title: '读数据', sub: 'local_grad' },
      { title: '梯度加密', sub: 'EncryptGrad' },
      { title: '安全聚合', sub: 'SecAgg' },
      { title: '全局模型', sub: 'GlobalModel' },
    ],
  },
};

const scenarioSelect = document.getElementById('dag-scenario-select');
const scenarioTitle = document.getElementById('dag-scenario-title');
if (scenarioSelect) {
  scenarioSelect.addEventListener('change', (e) => {
    const key = e.target.value;
    const cfg = scenarioMap[key];
    if (!cfg) return;
    scenarioTitle.innerText = cfg.title;
    const nodes = document.querySelectorAll('#dag-canvas-area .dag-node');
    nodes.forEach((node, idx) => {
      if (cfg.nodes[idx]) {
        node.querySelector('.dag-node-title').innerText = cfg.nodes[idx].title;
        node.querySelector('.dag-node-sub').innerText = cfg.nodes[idx].sub;
      }
    });
  });
}

// 登录演示：简单交互
const loginBtn = document.querySelector('#login-demo .btn-primary');
if (loginBtn) {
  loginBtn.addEventListener('click', () => {
    const err = document.getElementById('login-error');
    err.style.display = 'block';
    err.innerText = '演示环境：任意账号/密码即可进入首页';
  });
}
