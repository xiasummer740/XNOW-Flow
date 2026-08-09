import { useState, useEffect, useCallback } from 'react'

interface Task {
  id: number
  name?: string
  type?: string
  status?: string
  target?: string
  device?: string
  progress?: number
  total?: number
  done?: number
  last_log?: string
  error?: string
  config?: any
  created_at?: string
}

const taskTypes = [
  { value: 'comment_like', label: '评论点赞', icon: '👍', action: 'like_comment', risk: 300, hint: '选评论分组数据，逐条点赞' },
  { value: 'follow_back', label: '回关', icon: '🤝', action: 'follow_user', risk: 200, hint: '选粉丝池分组，逐粉丝回关' },
  { value: 'follow', label: '批量关注', icon: '➕', action: 'follow', risk: 200, hint: '关注指定用户/关键词结果' },
  { value: 'like', label: '批量点赞', icon: '❤️', action: 'like', risk: 300, hint: '点赞 feed 视频' },
  { value: 'comment', label: '批量评论', icon: '💬', action: 'comment', risk: 0, hint: '每条评论=一个目标，自动轮换' },
  { value: 'dm', label: '批量私信', icon: '✉️', action: 'send_dm', risk: 0, hint: '私信指定用户（粉丝池）' },
  { value: 'post_video', label: '自动发视频', icon: '🎬', action: 'post_video', risk: 0, hint: '每个 video_url 发一条，标题轮换' },
  { value: 'collect', label: '数据采集', icon: '📡', action: 'collect_fans', risk: 0, hint: '采集粉丝/视频数据' },
]

const statusCfg: Record<string, { label: string; cls: string }> = {
  pending: { label: '待启动', cls: 'bg-yellow-50 text-yellow-600' },
  running: { label: '执行中', cls: 'bg-blue-50 text-blue-500' },
  done: { label: '已完成', cls: 'bg-green-50 text-green-600' },
  success: { label: '已完成', cls: 'bg-green-50 text-green-600' },
  failed: { label: '失败', cls: 'bg-red-50 text-red-500' },
  stopped: { label: '已停止', cls: 'bg-gray-50 text-gray-500' },
  paused: { label: '已暂停', cls: 'bg-orange-50 text-orange-500' },
}

