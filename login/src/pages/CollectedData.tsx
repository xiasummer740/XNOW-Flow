import { useState } from 'react'

interface CollectionRecord {
  id: number
  source: string
  type: string
  content: string
  author: string
  collectedAt: string
  status: string
}

const mockData: CollectionRecord[] = [
  { id: 1, source: '抖音', type: '用户', content: '张三 (zsshipping)', author: 'device-01', collectedAt: '2026-06-23 10:30', status: '已完成' },
  { id: 2, source: '抖音', type: '视频', content: '今天天气真好...', author: 'device-01', collectedAt: '2026-06-23 10:28', status: '已完成' },
  { id: 3, source: '抖音', type: '评论', content: '这个产品不错', author: 'device-02', collectedAt: '2026-06-23 10:25', status: '已完成' },
  { id: 4, source: 'TikTok', type: '用户', content: 'John Doe (@johndoe)', author: 'device-03', collectedAt: '2026-06-23 10:20', status: '已完成' },
  { id: 5, source: 'TikTok', type: '视频', content: 'Check out this new...', author: 'device-03', collectedAt: '2026-06-23 10:18', status: '已完成' },
  { id: 6, source: '抖音', type: '评论', content: '666666', author: 'device-01', collectedAt: '2026-06-23 10:15', status: '已完成' },
  { id: 7, source: '抖音', type: '用户', content: '李四 (lsiii)', author: 'device-02', collectedAt: '2026-06-23 10:10', status: '异常' },
  { id: 8, source: 'TikTok', type: '评论', content: 'Nice video!', author: 'device-03', collectedAt: '2026-06-23 10:05', status: '已完成' },
  { id: 9, source: '抖音', type: '视频', content: '美食探店...', author: 'device-01', collectedAt: '2026-06-23 09:55', status: '已完成' },
  { id: 10, source: 'TikTok', type: '用户', content: 'Jane Smith (@janesmith)', author: 'device-03', collectedAt: '2026-06-23 09:50', status: '已完成' },
]

const sourceColors: Record<string, string> = {
  '抖音': 'bg-red-50 text-red-500',
  'TikTok': 'bg-blue-50 text-blue-500',
}

const typeIcons: Record<string, string> = {
  '用户': '👤',
  '视频': '🎬',
  '评论': '💬',
}

export default function CollectedData({ token: _token }: { token: string }) {
  const [data] = useState<CollectionRecord[]>(mockData)
  const [search, setSearch] = useState('')
  const [sourceFilter, setSourceFilter] = useState('all')

  const sources = ['all', ...new Set(data.map(d => d.source))]
  const filtered = data.filter(d => {
    if (sourceFilter !== 'all' && d.source !== sourceFilter) return false
    if (search && !d.content.toLowerCase().includes(search.toLowerCase()) && !d.author.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  const stats = {
    users: data.filter(d => d.type === '用户').length,
    videos: data.filter(d => d.type === '视频').length,
    comments: data.filter(d => d.type === '评论').length,
  }

  return (
    <div className="space-y-6">
      <h3 className="text-sm font-medium text-gray-700">采集数据</h3>

      {/* 统计小卡片 */}
      <div className="grid grid-cols-3 gap-4">
        {[
          { label: '用户数据', val: stats.users, icon: '👤', bg: 'bg-blue-50 text-blue-600' },
          { label: '视频数据', val: stats.videos, icon: '🎬', bg: 'bg-purple-50 text-purple-600' },
          { label: '评论数据', val: stats.comments, icon: '💬', bg: 'bg-green-50 text-green-600' },
        ].map(s => (
          <div key={s.label} className={`${s.bg} bg-opacity-50 rounded-xl p-4 border border-gray-100 shadow-sm`}>
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xs text-gray-500">{s.label}</div>
                <div className="text-xl font-bold mt-1">{s.val}</div>
              </div>
              <span className="text-2xl">{s.icon}</span>
            </div>
          </div>
        ))}
      </div>

      {/* 搜索+过滤 */}
      <div className="flex items-center gap-3">
        <div className="relative flex-1 max-w-xs">
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            className="w-full border border-gray-200 rounded-lg pl-9 pr-3 py-2 text-sm outline-none focus:border-blue-400"
            placeholder="搜索内容或设备..." />
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">🔍</span>
        </div>
        <div className="flex gap-1 bg-gray-100 rounded-lg p-0.5">
          {sources.map(s => (
            <button key={s}
              onClick={() => setSourceFilter(s)}
              className={`px-3 py-1 text-xs rounded-md transition-colors cursor-pointer ${
                sourceFilter === s ? 'bg-white text-gray-700 shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}>
              {s === 'all' ? '全部' : s}
            </button>
          ))}
        </div>
      </div>

      {/* 数据表格 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700">采集记录</span>
          <span className="text-xs text-gray-400">共 {filtered.length} 条</span>
        </div>
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📡</div>
            <p className="text-sm text-gray-400">暂无采集数据</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
                  <th className="pb-2 pt-3 px-5 font-medium">来源</th>
                  <th className="pb-2 pt-3 px-5 font-medium">类型</th>
                  <th className="pb-2 pt-3 px-5 font-medium">内容</th>
                  <th className="pb-2 pt-3 px-5 font-medium">采集设备</th>
                  <th className="pb-2 pt-3 px-5 font-medium">采集时间</th>
                  <th className="pb-2 pt-3 px-5 font-medium">状态</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(r => (
                  <tr key={r.id} className="border-b border-gray-50 text-gray-700 hover:bg-gray-50/50">
                    <td className="py-3 px-5">
                      <span className={`text-xs px-2 py-0.5 rounded ${sourceColors[r.source] || 'bg-gray-50 text-gray-500'}`}>
                        {r.source}
                      </span>
                    </td>
                    <td className="py-3 px-5">
                      <span className="flex items-center gap-1">
                        <span>{typeIcons[r.type]}</span>
                        <span>{r.type}</span>
                      </span>
                    </td>
                    <td className="py-3 px-5 max-w-[200px] truncate">{r.content}</td>
                    <td className="py-3 px-5 text-gray-400 text-xs">{r.author}</td>
                    <td className="py-3 px-5 text-gray-400 text-xs">{r.collectedAt}</td>
                    <td className="py-3 px-5">
                      <span className={`text-xs px-2 py-0.5 rounded ${
                        r.status === '已完成' ? 'bg-green-50 text-green-600' : 'bg-red-50 text-red-500'
                      }`}>
                        {r.status}
                      </span>
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
