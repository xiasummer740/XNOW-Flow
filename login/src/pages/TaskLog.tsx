import { useState, useEffect } from 'react'

interface Log {
  id: number
  task_name?: string
  status?: string
  started_at?: string
  finished_at?: string
}

export default function TaskLog({ token }: { token: string }) {
  const [data, setData] = useState<Log[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    fetch('/api/biz/v2/task-executions/?limit=20', {
      headers: { Authorization: `Token ${token}` }
    })
      .then(r => r.json())
      .then(d => { setData(d.results || d); setLoading(false) })
      .catch(() => { setError('加载失败'); setLoading(false) })
  }, [token])

  if (loading) return <div className="flex items-center justify-center h-64 text-gray-400">加载中...</div>
  if (error) return <div className="flex items-center justify-center h-64 text-red-400">{error}</div>

  return (
    <div className="xx-card rounded-xl">
      <div className="px-5 py-4 border-b" style={{borderColor:'rgba(0,0,0,0.06)'}}>
        <h3 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>任务日志</h3>
      </div>
      {data.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📝</div>
          <p className="text-sm text-gray-400">暂无任务日志</p>
        </div>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
              <th className="pb-2 pt-3 px-5 font-medium">编号</th>
              <th className="pb-2 pt-3 px-5 font-medium">任务</th>
              <th className="pb-2 pt-3 px-5 font-medium">状态</th>
              <th className="pb-2 pt-3 px-5 font-medium">开始时间</th>
              <th className="pb-2 pt-3 px-5 font-medium">完成时间</th>
            </tr>
          </thead>
          <tbody>
            {data.map((log, i) => (
              <tr key={log.id || i} className="border-b border-gray-50 text-gray-700">
                <td className="py-3 px-5">{log.id || i + 1}</td>
                <td className="py-3 px-5">{log.task_name || '—'}</td>
                <td className="py-3 px-5">
                  <span className={`inline-flex items-center gap-1 ${
                    log.status === 'success' ? 'text-green-500' :
                    log.status === 'failed' ? 'text-red-400' :
                    log.status === 'running' ? 'text-blue-500' : 'text-gray-400'
                  }`}>
                    <span className={`w-2 h-2 rounded-full ${
                      log.status === 'success' ? 'bg-green-400' :
                      log.status === 'failed' ? 'bg-red-300' :
                      log.status === 'running' ? 'bg-blue-400' : 'bg-gray-300'
                    }`} />
                    {log.status === 'success' ? '成功' : log.status === 'failed' ? '失败' : log.status === 'running' ? '执行中' : log.status || '—'}
                  </span>
                </td>
                <td className="py-3 px-5 text-gray-400">{log.started_at ? new Date(log.started_at).toLocaleString('zh-CN') : '—'}</td>
                <td className="py-3 px-5 text-gray-400">{log.finished_at ? new Date(log.finished_at).toLocaleString('zh-CN') : '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