export default function TaskList({ token }: { token: string }) {
  const [data, setData] = useState<Task[]>([])
  const [loading, setLoading] = useState(true)
  const [msg, setMsg] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [groups, setGroups] = useState<string[]>([])
  const [filter, setFilter] = useState('all')

  // 表单
  const [form, setForm] = useState({
    type: 'comment_like',
    targetMode: 'group' as 'group' | 'manual',
    targetGroup: '',
    targets: '',
    count: '',
    minInterval: '3',
    maxInterval: '8',
    deviceIds: '',
    extra: '',          // post_video 标题 或 dm 内容固定前缀
  })

  const api = (path: string, opts: RequestInit = {}) =>
    fetch(path, {
      ...opts,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${token}`,
        ...(opts.headers || {}),
      },
    })

  const fetchTasks = useCallback(() => {
    api('/api/biz/v2/tasks/?limit=50').then(r => r.json()).then(d => {
      setData(d.results || []); setLoading(false)
    }).catch(() => setLoading(false))
  }, [])

  useEffect(() => {
    fetchTasks()
    api('/api/biz/v2/collected-data/groups/').then(r => r.json()).then(d => {
      setGroups((d.groups || []).map((g: any) => g.name))
    }).catch(() => {})
    const t = setInterval(fetchTasks, 8000)  // 8s 轮询进度
    return () => clearInterval(t)
  }, [fetchTasks])

  const flash = (m: string) => { setMsg(m); setTimeout(() => setMsg(''), 4000) }

  const buildConfig = () => {
    const t = taskTypes.find(x => x.value === form.type)!
    const cfg: any = {
      action: t.action,
      min_interval: parseInt(form.minInterval) || 3,
      max_interval: parseInt(form.maxInterval) || 8,
      risk_cap: t.risk || undefined,
      device_ids: form.deviceIds.split(',').map(s => s.trim()).filter(Boolean),
    }
    if (form.targetMode === 'manual' && form.targets.trim()) {
      cfg.targets = form.targets.split(/[,，\n]/).map(s => s.trim()).filter(Boolean)
    }
    if (form.type === 'comment') cfg.unit_param = 'text'
    if (form.type === 'dm') cfg.unit_param = 'content'
    if (form.type === 'post_video') cfg.unit_param = 'video_url'
    if (form.count) cfg.count = parseInt(form.count)
    return cfg
  }

  const doCreate = async () => {
    const t = taskTypes.find(x => x.value === form.type)!
    const config = buildConfig()
    if (form.targetMode === 'group' && !form.targetGroup) { flash('请选择目标数据组'); return }
    if (form.targetMode === 'manual' && !(config.targets || []).length) { flash('请填写目标列表'); return }
    const res = await api('/api/biz/v2/tasks/', {
      method: 'POST',
      body: JSON.stringify({ type: form.type, name: `${t.label}任务`, config }),
    })
    if (!res.ok) { flash('创建失败'); return }
    const task = await res.json()
    // 自动启动（数据组在 start 时解析）
    const startRes = await api(`/api/biz/v2/tasks/${task.id}/start/`, {
      method: 'POST',
      body: JSON.stringify({ target_group: form.targetMode === 'group' ? form.targetGroup : '' }),
    })
    if (!startRes.ok) { flash('任务已创建，但启动失败'); return }
    flash('任务已创建并启动')
    setShowCreate(false)
    fetchTasks()
  }

  const act = async (id: number, action: 'start' | 'stop' | 'pause' | 'resume') => {
    await api(`/api/biz/v2/tasks/${id}/${action}/`, { method: 'POST', body: '{}' })
    fetchTasks()
  }

  const stats = {
    total: data.length,
    running: data.filter(t => t.status === 'running').length,
    done: data.filter(t => t.status === 'done' || t.status === 'success').length,
    failed: data.filter(t => t.status === 'failed').length,
  }

  const filtered = data.filter(t => filter === 'all' || t.status === filter)
  const curType = taskTypes.find(x => x.value === form.type)!

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-700">批量任务 · 任务引擎</h3>
        <div className="flex items-center gap-2">
          <button onClick={fetchTasks} className="px-3 py-1.5 rounded-lg text-xs text-gray-500 hover:bg-gray-100 cursor-pointer">🔄 刷新</button>
          <button onClick={() => setShowCreate(!showCreate)} className="px-4 py-2 rounded-lg bg-blue-500 text-white text-sm hover:bg-blue-600 cursor-pointer">
            {showCreate ? '取消' : '+ 新建任务'}
          </button>
        </div>
      </div>

      {msg && <div className="text-xs px-4 py-2 rounded-lg bg-blue-50 text-blue-600 border border-blue-100">{msg}</div>}

      {/* 统计 */}
      <div className="grid grid-cols-4 gap-4">
        {[
          { label: '总任务', val: stats.total, icon: '📋', c: 'text-gray-800' },
          { label: '执行中', val: stats.running, icon: '🔄', c: 'text-blue-500' },
          { label: '已完成', val: stats.done, icon: '✅', c: 'text-green-600' },
          { label: '失败', val: stats.failed, icon: '❌', c: 'text-red-500' },
        ].map(s => (
          <div key={s.label} className="xx-card rounded-xl p-4 flex items-center justify-between">
            <div><div className="text-xs text-gray-400">{s.label}</div><div className={`text-2xl font-bold ${s.c}`}>{s.val}</div></div>
            <span className="text-2xl">{s.icon}</span>
          </div>
        ))}
      </div>

      {/* 创建表单 */}
      {showCreate && (
        <div className="xx-card rounded-xl p-5">
          <h4 className="text-sm font-medium text-gray-700 mb-4">新建引擎任务</h4>
          <div>
            <label className="text-xs text-gray-400 block mb-2">任务类型</label>
            <div className="grid grid-cols-4 gap-2">
              {taskTypes.map(t => (
                <button key={t.value} type="button" onClick={() => setForm({ ...form, type: t.value })}
                  className={`px-3 py-2 rounded-lg text-xs transition-all cursor-pointer ${
                    form.type === t.value ? 'border-2 border-purple-500 text-purple-700' : 'border border-gray-200 text-gray-500 hover:border-gray-300'
                  }`}>
                  <div className="text-base mb-0.5">{t.icon}</div>
                  {t.label}
                </button>
              ))}
            </div>
            <p className="text-xs text-gray-400 mt-2">💡 {curType.hint}{curType.risk ? ` · 风控上限 ${curType.risk}（对齐 PPT 推荐）` : ''}</p>
          </div>

          {/* 目标来源 */}
          <div className="mt-4">
            <label className="text-xs text-gray-400 block mb-1">目标来源</label>
            <div className="flex gap-2 mb-2">
              <button onClick={() => setForm({ ...form, targetMode: 'group' })}
                className={`px-3 py-1.5 rounded-lg text-xs cursor-pointer ${form.targetMode === 'group' ? 'bg-purple-500 text-white' : 'bg-gray-100 text-gray-500'}`}>📂 数据组</button>
              <button onClick={() => setForm({ ...form, targetMode: 'manual' })}
                className={`px-3 py-1.5 rounded-lg text-xs cursor-pointer ${form.targetMode === 'manual' ? 'bg-purple-500 text-white' : 'bg-gray-100 text-gray-500'}`}>✍️ 手动输入</button>
            </div>
            {form.targetMode === 'group' ? (
              <select value={form.targetGroup} onChange={e => setForm({ ...form, targetGroup: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none">
                <option value="">选择目标数据组（来自采集数据分组）</option>
                {groups.map(g => <option key={g} value={g}>{g}</option>)}
              </select>
            ) : (
              <textarea value={form.targets} onChange={e => setForm({ ...form, targets: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none h-16"
                placeholder={`每个一行（评论点赞=评论文本 / 发视频=video_url / 其它=用户名）`} />
            )}
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-4">
            <div>
              <label className="text-xs text-gray-400 block mb-1">数量（0=全部）</label>
              <input type="number" value={form.count} onChange={e => setForm({ ...form, count: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none" min={0} placeholder="0=数据组全部" />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">最小间隔(秒)</label>
              <input type="number" value={form.minInterval} onChange={e => setForm({ ...form, minInterval: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none" min={1} />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">最大间隔(秒)</label>
              <input type="number" value={form.maxInterval} onChange={e => setForm({ ...form, maxInterval: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none" min={1} />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">设备（逗号分隔，可空）</label>
              <input type="text" value={form.deviceIds} onChange={e => setForm({ ...form, deviceIds: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none" placeholder="device_id1,device_id2" />
            </div>
          </div>

          {form.type === 'post_video' && (
            <div className="mt-3">
              <label className="text-xs text-gray-400 block mb-1">视频标题（可空，素材库/文案轮换后续接）</label>
              <input type="text" value={form.extra} onChange={e => setForm({ ...form, extra: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none" placeholder="标题文案" />
            </div>
          )}

          <button onClick={doCreate} className="mt-4 px-6 py-2 rounded-lg bg-blue-500 text-white text-sm hover:bg-blue-600 cursor-pointer">
            创建并启动
          </button>
        </div>
      )}

      {/* 过滤 */}
      <div className="flex gap-1 bg-gray-100 rounded-lg p-0.5 w-fit">
        {[
          { k: 'all', l: '全部' }, { k: 'running', l: '执行中' }, { k: 'done', l: '已完成' },
          { k: 'paused', l: '已暂停' }, { k: 'stopped', l: '已停止' }, { k: 'failed', l: '失败' },
        ].map(f => (
          <button key={f.k} onClick={() => setFilter(f.k)}
            className={`px-3 py-1 text-xs rounded-md cursor-pointer ${filter === f.k ? 'bg-white text-gray-700 shadow-sm' : 'text-gray-500'}`}>
            {f.l}
          </button>
        ))}
      </div>

      {/* 任务列表 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700">任务列表</span>
          <span className="text-xs text-gray-400">共 {filtered.length} 条 · 每 8 秒自动刷新进度</span>
        </div>
        {loading ? (
          <div className="flex justify-center py-16"><div className="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" /></div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📋</div>
            <p className="text-sm text-gray-400">暂无任务，点右上角「新建任务」创建</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
                  <th className="pb-2 pt-3 px-5 font-medium">任务</th>
                  <th className="pb-2 pt-3 px-5 font-medium">类型</th>
                  <th className="pb-2 pt-3 px-5 font-medium">进度</th>
                  <th className="pb-2 pt-3 px-5 font-medium">最近日志</th>
                  <th className="pb-2 pt-3 px-5 font-medium">状态</th>
                  <th className="pb-2 pt-3 px-5 font-medium">操作</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(t => {
                  const st = statusCfg[t.status || 'pending'] || statusCfg.pending
                  const pct = t.total ? Math.min(100, Math.round(((t.done || 0) / t.total) * 100)) : (t.progress || 0)
                  return (
                    <tr key={t.id} className="border-b border-gray-50 text-gray-700 hover:bg-gray-50/50">
                      <td className="py-3 px-5 font-medium max-w-[160px] truncate">{t.name || `Task #${t.id}`}</td>
                      <td className="py-3 px-5 text-xs text-gray-400">{t.type || '—'}</td>
                      <td className="py-3 px-5">
                        <div className="flex items-center gap-2">
                          <div className="w-20 bg-gray-100 rounded-full h-1.5 overflow-hidden">
                            <div className="h-full rounded-full" style={{ width: `${pct}%`, background: 'linear-gradient(90deg,#a855f7,#3b82f6)' }} />
                          </div>
                          <span className="text-xs text-gray-400">{t.done}/{t.total || '?'}</span>
                        </div>
                      </td>
                      <td className="py-3 px-5 max-w-[220px]">
                        <span className="text-xs text-gray-500 truncate block">{t.last_log || '—'}</span>
                        {t.error && <span className="text-xs text-red-400 truncate block">{t.error}</span>}
                      </td>
                      <td className="py-3 px-5"><span className={`text-xs px-2 py-0.5 rounded ${st.cls}`}>{st.label}</span></td>
                      <td className="py-3 px-5">
                        <div className="flex items-center gap-1">
                          {t.status === 'running' && (
                            <>
                              <button onClick={() => act(t.id, 'pause')} className="text-xs px-2 py-0.5 rounded bg-orange-50 text-orange-500 hover:bg-orange-100 cursor-pointer">暂停</button>
                              <button onClick={() => act(t.id, 'stop')} className="text-xs px-2 py-0.5 rounded bg-red-50 text-red-500 hover:bg-red-100 cursor-pointer">停止</button>
                            </>
                          )}
                          {t.status === 'pending' && (
                            <button onClick={() => act(t.id, 'start')} className="text-xs px-2 py-0.5 rounded bg-blue-50 text-blue-500 hover:bg-blue-100 cursor-pointer">启动</button>
                          )}
                          {(t.status === 'paused' || t.status === 'stopped') && (
                            <button onClick={() => act(t.id, 'resume')} className="text-xs px-2 py-0.5 rounded bg-green-50 text-green-600 hover:bg-green-100 cursor-pointer">恢复</button>
                          )}
                          <button onClick={() => act(t.id, 'stop')} className="text-xs px-2 py-0.5 rounded bg-gray-50 text-gray-400 hover:bg-gray-100 cursor-pointer">停止</button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
