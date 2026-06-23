import { useState, useMemo } from 'react'

interface StatsRecord {
  date: string
  total: number
  success: number
  failed: number
  devices: number
}

const mockStats: StatsRecord[] = [
  { date: '06-17', total: 156, success: 142, failed: 14, devices: 12 },
  { date: '06-18', total: 178, success: 165, failed: 13, devices: 14 },
  { date: '06-19', total: 203, success: 188, failed: 15, devices: 14 },
  { date: '06-20', total: 167, success: 155, failed: 12, devices: 13 },
  { date: '06-21', total: 189, success: 172, failed: 17, devices: 15 },
  { date: '06-22', total: 221, success: 208, failed: 13, devices: 15 },
  { date: '06-23', total: 145, success: 138, failed: 7, devices: 14 },
]

const taskTypeStats = [
  { type: '批量关注', count: 412, success: 94 },
  { type: '数据采集', count: 356, success: 97 },
  { type: '批量私信', count: 189, success: 91 },
  { type: '评论采集', count: 278, success: 95 },
  { type: '账号检测', count: 95, success: 100 },
]

export default function ExecutionStats({ token: _token }: { token: string }) {
  const [dateRange, setDateRange] = useState('7d')

  const totals = useMemo(() => {
    const sum = mockStats.reduce((acc, s) => ({
      total: acc.total + s.total,
      success: acc.success + s.success,
      failed: acc.failed + s.failed,
    }), { total: 0, success: 0, failed: 0 })
    return sum
  }, [])

  const overallRate = totals.total > 0 ? ((totals.success / totals.total) * 100).toFixed(1) : '0'

  return (
    <div className="space-y-6">
      {/* 头部过滤 */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-700">执行统计</h3>
        <div className="flex gap-1 bg-gray-100 rounded-lg p-0.5">
          {['7d', '30d', '90d'].map(r => (
            <button key={r}
              onClick={() => setDateRange(r)}
              className={`px-3 py-1 text-xs rounded-md transition-colors cursor-pointer ${
                dateRange === r ? 'bg-white text-gray-700 shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}>
              {r === '7d' ? '近7天' : r === '30d' ? '近30天' : '近90天'}
            </button>
          ))}
        </div>
      </div>

      {/* 统计概览卡片 */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {[
          { label: '总执行次数', value: totals.total.toLocaleString(), color: 'text-blue-600', bg: 'bg-blue-50' },
          { label: '成功次数', value: totals.success.toLocaleString(), color: 'text-green-600', bg: 'bg-green-50' },
          { label: '失败次数', value: totals.failed.toLocaleString(), color: 'text-red-600', bg: 'bg-red-50' },
          { label: '总成功率', value: `${overallRate}%`, color: 'text-emerald-600', bg: 'bg-emerald-50' },
        ].map(card => (
          <div key={card.label} className="xx-card rounded-xl p-5">
            <div className="text-xs text-gray-500 mb-1">{card.label}</div>
            <div className={`text-2xl font-bold ${card.color}`}>{card.value}</div>
          </div>
        ))}
      </div>

      {/* 每日执行趋势 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b" style={{borderColor:'rgba(0,0,0,0.06)'}}>
          <h4 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>每日执行趋势</h4>
        </div>
        <div className="p-5">
          <div className="h-48 flex items-end gap-2">
            {mockStats.map((s, i) => {
              const max = Math.max(...mockStats.map(x => x.total))
              const h = (s.total / max) * 100
              return (
                <div key={i} className="flex-1 flex flex-col items-center gap-1 group relative">
                  <div className="w-full flex flex-col items-center gap-0.5" style={{ height: '100%' }}>
                    <div className="w-full flex flex-col justify-end" style={{ height: `${h}%` }}>
                      <div className="w-full bg-green-200 rounded-t"
                        style={{ height: `${(s.success / s.total) * 100}%`, minHeight: s.total > 0 ? 2 : 0 }} />
                      <div className="w-full bg-red-200 rounded-b"
                        style={{ height: `${(s.failed / s.total) * 100}%`, minHeight: s.total > 0 ? 2 : 0 }} />
                    </div>
                  </div>
                  <span className="text-[10px] text-gray-400">{s.date}</span>
                  {/* tooltip */}
                  <div className="absolute -top-10 left-1/2 -translate-x-1/2 bg-gray-800 text-white text-[10px] px-2 py-1 rounded opacity-0 group-hover:opacity-100 whitespace-nowrap transition-opacity pointer-events-none z-10">
                    成功 {s.success} / 失败 {s.failed}
                    <div className="absolute top-full left-1/2 -translate-x-1/2 border-4 border-transparent border-t-gray-800" />
                  </div>
                </div>
              )
            })}
          </div>
          <div className="flex items-center justify-center gap-4 mt-4 text-xs text-gray-400">
            <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-green-200" /> 成功</span>
            <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-red-200" /> 失败</span>
          </div>
        </div>
      </div>

      {/* 任务类型分布 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b" style={{borderColor:'rgba(0,0,0,0.06)'}}>
          <h4 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>任务类型统计</h4>
        </div>
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
              <th className="pb-2 pt-3 px-5 font-medium">任务类型</th>
              <th className="pb-2 pt-3 px-5 font-medium text-right">执行次数</th>
              <th className="pb-2 pt-3 px-5 font-medium text-right">成功率</th>
              <th className="pb-2 pt-3 px-5 font-medium">进度条</th>
            </tr>
          </thead>
          <tbody>
            {taskTypeStats.map((t, i) => (
              <tr key={i} className="border-b border-gray-50 text-gray-700">
                <td className="py-3 px-5">{t.type}</td>
                <td className="py-3 px-5 text-right">{t.count}</td>
                <td className="py-3 px-5 text-right font-medium">{t.success}%</td>
                <td className="py-3 px-5">
                  <div className="w-full bg-gray-100 rounded-full h-2 max-w-xs">
                    <div className="bg-blue-500 h-2 rounded-full transition-all"
                      style={{ width: `${t.success}%` }} />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
