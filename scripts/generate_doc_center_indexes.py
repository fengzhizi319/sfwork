#!/usr/bin/env python3
"""Generate index.md files for docs/doc-center based on copied files."""

from pathlib import Path

ROOT = Path('/home/charles/code/sfwork/docs/doc-center')

# Category metadata: directory name -> (title, description, source descriptions)
CATEGORIES = {
    '00-项目总览': ('00-项目总览', '项目白皮书、汇报 PPT、总体介绍、开发计划', {}),
    '01-架构设计': ('01-架构设计', '系统架构、HLD/LLD、模块设计、数据模型、接口映射', {
        'sfwork-': 'sfwork 项目级',
        'secretpad-': 'SecretPad 后端',
        'kuscia-': 'Kuscia',
        'frontend-': 'SecretPad 前端',
        'privacy-local-agent-': '本地隐私 Agent',
    }),
    '02-前端开发': ('02-前端开发', 'SecretPad 前端开发、页面 PRD、组件、主题、构建', {
        'frontend-': '前端开发文档',
        'secretpad-': 'SecretPad 前端设计',
    }),
    '03-后端开发': ('03-后端开发', 'SecretPad 后端开发、API、存储、集成、本地运行', {
        'secretpad-': 'SecretPad 后端',
    }),
    '04-Kuscia': ('04-Kuscia', 'Kuscia 部署、开发、架构、任务调度、组网、教程', {
        'kuscia-': 'Kuscia',
    }),
    '05-算法与隐私': ('05-算法与隐私', '数据分类分级、差分隐私、本地隐私原语、隐私组件', {}),
    '06-部署运维': ('06-部署运维', '部署指南、运维手册、监控、日志、网络要求', {
        'sfwork-': 'sfwork 级',
        'secretpad-': 'SecretPad',
        'kuscia-': 'Kuscia',
    }),
    '07-开发规范': ('07-开发规范', '贡献指南、代码规范、CI/CD、法律声明', {
        'sfwork-': 'sfwork 级',
        'frontend-': 'SecretPad 前端',
        'secretpad-': 'SecretPad 后端',
        'kuscia-': 'Kuscia',
    }),
    '08-问题排查': ('08-问题排查', 'FAQ、常见问题、Bug 定位、诊断工具、运行说明', {
        'sfwork-': 'sfwork 级',
        'secretpad-': 'SecretPad',
        'kuscia-': 'Kuscia',
    }),
    '99-参考杂项': ('99-参考杂项', '变更日志、未分类参考', {
        'kuscia-': 'Kuscia',
        'secretpad-': 'SecretPad',
    }),
}

SOURCE_ORDER = ['sfwork-', 'frontend-', 'secretpad-', 'kuscia-', 'privacy-local-agent-']


def source_of(filename: str, source_map: dict) -> str:
    for prefix in SOURCE_ORDER:
        if filename.startswith(prefix):
            return prefix
    return ''


def display_name(filename: str) -> str:
    # Remove common prefix and .md
    name = filename
    for prefix in SOURCE_ORDER:
        if name.startswith(prefix):
            name = name[len(prefix):]
            break
    if name.endswith('.md'):
        name = name[:-3]
    return name


def generate_index(dir_name: str, title: str, description: str, source_map: dict) -> str:
    cat_dir = ROOT / dir_name
    files = sorted([f.name for f in cat_dir.iterdir() if f.is_file() and f.suffix in {'.md', '.html'} and f.name not in {'index.md', 'README.md'}])

    lines = [
        f'# {title}',
        '',
        f'> {description}',
        '',
        '## 文档列表',
        '',
    ]

    if not source_map:
        for fn in files:
            if fn.endswith('.html'):
                lines.append(f'- [{fn}](./{fn})')
            else:
                lines.append(f'- [{display_name(fn)}](./{fn})')
        lines.append('')
        return '\n'.join(lines)

    # Group by source prefix
    groups = {prefix: [] for prefix in SOURCE_ORDER if any(f.startswith(prefix) for f in files)}
    ungrouped = []

    for fn in files:
        prefix = source_of(fn, source_map)
        if prefix in groups:
            groups[prefix].append(fn)
        else:
            ungrouped.append(fn)

    for prefix in SOURCE_ORDER:
        if prefix not in groups or not groups[prefix]:
            continue
        label = source_map.get(prefix, prefix.rstrip('-'))
        lines.append(f'### {label}')
        lines.append('')
        for fn in groups[prefix]:
            if fn.endswith('.html'):
                lines.append(f'- [{fn}](./{fn})')
            else:
                lines.append(f'- [{display_name(fn)}](./{fn})')
        lines.append('')

    if ungrouped:
        lines.append('### 其他')
        lines.append('')
        for fn in ungrouped:
            if fn.endswith('.html'):
                lines.append(f'- [{fn}](./{fn})')
            else:
                lines.append(f'- [{display_name(fn)}](./{fn})')
        lines.append('')

    return '\n'.join(lines)


def main():
    for dir_name, (title, description, source_map) in CATEGORIES.items():
        content = generate_index(dir_name, title, description, source_map)
        index_path = ROOT / dir_name / 'index.md'
        index_path.write_text(content, encoding='utf-8')
        print(f'Updated: {index_path}')


if __name__ == '__main__':
    main()
