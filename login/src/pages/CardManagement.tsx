import { useState, useEffect, useCallback } from 'react'

interface License {
  id: number
  key: string
  plan: string
  status: string
  device_id: string
  udid: string
  api_id: string
  activated_at?: string | null
  expires_at?: string | null
  device_limit?: number | null
  account_limit?: number | null
  remark?: string
  created_at?: string | null
}

const PLAN_LABELS: Record<string, string> = {
  year1: '年卡', month3: '季卡', month1: '月卡',
}

const PLAN_META: Record<string, { device: number; account: number }> = {
  year1: { device: 20, account: 200 },
  month3: { device: 8, account: 80 },
  month1: { device: 3, account: 30 },
}

const STATUS_BADGES: Record<string, { label: string; bg: string; text: string }> = {
  active:    { label: '已激活', bg: 'rgba(34,197,94,0.10)',    text: '#16a34a' },
  unused:    { label: '未使用', bg: 'rgba(59,130,246,0.10)',   text: '#2563eb' },
  expired:   { label: '已过期', bg: 'rgba(245,158,11,0.10)',   text: '#d97706' },
  disabled:  { label: '已禁用', bg: 'rgba(239,68,68,0.10)',    text: '#dc2626' },
}

const formatTime = (iso?: string | null): string =>
  iso ? new Date(iso).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'

