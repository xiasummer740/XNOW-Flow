import { useState, useEffect, useCallback } from 'react'

/* ---- Types ---- */

interface Advert {
  id: number
  title: string
  image_url?: string
  link?: string
  description?: string
  status: string
  created_at?: string
}

/* ---- Constants ---- */

const STATUS_BADGES: Record<string, { label: string; bg: string; text: string }> = {
  active:   { label: '启用', bg: 'rgba(34,197,94,0.10)', text: '#16a34a' },
  disabled: { label: '停用', bg: 'rgba(0,0,0,0.05)',    text: 'rgba(0,0,0,0.35)' },
}

const EMPTY_FORM = { title: '', image_url: '', link: '', description: '' }

/* ---- Helpers ---- */

const formatTime = (iso?: string): string =>
  iso ? new Date(iso).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'

const truncate = (s?: string | null, max = 30): string =>
  s && s.length > max ? s.slice(0, max) + '…' : (s || '—')

/* ---- Component ---- */

export default function AdvertManagement({ token }: { token: string }) {
  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  /* ---- Data state ---- */
  const [adverts, setAdverts] = useState<Advert[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState('')

  /* ---- Form / Modal state ---- */
  const [showModal, setShowModal] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [form, setForm] = useState({ ...EMPTY_FORM })

  /* ---- Data fetching ---- */

  const fetchAdverts = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const r = await fetch('/api/biz/v2/adverts/?limit=100', { headers })
      if (!r.ok) throw new Error('加载失败')
      const d = await r.json()
      setAdverts(d.results || [])
    } catch (err: any) {
      setError(err.message || '加载失败')
      setAdverts([])
    } finally {
      setLoading(false)
    }
  }, [token])

  useEffect(() => {
    fetchAdverts()
  }, [fetchAdverts])

  /* ---- Handlers ---- */

  const openCreate = () => {
    setEditingId(null)
    setForm({ ...EMPTY_FORM })
    setShowModal(true)
  }

  const openEdit = (adv: Advert) => {
    setEditingId(adv.id)
    setForm({
      title: adv.title || '',
      image_url: adv.image_url || '',
      link: adv.link || '',
      description: adv.description || '',
    })
    setShowModal(true)
  }

  const handleSubmit = async () => {
    if (!form.title.trim() || submitting) return
    setSubmitting('save')
    setError('')
    try {
      const url = editingId === null
        ? '/api/biz/v2/adverts/'
        : `/api/biz/v2/adverts/${editingId}/`
      const r = await fetch(url, {
        method: editingId === null ? 'POST' : 'PUT', headers,
        body: JSON.stringify({
          title: form.title.trim(),
          image_url: form.image_url.trim(),
          link: form.link.trim(),
          description: form.description.trim(),
        }),
      })
      if (!r.ok) throw new Error('保存失败')
      setShowModal(false)
      setForm({ ...EMPTY_FORM })
      await fetchAdverts()
    } catch {
      setError(editingId === null ? '创建广告失败' : '更新广告失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleToggle = async (adv: Advert) => {
    if (submitting) return
    const next = adv.status === 'active' ? 'disabled' : 'active'
    setSubmitting('toggle-' + adv.id)
    try {
      const r = await fetch(`/api/biz/v2/adverts/${adv.id}/`, {
        method: 'PUT', headers,
        body: JSON.stringify({ status: next }),
      })
      if (!r.ok) throw new Error('切换失败')
      await fetchAdverts()
    } catch {
      setError('切换状态失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleDelete = async (id: number) => {
    if (submitting) return
    setSubmitting('del-' + id)
    try {
      const r = await fetch(`/api/biz/v2/adverts/${id}/`, { method: 'DELETE', headers })
      if (!r.ok) throw new Error('删除失败')
      await fetchAdverts()
    } catch {
      setError('删除失败')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Derived ---- */

  const stats = {
    total: adverts.length,
    active: adverts.filter(a => a.status === 'active').length,
    disabled: adverts.filter(a => a.status === 'disabled').length,
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

  if (loading && adverts.length === 0) {
    return <div className="flex items-center justify-center h-64" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
  }

  /* ---- Render ---- */

  return (
    <div className="space-y-5">

      {/* ========== 1. 顶部统计 ========== */}
      <div className="grid grid-cols-3 gap-4">
        {[
          { label: '全部广告', val: stats.total, icon: '📣', color: 'rgba(0,0,0,0.70)' },
          { label: '启用中',   val: stats.active, icon: '✅', color: '#16a34a' },
          { label: '已停用',   val: stats.disabled, icon: '⏸️', color: 'rgba(0,0,0,0.35)' },
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
        <button
          onClick={() => { fetchAdverts() }}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
        >
          🔄 刷新
        </button>
        <button
          onClick={openCreate}
          className="px-4 py-2 rounded-lg text-sm font-medium cursor-pointer"
          style={{ background: '#1677FF', color: '#fff' }}
        >
          ＋ 新建广告
        </button>
      </div>

      {/* Error banner */}
      {error && (
        <div className="px-5 py-2 rounded-lg text-xs" style={{ background: 'rgba(239,68,68,0.08)', color: '#dc2626' }}>
          {error}
          <button onClick={() => setError('')} className="ml-2 underline cursor-pointer">关闭</button>
        </div>
      )}

      {/* ========== 3. 广告列表表格 ========== */}
      <div className="xx-card rounded-xl overflow-hidden">
        {adverts.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>📣</div>
            <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>暂无广告</p>
            <button onClick={openCreate} className="mt-3 text-xs underline cursor-pointer" style={{ color: '#1677FF' }}>
              新建广告
            </button>
          </div>
        ) : (
          <>
            <div className="px-5 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
              <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>广告列表</span>
              <span className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>共 {adverts.length} 条</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm whitespace-nowrap">
                <thead>
                  <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                    <th className="pb-2 pt-3 px-4 font-medium">标题</th>
                    <th className="pb-2 pt-3 px-4 font-medium">图片</th>
                    <th className="pb-2 pt-3 px-4 font-medium">链接</th>
                    <th className="pb-2 pt-3 px-4 font-medium">描述</th>
                    <th className="pb-2 pt-3 px-4 font-medium">状态</th>
                    <th className="pb-2 pt-3 px-4 font-medium">创建时间</th>
                    <th className="pb-2 pt-3 px-4 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {adverts.map(a => (
                    <tr key={a.id} className="border-b transition-colors hover:bg-black/[0.02]"
                      style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                      <td className="py-3 px-4 max-w-[180px]" title={a.title}>
                        <span className="text-xs">{a.title || '—'}</span>
                      </td>
                      <td className="py-3 px-4">
                        {a.image_url ? (
                          <img src={a.image_url} alt=""
                            className="w-9 h-9 rounded object-cover"
                            onError={e => { (e.target as HTMLImageElement).style.display = 'none' }} />
                        ) : (
                          <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>
                        )}
                      </td>
                      <td className="py-3 px-4 max-w-[180px]" title={a.link}>
                        {a.link ? (
                          <a href={a.link} target="_blank" rel="noreferrer"
                            className="font-mono text-xs underline" style={{ color: '#1677FF' }}>
                            {truncate(a.link, 22)}
                          </a>
                        ) : (
                          <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>
                        )}
                      </td>
                      <td className="py-3 px-4 max-w-[200px]" title={a.description}>
                        <span className="text-xs">{truncate(a.description, 20) || '—'}</span>
                      </td>
                      <td className="py-3 px-4">{statusBadge(a.status)}</td>
                      <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>
                        {formatTime(a.created_at)}
                      </td>
                      <td className="py-3 px-4">
                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => openEdit(a)}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer"
                            style={{ color: '#1677FF', background: 'rgba(22,119,255,0.08)' }}
                          >
                            编辑
                          </button>
                          <button
                            onClick={() => handleToggle(a)}
                            disabled={submitting === 'toggle-' + a.id}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                            style={{ color: a.status === 'active' ? '#d97706' : '#16a34a', background: a.status === 'active' ? 'rgba(217,119,6,0.08)' : 'rgba(34,197,94,0.08)' }}
                          >
                            {submitting === 'toggle-' + a.id ? '...' : (a.status === 'active' ? '停用' : '启用')}
                          </button>
                          <button
                            onClick={() => handleDelete(a.id)}
                            disabled={submitting === 'del-' + a.id}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                            style={{ color: '#dc2626', background: 'rgba(239,68,68,0.08)' }}
                          >
                            {submitting === 'del-' + a.id ? '删除中...' : '删除'}
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

      {/* ========== 新建/编辑广告 Modal ========== */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowModal(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>
                {editingId === null ? '新建广告' : '编辑广告'}
              </h4>
              <button onClick={() => setShowModal(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>广告标题 *</label>
                <input
                  type="text"
                  value={form.title}
                  onChange={e => setForm({ ...form, title: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="广告标题"
                />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>图片URL</label>
                <input
                  type="text"
                  value={form.image_url}
                  onChange={e => setForm({ ...form, image_url: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="https://example.com/ad.jpg"
                />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>跳转链接</label>
                <input
                  type="text"
                  value={form.link}
                  onChange={e => setForm({ ...form, link: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="https://example.com"
                />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>描述</label>
                <textarea
                  value={form.description}
                  onChange={e => setForm({ ...form, description: e.target.value })}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none resize-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  rows={3}
                  placeholder="广告描述/文案（可选）"
                />
              </div>
              <button
                onClick={handleSubmit}
                disabled={!form.title.trim() || !!submitting}
                className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                {submitting === 'save' ? '保存中...' : (editingId === null ? '创建广告' : '保存修改')}
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  )
}
