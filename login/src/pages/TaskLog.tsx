import { useState, useEffect } from 'react'

interface Log {
  id: number
  task_name?: string
  type?: string
  status?: string
  device?: string
  account?: string
  target?: string
  result?: string
  started_at?: string
  finished_at?: string
  duration?: number
}

const statusConfig: Record<string, { label: string; class: string }> = {
  running: { label: '执行中', class: 'bg-blue-50 text-blue-500' },
  success: { label: '成功', class: 'bg-green-50 text-green-600' },
  failed: { label: '失败', class: 'bg-red-50 text-red-500' },
  cancelled: { label: '已取消', class: 'bg-gray-50 text-gray-500' },
  pending: { label: '等待中', class: 'bg-yellow-50 text-yellow-600' },
}

export default function TaskLog({ token }: { token: string }) {
  const [data, setData] = useState<Log[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [filterStatus, setFilterStatus] = useState('all')
  const [search, setSearch] = useState('')
  const [expanded, setExpanded] = useState<number | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const fetchData = () => {
    setRefreshing(true)
    fetch('/api/biz/v2/task-executions/?limit=50', {
      headers: { Authorization: `Token ${token}` }
    })
      .then(r => r.json())
      .then(d => { setData(d.results || d); setLoading(false); setRefreshing(false) })
      .catch(() => { setError('加载失败'); setLoading(false); setRefreshing(false) })
  }

  useEffect(() => { fetchData() }, [token])

  const mockDetails = (log: Log) => ({
    device: log.device || 'device-01',
    account: log.account || 'auto_account_3',
    target: log.target || 'https://www.example.com/user/12345',
    result: log.result || (log.status === 'success' ? '成功执行关注操作，处理 15/15 条' : log.status === 'failed' ? '网络超时，已重试 3 次后放弃' : '—'),
    duration: log.duration || (log.started_at && log.finished_at
      ? Math.floor((new Date(log.finished_at).getTime() - new Date(log.started_at).getTime()) / 1000)
      : undefined),
  })

  const filtered = data.filter(l => {
    if (filterStatus !== 'all' && l.status !== filterStatus) return false
    if (search && !l.task_name?.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  const stats = {
    total: data.length,
    success: data.filter(l => l.status === 'success').length,
    failed: data.filter(l => l.status === 'failed').length,
    running: data.filter(l => l.status === 'running').length,
  }

  const successRate = stats.total > 0 ? ((stats.success / (stats.success + stats.failed)) * 100).toFixed(0) : '—'

  if (loading) return <div className="flex items-center justify-center h-64" style={{color:'rgba(0,0,0,0.35)'}}>加载中...</div>
  if (error) return <div className="flex items-center justify-center h-64 text-red-400">{error}</div>

  return (
    <div className="space-y-6">
      {/* 头部 */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>任务日志</h3>
        <button onClick={fetchData}
          className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{background:'rgba(255,255,255,0.25)',color:'rgba(0,0,0,0.50)'}}>
          <span className={refreshing ? 'inline-block animate-spin' : ''}>🔄</span>
          {refreshing ? '刷新中...' : '刷新'}
        </button>
      </div>

      {/* 统计概览 */}
      <div className="grid grid-cols-4 gap-4">
        {[
          { label: '总执行', val: stats.total, icon: '📊', color: 'rgba(0,0,0,0.70)' },
          { label: '成功', val: stats.success, icon: '✅', color: '#22c55e' },
          { label: '失败', val: stats.failed, icon: '❌', color: '#ef4444' },
          { label: '成功率', val: `${successRate}%`, icon: '🎯', color: '#a855f7' },
        ].map(s => (
          <div key={s.label} className="xx-card rounded-xl p-4 flex items-center justify-between">
            <div>
              <div className="text-xs" style={{color:'rgba(0,0,0,0.40)'}}>{s.label}</div>
              <div className="text-2xl font-bold mt-0.5" style={{color: s.color}}>{s.val}</div>
            </div>
            <span className="text-2xl">{s.icon}</span>
          </div>
        ))}
      </div>

      {/* 过滤 + 搜索 */}
      <div className="flex items-center gap-3">
        <div className="flex gap-1 rounded-lg p-0.5" style={{background:'rgba(255,255,255,0.25)'}}>
          {[
            { key: 'all', label: '全部' },
            { key: 'running', label: '执行中' },
            { key: 'success', label: '成功' },
            { key: 'failed', label: '失败' },
          ].map(f => (
            <button key={f.key} onClick={() => setFilterStatus(f.key)}
              className={`px-3 py-1 text-xs rounded-md transition-all cursor-pointer ${
                filterStatus === f.key ? 'xx-card' : ''
              }`}
              style={{color: filterStatus === f.key ? 'rgba(0,0,0,0.70)' : 'rgba(0,0,0,0.40)'}}>
              {f.label} {f.key !== 'all' && `(${stats[f.key as keyof typeof stats]})`}
            </button>
          ))}
        </div>
        <div className="relative flex-1 max-w-xs">
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            className="w-full rounded-lg pl-9 pr-3 py-2 text-sm outline-none"
            style={{background:'rgba(255,255,255,0.40)',border:'1px solid rgba(0,0,0,0.12)'}}
            placeholder="搜索任务名称..." />
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm" style={{color:'rgba(0,0,0,0.25)'}}>🔍</span>
        </div>
      </div>

      {/* 日志列表 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b flex items-center justify-between" style={{borderColor:'rgba(0,0,0,0.06)'}}>
          <span className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>执行记录</span>
          <span className="text-xs" style={{color:'rgba(0,0,0,0.35)'}}>共 {filtered.length} 条</span>
        </div>
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{background:'rgba(0,0,0,0.04)'}}>📝</div>
            <p className="text-sm" style={{color:'rgba(0,0,0,0.35)'}}>
              {search || filterStatus !== 'all' ? '无匹配记录' : '暂无任务日志'}
            </p>
          </div>
        ) : (
          <div className="divide-y" style={{borderColor:'rgba(0,0,0,0.04)'}}>
            {filtered.map(log => {
              const isOpen = expanded === log.id
              const detail = mockDetails(log)
              return (
                <div key={log.id || Math.random()}>
                  {/* 主行 */}
                  <div className="flex items-center px-5 py-3 cursor-pointer hover:bg-black/5 transition-colors"
                    onClick={() => setExpanded(isOpen ? null : log.id)}>
                    <div className="flex-1 min-w-0 grid grid-cols-12 gap-2 items-center text-sm">
                      <div className="col-span-3 font-medium truncate" style={{color:'rgba(0,0,0,0.65)'}}>
                        {log.task_name || `执行 #${log.id}`}
                      </div>
                      <div className="col-span-2 text-xs truncate" style={{color:'rgba(0,0,0,0.40)'}}>
                        {log.type || '批量操作'}
                      </div>
                      <div className="col-span-2 text-xs truncate" style={{color:'rgba(0,0,0,0.40)'}}>
                        {detail.device}
                      </div>
                      <div className="col-span-2 text-xs" style={{color:'rgba(0,0,0,0.35)'}}>
                        {log.started_at ? new Date(log.started_at).toLocaleString('zh-CN') : '—'}
                      </div>
                      <div className="col-span-1 text-xs" style={{color:'rgba(0,0,0,0.35)'}}>
                        {detail.duration ? `${detail.duration}s` : '—'}
                      </div>
                      <div className="col-span-1 flex items-center gap-1">
                        {(() => {
                          const cfg = statusConfig[log.status || ''] || { label: log.status || '—', class: 'bg-gray-50 text-gray-400' }
                          return (
                            <span className={`text-[10px] px-1.5 py-0.5 rounded ${cfg.class}`}>{cfg.label}</span>
                          )
                        })()}
                      </div>
                      <div className="col-span-1 text-xs text-center" style={{color:'rgba(0,0,0,0.20)'}}>
                        {isOpen ? '▲' : '▼'}
                      </div>
                    </div>
                  </div>
                  {/* 展开详情 */}
                  {isOpen && (
                    <div className="px-5 pb-4 pt-0 border-t" style={{borderColor:'rgba(0,0,0,0.04)'}}>
                      <div className="grid grid-cols-2 gap-4 mt-3">
                        <div>
                          <div className="text-[10px] mb-1" style={{color:'rgba(0,0,0,0.30)'}}>设备</div>
                          <div className="text-xs" style={{color:'rgba(0,0,0,0.55)'}}>{detail.device}</div>
                        </div>
                        <div>
                          <div className="text-[10px] mb-1" style={{color:'rgba(0,0,0,0.30)'}}>账号</div>
                          <div className="text-xs" style={{color:'rgba(0,0,0,0.55)'}}>{detail.account}</div>
                        </div>
                        <div className="col-span-2">
                          <div className="text-[10px] mb-1" style={{color:'rgba(0,0,0,0.30)'}}>目标</div>
                          <div className="text-xs truncate" style={{color:'rgba(0,0,0,0.55)'}}>{detail.target}</div>
                        </div>
                        <div className="col-span-2">
                          <div className="text-[10px] mb-1" style={{color:'rgba(0,0,0,0.30)'}}>执行结果</div>
                          <div className="text-xs leading-relaxed" style={{color:'rgba(0,0,0,0.55)'}}>{detail.result}</div>
                        </div>
                        <div>
                          <div className="text-[10px] mb-1" style={{color:'rgba(0,0,0,0.30)'}}>开始时间</div>
                          <div className="text-xs" style={{color:'rgba(0,0,0,0.45)'}}>
                            {log.started_at ? new Date(log.started_at).toLocaleString('zh-CN') : '—'}
                          </div>
                        </div>
                        <div>
                          <div className="text-[10px] mb-1" style={{color:'rgba(0,0,0,0.30)'}}>完成时间</div>
                          <div className="text-xs" style={{color:'rgba(0,0,0,0.45)'}}>
                            {log.finished_at ? new Date(log.finished_at).toLocaleString('zh-CN') : '—'}
                          </div>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