export default function CardManagement({ token }: { token: string }) {
  const [licenses, setLicenses] = useState<License[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [statusFilter, setStatusFilter] = useState('')

  const [showGenerate, setShowGenerate] = useState(false)
  const [genPlan, setGenPlan] = useState('year1')
  const [genCount, setGenCount] = useState(1)
  const [genRemark, setGenRemark] = useState('')
  const [generated, setGenerated] = useState<string[]>([])
  const [submitting, setSubmitting] = useState('')

  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  const fetchLicenses = useCallback(async () => {
    setLoading(true); setError('')
    const params = new URLSearchParams({ limit: '100', offset: '0' })
    if (statusFilter) params.set('status', statusFilter)
    try {
      const r = await fetch(`/api/biz/v2/licenses/?${params}`, { headers })
      if (!r.ok) throw new Error(`请求失败 (${r.status})`)
      const d = await r.json()
      setLicenses(d.results || [])
      setTotal(d.count ?? 0)
    } catch (err: any) {
      setError(err.message || '加载失败'); setLicenses([])
    } finally { setLoading(false) }
  }, [token, statusFilter])

  useEffect(() => { fetchLicenses() }, [fetchLicenses])

  const handleGenerate = async () => {
    if (submitting) return
    setSubmitting('gen'); setError('')
    try {
      const r = await fetch('/api/biz/v2/licenses/generate/', {
        method: 'POST', headers,
        body: JSON.stringify({ count: genCount, plan: genPlan, remark: genRemark }),
      })
      if (!r.ok) throw new Error((await r.text()).slice(0, 60))
      const d = await r.json()
      setGenerated(d.keys || [])
      setShowGenerate(false)
      setGenRemark('')
      await fetchLicenses()
    } catch (err: any) {
      setError(err.message || '生成失败')
    } finally { setSubmitting('') }
  }

  const handleDisable = async (id: number) => {
    if (submitting) return
    setSubmitting('dis-' + id)
    try {
      const r = await fetch(`/api/biz/v2/licenses/${id}/disable/`, { method: 'POST', headers })
      if (!r.ok) throw new Error('禁用失败')
      await fetchLicenses()
    } catch { setError('禁用失败') } finally { setSubmitting('') }
  }

  const handleSetQuota = async (lic: License) => {
    const deviceRaw = prompt(`设置「${lic.key}」设备配额上限（空=恢复套餐默认 ${PLAN_META[lic.plan]?.device ?? '—'}）`, lic.device_limit?.toString() ?? '')
    if (deviceRaw === null) return
    const accountRaw = prompt(`设置「${lic.key}」账号配额上限（空=恢复套餐默认 ${PLAN_META[lic.plan]?.account ?? '—'}）`, lic.account_limit?.toString() ?? '')
    if (accountRaw === null) return
    setSubmitting('quota-' + lic.id)
    try {
      const r = await fetch(`/api/biz/v2/licenses/${lic.id}/quota/`, {
        method: 'POST', headers,
        body: JSON.stringify({
          device_limit: deviceRaw.trim() === '' ? null : parseInt(deviceRaw, 10),
          account_limit: accountRaw.trim() === '' ? null : parseInt(accountRaw, 10),
        }),
      })
      if (!r.ok) throw new Error('设置失败')
      await fetchLicenses()
    } catch { setError('设置配额失败') } finally { setSubmitting('') }
  }

  const planOf = (plan: string) => PLAN_META[plan] || { device: '—', account: '—' }

  return (
    <div className="space-y-5">
      {/* 顶部操作栏 */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>卡密管理</span>
          <span className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>共 {total} 张</span>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={statusFilter}
            onChange={e => setStatusFilter(e.target.value)}
            className="rounded-lg px-3 py-2 text-sm outline-none cursor-pointer"
            style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}
          >
            <option value="">全部状态</option>
            <option value="unused">未使用</option>
            <option value="active">已激活</option>
            <option value="expired">已过期</option>
            <option value="disabled">已禁用</option>
          </select>
          <button onClick={() => { setShowGenerate(true); setError('') }}
            className="px-4 py-2 rounded-lg text-xs font-medium cursor-pointer"
            style={{ background: '#1677FF', color: '#fff' }}>
            ＋ 生成卡密
          </button>
        </div>
      </div>

      {/* 错误提示 */}
      {error && (
        <div className="px-5 py-2 rounded-lg text-xs flex justify-between" style={{ background: 'rgba(239,68,68,0.08)', color: '#dc2626' }}>
          <span>{error}</span>
          <button onClick={() => setError('')} className="underline cursor-pointer">关闭</button>
        </div>
      )}

      {/* 生成结果 */}
      {generated.length > 0 && (
        <div className="xx-card rounded-xl p-5" style={{ borderLeft: '3px solid #16a34a' }}>
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>✅ 已生成 {generated.length} 张卡密</span>
            <button onClick={() => setGenerated([])} className="text-xs cursor-pointer underline" style={{ color: '#16a34a' }}>收起</button>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
            {generated.map(k => (
              <div key={k} className="flex items-center justify-between px-3 py-2 rounded-lg font-mono text-sm"
                style={{ background: 'rgba(34,197,94,0.06)', color: 'rgba(0,0,0,0.70)' }}>
                <span>{k}</span>
                <button
                  onClick={() => navigator.clipboard?.writeText(k)}
                  className="text-[10px] px-2 py-0.5 rounded cursor-pointer"
                  style={{ background: 'rgba(22,119,255,0.10)', color: '#1677FF' }}
                >复制</button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* 生成弹窗 */}
      {showGenerate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setShowGenerate(false)}>
          <div className="xx-card rounded-xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>生成卡密</h4>
              <button onClick={() => setShowGenerate(false)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>套餐</label>
                <select value={genPlan} onChange={e => setGenPlan(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none cursor-pointer"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)', color: 'rgba(0,0,0,0.55)' }}>
                  <option value="year1">年卡（20台 / 200账号）</option>
                  <option value="month3">季卡（8台 / 80账号）</option>
                  <option value="month1">月卡（3台 / 30账号）</option>
                </select>
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>数量</label>
                <input type="number" min={1} max={100} value={genCount}
                  onChange={e => setGenCount(Math.max(1, Math.min(100, parseInt(e.target.value) || 1)))}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }} />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>备注（客户名等）</label>
                <input type="text" value={genRemark} onChange={e => setGenRemark(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="可选" />
              </div>
              <button onClick={handleGenerate} disabled={!!submitting}
                className="w-full py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                style={{ background: '#1677FF', color: '#fff' }}>
                {submitting === 'gen' ? '生成中...' : '确认生成'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 卡密表格 */}
      <div className="xx-card rounded-xl overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-16" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
        ) : licenses.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-3 text-2xl" style={{ background: 'rgba(0,0,0,0.04)' }}>🎫</div>
            <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>暂无卡密</p>
          </div>
        ) : (
          <>
            <div className="px-5 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(0,0,0,0.06)' }}>
              <span className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>卡密列表</span>
              <span className="text-xs" style={{ color: 'rgba(0,0,0,0.35)' }}>共 {total} 条</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm whitespace-nowrap">
                <thead>
                  <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                    <th className="pb-2 pt-3 px-4 font-medium">卡密</th>
                    <th className="pb-2 pt-3 px-4 font-medium">套餐</th>
                    <th className="pb-2 pt-3 px-4 font-medium">状态</th>
                    <th className="pb-2 pt-3 px-4 font-medium">绑定设备</th>
                    <th className="pb-2 pt-3 px-4 font-medium">归属租户</th>
                    <th className="pb-2 pt-3 px-4 font-medium text-right">配额(设备/账号)</th>
                    <th className="pb-2 pt-3 px-4 font-medium">到期时间</th>
                    <th className="pb-2 pt-3 px-4 font-medium">备注</th>
                    <th className="pb-2 pt-3 px-4 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {licenses.map(lic => {
                    const meta = planOf(lic.plan)
                    const badge = STATUS_BADGES[lic.status] || { label: lic.status, bg: 'rgba(0,0,0,0.05)', text: 'rgba(0,0,0,0.35)' }
                    const dLimit = lic.device_limit ?? meta.device
                    const aLimit = lic.account_limit ?? meta.account
                    return (
                      <tr key={lic.id} className="border-b" style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                        <td className="py-3 px-4">
                          <span className="font-mono text-xs">{lic.key}</span>
                        </td>
                        <td className="py-3 px-4 text-xs">{PLAN_LABELS[lic.plan] || lic.plan}</td>
                        <td className="py-3 px-4">
                          <span className="inline-flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full" style={{ background: badge.bg, color: badge.text }}>
                            <span className="w-1.5 h-1.5 rounded-full" style={{ background: badge.text }} />
                            {badge.label}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-xs font-mono" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {lic.device_id || '—'}
                        </td>
                        <td className="py-3 px-4 text-xs">
                          {lic.api_id ? (
                            <span className="font-mono px-2 py-0.5 rounded" style={{ background: 'rgba(108,92,231,0.10)', color: '#6c5ce7' }}>
                              {lic.api_id}
                            </span>
                          ) : <span style={{ color: 'rgba(0,0,0,0.25)' }}>—</span>}
                        </td>
                        <td className="py-3 px-4 text-right text-xs">
                          <span style={{ color: 'rgba(0,0,0,0.55)' }}>{dLimit}</span>
                          <span style={{ color: 'rgba(0,0,0,0.25)' }}> / {aLimit}</span>
                        </td>
                        <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {lic.status === 'active' ? formatTime(lic.expires_at) : '—'}
                        </td>
                        <td className="py-3 px-4 text-xs" style={{ color: 'rgba(0,0,0,0.40)' }}>
                          {lic.remark || '—'}
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-1">
                            {lic.status !== 'disabled' && (
                              <button onClick={() => handleDisable(lic.id)}
                                disabled={submitting === 'dis-' + lic.id}
                                className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                                style={{ color: '#dc2626', background: 'rgba(239,68,68,0.08)' }}>
                                禁用
                              </button>
                            )}
                            <button onClick={() => handleSetQuota(lic)}
                              disabled={!!submitting}
                              className="text-xs px-2 py-0.5 rounded cursor-pointer disabled:opacity-50"
                              style={{ color: '#1677FF', background: 'rgba(22,119,255,0.08)' }}>
                              改配额
                            </button>
                          </div>
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
    </div>
  )
}
