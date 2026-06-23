import { useState } from 'react'

interface FeedbackItem {
  id: number
  type: string
  title: string
  content: string
  status: 'pending' | 'processing' | 'resolved' | 'rejected'
  reply?: string
  createdAt: string
  resolvedAt?: string
}

const mockFeedback: FeedbackItem[] = [
  { id: 1, type: '功能建议', title: '建议增加批量导入账号功能', content: '现在一个个加账号太慢了，希望能支持 Excel 批量导入。', status: 'resolved', reply: '感谢您的建议！批量导入功能已在开发中，预计下个版本上线。', createdAt: '2026-06-15', resolvedAt: '2026-06-17' },
  { id: 2, type: 'Bug 反馈', title: '设备管理页面加载缓慢', content: '设备数量超过 50 台时，页面滚动会卡顿。', status: 'processing', createdAt: '2026-06-20' },
  { id: 3, type: '功能建议', title: '希望支持更多数据导出格式', content: '目前只支持 CSV，希望能增加 Excel 和 PDF 格式。', status: 'pending', createdAt: '2026-06-22' },
]

const statusLabels: Record<string, string> = { pending: '待处理', processing: '处理中', resolved: '已解决', rejected: '已驳回' }
const statusColors: Record<string, string> = {
  pending: 'bg-yellow-50 text-yellow-600',
  processing: 'bg-blue-50 text-blue-500',
  resolved: 'bg-green-50 text-green-600',
  rejected: 'bg-gray-50 text-gray-500',
}
const typeColors: Record<string, string> = {
  '功能建议': 'bg-purple-50 text-purple-500',
  'Bug 反馈': 'bg-red-50 text-red-500',
  '使用咨询': 'bg-blue-50 text-blue-500',
  '其他': 'bg-gray-50 text-gray-500',
}

export default function Feedback({ token: _token }: { token: string }) {
  const [list, setList] = useState<FeedbackItem[]>(mockFeedback)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ type: '功能建议', title: '', content: '' })
  const [msg, setMsg] = useState('')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.title || !form.content) { setMsg('请填写完整信息'); return }
    const newItem: FeedbackItem = {
      id: Math.max(...list.map(f => f.id), 0) + 1,
      type: form.type,
      title: form.title,
      content: form.content,
      status: 'pending',
      createdAt: new Date().toISOString().slice(0, 10),
    }
    setList(prev => [newItem, ...prev])
    setForm({ type: '功能建议', title: '', content: '' })
    setShowForm(false)
    setMsg('')
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-700">反馈中心</h3>
        <button onClick={() => setShowForm(!showForm)}
          className="px-4 py-2 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-sm font-medium transition-colors cursor-pointer">
          {showForm ? '取消' : '提交反馈'}
        </button>
      </div>

      {/* 提交表单 */}
      {showForm && (
        <div className="xx-card rounded-xl p-5">
          <h4 className="text-sm font-medium text-gray-700 mb-4">提交反馈</h4>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="text-xs text-gray-400 block mb-1">反馈类型</label>
              <select value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 bg-white">
                <option>功能建议</option>
                <option>Bug 反馈</option>
                <option>使用咨询</option>
                <option>其他</option>
              </select>
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">标题</label>
              <input type="text" value={form.title} onChange={e => setForm({ ...form, title: e.target.value })}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
                placeholder="简洁描述你的问题或建议" />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">详细描述</label>
              <textarea value={form.content} onChange={e => setForm({ ...form, content: e.target.value })}
                rows={4}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 resize-none"
                placeholder="请详细描述..." />
            </div>
            {msg && <div className="text-red-500 text-xs">{msg}</div>}
            <button type="submit"
              className="px-6 py-2 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-sm font-medium transition-colors cursor-pointer">
              提交
            </button>
          </form>
        </div>
      )}

      {/* 反馈列表 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700">历史反馈</span>
          <span className="text-xs text-gray-400">共 {list.length} 条</span>
        </div>
        {list.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">💬</div>
            <p className="text-sm text-gray-400">暂无反馈记录</p>
          </div>
        ) : (
          <div className="divide-y divide-gray-50">
            {list.map(item => (
              <div key={item.id} className="px-5 py-4">
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className={`text-xs px-2 py-0.5 rounded ${typeColors[item.type] || 'bg-gray-50 text-gray-500'}`}>
                      {item.type}
                    </span>
                    <span className={`text-xs px-2 py-0.5 rounded ${statusColors[item.status]}`}>
                      {statusLabels[item.status]}
                    </span>
                  </div>
                  <span className="text-xs text-gray-400">{item.createdAt}</span>
                </div>
                <h4 className="text-sm font-medium text-gray-700 mb-1">{item.title}</h4>
                <p className="text-xs text-gray-500">{item.content}</p>
                {item.reply && (
                  <div className="mt-3 pl-3 border-l-2 border-blue-200">
                    <p className="text-xs text-blue-600 font-medium mb-0.5">官方回复：</p>
                    <p className="text-xs text-gray-500">{item.reply}</p>
                    {item.resolvedAt && <p className="text-[10px] text-gray-400 mt-1">回复于 {item.resolvedAt}</p>}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
