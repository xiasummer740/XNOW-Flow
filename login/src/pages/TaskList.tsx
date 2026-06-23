import { useState, useEffect } from 'react'

interface Task {
  id: number
  name?: string
  type?: string
  status?: string
  target?: string
  device?: string
  account?: string
  progress?: number
  created_at?: string
  finished_at?: string
}

const taskTypes = [
  { value: 'follow', label: '批量关注', icon: '➕' },
  { value: 'like', label: '批量点赞', icon: '❤️' },
  { value: 'comment', label: '批量评论', icon: '💬' },
  { value: 'dm', label: '批量私信', icon: '✉️' },
  { value: 'collect', label: '数据采集', icon: '📡' },
]

const statusConfig: Record<string, { label: string; class: string }> = {
  pending: { label: '待执行', class: 'bg-yellow-50 text-yellow-600' },
  running: { label: '执行中', class: 'bg-blue-50 text-blue-500' },
  success: { label: '已完成', class: 'bg-green-50 text-green-600' },
  failed: { label: '失败', class: 'bg-red-50 text-red-500' },
  cancelled: { label: '已取消', class: 'bg-gray-50 text-gray-500' },
}

export default function TaskList({ token }: { token: string }) {
  const [data, setData] = useState<Task[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [filterStatus, setFilterStatus] = useState('all')
  const [search, setSearch] = useState('')
  const [form, setForm] = useState({ type: 'follow', target: '', device: '', account: '', count: '10' })
  const [msg, setMsg] = useState('')

  useEffect(() => {
    fetch('/api/biz/v2/tasks/?limit=50', {
      headers: { Authorization: `Token ${token}` }
    })
      .then(r => r.json())
      .then(d => { setData(d.results || d); setLoading(false) })
      .catch(() => { setError('加载失败'); setLoading(false) })
  }, [token])

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.target) { setMsg('请填写目标信息'); return }
    const newTask: Task = {
      id: Date.now(),
      name: taskTypes.find(t => t.value === form.type)?.label || form.type,
      type: form.type,
      status: 'pending',
      target: form.target,
      device: form.device || '自动分配',
      account: form.account || '自动选择',
      progress: 0,
      created_at: new Date().toISOString(),
    }
    setData(prev => [newTask, ...prev])
    setForm({ type: 'follow', target: '', device: '', account: '', count: '10' })
    setShowCreate(false)
    setMsg('')
  }

  const filtered = data.filter(t => {
    if (filterStatus !== 'all' && t.status !== filterStatus) return false
    if (search && !t.name?.includes(search) && !t.target?.includes(search)) return false
    return true
  })

  const getStatusBadge = (status?: string) => {
    const cfg = statusConfig[status || 'pending'] || statusConfig.pending
    return <span className={`text-xs px-2 py-0.5 rounded ${cfg.class}`}>{cfg.label}</span>
  }

  const stats = {
    total: data.length,
    running: data.filter(t => t.status === 'running').length,
    success: data.filter(t => t.status === 'success' || t.status === 'completed').length,
    failed: data.filter(t => t.status === 'failed').length,
  }

  if (loading) return <div className="flex items-center justify-center h-64" style={{color:'rgba(0,0,0,0.35)'}}>加载中...</div>
  if (error) return <div className="flex items-center justify-center h-64 text-red-400">{error}</div>

  return (
    <div className="space-y-6">
      {/* 头部 */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>批量任务</h3>
        <button onClick={() => setShowCreate(!showCreate)}
          className="xx-btn-primary px-4 py-2 rounded-lg text-sm font-medium cursor-pointer">
          {showCreate ? '取消' : '+ 新建任务'}
        </button>
      </div>

      {/* 统计概览 */}
      <div className="grid grid-cols-4 gap-4">
        {[
          { label: '总任务', val: stats.total, icon: '📋', color: 'rgba(0,0,0,0.70)' },
          { label: '执行中', val: stats.running, icon: '🔄', color: '#3b82f6' },
          { label: '已完成', val: stats.success, icon: '✅', color: '#22c55e' },
          { label: '失败', val: stats.failed, icon: '❌', color: '#ef4444' },
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

      {/* 新建任务表单 */}
      {showCreate && (
        <div className="xx-card rounded-xl p-5">
          <h4 className="text-sm font-medium mb-4" style={{color:'rgba(0,0,0,0.65)'}}>新建批量任务</h4>
          <form onSubmit={handleCreate} className="space-y-4">
            <div>
              <label className="text-xs block mb-1" style={{color:'rgba(0,0,0,0.40)'}}>任务类型</label>
              <div className="grid grid-cols-5 gap-2">
                {taskTypes.map(t => (
                  <button key={t.value} type="button" onClick={() => setForm({ ...form, type: t.value })}
                    className={`px-3 py-2 rounded-lg text-xs transition-all cursor-pointer ${
                      form.type === t.value
                        ? 'xx-card border-2'
                        : 'border border-dashed'
                    }`}
                    style={{
                      borderColor: form.type === t.value ? '#a855f7' : 'rgba(0,0,0,0.12)',
                      color: form.type === t.value ? '#7c3aed' : 'rgba(0,0,0,0.50)',
                    }}>
                    <div className="text-base mb-0.5">{t.icon}</div>
                    {t.label}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="text-xs block mb-1" style={{color:'rgba(0,0,0,0.40)'}}>目标</label>
                <input type="text" value={form.target} onChange={e => setForm({ ...form, target: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{background:'rgba(255,255,255,0.40)',border:'1px solid rgba(0,0,0,0.12)'}}
                  placeholder="用户链接 / 关键词 / 话题" />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{color:'rgba(0,0,0,0.40)'}}>执行数量</label>
                <input type="number" value={form.count} onChange={e => setForm({ ...form, count: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{background:'rgba(255,255,255,0.40)',border:'1px solid rgba(0,0,0,0.12)'}}
                  min="1" max="100" />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{color:'rgba(0,0,0,0.40)'}}>指定设备（可选）</label>
                <input type="text" value={form.device} onChange={e => setForm({ ...form, device: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{background:'rgba(255,255,255,0.40)',border:'1px solid rgba(0,0,0,0.12)'}}
                  placeholder="留空自动分配" />
              </div>
            </div>
            {msg && <div className="text-red-500 text-xs">{msg}</div>}
            <button type="submit"
              className="xx-btn-primary px-6 py-2 rounded-lg text-sm font-medium cursor-pointer">
              创建任务
            </button>
          </form>
        </div>
      )}

      {/* 过滤 + 搜索 */}
      <div className="flex items-center gap-3">
        <div className="flex gap-1 rounded-lg p-0.5" style={{background:'rgba(255,255,255,0.25)'}}>
          {[
            { key: 'all', label: '全部' },
            { key: 'pending', label: '待执行' },
            { key: 'running', label: '执行中' },
            { key: 'success', label: '已完成' },
            { key: 'failed', label: '失败' },
          ].map(f => (
            <button key={f.key} onClick={() => setFilterStatus(f.key)}
              className={`px-3 py-1 text-xs rounded-md transition-all cursor-pointer ${
                filterStatus === f.key ? 'xx-card' : ''
              }`}
              style={{
                color: filterStatus === f.key ? 'rgba(0,0,0,0.70)' : 'rgba(0,0,0,0.40)',
              }}>
              {f.label}
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

      {/* 任务列表 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b flex items-center justify-between" style={{borderColor:'rgba(0,0,0,0.06)'}}>
          <span className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>任务列表</span>
          <span className="text-xs" style={{color:'rgba(0,0,0,0.35)'}}>共 {filtered.length} 条</span>
        </div>
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{background:'rgba(0,0,0,0.04)'}}>📋</div>
            <p className="text-sm" style={{color:'rgba(0,0,0,0.35)'}}>
              {search || filterStatus !== 'all' ? '无匹配任务' : '暂无批量任务，点击右上角创建'}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs border-b" style={{color:'rgba(0,0,0,0.35)',borderColor:'rgba(0,0,0,0.06)'}}>
                  <th className="pb-2 pt-3 px-5 font-medium">任务</th>
                  <th className="pb-2 pt-3 px-5 font-medium">类型</th>
                  <th className="pb-2 pt-3 px-5 font-medium">目标</th>
                  <th className="pb-2 pt-3 px-5 font-medium">设备</th>
                  <th className="pb-2 pt-3 px-5 font-medium">进度</th>
                  <th className="pb-2 pt-3 px-5 font-medium">状态</th>
                  <th className="pb-2 pt-3 px-5 font-medium">时间</th>
                  <th className="pb-2 pt-3 px-5 font-medium">操作</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(t => (
                  <tr key={t.id} className="border-b" style={{borderColor:'rgba(0,0,0,0.04)',color:'rgba(0,0,0,0.65)'}}>
                    <td className="py-3 px-5 font-medium">{t.name || `Task #${t.id}`}</td>
                    <td className="py-3 px-5">
                      <span className="text-xs" style={{color:'rgba(0,0,0,0.40)'}}>{t.type || '—'}</span>
                    </td>
                    <td className="py-3 px-5 max-w-[120px] truncate">{t.target || '—'}</td>
                    <td className="py-3 px-5 text-xs" style={{color:'rgba(0,0,0,0.40)'}}>{t.device || '—'}</td>
                    <td className="py-3 px-5">
                      <div className="flex items-center gap-2">
                        <div className="w-16 bg-gray-200 rounded-full h-1.5 overflow-hidden" style={{background:'rgba(0,0,0,0.06)'}}>
                          <div className="h-full rounded-full transition-all"
                            style={{
                              width: `${t.progress || 0}%`,
                              background: 'linear-gradient(90deg, #a855f7, #3b82f6)',
                            }} />
                        </div>
                        <span className="text-xs" style={{color:'rgba(0,0,0,0.40)'}}>{t.progress || 0}%</span>
                      </div>
                    </td>
                    <td className="py-3 px-5">{getStatusBadge(t.status)}</td>
                    <td className="py-3 px-5 text-xs" style={{color:'rgba(0,0,0,0.35)'}}>
                      {t.created_at ? new Date(t.created_at).toLocaleString('zh-CN') : '—'}
                    </td>
                    <td className="py-3 px-5">
                      <div className="flex items-center gap-1">
                        {t.status === 'pending' && (
                          <button className="text-xs px-2 py-0.5 rounded cursor-pointer"
                            style={{color:'#ef4444',background:'rgba(239,68,68,0.08)'}}>取消</button>
                        )}
                        {(t.status === 'failed' || t.status === 'cancelled') && (
                          <button className="text-xs px-2 py-0.5 rounded cursor-pointer"
                            style={{color:'#3b82f6',background:'rgba(59,130,246,0.08)'}}>重试</button>
                        )}
                        {t.status === 'success' && (
                          <button className="text-xs px-2 py-0.5 rounded cursor-pointer"
                            style={{color:'rgba(0,0,0,0.35)',background:'rgba(0,0,0,0.04)'}}>详情</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
