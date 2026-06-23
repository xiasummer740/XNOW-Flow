import { useState } from 'react'

interface ReplyTemplate {
  id: number
  name: string
  content: string
  matchType: 'keyword' | 'regex' | 'all'
  matchValue: string
  enabled: boolean
  platforms: string[]
  usageCount: number
}

const mockTemplates: ReplyTemplate[] = [
  { id: 1, name: '感谢关注', content: '感谢您的关注！如有任何问题欢迎私信咨询。', matchType: 'keyword', matchValue: '你好,您好,hi', enabled: true, platforms: ['抖音', 'TikTok'], usageCount: 245 },
  { id: 2, name: '产品咨询', content: '感谢您的咨询！我们的产品详情请查看主页链接，或私信获取更多信息。', matchType: 'keyword', matchValue: '多少钱,价格,怎么买', enabled: true, platforms: ['抖音'], usageCount: 189 },
  { id: 3, name: '合作咨询', content: '感谢您的合作意向！请私信留下联系方式，我们的商务人员会尽快与您取得联系。', matchType: 'regex', matchValue: '合作|商务|推广', enabled: true, platforms: ['抖音', 'TikTok'], usageCount: 67 },
  { id: 4, name: '默认回复', content: '感谢您的留言，我们会尽快回复您！', matchType: 'all', matchValue: '', enabled: false, platforms: ['抖音'], usageCount: 34 },
]

const platformColors: Record<string, string> = {
  '抖音': 'bg-red-50 text-red-500',
  'TikTok': 'bg-blue-50 text-blue-500',
}

export default function ReplyConfig({ token: _token }: { token: string }) {
  const [templates, setTemplates] = useState<ReplyTemplate[]>(mockTemplates)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [editForm, setEditForm] = useState<ReplyTemplate | null>(null)

  const toggleEnabled = (id: number) => {
    setTemplates(prev => prev.map(t => t.id === id ? { ...t, enabled: !t.enabled } : t))
  }

  const startEdit = (t: ReplyTemplate) => {
    setEditingId(t.id)
    setEditForm({ ...t })
  }

  const saveEdit = () => {
    if (!editForm) return
    setTemplates(prev => prev.map(t => t.id === editForm.id ? editForm : t))
    setEditingId(null)
    setEditForm(null)
  }

  return (
    <div className="space-y-6">
      <h3 className="text-sm font-medium text-gray-700">回复配置</h3>

      {/* 配置概览 */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {[
          { label: '回复模板', val: templates.length, icon: '📝', bg: 'bg-blue-50 text-blue-600' },
          { label: '已启用', val: templates.filter(t => t.enabled).length, icon: '✅', bg: 'bg-green-50 text-green-600' },
          { label: '总回复次数', val: templates.reduce((s, t) => s + t.usageCount, 0), icon: '📊', bg: 'bg-purple-50 text-purple-600' },
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

      {/* 模板列表 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100">
          <span className="text-sm font-medium text-gray-700">自动回复模板</span>
        </div>
        {templates.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">⚙️</div>
            <p className="text-sm text-gray-400">暂无回复配置</p>
          </div>
        ) : (
          <div className="divide-y divide-gray-50">
            {templates.map(t => (
              <div key={t.id} className="px-5 py-4">
                {editingId === t.id && editForm ? (
                  /* 编辑模式 */
                  <div className="space-y-3">
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="text-xs text-gray-400 block mb-1">模板名称</label>
                        <input type="text" value={editForm.name} onChange={e => setEditForm({ ...editForm, name: e.target.value })}
                          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-xs outline-none focus:border-blue-400" />
                      </div>
                      <div>
                        <label className="text-xs text-gray-400 block mb-1">匹配方式</label>
                        <select value={editForm.matchType} onChange={e => setEditForm({ ...editForm, matchType: e.target.value as any })}
                          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-xs outline-none focus:border-blue-400 bg-white">
                          <option value="keyword">关键词匹配</option>
                          <option value="regex">正则匹配</option>
                          <option value="all">全部匹配</option>
                        </select>
                      </div>
                    </div>
                    {editForm.matchType !== 'all' && (
                      <div>
                        <label className="text-xs text-gray-400 block mb-1">匹配值</label>
                        <input type="text" value={editForm.matchValue} onChange={e => setEditForm({ ...editForm, matchValue: e.target.value })}
                          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-xs outline-none focus:border-blue-400"
                          placeholder="多个关键词用逗号分隔" />
                      </div>
                    )}
                    <div>
                      <label className="text-xs text-gray-400 block mb-1">回复内容</label>
                      <textarea value={editForm.content} onChange={e => setEditForm({ ...editForm, content: e.target.value })}
                        rows={3}
                        className="w-full border border-gray-200 rounded-lg px-3 py-2 text-xs outline-none focus:border-blue-400 resize-none" />
                    </div>
                    <div className="flex gap-2">
                      <button onClick={saveEdit}
                        className="px-4 py-1.5 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-xs font-medium transition-colors cursor-pointer">
                        保存
                      </button>
                      <button onClick={() => setEditingId(null)}
                        className="px-4 py-1.5 border border-gray-200 text-gray-600 rounded-lg text-xs font-medium hover:bg-gray-50 transition-colors cursor-pointer">
                        取消
                      </button>
                    </div>
                  </div>
                ) : (
                  /* 展示模式 */
                  <div className="flex items-start justify-between">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-medium text-gray-700">{t.name}</span>
                        <span className={`text-[10px] px-1.5 py-0.5 rounded bg-gray-50 text-gray-500`}>
                          {t.matchType === 'keyword' ? '关键词' : t.matchType === 'regex' ? '正则' : '全部'}
                        </span>
                        {t.matchType !== 'all' && (
                          <code className="text-[10px] text-blue-500 bg-blue-50 px-1.5 py-0.5 rounded">{t.matchValue}</code>
                        )}
                      </div>
                      <p className="text-xs text-gray-500 mb-1">{t.content}</p>
                      <div className="flex items-center gap-2">
                        <div className="flex gap-1">
                          {t.platforms.map(p => (
                            <span key={p} className={`text-[10px] px-1.5 py-0.5 rounded ${platformColors[p] || 'bg-gray-50 text-gray-500'}`}>
                              {p}
                            </span>
                          ))}
                        </div>
                        <span className="text-[10px] text-gray-400">已使用 {t.usageCount} 次</span>
                      </div>
                    </div>
                    <div className="flex items-center gap-3 ml-4">
                      <button onClick={() => startEdit(t)}
                        className="text-xs text-gray-400 hover:text-blue-500 transition-colors cursor-pointer">编辑</button>
                      <button onClick={() => toggleEnabled(t.id)}
                        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors cursor-pointer ${
                          t.enabled ? 'bg-green-400' : 'bg-gray-200'
                        }`}>
                        <span className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white transition-transform shadow-sm ${
                          t.enabled ? 'translate-x-[18px]' : 'translate-x-[2px]'
                        }`} />
                      </button>
                    </div>
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
