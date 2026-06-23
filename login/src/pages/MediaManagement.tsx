import { useState, useEffect, useRef } from 'react'

interface MediaItem {
  id: number
  filename: string
  original_name: string
  file_type: string
  file_size: number
  url: string
  created_at: string
}

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

function formatSize(bytes: number): string {
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
}

function inferDisplayType(fileType: string): 'image' | 'video' | 'file' {
  const t = fileType.toLowerCase()
  if (t.startsWith('image')) return 'image'
  if (t.startsWith('video')) return 'video'
  return 'file'
}

export default function MediaManagement({ token }: { token: string }) {
  const [media, setMedia] = useState<MediaItem[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState<'all' | 'image' | 'video' | 'file'>('all')
  const [dragging, setDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const headers = { 'Authorization': `Token ${token}` }

  const fetchMedia = async () => {
    try {
      const res = await fetch('/api/biz/v2/media/', { headers })
      if (!res.ok) throw new Error('Failed to fetch')
      const data = await res.json()
      setMedia(data)
    } catch {
      // ignore
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchMedia() }, [])

  const uploadFile = async (file: File) => {
    const formData = new FormData()
    formData.append('file', file)
    try {
      await fetch('/api/biz/v2/media/upload/', {
        method: 'POST',
        headers: { 'Authorization': `Token ${token}` },
        body: formData,
      })
      await fetchMedia()
    } catch {
      // ignore
    }
  }

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setDragging(false)
    const file = e.dataTransfer.files[0]
    if (file) uploadFile(file)
  }

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) uploadFile(file)
    e.target.value = ''
  }

  const filtered = filter === 'all' ? media : media.filter(m => inferDisplayType(m.file_type) === filter)

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
        onDrop={handleDrop}
        onClick={() => fileInputRef.current?.click()}
        className={`border-2 border-dashed rounded-xl p-8 text-center transition-colors cursor-pointer ${
          dragging ? 'border-blue-400 bg-blue-50' : 'border-gray-200 hover:border-gray-300 bg-white'
        }`}>
        <input ref={fileInputRef} type="file" className="hidden" onChange={handleFileSelect} />
        <div className="text-3xl mb-2">📤</div>
        <p className="text-sm text-gray-500 mb-1">
          {dragging ? '松开鼠标上传文件' : '拖拽文件到此处上传'}
        </p>
        <p className="text-xs text-gray-400">支持 JPG、PNG、MP4、CSV 等格式</p>
        <button type="button" className="mt-3 px-4 py-2 bg-[#1677FF] hover:bg-blue-600 text-white rounded-lg text-xs font-medium transition-colors cursor-pointer">
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
        {loading ? (
          <div className="col-span-full flex items-center justify-center py-16">
            <div className="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="col-span-full flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">📦</div>
            <p className="text-sm text-gray-400">暂无素材文件</p>
          </div>
        ) : (
          filtered.map(item => {
            const displayType = inferDisplayType(item.file_type)
            return (
              <div key={item.id}
                className="xx-card rounded-xl overflow-hidden transition-all group cursor-pointer">
                <div className={`h-28 flex items-center justify-center ${typeColors[displayType]} bg-opacity-20`}>
                  <span className="text-4xl">{typeIcons[displayType]}</span>
                </div>
                <div className="p-3">
                  <p className="text-xs text-gray-700 truncate">{item.original_name || item.filename}</p>
                  <div className="flex items-center justify-between mt-1">
                    <span className="text-[10px] text-gray-400">{formatSize(item.file_size)}</span>
                    <span className="text-[10px] text-gray-400">{item.created_at}</span>
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
