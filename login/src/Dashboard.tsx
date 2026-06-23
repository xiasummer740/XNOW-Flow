import { useState, useEffect } from 'react'
import ReactEChartsCore from 'echarts-for-react'
import DeviceManagement from './pages/DeviceManagement'
import AccountManagement from './pages/AccountManagement'
import TaskList from './pages/TaskList'
import TaskLog from './pages/TaskLog'
import Settings from './pages/Settings'
import TimedTask from './pages/TimedTask'
import ExecutionStats from './pages/ExecutionStats'
import MediaManagement from './pages/MediaManagement'
import CollectedData from './pages/CollectedData'
import Announcements from './pages/Announcements'
import Feedback from './pages/Feedback'
import ReplyConfig from './pages/ReplyConfig'
import UsageGuide from './pages/UsageGuide'
import Placeholder from './pages/Placeholder'

const menuData = [
  { group: '概览', items: [{ icon: '📊', label: '数据概览', active: true }] },
  { group: '任务', items: [
    { icon: '📋', label: '批量任务' }, { icon: '⏰', label: '定时任务' },
    { icon: '📈', label: '执行统计' }, { icon: '📝', label: '任务日志' },
  ]},
  { group: '设备账号', items: [
    { icon: '💻', label: '设备管理' }, { icon: '👤', label: '账号管理' },
  ]},
  { group: '内容', items: [
    { icon: '📦', label: '素材管理' }, { icon: '📡', label: '采集数据' },
    { icon: '📢', label: '公告中心' }, { icon: '💬', label: '反馈中心' },
  ]},
  { group: '系统', items: [
    { icon: '⚙️', label: '回复配置' }, { icon: '🔧', label: '设置中心' },
  ]},
  { group: '帮助', items: [{ icon: '📖', label: '使用教程' }] },
]

interface DashboardData {
  device_stats: { total: number; online: number; offline: number; idle: number; executing: number; locked: number }
  task_stats: { total: number; active: number; exec_total: number; exec_pending: number; exec_running: number; exec_success: number; exec_failed: number; exec_today: number }
  account_stats: { total: number; active: number; executing: number; risk_control: number; banned: number; offline: number; pending: number; logging_in: number; pool_total: number; pool_in_use: number; pool_idle: number; pool_recycled: number; pool_invalid: number }
  collect_stats: { fans: number; videos: number; comments: number; live_users: number; friends: number }
  device_preview: { name: string; online: boolean; accounts: number; device_state: string }[]
  health_distribution: { excellent: number; good: number; warning: number; risk: number }
  today_success_rate: number
  device_online_rate_7d: { date: string; rate: number }[]
  risk_accounts_7d: { date: string; count: number }[]
  device_task_rank: any[]
  hourly_data: number[]
  today_fans_gain: number
  task_type_dist: { type: string; count: number; percentage: number }[]
  fail_reason_top5: { reason: string; count: number }[]
  recent_activities: { id: number; type: string; message: string; created_at: string }[]
  generated_at: string
}

