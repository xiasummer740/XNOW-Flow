import { useState } from 'react'

interface Announcement {
  id: number
  title: string
  content: string
  category: string
  priority: 'high' | 'normal' | 'low'
  author: string
  createdAt: string
  pinned: boolean
}

const mockData: Announcement[] = [
  {
    id: 1, title: '系统升级通知 - 2026年6月25日',
    content: '系统将于 6月25日凌晨 2:00-4:00 进行维护升级，届时无法登录和使用。请提前安排好任务调度。',
    category: '系统公告', priority: 'high', author: '管理员', createdAt: '2026-06-22', pinned: true,
  },
  {
    id: 2, title: '新功能上线：定时任务批量配置',
    content: '现在可以在定时任务中批量配置多个设备的执行计划，支持 CRON 表达式快速设置。',
    category: '功能更新', priority: 'normal', author: '产品部', createdAt: '2026-06-20', pinned: true,
  },
  {
    id: 3, title: '抖音接口变更通知',
    content: '近期抖音 API 进行了更新，部分采集接口可能需要适配。如有异常请及时联系技术支持。',
    category: '系统公告', priority: 'high', author: '技术部', createdAt: '2026-06-18', pinned: false,
  },
  {
    id: 4, title: '月度使用报告（5月）',
    content: '5月平台整体运行稳定，累计执行任务 12,458 次，成功率达 96.3%。详细数据请查看 Dashboard。',
    category: '运营报告', priority: 'normal', author: '运营部', createdAt: '2026-06-05', pinned: false,
  },
  {
    id: 5, title: '账号安全提醒',
    content: '请定期修改密码并开启二次验证。不要将账号借予他人使用，以免造成数据泄露。',
    category: '安全提醒', priority: 'normal', author: '管理员', createdAt: '2026-05-28', pinned: false,
  },
  {
    id: 6, title: '素材管理功能优化',
    content: '素材管理现支持批量上传、预览大图和文件夹分类管理，提升素材管理效率。',
    category: '功能更新', priority: 'low', author: '产品部', createdAt: '2026-05-20', pinned: false,
  },
]

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

export default function Announcements({ token: _token }: { token: string }) {
  const [data] = useState<Announcement[]>(mockData)
  const [expanded, setExpanded] = useState<number | null>(null)

  const sorted = [...data].sort((a, b) => {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
  })

  return (
    <div className="space-y-6">
      <h3 className="text-sm font-medium text-gray-700">公告中心</h3>

      <div className="space-y-3">
        {sorted.length === 0 ? (
          <div className="xx-card rounded-xl flex flex-col items-center justify-center text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📢</div>
            <p className="text-sm text-gray-400">暂无公告</p>
          </div>
        ) : (
          sorted.map(item => {
            const isOpen = expanded === item.id
            return (
              <div key={item.id}
                className={`xx-card rounded-xl transition-all ${
                  item.pinned ? '' : ''
                }`}>
                <button onClick={() => setExpanded(isOpen ? null : item.id)}
                  className="w-full text-left px-5 py-4 flex items-start gap-4 cursor-pointer">
                  {/* 优先级指示 */}
                  <div className={`mt-1 w-2 h-2 rounded-full shrink-0 ${
                    item.priority === 'high' ? 'bg-red-400' : item.priority === 'normal' ? 'bg-blue-400' : 'bg-gray-300'
                  }`} />

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      {item.pinned && (
                        <span className="text-[10px] bg-blue-50 text-blue-500 px-1.5 py-0.5 rounded border border-blue-100">置顶</span>
                      )}
                      <span className={`text-xs px-1.5 py-0.5 rounded border ${priorityStyles[item.priority]}`}>
                        {priorityLabels[item.priority]}
                      </span>
                      <span className="text-xs text-gray-400">{item.category}</span>
                    </div>
                    <h4 className="text-sm font-medium text-gray-800">{item.title}</h4>
                    {isOpen && (
                      <p className="mt-3 text-sm text-gray-500 leading-relaxed">{item.content}</p>
                    )}
                  </div>

                  <div className="flex items-center gap-3 shrink-0">
                    <span className="text-xs text-gray-400">{item.createdAt}</span>
                    <span className="text-gray-300 text-sm">{isOpen ? '▲' : '▼'}</span>
                  </div>
                </button>

                {isOpen && (
                  <div className="px-5 pb-4 pt-0 border-t border-gray-50 mt-0">
                    <div className="flex items-center justify-between pt-3">
                      <span className="text-xs text-gray-400">发布人：{item.author}</span>
                    </div>
                  </div>
                )}
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
