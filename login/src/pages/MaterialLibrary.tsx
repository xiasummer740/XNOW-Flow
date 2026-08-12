import { useState, useEffect, useCallback } from 'react'

/* ---- Types ---- */

interface MaterialGroup {
  id: number
  name: string
  category: string
  description?: string
  item_count: number
  created_at?: string
}

interface MaterialItem {
  id: number
  group_id: number
  category: string
  content: string
  image_url?: string
  used_count?: number
  created_at?: string
}

/* ---- Constants ---- */

const CATEGORIES = [
  { key: 'avatar',    category: 'avatar',    label: '头像素材', icon: '🖼️' },
  { key: 'nickname',  category: 'nickname',  label: '昵称管理', icon: '🏷️' },
  { key: 'signature', category: 'signature', label: '签名管理', icon: '✍️' },
  { key: 'ad_link',   category: 'link_ad',   label: '广告链接', icon: '📢' },
  { key: 'site_link', category: 'link_site', label: '网站链接', icon: '🌐' },
]

/* ---- Helpers ---- */

const formatTime = (iso?: string): string =>
  iso ? new Date(iso).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'

/* ---- Component ---- */

export default function MaterialLibrary({ token }: { token: string }) {
  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  /* ---- Category state ---- */
  const [activeKey, setActiveKey] = useState(CATEGORIES[0].key)
  const activeCat = CATEGORIES.find(c => c.key === activeKey) ?? CATEGORIES[0]

  /* ---- Data state ---- */
  const [groups, setGroups] = useState<MaterialGroup[]>([])
  const [selectedGroupId, setSelectedGroupId] = useState<number | null>(null)
  const [materials, setMaterials] = useState<MaterialItem[]>([])
  const [loading, setLoading] = useState(true)
  const [loadingItems, setLoadingItems] = useState(false)
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState('')

  /* ---- Modal state ---- */
  const [showAddGroup, setShowAddGroup] = useState(false)
  const [showAddMaterial, setShowAddMaterial] = useState(false)
  const [showBatchImport, setShowBatchImport] = useState(false)

  /* ---- Form state ---- */
  const [newGroupName, setNewGroupName] = useState('')
  const [newGroupDesc, setNewGroupDesc] = useState('')
  const [newContent, setNewContent] = useState('')
  const [newImageUrl, setNewImageUrl] = useState('')
  const [batchText, setBatchText] = useState('')

  /* ---- Data fetching ---- */

  const fetchGroups = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const r = await fetch(`/api/biz/v2/material-groups/?category=${activeCat.category}`, { headers })
      if (!r.ok) throw new Error('加载分组失败')
      const d = await r.json()
      const list: MaterialGroup[] = d.results || []
      setGroups(list)
      setSelectedGroupId(prev => (list.some(g => g.id === prev) ? prev : null))
    } catch (err: any) {
      setError(err.message || '加载失败')
      setGroups([])
      setSelectedGroupId(null)
    } finally {
      setLoading(false)
    }
  }, [token, activeCat.category])

  const fetchMaterials = useCallback(async () => {
    if (selectedGroupId === null) {
      setMaterials([])
      setLoadingItems(false)
      return
    }
    setLoadingItems(true)
    setError('')
    try {
      const r = await fetch(`/api/biz/v2/materials/?group_id=${selectedGroupId}&limit=200`, { headers })
      if (!r.ok) throw new Error('加载素材失败')
      const d = await r.json()
      setMaterials(d.results || [])
    } catch (err: any) {
      setError(err.message || '加载素材失败')
      setMaterials([])
    } finally {
      setLoadingItems(false)
    }
  }, [token, selectedGroupId])

  useEffect(() => {
    fetchGroups()
  }, [fetchGroups])

  useEffect(() => {
    fetchMaterials()
  }, [fetchMaterials])

  /* ---- Handlers ---- */

  const handleAddGroup = async () => {
    if (!newGroupName.trim() || submitting) return
    setSubmitting('add-group')
    try {
      const r = await fetch('/api/biz/v2/material-groups/', {
        method: 'POST', headers,
        body: JSON.stringify({ name: newGroupName.trim(), category: activeCat.category, description: newGroupDesc.trim() }),
      })
      if (!r.ok) throw new Error('创建分组失败')
      setNewGroupName('')
      setNewGroupDesc('')
      setShowAddGroup(false)
      await fetchGroups()
    } catch {
      setError('创建分组失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleDeleteGroup = async (id: number) => {
    if (submitting) return
    setSubmitting('del-group-' + id)
    try {
      const r = await fetch(`/api/biz/v2/material-groups/${id}/`, { method: 'DELETE', headers })
      if (!r.ok) throw new Error('删除分组失败')
      await fetchGroups()
    } catch {
      setError('删除分组失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleAddMaterial = async () => {
    if (!newContent.trim() || selectedGroupId === null || submitting) return
    setSubmitting('add-material')
    try {
      const r = await fetch('/api/biz/v2/materials/', {
        method: 'POST', headers,
        body: JSON.stringify({ group_id: selectedGroupId, category: activeCat.category, content: newContent.trim(), image_url: newImageUrl.trim() }),
      })
      if (!r.ok) throw new Error('新增素材失败')
      setNewContent('')
      setNewImageUrl('')
      setShowAddMaterial(false)
      await fetchMaterials()
      await fetchGroups()
    } catch {
      setError('新增素材失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleBatchImport = async () => {
    const contents = batchText.split('\n').map(s => s.trim()).filter(Boolean)
    if (contents.length === 0 || selectedGroupId === null || submitting) return
    setSubmitting('batch-import')
    try {
      const r = await fetch('/api/biz/v2/materials/batch/', {
        method: 'POST', headers,
        body: JSON.stringify({ group_id: selectedGroupId, category: activeCat.category, contents }),
      })
      if (!r.ok) throw new Error('批量导入失败')
      setBatchText('')
      setShowBatchImport(false)
      await fetchMaterials()
      await fetchGroups()
    } catch {
      setError('批量导入失败')
    } finally {
      setSubmitting('')
    }
  }

  const handleDeleteMaterial = async (id: number) => {
    if (submitting) return
    setSubmitting('del-mat-' + id)
    try {
      const r = await fetch(`/api/biz/v2/materials/${id}/`, { method: 'DELETE', headers })
      if (!r.ok) throw new Error('删除素材失败')
      await fetchMaterials()
      await fetchGroups()
    } catch {
      setError('删除素材失败')
    } finally {
      setSubmitting('')
    }
  }

  const selectedGroup = groups.find(g => g.id === selectedGroupId)

  /* ---- Render ---- */

  return (
    <div className="space-y-5">

      {/* ========== 1. 分类切换标签 ========== */}
      <div className="flex flex-wrap gap-1 bg-gray-100 rounded-lg p-0.5 w-fit">
        {CATEGORIES.map(c => (
          <button
            key={c.key}
            onClick={() => setActiveKey(c.key)}
            className={`px-3 py-1.5 text-xs rounded-md transition-colors cursor-pointer ${
              activeKey === c.key ? 'bg-white text-gray-700 shadow-sm' : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            <span className="mr-1">{c.icon}</span>{c.label}
          </button>
        ))}
      </div>

      {/* Error banner */}
      {error && (
        <div className="px-5 py-2 rounded-lg text-xs" style={{ background: 'rgba(239,68,68,0.08)', color: '#dc2626' }}>
          {error}
          <button onClick={() => setError('')} className="ml-2 underline cursor-pointer">关闭</button>
        </div>
      )}

      {/* ========== 2. 分组列表 + 素材条目 ========== */}
      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4 items-start">

        {/* 左：分组列表 */}
        <div className="lg:col-span-1 xx-card rounded-xl overflow-hidden">
          <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
            <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>分组列表</span>
            <button
              onClick={() => setShowAddGroup(true)}
              className="text-xs px-2 py-1 rounded cursor-pointer"
              style={{ background: 'rgba(22,119,255,0.10)', color: '#1677FF' }}
            >
              ＋ 新增分组
            </button>
          </div>
          <div className="max-h-[440px] overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-14" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
            ) : groups.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-14 text-center">
                <div className="w-12 h-12 rounded-full flex items-center justify-center mb-2 text-xl" style={{ background: 'rgba(0,0,0,0.04)' }}>🗂️</div>
                <p className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>暂无分组，先创建分组</p>
                <button onClick={() => setShowAddGroup(true)} className="mt-2 text-xs underline cursor-pointer" style={{ color: '#1677FF' }}>创建分组</button>
              </div>
            ) : (
              groups.map(g => {
                const isActive = selectedGroupId === g.id
                return (
                  <div
                    key={g.id}
                    onClick={() => setSelectedGroupId(g.id)}
                    className={`flex items-center justify-between px-4 py-3 border-b transition-colors cursor-pointer ${
                      isActive ? 'bg-[#1677FF]/[0.06]' : 'hover:bg-black/[0.02]'
                    }`}
                    style={{ borderColor: 'rgba(0,0,0,0.04)' }}
                  >
                    <div className="min-w-0 pr-2">
                      <div className="text-sm truncate" style={{ color: isActive ? '#1677FF' : 'rgba(0,0,0,0.65)' }}>{g.name}</div>
                      {g.description && (
                        <div className="text-xs truncate" style={{ color: 'rgba(0,0,0,0.30)' }}>{g.description}</div>
                      )}
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.45)' }}>
                        {g.item_count}
                      </span>
                      <button
                        onClick={e => { e.stopPropagation(); handleDeleteGroup(g.id) }}
                        disabled={submitting === 'del-group-' + g.id}
                        className="text-xs cursor-pointer disabled:opacity-50"
                        style={{ color: 'rgba(0,0,0,0.25)' }}
                        title="删除分组"
                      >
                        {submitting === 'del-group-' + g.id ? '...' : '✕'}
                      </button>
                    </div>
                  </div>
                )
              })
            )}
          </div>
        </div>

        {/* 右：素材条目列表 */}
        <div className="lg:col-span-3 xx-card rounded-xl overflow-hidden">
          <div className="px-5 py-3 border-b flex items-center justify-between flex-wrap gap-2" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
            <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>
              {activeCat.label} · {selectedGroup?.name || '素材条目'}
            </span>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setShowBatchImport(true)}
                disabled={selectedGroupId === null}
                className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer disabled:opacity-40"
                style={{ background: 'rgba(22,119,255,0.10)', color: '#1677FF' }}
              >
                📥 批量导入
              </button>
              <button
                onClick={() => setShowAddMaterial(true)}
                disabled={selectedGroupId === null}
                className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer disabled:opacity-40"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                ＋ 新增素材
              </button>
            </div>
          </div>

          {selectedGroupId === null ? (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>📦</div>
              <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>请在左侧选择或创建分组</p>
            </div>
          ) : loadingItems ? (
            <div className="flex items-center justify-center py-16">
              <div className="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : materials.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>📝</div>
              <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>暂无素材，点击右上角新增或批量导入</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm whitespace-nowrap">
                <thead>
                  <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                    <th className="pb-2 pt-3 px-4 font-medium">内容</th>
                    <th className="pb-2 pt-3 px-4 font-medium">图片</th>
                    <th className="pb-2 pt-3 px-4 font-medium text-right">使用次数</th>
                    <th className="pb-2 pt-3 px-4 font-medium">创建时间</th>
                    <th className="pb-2 pt-3 px-4 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {materials.map(m => (
                    <tr key={m.id} className="border-b transition-colors hover:bg-black/[0.02]"
                      style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                      <td className="py-3 px-4 max-w-[280px]" title={m.content}>
                        <span className="text-xs break-all whitespace-normal">{m.content || '—'}</span>
                      </td>
                      <td className="py-3 px-4">
                        {m.image_url ? (
                          <img src={m.image_url} alt=""
                            className="w-9 h-9 rounded object-cover"
                            onError={e => { (e.target as HTMLImageElement).style.display = 'none' }} />
                        ) : (
                          <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>
                        )}
                      </td>
                      <td className="py-3 px-4 text-right text-xs">{m.used_count ?? 0}</td>
                      <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>{formatTime(m.created_at)}</td>
                      <td className="py-3 px-4">
                        <button
                          onClick={() => handleDeleteMaterial(m.id)}
                          disabled={submitting === 'del-mat-' + m.id}
                          className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                          style={{ color: '#dc2626', background: 'rgba(239,68,68,0.08)' }}
                        >
                          {submitting === 'del-mat-' + m.id ? '删除中...' : '删除'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* ========== 3. 底部操作按钮 ========== */}
      <div className="flex items-center gap-2">
        <button
          onClick={() => setShowAddGroup(true)}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
        >
          📁 新增分组
        </button>
        <button
          onClick={() => setShowBatchImport(true)}
          disabled={selectedGroupId === null}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1 disabled:opacity-40"
          style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
        >
          📥 批量导入素材
        </button>
        {selectedGroupId === null && (
          <span className="text-xs" style={{ color: 'rgba(0,0,0,0.30)' }}>（请先选择分组再批量导入）</span>
        )}
      </div>

      {/* ========== 新增分组 Modal ========== */}
      {showAddGroup && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowAddGroup(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>新增分组（{activeCat.label}）</h4>
              <button onClick={() => setShowAddGroup(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <div className="space-y-2">
              <input
                type="text"
                value={newGroupName}
                onChange={e => setNewGroupName(e.target.value)}
                className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                placeholder="分组名称"
              />
              <input
                type="text"
                value={newGroupDesc}
                onChange={e => setNewGroupDesc(e.target.value)}
                className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                placeholder="分组描述（可选）"
              />
              <button
                onClick={handleAddGroup}
                disabled={!newGroupName.trim() || !!submitting}
                className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                {submitting === 'add-group' ? '创建中...' : '创建分组'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ========== 新增素材 Modal ========== */}
      {showAddMaterial && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowAddMaterial(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>新增素材 · {selectedGroup?.name}</h4>
              <button onClick={() => setShowAddMaterial(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <div className="space-y-2">
              <textarea
                value={newContent}
                onChange={e => setNewContent(e.target.value)}
                className="w-full rounded-lg px-3 py-2 text-sm outline-none resize-none"
                style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                rows={3}
                placeholder={activeCat.category === 'avatar' ? '请输入头像素材内容或图片地址' : '请输入素材内容'}
              />
              {activeCat.category === 'avatar' && (
                <input
                  type="text"
                  value={newImageUrl}
                  onChange={e => setNewImageUrl(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="图片 URL（可选）"
                />
              )}
              <button
                onClick={handleAddMaterial}
                disabled={!newContent.trim() || !!submitting}
                className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                {submitting === 'add-material' ? '新增中...' : '新增素材'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ========== 批量导入 Modal ========== */}
      {showBatchImport && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowBatchImport(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>批量导入素材 · {selectedGroup?.name}</h4>
              <button onClick={() => setShowBatchImport(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <p className="text-xs mb-2" style={{ color: 'rgba(0,0,0,0.40)' }}>每行一条，自动去除空行</p>
            <textarea
              value={batchText}
              onChange={e => setBatchText(e.target.value)}
              className="w-full rounded-lg px-3 py-2 text-sm outline-none resize-none"
              style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
              rows={8}
              placeholder={'素材1\n素材2\n素材3'}
            />
            <button
              onClick={handleBatchImport}
              disabled={!batchText.trim() || !!submitting}
              className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50 mt-3"
              style={{ background: '#1677FF', color: '#fff' }}
            >
              {submitting === 'batch-import' ? '导入中...' : '确认导入'}
            </button>
          </div>
        </div>
      )}

    </div>
  )
}
