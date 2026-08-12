import { useState, useEffect, useCallback } from 'react'

/* ---- Types ---- */

interface VideoPost {
  id: number
  device_id: string
  video_url: string
  title: string
  category: string
  status: string
  scheduled_at?: string | null
  result?: string | null
  created_at?: string
}

interface Device {
  id: number
  device_id: string
  device_name?: string
  name?: string
}

/* ---- Constants ---- */

const STATUS_BADGES: Record<string, { label: string; bg: string; text: string }> = {
  pending:    { label: '待发布', bg: 'rgba(168,85,247,0.10)', text: '#9333ea' },
  processing: { label: '发布中', bg: 'rgba(59,130,246,0.10)', text: '#2563eb' },
  done:       { label: '已完成', bg: 'rgba(34,197,94,0.10)', text: '#16a34a' },
  failed:     { label: '失败',   bg: 'rgba(239,68,68,0.10)', text: '#dc2626' },
}

/* ---- Helpers ---- */

const formatTime = (iso?: string): string =>
  iso ? new Date(iso).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'

const truncate = (s?: string | null, max = 30): string =>
  s && s.length > max ? s.slice(0, max) + '…' : (s || '—')

/* ---- Component ---- */

export default function VideoManagement({ token }: { token: string }) {
  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  /* ---- Data state ---- */
  const [posts, setPosts] = useState<VideoPost[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [submitting, setSubmitting] = useState('')

  /* ---- Create form state ---- */
  const [showCreate, setShowCreate] = useState(false)
  const [formDevice, setFormDevice] = useState('')
  const [formUrl, setFormUrl] = useState('')
  const [formTitle, setFormTitle] = useState('')

  /* ---- Data fetching ---- */

  const fetchPosts = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const r = await fetch('/api/biz/v2/video-posts/?limit=100', { headers })
      if (!r.ok) throw new Error('加载失败')
      const d = await r.json()
      setPosts(d.results || [])
    } catch (err: any) {
      setError(err.message || '加载失败')
      setPosts([])
    } finally {
      setLoading(false)
    }
  }, [token])

  const fetchDevices = useCallback(async () => {
    try {
      const r = await fetch('/api/biz/v2/device-bindings/?limit=100', { headers })
      if (r.ok) {
        const d = await r.json()
        setDevices(d.results || [])
      }
    } catch { /* non-critical */ }
  }, [token])

  useEffect(() => {
    fetchPosts()
    fetchDevices()
  }, [fetchPosts, fetchDevices])

  const deviceName = (deviceId: string) => {
    const dev = devices.find(d => d.device_id === deviceId)
    return dev ? (dev.device_name || dev.name || deviceId) : deviceId
  }

  /* ---- Handlers ---- */

  const handleCreate = async () => {
    if (!formDevice || submitting) return
    if (!formUrl.trim() && !formTitle.trim()) {
      setError('视频URL 和标题至少填一个')
      return
    }
    setSubmitting('create')
    setError('')
    try {
      const r = await fetch('/api/biz/v2/video-posts/', {
        method: 'POST', headers,
        body: JSON.stringify({ device_id: formDevice, video_url: formUrl.trim(), title: formTitle.trim() }),
      })
      if (!r.ok) throw new Error('创建失败')
      setShowCreate(false)
      setFormDevice('')
      setFormUrl('')
      setFormTitle('')
      await fetchPosts()
    } catch {
      setError('创建发布任务失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleDispatch = async (id: number) => {
    if (submitting) return
    setSubmitting('dispatch-' + id)
    setNotice('')
    setError('')
    try {
      const r = await fetch(`/api/biz/v2/video-posts/${id}/dispatch/`, { method: 'POST', headers })
      if (!r.ok) throw new Error('下发失败')
      const d = await r.json()
      setNotice(d.message || '发视频指令已下发')
      await fetchPosts()
    } catch {
      setError('下发失败，请重试')
    } finally {
      setSubmitting('')
    }
  }

  const handleDelete = async (id: number) => {
    if (submitting) return
    setSubmitting('del-' + id)
    try {
      const r = await fetch(`/api/biz/v2/video-posts/${id}/`, { method: 'DELETE', headers })
      if (!r.ok) throw new Error('删除失败')
      await fetchPosts()
    } catch {
      setError('删除失败')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Derived ---- */

  const stats = {
    total: posts.length,
    pending: posts.filter(p => p.status === 'pending').length,
    processing: posts.filter(p => p.status === 'processing').length,
    done: posts.filter(p => p.status === 'done').length,
    failed: posts.filter(p => p.status === 'failed').length,
  }

  const statusBadge = (s: string) => {
    const cfg = STATUS_BADGES[s] || { label: s || '—', bg: 'rgba(0,0,0,0.05)', text: 'rgba(0,0,0,0.35)' }
    return (
      <span className="inline-flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full" style={{ background: cfg.bg, color: cfg.text }}>
        <span className="w-1.5 h-1.5 rounded-full" style={{ background: cfg.text }} />
        {cfg.label}
      </span>
    )
  }

  /* ---- Loading ---- */

  if (loading && posts.length === 0) {
    return <div className="flex items-center justify-center h-64" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
  }

  /* ---- Render ---- */

  return (
    <div className="space-y-5">

      {/* ========== 1. 顶部统计 ========== */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
        {[
          { label: '全部发布', val: stats.total, icon: '🎬', color: 'rgba(0,0,0,0.70)' },
          { label: '待发布',   val: stats.pending, icon: '🕒', color: '#9333ea' },
          { label: '发布中',   val: stats.processing, icon: '🔄', color: '#2563eb' },
          { label: '已完成',   val: stats.done, icon: '✅', color: '#16a34a' },
          { label: '失败',     val: stats.failed, icon: '❌', color: '#dc2626' },
        ].map(s => (
          <div key={s.label} className="xx-card rounded-xl p-4 flex items-center justify-between">
            <div>
              <div className="text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>{s.label}</div>
              <div className="text-2xl font-bold mt-0.5" style={{ color: s.color }}>{s.val}</div>
            </div>
            <span className="text-xl">{s.icon}</span>
          </div>
        ))}
      </div>

      {/* ========== 2. 工具栏 ========== */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <button
            onClick={() => { fetchPosts() }}
            className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
            style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
          >
            🔄 刷新
          </button>
        </div>
        <button
          onClick={() => { setFormDevice(''); setFormUrl(''); setFormTitle(''); setShowCreate(true) }}
          className="px-4 py-2 rounded-lg text-sm font-medium cursor-pointer"
          style={{ background: '#1677FF', color: '#fff' }}
        >
          ＋ 新建发布
        </button>
      </div>

      {/* Notice / Error banners */}
      {notice && (
        <div className="px-5 py-2 rounded-lg text-xs" style={{ background: 'rgba(34,197,94,0.08)', color: '#16a34a' }}>
          {notice}
          <button onClick={() => setNotice('')} className="ml-2 underline cursor-pointer">关闭</button>
        </div>
      )}
      {error && (
        <div className="px-5 py-2 rounded-lg text-xs" style={{ background: 'rgba(239,68,68,0.08)', color: '#dc2626' }}>
          {error}
          <button onClick={() => setError('')} className="ml-2 underline cursor-pointer">关闭</button>
        </div>
      )}

      {/* ========== 3. 视频发布记录表格 ========== */}
      <div className="xx-card rounded-xl overflow-hidden">
        {posts.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>🎬</div>
            <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>暂无发布记录</p>
            <button onClick={() => setShowCreate(true)} className="mt-3 text-xs underline cursor-pointer" style={{ color: '#1677FF' }}>
              新建发布任务
            </button>
          </div>
        ) : (
          <>
            <div className="px-5 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
              <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>发布记录</span>
              <span className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>共 {posts.length} 条</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm whitespace-nowrap">
                <thead>
                  <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                    <th className="pb-2 pt-3 px-4 font-medium">视频URL</th>
                    <th className="pb-2 pt-3 px-4 font-medium">标题</th>
                    <th className="pb-2 pt-3 px-4 font-medium">设备</th>
                    <th className="pb-2 pt-3 px-4 font-medium">状态</th>
                    <th className="pb-2 pt-3 px-4 font-medium">创建时间</th>
                    <th className="pb-2 pt-3 px-4 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {posts.map(p => (
                    <tr key={p.id} className="border-b transition-colors hover:bg-black/[0.02]"
                      style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                      <td className="py-3 px-4 max-w-[220px]" title={p.video_url}>
                        {p.video_url ? (
                          <a href={p.video_url} target="_blank" rel="noreferrer"
                            className="font-mono text-xs underline" style={{ color: '#1677FF' }}>
                            {truncate(p.video_url, 26)}
                          </a>
                        ) : (
                          <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>
                        )}
                      </td>
                      <td className="py-3 px-4 max-w-[200px]" title={p.title}>
                        <span className="text-xs">{p.title || '—'}</span>
                      </td>
                      <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                        {p.device_id ? truncate(deviceName(p.device_id), 18) : '—'}
                      </td>
                      <td className="py-3 px-4">{statusBadge(p.status)}</td>
                      <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>
                        {formatTime(p.created_at)}
                      </td>
                      <td className="py-3 px-4">
                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => handleDispatch(p.id)}
                            disabled={!!submitting || p.status === 'processing' || p.status === 'done'}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-40"
                            style={{ color: '#1677FF', background: 'rgba(22,119,255,0.08)' }}
                          >
                            {submitting === 'dispatch-' + p.id ? '下发中...' : '立即发布'}
                          </button>
                          <button
                            onClick={() => handleDelete(p.id)}
                            disabled={submitting === 'del-' + p.id}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                            style={{ color: '#dc2626', background: 'rgba(239,68,68,0.08)' }}
                          >
                            {submitting === 'del-' + p.id ? '删除中...' : '删除'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      {/* ========== 新建发布 Modal ========== */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowCreate(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>新建发布任务</h4>
              <button onClick={() => setShowCreate(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>选择设备 *</label>
                <select
                  value={formDevice}
                  onChange={e => setFormDevice(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none cursor-pointer"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}
                >
                  <option value="">请选择设备</option>
                  {devices.map(dev => (
                    <option key={dev.id} value={dev.device_id}>
                      {dev.device_name || dev.name || dev.device_id}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>视频URL</label>
                <input
                  type="text"
                  value={formUrl}
                  onChange={e => setFormUrl(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="https://example.com/video.mp4"
                />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>标题</label>
                <input
                  type="text"
                  value={formTitle}
                  onChange={e => setFormTitle(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="视频标题（可选）"
                />
              </div>
              <p className="text-xs" style={{ color: 'rgba(0,0,0,0.30)' }}>视频URL 和标题至少填一个</p>
              <button
                onClick={handleCreate}
                disabled={!formDevice || (!formUrl.trim() && !formTitle.trim()) || !!submitting}
                className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                {submitting === 'create' ? '创建中...' : '创建任务'}
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  )
}
