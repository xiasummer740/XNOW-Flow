import { useState } from 'react'

const menuData = [
  {
    group: '概览',
    items: [
      { icon: '📊', label: '数据概览', active: true },
    ],
  },
  {
    group: '任务',
    items: [
      { icon: '📋', label: '批量任务' },
      { icon: '⏰', label: '定时任务' },
      { icon: '📈', label: '执行统计' },
      { icon: '📝', label: '任务日志' },
    ],
  },
  {
    group: '设备账号',
    items: [
      { icon: '💻', label: '设备管理' },
      { icon: '👤', label: '账号管理' },
    ],
  },
  {
    group: '内容',
    items: [
      { icon: '📦', label: '素材管理' },
      { icon: '📡', label: '采集数据' },
      { icon: '📢', label: '公告中心' },
      { icon: '💬', label: '反馈中心' },
    ],
  },
  {
    group: '系统',
    items: [
      { icon: '⚙️', label: '回复配置' },
      { icon: '🔧', label: '设置中心' },
    ],
  },
  {
    group: '帮助',
    items: [
      { icon: '📖', label: '使用教程' },
    ],
  },
]

const statsCards = [
  {
    title: '设备总数',
    value: '1',
    details: [
      { label: '在线', value: '0', color: 'text-green-500' },
      { label: '空闲', value: '0', color: 'text-gray-500' },
      { label: '执行', value: '0', color: 'text-blue-500' },
      { label: '锁定', value: '0', color: 'text-yellow-500' },
    ],
  },
  {
    title: '任务执行',
    value: '0',
    details: [
      { label: '今日', value: '0', color: 'text-blue-500' },
      { label: '成功', value: '0', color: 'text-green-500' },
      { label: '失败', value: '0', color: 'text-red-500' },
    ],
  },
  {
    title: '账号总数',
    value: '2',
    details: [
      { label: '仓库', value: '2' },
      { label: '列表', value: '2' },
      { label: '活跃', value: '0', color: 'text-green-500' },
      { label: '执行', value: '0', color: 'text-blue-500' },
      { label: '风控', value: '1', color: 'text-red-500' },
      { label: '封禁', value: '0', color: 'text-gray-400' },
      { label: '涨粉', value: '+0', color: 'text-green-500' },
    ],
  },
  {
    title: '采集数据',
    value: '0',
    details: [
      { label: '用户', value: '0' },
      { label: '视频', value: '0' },
      { label: '评论', value: '0' },
    ],
  },
]

const devices = [
  { id: 1, name: '1', status: '离线', accounts: 0 },
]

const menuIcons: Record<string, JSX.Element> = {}