export default function Dashboard({ user, token, onLogout }: { user: any; token: string; onLogout: () => void }) {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [activeMenu, setActiveMenu] = useState('数据概览')
  const [data, setData] = useState<DashboardData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/biz/v2/dashboard/stats/', {
      headers: { 'Authorization': `Token ${token}` }
    })
      .then(r => r.json())
      .then(d => { setData(d); setLoading(false) })
      .catch(() => setLoading(false))
  }, [token])

  const d = data?.device_stats
  const t = data?.task_stats
  const a = data?.account_stats
  const c = data?.collect_stats
  const devices = data?.device_preview || []

  return (
    <div className="min-h-screen flex dashboard-layout">
      <div className="xx-glow-overlay" />

      {/* 移动端遮罩 */}
      {mobileMenuOpen && (
        <div className="fixed inset-0 z-40 md:hidden" onClick={() => setMobileMenuOpen(false)}
          style={{ background: 'rgba(0,0,0,0.30)' }} />
      )}

      {/* 侧栏 — 磨砂玻璃 ｜ 移动端：抽屉覆盖 */}
      <aside className={`dashboard-sidebar flex flex-col shrink-0 transition-all duration-200 ${
        sidebarCollapsed ? 'w-16' : 'w-56'
      } ${
        /* 移动端：absolutely positioned overlay */
        'fixed md:relative z-50 h-full ' +
        (mobileMenuOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0')
      }`}>
        <div className="h-14 flex items-center gap-2 px-4 border-b shrink-0" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
          <svg viewBox="0 0 48 48" fill="none" className="w-7 h-7 shrink-0"
            style={{ filter: 'drop-shadow(0 0 6px rgba(168,85,247,0.4))' }}>
            <defs>
              <linearGradient id="sidebarLogo" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#a855f7" />
                <stop offset="50%" stop-color="#3b82f6" />
                <stop offset="100%" stop-color="#14b8a6" />
              </linearGradient>
            </defs>
            <path d="M34 6H28.5C25.18 6 22 8.46 22 12.5V22H16v6h6v14h6V28h5l1-6h-6v-8.5c0-1.38 0.88-2.5 2.5-2.5H34V6z" fill="url(#sidebarLogo)" />
          </svg>
          {!sidebarCollapsed && <span className="sidebar-brand-text">XNOW</span>}
          {/* 移动端关闭按钮 */}
          <button onClick={() => setMobileMenuOpen(false)} className="ml-auto md:hidden cursor-pointer text-sm" style={{color:'rgba(0,0,0,0.35)'}}>✕</button>
        </div>
        <nav className="flex-1 overflow-y-auto py-2">
          {menuData.map((group) => (
            <div key={group.group}>
              {!sidebarCollapsed && (
                <div className="px-4 py-1.5 text-[10px] uppercase tracking-wider" style={{ color: 'rgba(0,0,0,0.30)' }}>{group.group}</div>
              )}
              {group.items.map((item) => (
                <button
                  key={item.label}
                  onClick={() => { setActiveMenu(item.label); setMobileMenuOpen(false) }}
                  className={`w-full flex items-center gap-3 px-4 py-2 text-sm transition-all cursor-pointer ${
                    activeMenu === item.label
                      ? 'nav-item active'
                      : 'nav-item'
                  } ${sidebarCollapsed ? 'justify-center px-2' : ''}`}
                >
                  <span className="text-base shrink-0">{item.icon}</span>
                  {!sidebarCollapsed && <span className="truncate">{item.label}</span>}
                </button>
              ))}
            </div>
          ))}
        </nav>
        <button onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
          className="hidden md:flex border-t p-3 transition-colors cursor-pointer text-sm nav-item"
          style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
          {sidebarCollapsed ? '→' : '← 收起'}
        </button>
      </aside>

      {/* 主区域 */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Header — 磨砂玻璃 */}
        <header className="dashboard-header h-14 flex items-center justify-between px-3 md:px-6 shrink-0">
          <div className="flex items-center gap-2">
            {/* 移动端汉堡菜单 */}
            <button onClick={() => setMobileMenuOpen(true)} className="md:hidden cursor-pointer text-lg" style={{color:'rgba(0,0,0,0.40)'}}>
              ☰
            </button>
            <span className="text-xs md:text-sm font-medium truncate" style={{ color: 'rgba(0,0,0,0.55)' }}>
              {activeMenu === '数据概览' ? '数据看板' : activeMenu}
            </span>
          </div>
          <div className="flex items-center gap-2 md:gap-4 text-xs md:text-sm" style={{ color: 'rgba(0,0,0,0.45)' }}>
            <span className="flex items-center gap-1">
              <span className={`w-2 h-2 rounded-full ${d && d.online > 0 ? 'bg-green-400' : 'bg-gray-300'}`} />
              <span className="hidden md:inline">在线</span> {d?.online || 0}
            </span>
            <span className="hidden md:inline" style={{ color: 'rgba(0,0,0,0.15)' }}>|</span>
            <span className="hidden md:inline">API ID: {user?.id || '—'}</span>
            <span className="hidden md:inline" style={{ color: 'rgba(0,0,0,0.15)' }}>|</span>
            <span className="hidden md:inline text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>设备: {d?.online || 0} / {d?.total || 0}</span>
            <div className="flex items-center gap-1 md:gap-2 ml-1 md:ml-2 pl-2 md:pl-4 border-l" style={{ borderColor: 'rgba(0,0,0,0.10)' }}>
              <div className="w-6 h-6 md:w-7 md:h-7 rounded-full text-white text-[10px] md:text-xs flex items-center justify-center font-medium"
                style={{ background: 'linear-gradient(135deg, #a855f7, #3b82f6)' }}>
                {(user?.username || 'U')[0].toUpperCase()}
              </div>
              <span className="hidden md:inline" style={{ color: 'rgba(0,0,0,0.65)' }}>{user?.username || '用户'}</span>
              <button onClick={onLogout} className="text-[10px] md:text-xs cursor-pointer" style={{ color: 'rgba(0,0,0,0.35)' }}
                onMouseOver={e => (e.currentTarget.style.color = '#ef4444')}
                onMouseOut={e => (e.currentTarget.style.color = 'rgba(0,0,0,0.35)')}>
                退出
              </button>
            </div>
          </div>
        </header>

        {/* 内容区 */}
        <main className="flex-1 overflow-y-auto p-3 md:p-6" style={{ background: 'transparent' }}>
          {activeMenu !== '数据概览' ? (
            (() => {
              switch (activeMenu) {
                case '设备管理': return <DeviceManagement token={token} />
                case '账号管理': return <AccountManagement token={token} />
                case '批量任务': return <TaskList token={token} />
                case '任务日志': return <TaskLog token={token} />
                case '设置中心': return <Settings token={token} user={user} />
                case '定时任务': return <TimedTask token={token} />
                case '执行统计': return <ExecutionStats token={token} />
                case '素材管理': return <MediaManagement token={token} />
                case '采集数据': return <CollectedData token={token} />
                case '公告中心': return <Announcements token={token} />
                case '反馈中心': return <Feedback token={token} />
                case '回复配置': return <ReplyConfig token={token} />
                case '使用教程': return <UsageGuide token={token} />
                default: return <Placeholder title={activeMenu} />
              }
            })()
          ) : loading ? (
            <div className="flex items-center justify-center h-64" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
          ) : (
            <>
              <div className="mb-6">
                <h2 className="text-lg font-semibold" style={{ color: 'rgba(0,0,0,0.70)' }}>欢迎回来，{user?.username || '用户'}</h2>
              </div>

              {/* 统计卡片 */}
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4 mb-6">
                {[
                  { title: '设备总数', val: d?.total ?? 0, details: [
                    ['在线', d?.online ?? 0, 'text-green-500'],
                    ['空闲', d?.idle ?? 0, 'text-gray-500'],
                    ['执行', d?.executing ?? 0, 'text-blue-500'],
                    ['锁定', d?.locked ?? 0, 'text-yellow-500'],
                  ]},
                  { title: '任务执行', val: t?.exec_today ?? 0, details: [
                    ['今日', t?.exec_today ?? 0, 'text-blue-500'],
                    ['成功', t?.exec_success ?? 0, 'text-green-500'],
                    ['失败', t?.exec_failed ?? 0, 'text-red-500'],
                  ]},
                  { title: '账号总数', val: a?.total ?? 0, details: [
                    ['仓库', a?.pool_total ?? 0, ''],
                    ['列表', a?.pool_in_use ?? 0, ''],
                    ['活跃', a?.active ?? 0, 'text-green-500'],
                    ['风控', a?.risk_control ?? 0, 'text-red-500'],
                    ['封禁', a?.banned ?? 0, 'text-gray-400'],
                    ['涨粉', `+${data?.today_fans_gain || 0}`, 'text-green-500'],
                  ]},
                  { title: '采集数据', val: c ? c.fans + c.videos + c.comments : 0, details: [
                    ['用户', c?.fans ?? 0, ''],
                    ['视频', c?.videos ?? 0, ''],
                    ['评论', c?.comments ?? 0, ''],
                  ]},
                ].map((card) => (
                  <div key={card.title} className="xx-card rounded-xl p-5">
                    <div className="text-xs mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>{card.title}</div>
                    <div className="text-3xl font-bold mb-3" style={{ color: 'rgba(0,0,0,0.80)' }}>{card.val}</div>
                    <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs" style={{ color: 'rgba(0,0,0,0.45)' }}>
                      {card.details.map(([label, value, color]: any) => (
                        <span key={label}>{label} <span className={`font-medium ${color || ''}`}>{value}</span></span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>

              {/* ECharts 图表区域 */}
              <div className="grid grid-cols-1 xl:grid-cols-2 gap-4 mb-6">
                {/* 执行趋势 */}
                <div className="xx-card rounded-xl p-5">
                  <h3 className="text-sm font-medium mb-4" style={{ color: 'rgba(0,0,0,0.65)' }}>执行趋势</h3>
                  <ReactEChartsCore
                    option={{
                      grid: { left: 40, right: 10, top: 10, bottom: 25 },
                      xAxis: { type: 'category', data: Array.from({ length: 24 }, (_, i) => `${i}:00`), axisLabel: { fontSize: 10, color: '#9ca3af' }, axisLine: { show: false }, axisTick: { show: false } },
                      yAxis: { type: 'value', splitLine: { lineStyle: { color: 'rgba(0,0,0,0.06)' } }, axisLabel: { fontSize: 10, color: '#9ca3af' } },
                      series: [{
                        data: data?.hourly_data || Array(24).fill(0),
                        type: 'bar',
                        barWidth: '60%',
                        itemStyle: { color: '#a855f7', borderRadius: [2, 2, 0, 0], opacity: 0.20 },
                        emphasis: { itemStyle: { opacity: 0.4 } },
                      }, {
                        data: data?.hourly_data || Array(24).fill(0),
                        type: 'line',
                        smooth: true,
                        showSymbol: false,
                        lineStyle: { color: '#a855f7', width: 2 },
                        areaStyle: { color: 'rgba(168,85,247,0.05)' },
                      }],
                      tooltip: { trigger: 'axis' },
                    }}
                    style={{ height: 180 }}
                    notMerge
                  />
                </div>

                {/* 健康分分布 */}
                <div className="xx-card rounded-xl p-5">
                  <h3 className="text-sm font-medium mb-4" style={{ color: 'rgba(0,0,0,0.65)' }}>健康分分布</h3>
                  {data?.health_distribution ? (
                    <ReactEChartsCore
                      option={{
                        grid: { left: 10, right: 10, top: 10, bottom: 10 },
                        series: [{
                          type: 'pie',
                          radius: ['50%', '75%'],
                          center: ['50%', '50%'],
                          avoidLabelOverlap: false,
                          label: { show: true, position: 'outside', formatter: '{b}: {c}', fontSize: 11, color: 'rgba(0,0,0,0.45)' },
                          data: [
                            { value: data.health_distribution.excellent, name: '优秀', itemStyle: { color: '#22c55e' } },
                            { value: data.health_distribution.good, name: '良好', itemStyle: { color: '#3b82f6' } },
                            { value: data.health_distribution.warning, name: '警告', itemStyle: { color: '#eab308' } },
                            { value: data.health_distribution.risk, name: '危险', itemStyle: { color: '#ef4444' } },
                          ].filter(d => d.value > 0),
                        }],
                        tooltip: { trigger: 'item', formatter: '{b}: {c}' },
                      }}
                      style={{ height: 180 }}
                      notMerge
                    />
                  ) : <div className="h-[180px] flex items-center justify-center text-sm" style={{ color: 'rgba(0,0,0,0.20)' }}>暂无数据</div>}
                </div>

                {/* 今日成功率 */}
                <div className="xx-card rounded-xl p-5">
                  <h3 className="text-sm font-medium mb-4" style={{ color: 'rgba(0,0,0,0.65)' }}>今日成功率</h3>
                  <ReactEChartsCore
                    option={{
                      series: [{
                        type: 'gauge',
                        center: ['50%', '55%'],
                        radius: '80%',
                        startAngle: 220,
                        endAngle: -40,
                        min: 0,
                        max: 100,
                        splitNumber: 5,
                        progress: { show: true, width: 12, itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#ef4444' }, { offset: 0.5, color: '#eab308' }, { offset: 1, color: '#22c55e' }] } } },
                        axisLine: { lineStyle: { width: 12, color: [[1, 'rgba(0,0,0,0.06)']] } },
                        axisTick: { show: false },
                        splitLine: { show: false },
                        axisLabel: { show: false },
                        detail: { formatter: '{value}%', fontSize: 20, fontWeight: 'bold', color: 'rgba(0,0,0,0.70)', offsetCenter: [0, '40%'] },
                        data: [{ value: data?.today_success_rate ?? 0 }],
                      }],
                    }}
                    style={{ height: 180 }}
                    notMerge
                  />
                </div>

                {/* 近7日设备在线率 */}
                <div className="xx-card rounded-xl p-5">
                  <h3 className="text-sm font-medium mb-4" style={{ color: 'rgba(0,0,0,0.65)' }}>近7日设备在线率</h3>
                  {(data?.device_online_rate_7d || []).length > 0 ? (
                    <ReactEChartsCore
                      option={{
                        grid: { left: 40, right: 10, top: 10, bottom: 25 },
                        xAxis: { type: 'category', data: data!.device_online_rate_7d.map((d: any) => d.date.slice(5)), axisLabel: { fontSize: 10, color: '#9ca3af' }, axisLine: { show: false }, axisTick: { show: false } },
                        yAxis: { type: 'value', max: 1, splitLine: { lineStyle: { color: 'rgba(0,0,0,0.06)' } }, axisLabel: { fontSize: 10, color: '#9ca3af', formatter: '{value * 100}%' } },
                        series: [{
                          data: data!.device_online_rate_7d.map((d: any) => d.rate),
                          type: 'line',
                          smooth: true,
                          symbol: 'circle',
                          symbolSize: 8,
                          lineStyle: { color: '#3b82f6', width: 2 },
                          areaStyle: { color: 'rgba(59,130,246,0.06)' },
                          itemStyle: { color: '#3b82f6' },
                        }],
                        tooltip: { trigger: 'axis', valueFormatter: (v: number) => `${(v * 100).toFixed(0)}%` },
                      }}
                      style={{ height: 180 }}
                      notMerge
                    />
                  ) : <div className="h-[180px] flex items-center justify-center text-sm" style={{ color: 'rgba(0,0,0,0.20)' }}>暂无数据</div>}
                </div>
              </div>

              {/* 设备表格 */}
              <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
                <div className="xx-card rounded-xl p-5">
                  <h3 className="text-sm font-medium mb-4" style={{ color: 'rgba(0,0,0,0.65)' }}>设备任务量 Top10</h3>
                  <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                        <th className="pb-2 font-medium">#</th>
                        <th className="pb-2 font-medium">设备</th>
                        <th className="pb-2 font-medium text-right">执行次数</th>
                      </tr>
                    </thead>
                    <tbody>
                      {(data?.device_task_rank || []).length === 0 ? (
                        <tr><td colSpan={3} className="text-center py-8" style={{ color: 'rgba(0,0,0,0.20)' }}>暂无数据</td></tr>
                      ) : (
                        data?.device_task_rank.map((d: any, i: number) => (
                          <tr key={i} className="border-b" style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                            <td className="py-3">{i + 1}</td>
                            <td className="py-3">{d.name}</td>
                            <td className="py-3 text-right">{d.count}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                  </div>
                </div>

                <div className="xx-card rounded-xl p-5">
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>设备在线状态</h3>
                  </div>
                  <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                        <th className="pb-2 font-medium">#</th>
                        <th className="pb-2 font-medium">设备</th>
                        <th className="pb-2 font-medium">状态</th>
                        <th className="pb-2 font-medium text-right">账号数</th>
                      </tr>
                    </thead>
                    <tbody>
                      {devices.length === 0 ? (
                        <tr><td colSpan={4} className="text-center py-8" style={{ color: 'rgba(0,0,0,0.20)' }}>暂无设备</td></tr>
                      ) : (
                        devices.map((dev: any, i: number) => (
                          <tr key={i} className="border-b" style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                            <td className="py-3">{i + 1}</td>
                            <td className="py-3">{dev.name || '—'}</td>
                            <td className="py-3">
                              <span className={`inline-flex items-center gap-1 ${dev.online ? 'text-green-500' : ''}`} style={{ color: dev.online ? undefined : 'rgba(0,0,0,0.35)' }}>
                                <span className={`w-2 h-2 rounded-full ${dev.online ? 'bg-green-400' : ''}`} style={{ background: dev.online ? undefined : 'rgba(0,0,0,0.15)' }} />
                                {dev.device_state === 'offline' ? '离线' : dev.device_state || '离线'}
                              </span>
                            </td>
                            <td className="py-3 text-right">{dev.accounts || 0}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                  </div>
                </div>
              </div>

              {/* 最近活动 */}
              {data?.recent_activities && data.recent_activities.length > 0 && (
                <div className="xx-card rounded-xl p-5 mt-4">
                  <h3 className="text-sm font-medium mb-3" style={{ color: 'rgba(0,0,0,0.65)' }}>最近活动</h3>
                  <div className="space-y-2">
                    {data.recent_activities.map((act: any) => (
                      <div key={act.id} className="flex items-center gap-3 text-xs py-1.5 border-b last:border-0" style={{ borderColor: 'rgba(0,0,0,0.04)' }}>
                        <span className="w-1.5 h-1.5 rounded-full bg-blue-400 shrink-0" />
                        <span style={{ color: 'rgba(0,0,0,0.55)' }}>{act.message}</span>
                        <span className="ml-auto shrink-0" style={{ color: 'rgba(0,0,0,0.30)' }}>{act.created_at}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </>
          )}
        </main>
      </div>
    </div>
  )
}
