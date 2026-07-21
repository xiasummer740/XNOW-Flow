import { useState, useEffect, useCallback } from 'react'

/* ---- Types ---- */

interface Stats {
  total: number
  online: number
  offline: number
  executing: number
}

interface DeviceGroup {
  id: number
  name: string
  description?: string
}

interface Device {
  id: number
  device_id: string
  bundle_id?: string
  group_name?: string | null
  mobile_no?: string
  device_state: string
  is_online: boolean
  daily_task_count?: number
  account_count?: number
  max_accounts?: number
  app_version?: string
  last_seen?: string
  name?: string
  device_name?: string
  status?: string
  lock_reason?: string
  tags?: string[]
  api_id?: number
  created_at?: string
}

interface PaginatedResponse {
  count: number
  results: Device[]
}

/* ---- Constants ---- */

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'online', label: '在线' },
  { value: 'offline', label: '离线' },
  { value: 'executing', label: '执行中' },
  { value: 'idle', label: '空闲' },
]

const STATE_BADGES: Record<string, { label: string; bg: string; text: string }> = {
  online:    { label: '在线',    bg: 'rgba(34,197,94,0.10)', text: '#16a34a' },
  offline:   { label: '离线',    bg: 'rgba(0,0,0,0.05)',    text: 'rgba(0,0,0,0.35)' },
  idle:      { label: '空闲',    bg: 'rgba(59,130,246,0.10)', text: '#2563eb' },
  executing: { label: '执行中',  bg: 'rgba(168,85,247,0.10)', text: '#9333ea' },
  locked:    { label: '锁定',    bg: 'rgba(239,68,68,0.10)', text: '#dc2626' },
}

const DISPATCH_ACTIONS = [
  { value: 'scroll_down',       label: '滚动浏览' },
  { value: 'screenshot',        label: '截图' },
  { value: 'collect_fans',      label: '采集粉丝' },
  { value: 'collect_videos',    label: '采集视频' },
  { value: 'batch_like',        label: '批量点赞' },
  { value: 'batch_follow',      label: '批量关注' },
  { value: 'batch_comment',     label: '批量评论' },
]

const PAGE_LIMIT = 20

/* ---- Helpers ---- */

/** Format an ISO timestamp into a short Chinese locale string. */
const formatTime = (iso?: string): string =>
  iso ? new Date(iso).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'

/** Truncate a string and show full value on title tooltip. */
const truncate = (s?: string | null, max = 16): string =>
  s && s.length > max ? s.slice(0, max) + '…' : (s || '—')

/* ---- Component ---- */

