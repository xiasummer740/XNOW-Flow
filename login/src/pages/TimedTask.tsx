import { useState } from 'react'

interface Schedule {
  id: number
  name: string
  cron: string
  taskType: string
  enabled: boolean
  lastRun: string
  nextRun: string
}

const mockSchedules: Schedule[] = [
  { id: 1, name: '每日采集-用户数据', cron: '0 2 * * *', taskType: '数据采集', enabled: true, lastRun: '2026-06-22 02:00', nextRun: '2026-06-23 02:00' },
  { id: 2, name: '批量关注任务', cron: '0 9 * * 1-5', taskType: '批量操作', enabled: true, lastRun: '2026-06-22 09:00', nextRun: '2026-06-23 09:00' },
  { id: 3, name: '评论采集-每小时', cron: '0 * * * *', taskType: '数据采集', enabled: false, lastRun: '2026-06-22 10:00', nextRun: '—' },
  { id: 4, name: '素材同步', cron: '0 3 */2 * *', taskType: '系统维护', enabled: true, lastRun: '2026-06-22 03:00', nextRun: '2026-06-24 03:00' },
  { id: 5, name: '数据报表生成', cron: '30 8 * * 1', taskType: '报表', enabled: false, lastRun: '2026-06-16 08:30', nextRun: '—' },
]

export default function TimedTask({ token: _token }: { token: string }) {
  const [schedules, setSchedules] = useState<Schedule[]>(mockSchedules)
  const [showAdd, setShowAdd] = useState(false)
  const [form, setForm] = useState({ name: '', cron: '', taskType: '数据采集' })
  const [msg, setMsg] = useState('')

  const toggleEnabled = (id: number) => {
    setSchedules(prev => prev.map(s => s.id === id ? { ...s, enabled: !s.enabled } : s))
  }

  const handleAdd = (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.name || !form.cron) { setMsg('请填写完整信息'); return }
    const newSched: Schedule = {
      id: Math.max(...schedules.map(s => s.id)) + 1,
      name: form.name,
      cron: form.cron,
      taskType: form.taskType,
      enabled: true,
      lastRun: '—',
      nextRun: '待计算',
    }
    setSchedules(prev => [...prev, newSched])
    setForm({ name: '', cron: '', taskType: '数据采集' })
    setShowAdd(false)
    setMsg('')
  }

  const cronHelp = [
    { expr: '0 2 * * *', desc: '每天凌晨2点' },
    { expr: '0 9 * * 1-5', desc: '工作日早9点' },
    { expr: '0 * * * *', desc: '每小时整点' },
    { expr: '*/30 * * * *', desc: '每30分钟' },
  ]

  return (
    <div className="space-y-6">
      {/* 快捷操作 */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-700">定时任务管理</h3>
        <button onClick={() => setShowAdd(!showAdd)}
          className="px-4 py-2 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-sm font-medium transition-colors cursor-pointer">
          {showAdd ? '取消' : '+ 新建定时任务'}
        </button>
      </div>

      {/* 新建表单 */}
      {showAdd && (
        <div className="xx-card rounded-xl p-5">
          <h4 className="text-sm font-medium text-gray-700 mb-4">新建定时任务</h4>
          <form onSubmit={handleAdd} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="text-xs text-gray-400 block mb-1">任务名称</label>
                <input type="text" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
                  placeholder="例: 每日采集" />
              </div>
              <div>
                <label className="text-xs text-gray-400 block mb-1">CRON 表达式</label>
                <input type="text" value={form.cron} onChange={e => setForm({ ...form, cron: e.target.value })}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 font-mono"
                  placeholder="例: 0 2 * * *" />
              </div>
              <div>
                <label className="text-xs text-gray-400 block mb-1">任务类型</label>
                <select value={form.taskType} onChange={e => setForm({ ...form, taskType: e.target.value })}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 bg-white">
                  <option>数据采集</option>
                  <option>批量操作</option>
                  <option>系统维护</option>
                  <option>报表</option>
                </select>
              </div>
            </div>

            {/* CRON 常用表达式参考 */}
            <div>
              <details className="text-xs text-gray-400">
                <summary className="cursor-pointer hover:text-gray-600">常用 CRON 表达式参考</summary>
                <div className="mt-2 space-y-1">
                  {cronHelp.map(c => (
                    <div key={c.expr} className="flex gap-4 text-gray-500">
                      <code className="font-mono text-blue-500 w-32">{c.expr}</code>
                      <span>{c.desc}</span>
                    </div>
                  ))}
                </div>
              </details>
            </div>

            {msg && <div className="text-red-500 text-xs">{msg}</div>}

            <button type="submit"
              className="px-6 py-2 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-sm font-medium transition-colors cursor-pointer">
              创建
            </button>
          </form>
        </div>
      )}

      {/* 任务列表 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700">定时任务列表</span>
          <span className="text-xs text-gray-400">共 {schedules.length} 个任务</span>
        </div>
        {schedules.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">⏰</div>
            <p className="text-sm text-gray-400">暂无定时任务</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
                  <th className="pb-2 pt-3 px-5 font-medium">任务名称</th>
                  <th className="pb-2 pt-3 px-5 font-medium">CRON</th>
                  <th className="pb-2 pt-3 px-5 font-medium">类型</th>
                  <th className="pb-2 pt-3 px-5 font-medium">上次执行</th>
                  <th className="pb-2 pt-3 px-5 font-medium">下次执行</th>
                  <th className="pb-2 pt-3 px-5 font-medium">状态</th>
                </tr>
              </thead>
              <tbody>
                {schedules.map((s) => (
                  <tr key={s.id} className="border-b border-gray-50 text-gray-700 hover:bg-gray-50/50">
                    <td className="py-3 px-5 font-medium">{s.name}</td>
                    <td className="py-3 px-5">
                      <code className="text-blue-500 font-mono text-xs bg-blue-50 px-2 py-0.5 rounded">{s.cron}</code>
                    </td>
                    <td className="py-3 px-5">
                      <span className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded">{s.taskType}</span>
                    </td>
                    <td className="py-3 px-5 text-gray-400">{s.lastRun}</td>
                    <td className="py-3 px-5 text-gray-400">{s.nextRun}</td>
                    <td className="py-3 px-5">
                      <button onClick={() => toggleEnabled(s.id)}
                        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors cursor-pointer ${
                          s.enabled ? 'bg-green-400' : 'bg-gray-200'
                        }`}>
                        <span className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white transition-transform shadow-sm ${
                          s.enabled ? 'translate-x-[18px]' : 'translate-x-[2px]'
                        }`} />
                      </button>
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