export default function Dashboard({ user, onLogout }: { user: any; onLogout: () => void }) {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [activeMenu, setActiveMenu] = useState('数据概览')

  return (
    <div className="min-h-screen flex bg-gray-50">
      {/* 侧栏 */}
      <aside className={`${sidebarCollapsed ? 'w-16' : 'w-56'} bg-[#0F1923] text-white flex flex-col transition-all duration-200 shrink-0`}>
        {/* Logo */}
        <div className="h-14 flex items-center gap-2 px-4 border-b border-white/10">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-blue-500 to-cyan-400 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 48 48" fill="none" className="w-4 h-4">
              <path d="M34 6H28.5C25.18 6 22 8.46 22 12.5V22H16v6h6v14h6V28h5l1-6h-6v-8.5c0-1.38 0.88-2.5 2.5-2.5H34V6z" fill="white" />
            </svg>
          </div>
          {!sidebarCollapsed && <span className="font-bold text-sm">XNOW 云控</span>}
        </div>

        {/* 菜单 */}
        <nav className="flex-1 overflow-y-auto py-2 scrollbar-thin">
          {menuData.map((group) => (
            <div key={group.group}>
              {!sidebarCollapsed && (
                <div className="px-4 py-2 text-[10px] text-gray-500 uppercase tracking-wider">{group.group}</div>
              )}
              {group.items.map((item) => (
                <button
                  key={item.label}
                  onClick={() => setActiveMenu(item.label)}
                  className={`w-full flex items-center gap-3 px-4 py-2 text-sm transition-colors cursor-pointer ${
                    activeMenu === item.label
                      ? 'bg-blue-500/10 text-blue-400 border-r-2 border-blue-500'
                      : 'text-gray-400 hover:text-white hover:bg-white/5'
                  } ${sidebarCollapsed ? 'justify-center px-2' : ''}`}
                >
                  <span className="text-base shrink-0">{item.icon}</span>
                  {!sidebarCollapsed && <span className="truncate">{item.label}</span>}
                </button>
              ))}
            </div>
          ))}
        </nav>

        {/* 折叠按钮 */}
        <button
          onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
          className="border-t border-white/10 p-3 text-gray-500 hover:text-white transition-colors cursor-pointer text-sm"
        >
          {sidebarCollapsed ? '→' : '← 收起'}
        </button>
      </aside>

      {/* 主区域 */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* 顶部栏 */}
        <header className="h-14 bg-white border-b flex items-center justify-between px-6 shrink-0">
          <div className="flex items-center gap-4">
            <span className="text-sm font-medium text-gray-700">首页 / 数据看板</span>
          </div>
          <div className="flex items-center gap-4 text-sm text-gray-500">
            <span className="flex items-center gap-1">
              <span className="w-2 h-2 rounded-full bg-green-400" />
              在线 0 台
            </span>
            <span className="text-gray-300">|</span>
            <span>API ID: {user?.id || '468043'}</span>
            <span className="text-gray-300">|</span>
            <span className="text-xs text-gray-400">设备: 0 / 1</span>
            <div className="flex items-center gap-2 ml-2 pl-4 border-l">
              <div className="w-7 h-7 rounded-full bg-blue-500 text-white text-xs flex items-center justify-center font-medium">
                {user?.username?.[0]?.toUpperCase() || 'Y'}
              </div>
              <span className="text-gray-700">{user?.username || 'yk0417'}</span>
              <button onClick={onLogout} className="text-gray-400 hover:text-red-500 ml-2 text-xs cursor-pointer">退出</button>
            </div>
          </div>
        </header>

        {/* 内容区 */}
        <main className="flex-1 overflow-y-auto p-6">
          {/* 欢迎 */}
          <div className="mb-6">
            <h2 className="text-lg font-semibold text-gray-900">
              欢迎回来，{user?.username || 'yk0417'}
            </h2>
          </div>

          {/* 统计卡片 */}
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4 mb-6">
            {statsCards.map((card) => (
              <div key={card.title} className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
                <div className="text-xs text-gray-400 mb-1">{card.title}</div>
                <div className="text-3xl font-bold text-gray-900 mb-3">{card.value}</div>
                <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs">
                  {card.details.map((d) => (
                    <span key={d.label}>
                      {d.label}{' '}
                      <span className={`font-medium ${d.color || 'text-gray-700'}`}>{d.value}</span>
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>

          {/* 图表和表格区域 */}
          <div className="grid grid-cols-1 xl:grid-cols-2 gap-4 mb-6">
            {/* 执行趋势 */}
            <div className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
              <h3 className="text-sm font-medium text-gray-700 mb-4">执行趋势</h3>
              <div className="h-48 flex items-center justify-center text-gray-300 text-sm">
                <div className="text-center">
                  <div className="text-4xl mb-2">📈</div>
                  <div>暂无数据</div>
                </div>
              </div>
            </div>

            {/* 任务类型分布 */}
            <div className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
              <h3 className="text-sm font-medium text-gray-700 mb-4">任务类型分布</h3>
              <div className="h-48 flex items-center justify-center text-gray-300 text-sm">
                <div className="text-center">
                  <div className="text-4xl mb-2">📊</div>
                  <div>暂无任务</div>
                </div>
              </div>
            </div>

            {/* 今日成功率 */}
            <div className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
              <h3 className="text-sm font-medium text-gray-700 mb-4">今日成功率</h3>
              <div className="h-40 flex items-center justify-center text-gray-300 text-sm">
                <div className="text-center">
                  <div className="text-4xl mb-2">🎯</div>
                  <div>暂无数据</div>
                </div>
              </div>
            </div>

            {/* 近7日设备在线率 */}
            <div className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
              <h3 className="text-sm font-medium text-gray-700 mb-4">近7日设备在线率</h3>
              <div className="h-40 flex items-center justify-center text-gray-300 text-sm">
                <div className="text-center">
                  <div className="text-4xl mb-2">📅</div>
                  <div>暂无数据</div>
                </div>
              </div>
            </div>
          </div>

          {/* 设备表格 */}
          <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
            {/* 设备任务量 Top10 */}
            <div className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
              <h3 className="text-sm font-medium text-gray-700 mb-4">设备任务量 Top10</h3>
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-gray-400 text-xs border-b">
                    <th className="pb-2 font-medium">#</th>
                    <th className="pb-2 font-medium">设备</th>
                    <th className="pb-2 font-medium text-right">执行次数</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td colSpan={3} className="text-center text-gray-300 py-8">暂无数据</td>
                  </tr>
                </tbody>
              </table>
            </div>

            {/* 设备在线状态 */}
            <div className="bg-white rounded-xl p-5 border border-gray-100 shadow-sm">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-medium text-gray-700">设备在线状态</h3>
                <button className="text-xs text-blue-500 hover:text-blue-600 cursor-pointer">刷新</button>
              </div>
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-gray-400 text-xs border-b">
                    <th className="pb-2 font-medium">#</th>
                    <th className="pb-2 font-medium">设备</th>
                    <th className="pb-2 font-medium">状态</th>
                    <th className="pb-2 font-medium text-right">账号数</th>
                  </tr>
                </thead>
                <tbody>
                  {devices.map((d) => (
                    <tr key={d.id} className="border-b border-gray-50 text-gray-700">
                      <td className="py-3">{d.id}</td>
                      <td className="py-3">{d.name}</td>
                      <td className="py-3">
                        <span className="inline-flex items-center gap-1 text-gray-400">
                          <span className="w-2 h-2 rounded-full bg-gray-300" />
                          离线
                        </span>
                      </td>
                      <td className="py-3 text-right">{d.accounts}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
