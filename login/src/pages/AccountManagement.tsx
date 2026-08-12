import { useState, useEffect, useCallback } from 'react'

/* ---- Types ---- */

interface AccountTag {
  id?: number
  name?: string
}

interface Account {
  id: number
  aweme_id?: string
  aweme_number?: string
  nickname?: string
  avatar_url?: string
  fans_count?: number
  following_count?: number
  digg_count?: number
  video_count?: number
  diamond?: number
  health_score?: number
  signature?: string
  web_url?: string
  status: string
  bundle_id?: string
  act_country?: string
  act_language?: string
  register_time?: number
  phone?: string
  email?: string
  has_2fa?: boolean
  is_email_bound?: boolean
  is_phone_bound?: boolean
  tags?: AccountTag[]
  device_id?: string
  remark?: string
  friends_count?: number
  act_city?: string
  act_sex?: string
  act_age?: number
}

interface PaginatedResponse {
  count: number
  results: Account[]
}

/* ---- Constants ---- */

const PAGE_LIMIT = 20

const STATUS_OPTIONS = [
  { value: '', label: '全部' },
  { value: 'active', label: '正常' },
  { value: 'risk_control', label: '风控' },
  { value: 'banned', label: '封禁' },
]

const STATUS_BADGE: Record<string, { label: string; bg: string; text: string }> = {
  active:       { label: '正常', bg: 'rgba(34,197,94,0.10)', text: '#16a34a' },
  risk_control: { label: '风控', bg: 'rgba(234,179,8,0.10)', text: '#ca8a04' },
  banned:       { label: '封禁', bg: 'rgba(239,68,68,0.10)', text: '#dc2626' },
}

/* ---- Helpers ---- */

const formatCount = (n?: number): string => {
  if (n === undefined || n === null) return '0'
  if (n >= 10000) {
    const wan = n / 10000
    return wan % 1 === 0 ? wan.toFixed(0) + '万' : wan.toFixed(1) + '万'
  }
  if (n >= 1000) {
    const k = n / 1000
    return k % 1 === 0 ? k.toFixed(0) + 'k' : k.toFixed(1) + 'k'
  }
  return n.toLocaleString()
}

const formatTimestamp = (ts?: number): string => {
  if (!ts) return '—'
  const d = new Date(ts * 1000)
  return d.toLocaleString('zh-CN', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  })
}

const healthColor = (score?: number): string => {
  if (score === undefined || score === null) return 'rgba(0,0,0,0.25)'
  if (score >= 80) return '#16a34a'
  if (score >= 60) return '#ca8a04'
  return '#dc2626'
}

const healthBg = (score?: number): string => {
  if (score === undefined || score === null) return 'rgba(0,0,0,0.06)'
  if (score >= 80) return 'rgba(34,197,94,0.10)'
  if (score >= 60) return 'rgba(234,179,8,0.10)'
  return 'rgba(239,68,68,0.10)'
}

/* ---- Component ---- */

