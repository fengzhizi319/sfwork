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
