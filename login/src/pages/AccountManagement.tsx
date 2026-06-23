import { useState, useEffect } from 'react'

interface Account {
  id: number
  nickname?: string
  username?: string
  tk_number?: string
  unique_id?: string
  followers?: number
  following_count?: number
  video_count?: number
  status?: string
  region?: string
  country?: string
}

export default function AccountManagement({ token }: { token: string }) {
  const [data, setData] = useState<Account[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    fetch('/api/biz/v2/accounts/?limit=20', {
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
        <h3 className="text-sm font-medium" style={{color:'rgba(0,0,0,0.65)'}}>账号列表</h3>
      </div>
      {data.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">👤</div>
          <p className="text-sm text-gray-400">暂无账号数据</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
              <th className="pb-2 pt-3 px-5 font-medium">昵称</th>
              <th className="pb-2 pt-3 px-5 font-medium">TK号</th>
              <th className="pb-2 pt-3 px-5 font-medium text-right">粉丝</th>
              <th className="pb-2 pt-3 px-5 font-medium text-right">关注</th>
              <th className="pb-2 pt-3 px-5 font-medium text-right">作品</th>
              <th className="pb-2 pt-3 px-5 font-medium">状态</th>
              <th className="pb-2 pt-3 px-5 font-medium">国家</th>
            </tr>
          </thead>
          <tbody>
            {data.map((acc, i) => (
              <tr key={acc.id || i} className="border-b border-gray-50 text-gray-700">
                <td className="py-3 px-5">{acc.nickname || acc.username || '—'}</td>
                <td className="py-3 px-5 text-gray-400">{acc.tk_number || acc.unique_id || '—'}</td>
                <td className="py-3 px-5 text-right">{acc.followers?.toLocaleString() ?? 0}</td>
                <td className="py-3 px-5 text-right">{acc.following_count?.toLocaleString() ?? 0}</td>
                <td className="py-3 px-5 text-right">{acc.video_count?.toLocaleString() ?? 0}</td>
                <td className="py-3 px-5">
                  <span className={`inline-flex items-center gap-1 ${acc.status === 'active' ? 'text-green-500' : acc.status === 'banned' ? 'text-red-400' : 'text-gray-400'}`}>
                    <span className={`w-2 h-2 rounded-full ${acc.status === 'active' ? 'bg-green-400' : acc.status === 'banned' ? 'bg-red-300' : 'bg-gray-300'}`} />
                    {acc.status === 'active' ? '正常' : acc.status === 'banned' ? '封禁' : acc.status === 'risk_control' ? '风控' : acc.status || '—'}
                  </span>
                </td>
                <td className="py-3 px-5 text-gray-400">{acc.region || acc.country || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}
    </div>
  )
}
