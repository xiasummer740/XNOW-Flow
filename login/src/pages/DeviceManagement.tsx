import { useState, useEffect } from 'react'

interface Device {
  id: number
  device_name?: string
  name?: string
  status?: string
  online?: boolean
  account_count?: number
  accounts?: number
  last_online?: string
  app_version?: string
}

export default function DeviceManagement({ token }: { token: string }) {
  const [data, setData] = useState<Device[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    fetch('/api/biz/v2/device-bindings/?limit=20', {
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
        <h3 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>设备列表</h3>
      </div>
      {data.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📱</div>
          <p className="text-sm text-gray-400">暂无设备数据</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
              <th className="pb-2 pt-3 px-5 font-medium">编号</th>
              <th className="pb-2 pt-3 px-5 font-medium">设备名</th>
              <th className="pb-2 pt-3 px-5 font-medium">状态</th>
              <th className="pb-2 pt-3 px-5 font-medium text-right">账号数</th>
              <th className="pb-2 pt-3 px-5 font-medium">最后在线</th>
              <th className="pb-2 pt-3 px-5 font-medium">App版本</th>
            </tr>
          </thead>
          <tbody>
            {data.map((dev, i) => (
              <tr key={dev.id || i} className="border-b border-gray-50 text-gray-700">
                <td className="py-3 px-5">{dev.id || i + 1}</td>
                <td className="py-3 px-5">{dev.device_name || dev.name || '—'}</td>
                <td className="py-3 px-5">
                  <span className={`inline-flex items-center gap-1 ${(dev.status === 'online' || dev.online) ? 'text-green-500' : 'text-gray-400'}`}>
                    <span className={`w-2 h-2 rounded-full ${(dev.status === 'online' || dev.online) ? 'bg-green-400' : 'bg-gray-300'}`} />
                    {(dev.status === 'online' || dev.online) ? '在线' : '离线'}
                  </span>
                </td>
                <td className="py-3 px-5 text-right">{dev.account_count ?? dev.accounts ?? 0}</td>
                <td className="py-3 px-5 text-gray-400">{dev.last_online ? new Date(dev.last_online).toLocaleString('zh-CN') : '—'}</td>
                <td className="py-3 px-5 text-gray-400">{dev.app_version || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}
    </div>
  )
}
