import { useState } from 'react'

interface MediaItem {
  id: number
  name: string
  type: 'image' | 'video' | 'file'
  size: string
  createdAt: string
  url: string
}

const mockMedia: MediaItem[] = [
  { id: 1, name: 'product_01.jpg', type: 'image', size: '234 KB', createdAt: '2026-06-20', url: '' },
  { id: 2, name: 'product_02.jpg', type: 'image', size: '189 KB', createdAt: '2026-06-20', url: '' },
  { id: 3, name: 'banner_main.jpg', type: 'image', size: '512 KB', createdAt: '2026-06-19', url: '' },
  { id: 4, name: 'intro_video.mp4', type: 'video', size: '12.3 MB', createdAt: '2026-06-18', url: '' },
  { id: 5, name: 'avatar_template.png', type: 'image', size: '45 KB', createdAt: '2026-06-17', url: '' },
  { id: 6, name: 'data_export.csv', type: 'file', size: '1.2 MB', createdAt: '2026-06-16', url: '' },
  { id: 7, name: 'screenshot_01.png', type: 'image', size: '678 KB', createdAt: '2026-06-15', url: '' },
  { id: 8, name: 'tutorial_video.mp4', type: 'video', size: '45.6 MB', createdAt: '2026-06-14', url: '' },
]

const typeIcons: Record<string, string> = {
  image: '🖼️',
  video: '🎬',
  file: '📄',
}

const typeColors: Record<string, string> = {
  image: 'bg-blue-50 text-blue-500',
  video: 'bg-purple-50 text-purple-500',
  file: 'bg-gray-50 text-gray-500',
}

export default function MediaManagement({ token: _token }: { token: string }) {
  const [media] = useState<MediaItem[]>(mockMedia)
  const [filter, setFilter] = useState<'all' | 'image' | 'video' | 'file'>('all')
  const [dragging, setDragging] = useState(false)

  const filtered = filter === 'all' ? media : media.filter(m => m.type === filter)

  const filters = [
    { key: 'all' as const, label: '全部' },
    { key: 'image' as const, label: '图片' },
    { key: 'video' as const, label: '视频' },
    { key: 'file' as const, label: '文件' },
  ]

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-700">素材管理</h3>
        <span className="text-xs text-gray-400">共 {media.length} 个文件</span>
      </div>

      {/* 上传区域 */}
      <div
        onDragOver={e => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={e => { e.preventDefault(); setDragging(false) }}
        className={`border-2 border-dashed rounded-xl p-8 text-center transition-colors cursor-pointer ${
          dragging ? 'border-blue-400 bg-blue-50' : 'border-gray-200 hover:border-gray-300 bg-white'
        }`}>
        <div className="text-3xl mb-2">📤</div>
        <p className="text-sm text-gray-500 mb-1">
          {dragging ? '松开鼠标上传文件' : '拖拽文件到此处上传'}
        </p>
        <p className="text-xs text-gray-400">支持 JPG、PNG、MP4、CSV 等格式</p>
        <button className="mt-3 px-4 py-2 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-xs font-medium transition-colors cursor-pointer">
          选择文件
        </button>
      </div>

      {/* 过滤 */}
      <div className="flex gap-1 bg-gray-100 rounded-lg p-0.5 w-fit">
        {filters.map(f => (
          <button key={f.key}
            onClick={() => setFilter(f.key)}
            className={`px-3 py-1 text-xs rounded-md transition-colors cursor-pointer ${
              filter === f.key ? 'bg-white text-gray-700 shadow-sm' : 'text-gray-500 hover:text-gray-700'
            }`}>
            {f.label}
          </button>
        ))}
      </div>

      {/* 素材网格 */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-5 gap-4">
        {filtered.length === 0 ? (
          <div className="col-span-full flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📦</div>
            <p className="text-sm text-gray-400">暂无素材文件</p>
          </div>
        ) : (
          filtered.map(item => (
            <div key={item.id}
              className="xx-card rounded-xl overflow-hidden transition-all group cursor-pointer">
              <div className={`h-28 flex items-center justify-center ${typeColors[item.type]} bg-opacity-20`}>
                <span className="text-4xl">{typeIcons[item.type]}</span>
              </div>
              <div className="p-3">
                <p className="text-xs text-gray-700 truncate">{item.name}</p>
                <div className="flex items-center justify-between mt-1">
                  <span className="text-[10px] text-gray-400">{item.size}</span>
                  <span className="text-[10px] text-gray-400">{item.createdAt}</span>
                </div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  )
}
