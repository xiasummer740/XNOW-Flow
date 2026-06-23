import { useState, useEffect } from 'react'

interface Announcement {
  id: number
  title: string
  content: string
  priority: 'high' | 'normal' | 'low'
  is_pinned: boolean
  created_at: string
}

const priorityStyles: Record<string, string> = {
  high: 'bg-red-50 text-red-500 border-red-100',
  normal: 'bg-blue-50 text-blue-500 border-blue-100',
  low: 'bg-gray-50 text-gray-500 border-gray-100',
}

const priorityLabels: Record<string, string> = {
  high: '重要',
  normal: '普通',
  low: '低',
}

export default function Announcements({ token }: { token: string }) {
  const [data, setData] = useState<Announcement[]>([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<number | null>(null)

  useEffect(() => {
    const fetchData = async () => {
      try {
        const res = await fetch('/api/biz/v2/announcements/', {
          headers: { 'Authorization': `Token ${token}` },
        })
        if (!res.ok) throw new Error('Failed to fetch')
        const json = await res.json()
        setData(json)
      } catch {
        // ignore
      } finally {
        setLoading(false)
      }
    }
    fetchData()
  }, [])

  const sorted = [...data].sort((a, b) => {
    if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  })

  return (
    <div className="space-y-6">
      <h3 className="text-sm font-medium text-gray-700">公告中心</h3>

      <div className="space-y-3">
        {loading ? (
          <div className="xx-card rounded-xl flex items-center justify-center py-16">
            <div className="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : sorted.length === 0 ? (
          <div className="xx-card rounded-xl flex flex-col items-center justify-center text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📢</div>
            <p className="text-sm text-gray-400">暂无公告</p>
          </div>
        ) : (
          sorted.map(item => {
            const isOpen = expanded === item.id
            return (
              <div key={item.id}
                className="xx-card rounded-xl transition-all">
                <button onClick={() => setExpanded(isOpen ? null : item.id)}
                  className="w-full text-left px-5 py-4 flex items-start gap-4 cursor-pointer">
                  {/* 优先级指示 */}
                  <div className={`mt-1 w-2 h-2 rounded-full shrink-0 ${
                    item.priority === 'high' ? 'bg-red-400' : item.priority === 'normal' ? 'bg-blue-400' : 'bg-gray-300'
                  }`} />

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      {item.is_pinned && (
                        <span className="text-[10px] bg-blue-50 text-blue-500 px-1.5 py-0.5 rounded border border-blue-100">置顶</span>
                      )}
                      <span className={`text-xs px-1.5 py-0.5 rounded border ${priorityStyles[item.priority]}`}>
                        {priorityLabels[item.priority]}
                      </span>
                    </div>
                    <h4 className="text-sm font-medium text-gray-800">{item.title}</h4>
                    {isOpen && (
                      <p className="mt-3 text-sm text-gray-500 leading-relaxed">{item.content}</p>
                    )}
                  </div>

                  <div className="flex items-center gap-3 shrink-0">
                    <span className="text-xs text-gray-400">{item.created_at}</span>
                    <span className="text-gray-300 text-sm">{isOpen ? '▲' : '▼'}</span>
                  </div>
                </button>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