export default function AccountManagement({ token }: { token: string }) {
  /* ---- Data state ---- */
  const [accounts, setAccounts] = useState<Account[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  /* ---- Filter state ---- */
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  const [offset, setOffset] = useState(0)

  /* ---- Selection state ---- */
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set())
  const [selectAll, setSelectAll] = useState(false)

  /* ---- Modal state ---- */
  const [detailAccount, setDetailAccount] = useState<Account | null>(null)
  const [editRemark, setEditRemark] = useState('')
  const [savingRemark, setSavingRemark] = useState(false)

  /* ---- Import modal state ---- */
  const [showImport, setShowImport] = useState(false)
  const [importTab, setImportTab] = useState<'manual' | 'csv'>('manual')
  const [importing, setImporting] = useState(false)
  const [importResult, setImportResult] = useState('')

  /* ---- Batch edit profile modal state ---- */
  const [showBatchEdit, setShowBatchEdit] = useState(false)
  const [editNickname, setEditNickname] = useState(true)
  const [editSignature, setEditSignature] = useState(true)
  const [editLink, setEditLink] = useState(true)
  const [submittingBatch, setSubmittingBatch] = useState(false)

  // 手动导入表单
  const [form, setForm] = useState({
    nickname: '', username: '', aweme_number: '', password: '', cookies: '', token: '',
    phone: '', email: '', region: '', country: '', remark: '',
  })
  const resetForm = () => setForm({
    nickname: '', username: '', aweme_number: '', password: '', cookies: '', token: '',
    phone: '', email: '', region: '', country: '', remark: '',
  })

  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  /* ---- Data fetching ---- */

  const fetchAccounts = useCallback(async () => {
    setLoading(true)
    setError('')
    const params = new URLSearchParams({ limit: String(PAGE_LIMIT), offset: String(offset) })
    if (search) params.set('search', search)
    if (filterStatus) params.set('status', filterStatus)
    try {
      const r = await fetch(`/api/biz/v2/accounts/?${params}`, { headers })
      if (!r.ok) throw new Error(`请求失败 (${r.status})`)
      const d: PaginatedResponse = await r.json()
      setAccounts(d.results || [])
      setTotal(d.count ?? 0)
    } catch (err: any) {
      setError(err.message || '加载失败')
      setAccounts([])
    } finally {
      setLoading(false)
    }
  }, [token, offset, search, filterStatus])

  useEffect(() => {
    fetchAccounts()
    setSelectedIds(new Set())
    setSelectAll(false)
  }, [fetchAccounts])

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
      setSelectedIds(new Set(accounts.map(a => a.id)))
      setSelectAll(true)
    }
  }

  const selectedCount = selectedIds.size

  /* ---- Pagination ---- */

  const totalPages = Math.ceil(total / PAGE_LIMIT)
  const currentPage = Math.floor(offset / PAGE_LIMIT) + 1

  const goPrev = () => { if (offset > 0) setOffset(Math.max(0, offset - PAGE_LIMIT)) }
  const goNext = () => { if (offset + PAGE_LIMIT < total) setOffset(offset + PAGE_LIMIT) }

  /* ---- Detail modal ---- */

  const openDetail = (acc: Account) => {
    setDetailAccount(acc)
    setEditRemark(acc.remark || '')
  }

  const closeDetail = () => {
    setDetailAccount(null)
    setEditRemark('')
  }

  const saveRemark = async () => {
    if (!detailAccount || savingRemark) return
    setSavingRemark(true)
    try {
      const r = await fetch(`/api/biz/v2/accounts/${detailAccount.id}/`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify({ remark: editRemark }),
      })
      if (!r.ok) throw new Error('保存失败')
      setAccounts(prev => prev.map(a => a.id === detailAccount.id ? { ...a, remark: editRemark } : a))
      closeDetail()
    } catch {
      setError('保存备注失败')
    } finally {
      setSavingRemark(false)
    }
  }

  /* ---- Batch edit profile ---- */

  const openBatchEdit = () => {
    setEditNickname(true)
    setEditSignature(true)
    setEditLink(true)
    setShowBatchEdit(true)
  }

  const submitBatchEdit = async () => {
    if (selectedCount === 0 || submittingBatch) return
    if (!(editNickname || editSignature || editLink)) return
    setSubmittingBatch(true)
    try {
      const r = await fetch('/api/biz/v2/accounts/batch-edit-profile/', {
        method: 'POST',
        headers,
        body: JSON.stringify({
          account_ids: Array.from(selectedIds),
          edit_nickname: editNickname,
          edit_signature: editSignature,
          edit_link: editLink,
          material_group_id: null,
        }),
      })
      if (!r.ok) throw new Error((await r.text()).slice(0, 120) || '下发失败')
      const d = await r.json()
      alert(d.message || '已下发')
      setShowBatchEdit(false)
      setSelectedIds(new Set())
      setSelectAll(false)
      fetchAccounts()
    } catch (e: any) {
      alert('下发失败: ' + (e.message || '未知错误'))
    } finally {
      setSubmittingBatch(false)
    }
  }

  /* ---- Render helper ---- */

  const statusBadge = (status: string) => {
    const cfg = STATUS_BADGE[status] || { label: status || '—', bg: 'rgba(0,0,0,0.05)', text: 'rgba(0,0,0,0.35)' }
    return (
      <span className="inline-flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full" style={{ background: cfg.bg, color: cfg.text }}>
        <span className="w-1.5 h-1.5 rounded-full" style={{ background: cfg.text }} />
        {cfg.label}
      </span>
    )
  }

  /* ================================================================ */
  /*                            RENDER                                */
  /* ================================================================ */

  if (loading && accounts.length === 0) {
    return <div className="flex items-center justify-center h-64" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
  }

  /* ---- Computed stats from current page data ---- */
  const activeCount = accounts.filter(a => a.status === 'active').length
  const riskCount = accounts.filter(a => a.status === 'risk_control').length
  const bannedCount = accounts.filter(a => a.status === 'banned').length

  return (
    <div className="space-y-5">

      {/* ========== 1. Statistics Cards ========== */}
      <div className="grid grid-cols-4 gap-4">
        {[
          { label: '全部账号', val: total, icon: '📱', color: 'rgba(0,0,0,0.70)' },
          { label: '正常',     val: activeCount, icon: '✅', color: '#16a34a' },
          { label: '风控',     val: riskCount, icon: '⚠️', color: '#ca8a04' },
          { label: '封禁',     val: bannedCount, icon: '🚫', color: '#dc2626' },
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

      {/* ========== 2. Search + Filter Bar ========== */}
      <div className="flex flex-wrap items-center gap-3">
        {/* Search */}
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <input
            type="text"
            value={search}
            onChange={e => { setSearch(e.target.value); setOffset(0) }}
            className="w-full rounded-lg pl-9 pr-3 py-2 text-sm outline-none"
            style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
            placeholder="搜索昵称、TK号、手机号..."
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

        {/* Refresh */}
        <button
          onClick={() => fetchAccounts()}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{ background: 'rgba(255,255,255,0.25)', color: 'rgba(0,0,0,0.50)' }}
        >
          🔄 刷新
        </button>

        {/* Import */}
        <button
          onClick={() => { resetForm(); setImportResult(''); setShowImport(true) }}
          className="px-3 py-2 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
          style={{ background: 'rgba(22,119,255,0.12)', color: '#1677FF' }}
        >
          📥 导入账号
        </button>
      </div>

      {/* Error banner */}
      {error && (
        <div className="px-5 py-2 rounded-lg text-xs" style={{ background: 'rgba(239,68,68,0.08)', color: '#dc2626' }}>
          {error}
          <button onClick={() => setError('')} className="ml-2 underline cursor-pointer">关闭</button>
        </div>
      )}

      {/* ========== 3. Batch Selection Bar ========== */}
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
              onClick={openBatchEdit}
              className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer flex items-center gap-1"
              style={{ background: '#1677FF', color: '#fff' }}
            >
              ✏️ 批量改资料
            </button>
            <button
              onClick={() => { setSelectedIds(new Set()); setSelectAll(false) }}
              className="px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
              style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.50)' }}
            >
              取消选择
            </button>
          </div>
        </div>
      )}

      {/* ========== 4. Account Table ========== */}
      <div className="xx-card rounded-xl overflow-hidden">
        {accounts.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>👤</div>
            <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>
              {search || filterStatus ? '无匹配账号' : '暂无账号数据'}
            </p>
          </div>
        ) : (
          <>
            {/* Table header bar */}
            <div className="px-5 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
              <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>账号列表</span>
              <span className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>共 {total} 条</span>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-sm whitespace-nowrap">
                <thead>
                  <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                    <th className="pb-2 pt-3 px-3 w-8">
                      <input
                        type="checkbox"
                        checked={selectAll}
                        onChange={toggleSelectAll}
                        className="cursor-pointer accent-[#1677FF]"
                      />
                    </th>
                    <th className="pb-2 pt-3 px-3 font-medium">昵称</th>
                    <th className="pb-2 pt-3 px-3 font-medium">TK号</th>
                    <th className="pb-2 pt-3 px-3 font-medium text-right">粉丝</th>
                    <th className="pb-2 pt-3 px-3 font-medium text-right">关注</th>
                    <th className="pb-2 pt-3 px-3 font-medium text-right">获赞</th>
                    <th className="pb-2 pt-3 px-3 font-medium text-right">作品</th>
                    <th className="pb-2 pt-3 px-3 font-medium text-right">健康分</th>
                    <th className="pb-2 pt-3 px-3 font-medium">状态</th>
                    <th className="pb-2 pt-3 px-3 font-medium">国家</th>
                    <th className="pb-2 pt-3 px-3 font-medium">包名</th>
                    <th className="pb-2 pt-3 px-3 font-medium">注册时间</th>
                    <th className="pb-2 pt-3 px-3 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {accounts.map(acc => {
                    const isSelected = selectedIds.has(acc.id)
                    return (
                      <tr
                        key={acc.id}
                        className="border-b transition-colors hover:bg-black/[0.02] cursor-pointer"
                        style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}
                        onClick={() => openDetail(acc)}
                      >
                        {/* Checkbox */}
                        <td className="py-3 px-3" onClick={e => e.stopPropagation()}>
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => toggleSelect(acc.id)}
                            className="cursor-pointer accent-[#1677FF]"
                          />
                        </td>

                        {/* Nickname + avatar */}
                        <td className="py-3 px-3">
                          <div className="flex items-center gap-2">
                            {acc.avatar_url ? (
                              <img
                                src={acc.avatar_url}
                                alt=""
                                className="w-7 h-7 rounded-full object-cover shrink-0"
                                onError={e => { (e.target as HTMLImageElement).style.display = 'none' }}
                              />
                            ) : (
                              <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs shrink-0" style={{ background: 'rgba(0,0,0,0.06)', color: 'rgba(0,0,0,0.25)' }}>
                                👤
                              </div>
                            )}
                            <span className="max-w-[100px] truncate" title={acc.nickname}>{acc.nickname || '—'}</span>
                          </div>
                        </td>

                        {/* TK号 */}
                        <td className="py-3 px-3 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {acc.aweme_number || '—'}
                        </td>

                        {/* Fans / Follow / Digg / Video */}
                        <td className="py-3 px-3 text-right text-xs">{formatCount(acc.fans_count)}</td>
                        <td className="py-3 px-3 text-right text-xs">{formatCount(acc.following_count)}</td>
                        <td className="py-3 px-3 text-right text-xs">{formatCount(acc.digg_count)}</td>
                        <td className="py-3 px-3 text-right text-xs">{acc.video_count?.toLocaleString() ?? '0'}</td>

                        {/* Health score */}
                        <td className="py-3 px-3 text-right">
                          {acc.health_score !== undefined && acc.health_score !== null ? (
                            <span className="text-xs font-medium px-2 py-0.5 rounded" style={{ background: healthBg(acc.health_score), color: healthColor(acc.health_score) }}>
                              {acc.health_score}
                            </span>
                          ) : (
                            <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>
                          )}
                        </td>

                        {/* Status */}
                        <td className="py-3 px-3">{statusBadge(acc.status)}</td>

                        {/* Country */}
                        <td className="py-3 px-3 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>{acc.act_country || '—'}</td>

                        {/* Bundle */}
                        <td className="py-3 px-3 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>{acc.bundle_id || '—'}</td>

                        {/* Register time */}
                        <td className="py-3 px-3 text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>{formatTimestamp(acc.register_time)}</td>

                        {/* Actions */}
                        <td className="py-3 px-3" onClick={e => e.stopPropagation()}>
                          <button
                            onClick={() => openDetail(acc)}
                            className="text-xs px-2 py-0.5 rounded cursor-pointer"
                            style={{ color: '#1677FF', background: 'rgba(22,119,255,0.08)' }}
                          >
                            编辑备注
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

      {/* ========== 6. Detail Modal ========== */}
      {detailAccount && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={closeDetail}
        >
          <div className="xx-card rounded-xl w-full max-w-lg p-6 my-8" onClick={e => e.stopPropagation()}>
            {/* Header */}
            <div className="flex items-center justify-between mb-5">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>账号详情</h4>
              <button onClick={closeDetail} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>

            {/* Basic info header */}
            <div className="flex items-center gap-3 mb-5 p-3 rounded-lg" style={{ background: 'rgba(0,0,0,0.03)' }}>
              {detailAccount.avatar_url ? (
                <img src={detailAccount.avatar_url} alt="" className="w-12 h-12 rounded-full object-cover shrink-0" />
              ) : (
                <div className="w-12 h-12 rounded-full flex items-center justify-center text-lg shrink-0" style={{ background: 'rgba(0,0,0,0.06)' }}>👤</div>
              )}
              <div className="min-w-0">
                <div className="text-sm font-medium truncate" style={{ color: 'rgba(0,0,0,0.70)' }}>{detailAccount.nickname || '—'}</div>
                <div className="text-xs mt-0.5 truncate" style={{ color: 'rgba(0,0,0,0.35)' }}>TK号: {detailAccount.aweme_number || '—'}</div>
              </div>
              <div className="ml-auto shrink-0">{statusBadge(detailAccount.status)}</div>
            </div>

            {/* Stats grid */}
            <div className="grid grid-cols-4 gap-3 mb-4">
              {[
                { label: '粉丝', val: formatCount(detailAccount.fans_count) },
                { label: '关注', val: formatCount(detailAccount.following_count) },
                { label: '获赞', val: formatCount(detailAccount.digg_count) },
                { label: '作品', val: detailAccount.video_count?.toLocaleString() ?? '0' },
              ].map(stat => (
                <div key={stat.label} className="text-center p-2 rounded-lg" style={{ background: 'rgba(0,0,0,0.03)' }}>
                  <div className="text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>{stat.label}</div>
                  <div className="text-sm font-bold mt-0.5" style={{ color: 'rgba(0,0,0,0.65)' }}>{stat.val}</div>
                </div>
              ))}
            </div>

            {/* Health score progress bar */}
            {detailAccount.health_score !== undefined && detailAccount.health_score !== null && (
              <div className="mb-4 p-3 rounded-lg" style={{ background: 'rgba(0,0,0,0.03)' }}>
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>健康分</span>
                  <span className="text-xs font-medium" style={{ color: healthColor(detailAccount.health_score) }}>{detailAccount.health_score}</span>
                </div>
                <div className="h-2 rounded-full overflow-hidden" style={{ background: 'rgba(0,0,0,0.06)' }}>
                  <div className="h-full rounded-full transition-all" style={{
                    width: `${detailAccount.health_score}%`,
                    background: detailAccount.health_score >= 80
                      ? 'linear-gradient(90deg, #22c55e, #16a34a)'
                      : detailAccount.health_score >= 60
                        ? 'linear-gradient(90deg, #eab308, #ca8a04)'
                        : 'linear-gradient(90deg, #ef4444, #dc2626)',
                  }} />
                </div>
              </div>
            )}

            {/* Detail fields */}
            <div className="space-y-2 mb-4">
              {detailAccount.signature && (
                <Row label="签名" value={detailAccount.signature} />
              )}
              {detailAccount.web_url && (
                <div className="flex gap-2">
                  <span className="text-xs shrink-0" style={{ color: 'rgba(0,0,0,0.35)', minWidth: 56 }}>主页</span>
                  <a href={detailAccount.web_url} target="_blank" rel="noopener noreferrer"
                    className="text-xs underline break-all" style={{ color: '#1677FF' }}>
                    {detailAccount.web_url}
                  </a>
                </div>
              )}
              {detailAccount.device_id && <Row label="设备" value={detailAccount.device_id} />}
              <Row label="手机" value={detailAccount.phone || '未绑定'} />
              <Row label="邮箱" value={detailAccount.email || '未绑定'} />
              <Row label="国家/语言" value={`${detailAccount.act_country || '—'} / ${detailAccount.act_language || '—'}`} />
              <Row label="包名" value={detailAccount.bundle_id || '—'} />
              <Row label="注册时间" value={formatTimestamp(detailAccount.register_time)} />
              {detailAccount.tags && detailAccount.tags.length > 0 && (
                <div className="flex gap-2">
                  <span className="text-xs shrink-0" style={{ color: 'rgba(0,0,0,0.35)', minWidth: 56 }}>标签</span>
                  <div className="flex flex-wrap gap-1">
                    {detailAccount.tags.map((tag, i) => (
                      <span key={i} className="text-xs px-2 py-0.5 rounded"
                        style={{ background: 'rgba(22,119,255,0.08)', color: '#1677FF' }}>
                        {tag.name || String(tag)}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Remark editor */}
            <div className="border-t pt-4" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
              <label className="text-xs block mb-1.5" style={{ color: 'rgba(0,0,0,0.40)' }}>备注</label>
              <textarea
                value={editRemark}
                onChange={e => setEditRemark(e.target.value)}
                className="w-full rounded-lg px-3 py-2 text-sm outline-none resize-none"
                style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                rows={3}
                placeholder="添加备注..."
              />
              <div className="flex justify-end gap-2 mt-2">
                <button
                  onClick={closeDetail}
                  className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
                  style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.50)' }}
                >
                  取消
                </button>
                <button
                  onClick={saveRemark}
                  disabled={savingRemark}
                  className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer disabled:opacity-50"
                  style={{ background: '#1677FF', color: '#fff' }}
                >
                  {savingRemark ? '保存中...' : '保存'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========== 7. Import Modal ========== */}
      {showImport && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowImport(false)}>
          <div className="xx-card rounded-xl w-full max-w-lg p-6 my-8" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>📥 导入账号</h4>
              <button onClick={() => setShowImport(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>

            <div className="flex gap-2 mb-4">
              {(['manual', 'csv'] as const).map(t => (
                <button key={t} onClick={() => { setImportTab(t); setImportResult('') }}
                  className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
                  style={{ background: importTab === t ? '#1677FF' : 'rgba(0,0,0,0.05)', color: importTab === t ? '#fff' : 'rgba(0,0,0,0.50)' }}>
                  {t === 'manual' ? '手动输入' : 'CSV 批量导入'}
                </button>
              ))}
            </div>

            {importResult && (
              <div className="mb-4 px-4 py-2 rounded-lg text-xs flex items-center justify-between"
                style={{ background: importResult.includes('失败') ? 'rgba(239,68,68,0.08)' : 'rgba(34,197,94,0.10)', color: importResult.includes('失败') ? '#dc2626' : '#16a34a' }}>
                {importResult} <button onClick={() => setImportResult('')} className="underline cursor-pointer">✕</button>
              </div>
            )}

            {importTab === 'manual' ? (
              <div className="space-y-3 max-h-[60vh] overflow-y-auto pr-1">
                <div className="grid grid-cols-2 gap-3">
                  <SL label="昵称" v={form.nickname} s={v => setForm(p => ({...p, nickname: v}))} />
                  <SL label="TK号" v={form.aweme_number} s={v => setForm(p => ({...p, aweme_number: v}))} />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <SL label="用户名" v={form.username} s={v => setForm(p => ({...p, username: v}))} />
                  <SL label="手机号" v={form.phone} s={v => setForm(p => ({...p, phone: v}))} />
                </div>
                <div className="border-t pt-3" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
                  <p className="text-xs mb-2 font-medium" style={{ color: 'rgba(0,0,0,0.40)' }}>登录凭证（至少填一项可自动登录）</p>
                  <div className="space-y-2">
                    <SL label="密码" v={form.password} s={v => setForm(p => ({...p, password: v}))} ph="登录密码" />
                    <SL label="Cookies" v={form.cookies} s={v => setForm(p => ({...p, cookies: v}))} ph="session/cookies" />
                    <SL label="Token" v={form.token} s={v => setForm(p => ({...p, token: v}))} ph="登录 token" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <SL label="国家" v={form.country} s={v => setForm(p => ({...p, country: v}))} ph="US" />
                  <SL label="区域" v={form.region} s={v => setForm(p => ({...p, region: v}))} ph="NA" />
                </div>
                <SL label="备注" v={form.remark} s={v => setForm(p => ({...p, remark: v}))} />
                <button onClick={async () => {
                  setImporting(true); setImportResult('')
                  try {
                    const body: any = { nickname: form.nickname, aweme_number: form.aweme_number, username: form.username, phone: form.phone, country: form.country, region: form.region, remark: form.remark }
                    if (form.password) body.password = form.password
                    if (form.cookies) body.cookies = form.cookies
                    if (form.token) body.token = form.token
                    const r = await fetch('/api/biz/v2/accounts/import/', { method: 'POST', headers, body: JSON.stringify(body) })
                    if (!r.ok) throw new Error((await r.text()).slice(0, 80))
                    setImportResult('✅ 导入成功！'); resetForm(); fetchAccounts()
                  } catch (e: any) { setImportResult('导入失败: ' + e.message) }
                  finally { setImporting(false) }
                }} disabled={importing}
                  className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                  style={{ background: '#1677FF', color: '#fff' }}>
                  {importing ? '导入中...' : '确认导入'}
                </button>
              </div>
            ) : (
              <div className="space-y-3">
                <p className="text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                  CSV 格式：第一行为列名，支持 nickname, aweme_number, password, cookies, token, phone, country, region 等
                </p>
                <input type="file" accept=".csv" onChange={async e => {
                  const file = e.target.files?.[0]; if (!file) return
                  setImporting(true); setImportResult('')
                  try {
                    const fd = new FormData(); fd.append('file', file)
                    const r = await fetch('/api/biz/v2/accounts/batch-import/', { method: 'POST', headers: { Authorization: `Token ${token}` }, body: fd })
                    if (!r.ok) throw new Error((await r.text()).slice(0, 80))
                    const d = await r.json(); setImportResult(`✅ 成功导入 ${d.count} 个账号`); fetchAccounts()
                  } catch (e: any) { setImportResult('导入失败: ' + e.message) }
                  finally { (e.target as any).value = ''; setImporting(false) }
                }} className="block w-full text-xs" style={{ color: 'rgba(0,0,0,0.55)' }} />
                {importing && <p className="text-xs" style={{ color: '#1677FF' }}>正在导入...</p>}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ========== 8. Batch Edit Profile Modal ========== */}
      {showBatchEdit && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowBatchEdit(false)}
        >
          <div className="xx-card rounded-xl w-full max-w-lg p-6 my-8" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-5">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>
                ✏️ 批量修改资料（{selectedCount} 个账号）
              </h4>
              <button onClick={() => setShowBatchEdit(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>

            <p className="text-xs mb-4" style={{ color: 'rgba(0,0,0,0.40)' }}>
              将随机使用素材库中的素材，未配置素材的项会被跳过
            </p>

            <div className="space-y-3 mb-5">
              {[
                { label: '修改昵称', val: editNickname, set: setEditNickname },
                { label: '修改签名', val: editSignature, set: setEditSignature },
                { label: '修改链接', val: editLink, set: setEditLink },
              ].map(opt => (
                <label key={opt.label} className="flex items-center gap-2 cursor-pointer text-sm" style={{ color: 'rgba(0,0,0,0.65)' }}>
                  <input type="checkbox" checked={opt.val} onChange={e => opt.set(e.target.checked)} className="cursor-pointer accent-[#1677FF]" />
                  {opt.label}
                </label>
              ))}
            </div>

            <div className="flex justify-end gap-2">
              <button
                onClick={() => setShowBatchEdit(false)}
                className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
                style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.50)' }}
              >
                取消
              </button>
              <button
                onClick={submitBatchEdit}
                disabled={submittingBatch || !(editNickname || editSignature || editLink)}
                className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer disabled:opacity-40"
                style={{ background: '#1677FF', color: '#fff' }}
              >
                {submittingBatch ? '下发中...' : '下发修改'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

/* ---- Inline small-input component ---- */
function SL({ label, v, s, ph }: { label: string; v: string; s: (x: string) => void; ph?: string }) {
  return (
    <div>
      <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>{label}</label>
      <input type="text" value={v} onChange={e => s(e.target.value)}
        className="w-full rounded-lg px-3 py-2 text-sm outline-none"
        style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
        placeholder={ph || ''} />
    </div>
  )
}

/* ---- Old Row sub-component for modal rows ---- */

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex gap-2">
      <span className="text-xs shrink-0" style={{ color: 'rgba(0,0,0,0.35)', minWidth: 56 }}>{label}</span>
      <span className="text-xs" style={{ color: 'rgba(0,0,0,0.55)' }}>{value}</span>
    </div>
  )
}
