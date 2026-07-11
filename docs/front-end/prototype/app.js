// 主题切换
const themeToggle = document.getElementById('theme-toggle');
if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
    const nextTheme = currentTheme === 'light' ? 'dark' : 'light';
    setTheme(nextTheme);
  });
}

function setTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('theme', theme);
  
  const sunIcon = document.querySelector('.sun-icon');
  const moonIcon = document.querySelector('.moon-icon');
  if (sunIcon && moonIcon) {
    if (theme === 'dark') {
      sunIcon.style.display = 'none';
      moonIcon.style.display = 'block';
    } else {
      sunIcon.style.display = 'block';
      moonIcon.style.display = 'none';
    }
  }
}

// 初始化主题
const initialTheme = localStorage.getItem('theme') || 'light';
setTheme(initialTheme);

// 侧边栏切换
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    item.classList.add('active');
    
    const target = item.getAttribute('data-target');
    const section = document.getElementById(target);
    if (section) section.classList.add('active');
    
    // 切换是否处于登录态背景样式
    if (target === 'login-demo') {
      document.body.classList.add('login-mode');
    } else {
      document.body.classList.remove('login-mode');
    }
  });
});

// 抽屉开关
function openDrawer(id) {
  const overlay = document.getElementById(id);
  if (overlay) {
    overlay.style.display = 'block';
    // 强制重绘以触发 transition 动画
    overlay.offsetHeight;
    overlay.classList.add('active');
  }
  const drawer = document.getElementById(id + '-el');
  if (drawer) {
    drawer.style.transform = 'translateX(0)';
  }
}

function closeDrawer(id) {
  const overlay = document.getElementById(id);
  if (overlay) {
    overlay.classList.remove('active');
    setTimeout(() => {
      if (!overlay.classList.contains('active')) {
        overlay.style.display = 'none';
      }
    }, 300);
  }
  const drawer = document.getElementById(id + '-el');
  if (drawer) {
    drawer.style.transform = 'translateX(calc(100% + 32px))';
  }
}

// Tab 切换（Segmented Control 风格）
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
    alert(`已为您模拟跳转到【${label}】列表界面`);
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

// 登录演示：输入框基本校验与模拟登入
const loginBtn = document.querySelector('.login-btn');
if (loginBtn) {
  loginBtn.addEventListener('click', (e) => {
    e.preventDefault();
    
    const userVal = document.getElementById('login-username').value.trim();
    const passVal = document.getElementById('login-password').value.trim();
    const err = document.getElementById('login-error');
    
    if (!userVal || !passVal) {
      err.style.display = 'block';
      err.innerText = '请输入完整的账号和密码';
      return;
    }
    
    err.style.display = 'none';
    
    // 获取相关节点
    const loginSection = document.getElementById('login-demo');
    const dashboardSection = document.getElementById('dashboard');
    const dashboardNav = document.querySelector('.nav-item[data-target="dashboard"]');
    
    // 触发苹果风格缩放渐隐登入动效
    loginSection.style.transition = 'opacity 0.4s ease, transform 0.4s ease';
    loginSection.style.opacity = '0';
    loginSection.style.transform = 'scale(0.95)';
    
    setTimeout(() => {
      loginSection.classList.remove('active');
      document.body.classList.remove('login-mode');
      
      // 清空所有的 active 状态，将 Dashboard 激活
      document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
      document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
      
      if (dashboardNav) dashboardNav.classList.add('active');
      if (dashboardSection) {
        dashboardSection.classList.add('active');
        dashboardSection.style.opacity = '0';
        dashboardSection.style.transform = 'translateY(10px)';
        
        // 强制回流以启动入场动画
        dashboardSection.offsetHeight;
        
        dashboardSection.style.transition = 'opacity 0.4s ease, transform 0.4s ease';
        dashboardSection.style.opacity = '1';
        dashboardSection.style.transform = 'translateY(0)';
      }
    }, 400);
  });
}