export default function DeviceManagement({ token }: { token: string }) {
  /* ---- Data state ---- */
  const [devices, setDevices] = useState<Device[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [stats, setStats] = useState<Stats>({ total: 0, online: 0, offline: 0, executing: 0 })
  const [groups, setGroups] = useState<DeviceGroup[]>([])

  /* ---- Filter state ---- */
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  const [filterGroup, setFilterGroup] = useState('')
  const [offset, setOffset] = useState(0)

  /* ---- Selection state ---- */
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set())
  const [selectAll, setSelectAll] = useState(false)

  /* ---- Modal state ---- */
  const [showGroupModal, setShowGroupModal] = useState(false)
  const [showBatchGroup, setShowBatchGroup] = useState(false)
  const [showDispatch, setShowDispatch] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)

  /* ---- Group form state ---- */
  const [newGroupName, setNewGroupName] = useState('')
  const [newGroupDesc, setNewGroupDesc] = useState('')
  const [batchGroupName, setBatchGroupName] = useState('')

  /* ---- Dispatch form state ---- */
  const [dispatchAction, setDispatchAction] = useState(DISPATCH_ACTIONS[0].value)
  const [dispatchParams, setDispatchParams] = useState('')

  /* ---- Submitting state ---- */
  const [submitting, setSubmitting] = useState('')

  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  /* ---- Data fetching ---- */

  const fetchStats = useCallback(async () => {
    try {
      const r = await fetch('/api/biz/v2/device-bindings/stats/summary/', { headers })
      if (r.ok) {
        const d = await r.json()
        setStats({ total: d.total ?? 0, online: d.online ?? 0, offline: d.offline ?? 0, executing: d.executing ?? 0 })
      }
    } catch { /* non-critical */ }
  }, [token])

  const fetchGroups = useCallback(async () => {
    try {
      const r = await fetch('/api/biz/v2/device-groups/', { headers })
      if (r.ok) setGroups(await r.json())
    } catch { /* non-critical */ }
  }, [token])

  const fetchDevices = useCallback(async () => {
    setLoading(true)
    setError('')
    const params = new URLSearchParams({ limit: String(PAGE_LIMIT), offset: String(offset) })
    if (search) params.set('search', search)
    if (filterStatus) params.set('status', filterStatus)
    if (filterGroup) params.set('group', filterGroup)
    try {
      const r = await fetch(`/api/biz/v2/device-bindings/?${params}`, { headers })
      if (!r.ok) throw new Error(`请求失败 (${r.status})`)
      const d: PaginatedResponse = await r.json()
      setDevices(d.results || [])
      setTotal(d.count ?? 0)
    } catch (err: any) {
      setError(err.message || '加载失败')
      setDevices([])
    } finally {
      setLoading(false)
    }
  }, [token, offset, search, filterStatus, filterGroup])

  useEffect(() => {
    fetchStats()
    fetchGroups()
  }, [fetchStats, fetchGroups])

  useEffect(() => {
    fetchDevices()
    setSelectedIds(new Set())
    setSelectAll(false)
  }, [fetchDevices])

  /* ---- Selection ---- */

  const toggleSelect = (id: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id); else next.add(id)
      return next
    })
    setSelectAll(false)
  }

  const toggleSelectAll = () => {
    if (selectAll) {
      setSelectedIds(new Set())
      setSelectAll(false)
    } else {
      setSelectedIds(new Set(devices.map(d => d.id)))
      setSelectAll(true)
    }
  }

  const selectedCount = selectedIds.size

  /* ---- Pagination ---- */

  const totalPages = Math.ceil(total / PAGE_LIMIT)
  const currentPage = Math.floor(offset / PAGE_LIMIT) + 1

  const goPrev = () => { if (offset > 0) setOffset(Math.max(0, offset - PAGE_LIMIT)) }
  const goNext = () => { if (offset + PAGE_LIMIT < total) setOffset(offset + PAGE_LIMIT) }

  /* ---- Single delete ---- */

  const handleDeleteOne = async (id: number) => {
    if (submitting) return
    setSubmitting('del-' + id)
    try {
      const r = await fetch(`/api/biz/v2/device-bindings/${id}/`, { method: 'DELETE', headers })
      if (!r.ok) throw new Error('删除失败')
      await fetchDevices()
      await fetchStats()
    } catch {
      setError('删除失败，请重试')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Batch delete ---- */

  const handleBatchDelete = async () => {
    if (submitting) return
    setSubmitting('batch-del')
    try {
      const r = await fetch('/api/biz/v2/device-bindings/batch/delete/', {
        method: 'POST', headers,
        body: JSON.stringify({ device_ids: Array.from(selectedIds) }),
      })
      if (!r.ok) throw new Error('批量删除失败')
      setShowDeleteConfirm(false)
      await fetchDevices()
      await fetchStats()
    } catch {
      setError('批量删除失败')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Batch group ---- */

  const handleBatchGroup = async () => {
    if (!batchGroupName || submitting) return
    setSubmitting('batch-group')
    try {
      const r = await fetch('/api/biz/v2/device-bindings/batch/group/', {
        method: 'POST', headers,
        body: JSON.stringify({ device_ids: Array.from(selectedIds), group_name: batchGroupName }),
      })
      if (!r.ok) throw new Error('修改分组失败')
      setShowBatchGroup(false)
      setBatchGroupName('')
      await fetchDevices()
    } catch {
      setError('修改分组失败')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Batch dispatch ---- */

  const handleDispatch = async () => {
    if (submitting) return
    setSubmitting('dispatch')
    try {
      let params: any = {}
      if (dispatchParams) {
        try { params = JSON.parse(dispatchParams) } catch { params = { extra: dispatchParams } }
      }
      const r = await fetch('/api/biz/v2/device-bindings/batch/dispatch/', {
        method: 'POST', headers,
        body: JSON.stringify({ device_ids: Array.from(selectedIds), action: dispatchAction, params }),
      })
      if (!r.ok) throw new Error('下发任务失败')
      setShowDispatch(false)
      setDispatchParams('')
    } catch {
      setError('下发任务失败')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Group management ---- */

  const handleAddGroup = async () => {
    if (!newGroupName.trim() || submitting) return
    setSubmitting('add-group')
    try {
      const r = await fetch('/api/biz/v2/device-groups/', {
        method: 'POST', headers,
        body: JSON.stringify({ name: newGroupName.trim(), description: newGroupDesc.trim() }),
      })
      if (!r.ok) throw new Error('创建分组失败')
      setNewGroupName('')
      setNewGroupDesc('')
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
      const r = await fetch(`/api/biz/v2/device-groups/${id}/`, { method: 'DELETE', headers })
      if (!r.ok) throw new Error('删除分组失败')
      await fetchGroups()
    } catch {
      setError('删除分组失败')
    } finally {
      setSubmitting('')
    }
  }

  /* ---- Render helpers ---- */

  const stateBadge = (state: string) => {
    const cfg = STATE_BADGES[state] || { label: state || '—', bg: 'rgba(0,0,0,0.05)', text: 'rgba(0,0,0,0.35)' }
    return (
      <span className="inline-flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full" style={{ background: cfg.bg, color: cfg.text }}>
        <span className="w-1.5 h-1.5 rounded-full" style={{ background: cfg.text }} />
        {cfg.label}
      </span>
    )
  }

  const onlineBadge = (online: boolean) => (
    <span className="text-xs" style={{ color: online ? '#16a34a' : 'rgba(0,0,0,0.35)' }}>
      {online ? '在线' : '离线'}
    </span>
  )

  /* ---- Loading / Error ---- */

  if (loading && devices.length === 0) {
    return <div className="flex items-center justify-center h-64" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
  }

  /* ---- Render ---- */

  return (
    <div className="space-y-5">

      {/* ========== 1. Top Statistics Bar ========== */}
      <div className="grid grid-cols-4 gap-4">
        {[
          { label: '全部设备', val: stats.total, icon: '💻', color: 'rgba(0,0,0,0.70)' },
          { label: '在线',     val: stats.online, icon: '🟢', color: '#16a34a' },
          { label: '离线',     val: stats.offline, icon: '⚫', color: 'rgba(0,0,0,0.35)' },
          { label: '执行中',   val: stats.executing, icon: '🔄', color: '#9333ea' },
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

      {/* ========== 2. Search + Filters Bar ========== */}
      <div className="flex flex-wrap items-center gap-3">
        {/* Search */}
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <input
            type="text"
            value={search}
            onChange={e => { setSearch(e.target.value); setOffset(0) }}
            className="w-full rounded-lg pl-9 pr-3 py-2 text-sm outline-none"
            style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
            placeholder="搜索设备编号、机器码..."
          />
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm" style={{ color: 'rgba(0,0,0,0.25)' }}>🔍</span>
        </div>

        {/* Status filter */}
        <select
          value={filterStatus}
          onChange={e => { setFilterStatus(e.target.value); setOffset(0) }}
          className="rounded-lg px-3 py-2 text-sm outline-none cursor-pointer"
          style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}
        >
          {STATUS_OPTIONS.map(o => (
            <option key={o.value} value={o.value}>{o.label}</option>
          ))}
        </select>

        {/* Group filter */}
        <select
          value={filterGroup}
          onChange={e => { setFilterGroup(e.target.value); setOffset(0) }}
          className="rounded-lg px-3 py-2 text-sm outline-none cursor-pointer"
          style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}
        >
          <option value="">全部设备</option>
          {groups.map(g => (
            <option key={g.id} value={g.name}>{g.name}</option>
          ))}
        </select>

        {/* Refresh */}
        <button
          onClick={() => { fetchDevices(); fetchStats() }}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
        >
          🔄 刷新
        </button>

        {/* Group management */}
        <button
          onClick={() => setShowGroupModal(true)}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
        >
          📁 分组管理
        </button>
      </div>

      {/* ========== 3. Batch Operations Bar ========== */}
      {selectedCount > 0 && (
        <div
          className="xx-card rounded-xl px-5 py-3 flex items-center justify-between"
          style={{ borderLeft: '3px solid #1677FF' }}
        >
          <span className="text-sm" style={{ color: 'rgba(0,0,0,0.55)' }}>
            已选 <strong style={{ color: '#1677FF' }}>{selectedCount}</strong> 项
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={() => { setBatchGroupName(''); setShowBatchGroup(true) }}
              className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
              style={{ background: 'rgba(22,119,255,0.10)', color: '#1677FF' }}
            >
              📂 批量修改分组
            </button>
            <button
              onClick={() => setShowDispatch(true)}
              className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
              style={{ background: 'rgba(22,119,255,0.10)', color: '#1677FF' }}
            >
              📨 下发任务
            </button>
            <button
              onClick={() => setShowDeleteConfirm(true)}
              className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
              style={{ background: 'rgba(239,68,68,0.10)', color: '#dc2626' }}
            >
              🗑️ 批量删除
            </button>
          </div>
        </div>
      )}

      {/* Error banner */}
      {error && (
        <div className="px-5 py-2 rounded-lg text-xs" style={{ background: 'rgba(239,68,68,0.08)', color: '#dc2626' }}>
          {error}
          <button onClick={() => setError('')} className="ml-2 underline cursor-pointer">关闭</button>
        </div>
      )}

      {/* ========== 4. Device Table ========== */}
      <div className="xx-card rounded-xl overflow-hidden">
        {devices.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>📱</div>
            <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>
              {search || filterStatus || filterGroup ? '无匹配设备' : '暂无设备数据'}
            </p>
          </div>
        ) : (
          <>
            {/* Table header bar */}
            <div className="px-5 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
              <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>设备列表</span>
              <span className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>共 {total} 条</span>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-sm whitespace-nowrap">
                <thead>
                  <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                    <th className="pb-2 pt-3 px-4 w-8">
                      <input
                        type="checkbox"
                        checked={selectAll}
                        onChange={toggleSelectAll}
                        className="cursor-pointer accent-[#1677FF]"
                      />
                    </th>
                    <th className="pb-2 pt-3 px-4 font-medium">机器码</th>
                    <th className="pb-2 pt-3 px-4 font-medium">应用程序</th>
                    <th className="pb-2 pt-3 px-4 font-medium">分组</th>
                    <th className="pb-2 pt-3 px-4 font-medium">手机号</th>
                    <th className="pb-2 pt-3 px-4 font-medium">运行状态</th>
                    <th className="pb-2 pt-3 px-4 font-medium">在线状态</th>
                    <th className="pb-2 pt-3 px-4 font-medium text-right">今日任务</th>
                    <th className="pb-2 pt-3 px-4 font-medium text-right">绑定账号</th>
                    <th className="pb-2 pt-3 px-4 font-medium">App版本</th>
                    <th className="pb-2 pt-3 px-4 font-medium">最后在线</th>
                    <th className="pb-2 pt-3 px-4 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {devices.map(dev => {
                    const isSelected = selectedIds.has(dev.id)
                    return (
                      <tr
                        key={dev.id}
                        className="border-b transition-colors hover:bg-black/[0.02]"
                        style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}
                      >
                        <td className="py-3 px-4">
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => toggleSelect(dev.id)}
                            className="cursor-pointer accent-[#1677FF]"
                          />
                        </td>
                        <td className="py-3 px-4 max-w-[120px]" title={dev.device_id}>
                          <span className="font-mono text-xs">{truncate(dev.device_id, 18)}</span>
                        </td>
                        <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {truncate(dev.bundle_id, 20)}
                        </td>
                        <td className="py-3 px-4 text-xs">
                          {dev.group_name ? (
                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded"
                              style={{ background: 'rgba(22,119,255,0.08)', color: '#1677FF' }}>
                              {dev.group_name}
                            </span>
                          ) : (
                            <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>
                          )}
                        </td>
                        <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {dev.mobile_no || '—'}
                        </td>
                        <td className="py-3 px-4">{stateBadge(dev.device_state)}</td>
                        <td className="py-3 px-4">{onlineBadge(dev.is_online)}</td>
                        <td className="py-3 px-4 text-right text-xs">{dev.daily_task_count ?? 0}</td>
                        <td className="py-3 px-4 text-right text-xs">
                          <span style={{ color: 'rgba(0,0,0,0.55)' }}>
                            {dev.account_count ?? 0}
                          </span>
                          <span style={{ color: 'rgba(0,0,0,0.25)' }}>
                            /{dev.max_accounts ?? '—'}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {dev.app_version || '—'}
                        </td>
                        <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>
                          {formatTime(dev.last_seen)}
                        </td>
                        <td className="py-3 px-4">
                          <button
                            onClick={() => handleDeleteOne(dev.id)}
                            disabled={submitting === 'del-' + dev.id}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                            style={{ color: '#dc2626', background: 'rgba(239,68,68,0.08)' }}
                          >
                            {submitting === 'del-' + dev.id ? '删除中...' : '删除'}
                          </button>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      {/* ========== 5. Pagination ========== */}
      {total > 0 && (
        <div className="flex items-center justify-between text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
          <span>共 {total} 条</span>
          <div className="flex items-center gap-2">
            <span>第 {currentPage}/{totalPages} 页</span>
            <button
              onClick={goPrev}
              disabled={offset <= 0}
              className="px-3 py-1.5 rounded-lg cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
              style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
            >
              上一页
            </button>
            <button
              onClick={goNext}
              disabled={offset + PAGE_LIMIT >= total}
              className="px-3 py-1.5 rounded-lg cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
              style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
            >
              下一页
            </button>
          </div>
        </div>
      )}

      {/* ========== 6. Group Management Modal ========== */}
      {showGroupModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowGroupModal(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>分组管理</h4>
              <button onClick={() => setShowGroupModal(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>

            {/* Existing groups */}
            <div className="max-h-48 overflow-y-auto space-y-1 mb-4">
              {groups.length === 0 ? (
                <div className="text-xs py-4 text-center" style={{ color: 'rgba(0,0,0,0.30)' }}>暂无分组</div>
              ) : (
                groups.map(g => (
                  <div key={g.id} className="flex items-center justify-between px-3 py-2 rounded-lg text-xs"
                    style={{ background: 'rgba(0,0,0,0.03)' }}>
                    <div>
                      <span style={{ color: 'rgba(0,0,0,0.65)' }}>{g.name}</span>
                      {g.description && (
                        <span className="ml-2" style={{ color: 'rgba(0,0,0,0.30)' }}>{g.description}</span>
                      )}
                    </div>
                    <button
                      onClick={() => handleDeleteGroup(g.id)}
                      disabled={submitting === 'del-group-' + g.id}
                      className="cursor-pointer disabled:opacity-50"
                      style={{ color: 'rgba(0,0,0,0.25)' }}
                      title="删除"
                    >
                      {submitting === 'del-group-' + g.id ? '...' : '✕'}
                    </button>
                  </div>
                ))
              )}
            </div>

            {/* Add group form */}
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

      {/* ========== Batch Group Modal ========== */}
      {showBatchGroup && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowBatchGroup(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>批量修改分组</h4>
              <button onClick={() => setShowBatchGroup(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <p className="text-xs mb-3" style={{ color: 'rgba(0,0,0,0.40)' }}>已选 {selectedCount} 台设备</p>
            <select
              value={batchGroupName}
              onChange={e => setBatchGroupName(e.target.value)}
              className="w-full rounded-lg px-3 py-2 text-sm outline-none mb-4 cursor-pointer"
              style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}
            >
              <option value="">选择分组</option>
              {groups.map(g => (
                <option key={g.id} value={g.name}>{g.name}</option>
              ))}
            </select>
            <button
              onClick={handleBatchGroup}
              disabled={!batchGroupName || !!submitting}
              className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
              style={{ background: '#1677FF', color: '#fff' }}
            >
              {submitting === 'batch-group' ? '提交中...' : '确认修改'}
            </button>
          </div>
        </div>
      )}

      {/* ========== Task Dispatch Modal ========== */}
      {showDispatch && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowDispatch(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>下发任务</h4>
              <button onClick={() => setShowDispatch(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <p className="text-xs mb-3" style={{ color: 'rgba(0,0,0,0.40)' }}>已选 {selectedCount} 台设备</p>
            <div className="space-y-3">
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>操作类型</label>
                <select
                  value={dispatchAction}
                  onChange={e => setDispatchAction(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none cursor-pointer"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}
                >
                  {DISPATCH_ACTIONS.map(a => (
                    <option key={a.value} value={a.value}>{a.label}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>参数（可选 JSON）</label>
                <textarea
                  value={dispatchParams}
                  onChange={e => setDispatchParams(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none resize-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  rows={3}
                  placeholder='{"key": "value"}'
                />
              </div>
              <button
                onClick={handleDispatch}
                disabled={!!submitting}
                className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                {submitting === 'dispatch' ? '下发中...' : '确认下发'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ========== Delete Confirm Modal ========== */}
      {showDeleteConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowDeleteConfirm(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <div className="mb-4">
              <h4 className="text-sm font-medium mb-2" style={{ color: 'rgba(0,0,0,0.65)' }}>确认删除</h4>
              <p className="text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                确定要删除选中的 <strong style={{ color: '#dc2626' }}>{selectedCount}</strong> 台设备吗？此操作不可撤销。
              </p>
            </div>
            <div className="flex gap-2">
              <button
                onClick={() => setShowDeleteConfirm(false)}
                className="flex-1 py-2 rounded-lg text-sm font-medium cursor-pointer"
                style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.50)' }}
              >
                取消
              </button>
              <button
                onClick={handleBatchDelete}
                disabled={!!submitting}
                className="flex-1 py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#dc2626', color: '#fff' }}
              >
                {submitting === 'batch-del' ? '删除中...' : '确认删除'}
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  )
}
