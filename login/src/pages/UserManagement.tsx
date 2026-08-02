import { useState, useEffect } from 'react'

export default function UserManagement({ token }: { token: string }) {
  const [users, setUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showCreate, setShowCreate] = useState(false)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [creating, setCreating] = useState(false)
  const [msg, setMsg] = useState('')
  const [quotaEditing, setQuotaEditing] = useState<number | null>(null)
  const [deviceLimit, setDeviceLimit] = useState('')
  const [accountLimit, setAccountLimit] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const headers = { Authorization: `Token ${token}`, 'Content-Type': 'application/json' }

  const fetchUsers = async () => {
    setLoading(true)
    try {
      const r = await fetch('/api/auth/users/', { headers })
      if (r.ok) {
        const d = await r.json()
        setUsers(d.results || [])
      }
    } catch {} finally { setLoading(false) }
  }

  useEffect(() => { fetchUsers() }, [])

  const handleCreate = async () => {
    if (!username || !password) return
    setCreating(true); setMsg('')
    try {
      const r = await fetch('/api/auth/register/', {
        method: 'POST', headers,
        body: JSON.stringify({ username, password }),
      })
      if (!r.ok) throw new Error((await r.text()).slice(0, 60))
      setMsg(`✅ 用户 ${username} 创建成功`)
      setUsername(''); setPassword(''); setShowCreate(false)
      fetchUsers()
    } catch (e: any) { setMsg('❌ ' + e.message) }
    finally { setCreating(false) }
  }

  const openQuota = (u: any) => {
    setQuotaEditing(u.id)
    setDeviceLimit(u.device_limit?.toString() ?? '')
    setAccountLimit(u.account_limit?.toString() ?? '')
    setMsg('')
  }

  const handleSetQuota = async () => {
    if (submitting) return
    setSubmitting(true); setMsg('')
    try {
      const r = await fetch(`/api/auth/users/${quotaEditing}/quota/`, {
        method: 'PATCH', headers,
        body: JSON.stringify({
          device_limit: deviceLimit.trim() === '' ? null : Math.max(0, parseInt(deviceLimit, 10) || 0),
          account_limit: accountLimit.trim() === '' ? null : Math.max(0, parseInt(accountLimit, 10) || 0),
        }),
      })
      if (!r.ok) throw new Error((await r.text()).slice(0, 60))
      setMsg('✅ 配额已更新')
      setQuotaEditing(null)
      fetchUsers()
    } catch (e: any) { setMsg('❌ ' + e.message) }
    finally { setSubmitting(false) }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>用户管理</h3>
        <button onClick={() => { setShowCreate(true); setMsg('') }}
          className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
          style={{ background: '#1677FF', color: '#fff' }}>
          + 创建用户
        </button>
      </div>

      {msg && (
        <div className="px-4 py-2 rounded-lg text-xs" style={{
          background: msg.includes('✅') ? 'rgba(34,197,94,0.10)' : 'rgba(239,68,68,0.08)',
          color: msg.includes('✅') ? '#16a34a' : '#dc2626'
        }}>{msg}</div>
      )}

      {showCreate && (
        <div className="xx-card rounded-xl p-5 space-y-3">
          <div>
            <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>用户名</label>
            <input type="text" value={username} onChange={e => setUsername(e.target.value)}
              className="w-full rounded-lg px-3 py-2 text-sm outline-none"
              style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
              placeholder="输入用户名" />
          </div>
          <div>
            <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>密码</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)}
              className="w-full rounded-lg px-3 py-2 text-sm outline-none"
              style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
              placeholder="输入密码" />
          </div>
          <div className="flex gap-2">
            <button onClick={() => setShowCreate(false)}
              className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer"
              style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.50)' }}>取消</button>
            <button onClick={handleCreate} disabled={creating || !username || !password}
              className="px-4 py-1.5 rounded-lg text-xs font-medium cursor-pointer disabled:opacity-50"
              style={{ background: '#1677FF', color: '#fff' }}>
              {creating ? '创建中...' : '确认创建'}
            </button>
          </div>
        </div>
      )}

      <div className="xx-card rounded-xl overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-12" style={{ color: 'rgba(0,0,0,0.35)' }}>加载中...</div>
        ) : users.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-center">
            <p className="text-sm" style={{ color: 'rgba(0,0,0,0.35)' }}>暂无用户</p>
          </div>
        ) : (
          <table className="w-full text-sm whitespace-nowrap">
            <thead>
              <tr className="text-left text-xs border-b" style={{ color: 'rgba(0,0,0,0.35)', borderColor: 'rgba(0,0,0,0.06)' }}>
                <th className="pb-2 pt-3 px-4 font-medium">ID</th>
                <th className="pb-2 pt-3 px-4 font-medium">用户名</th>
                <th className="pb-2 pt-3 px-4 font-medium">API ID</th>
                <th className="pb-2 pt-3 px-4 font-medium">状态</th>
                <th className="pb-2 pt-3 px-4 font-medium">卡密</th>
                <th className="pb-2 pt-3 px-4 font-medium">配额(设备)</th>
                <th className="pb-2 pt-3 px-4 font-medium">配额(账号)</th>
                <th className="pb-2 pt-3 px-4 font-medium">操作</th>
              </tr>
            </thead>
            <tbody>
              {users.map(u => {
                const overDevice = u.device_limit != null
                const overAccount = u.account_limit != null
                const dLimit = u.device_limit ?? u.device_limit_by_card
                const aLimit = u.account_limit ?? u.account_limit_by_card
                return (
                <tr key={u.id} className="border-b" style={{ borderColor: 'rgba(0,0,0,0.04)', color: 'rgba(0,0,0,0.65)' }}>
                  <td className="py-3 px-4 text-xs">{u.id}</td>
                  <td className="py-3 px-4">{u.username}</td>
                  <td className="py-3 px-4">
                    <span className="font-mono text-xs px-2 py-0.5 rounded" style={{ background: 'rgba(108,92,231,0.10)', color: '#6c5ce7' }}>
                      {u.api_id || '—'}
                    </span>
                  </td>
                  <td className="py-3 px-4">
                    <span className="text-xs" style={{ color: u.is_active ? '#16a34a' : '#dc2626' }}>
                      {u.is_active ? '正常' : '禁用'}
                    </span>
                  </td>
                  <td className="py-3 px-4 text-xs">{u.card_count ?? 0} 张</td>
                  <td className="py-3 px-4 text-xs">
                    <span style={{ color: 'rgba(0,0,0,0.55)' }}>{u.device_used ?? 0}</span>
                    <span style={{ color: 'rgba(0,0,0,0.25)' }}> / {dLimit ?? '—'}</span>
                    {overDevice && <span className="ml-1 text-[10px] px-1 rounded" style={{ background: 'rgba(108,92,231,0.10)', color: '#6c5ce7' }}>自定义</span>}
                  </td>
                  <td className="py-3 px-4 text-xs">
                    <span style={{ color: 'rgba(0,0,0,0.55)' }}>{u.account_used ?? 0}</span>
                    <span style={{ color: 'rgba(0,0,0,0.25)' }}> / {aLimit ?? '—'}</span>
                    {overAccount && <span className="ml-1 text-[10px] px-1 rounded" style={{ background: 'rgba(108,92,231,0.10)', color: '#6c5ce7' }}>自定义</span>}
                  </td>
                  <td className="py-3 px-4">
                    <button onClick={() => openQuota(u)}
                      className="text-xs px-2 py-0.5 rounded cursor-pointer"
                      style={{ color: '#1677FF', background: 'rgba(22,119,255,0.08)' }}>
                      设置配额
                    </button>
                  </td>
                </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* 设置配额弹窗 */}
      {quotaEditing != null && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: 'rgba(0,0,0,0.30)' }}
          onClick={() => setQuotaEditing(null)}>
          <div className="xx-card rounded-xl w-full max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium" style={{ color: 'rgba(0,0,0,0.65)' }}>设置用户配额</h4>
              <button onClick={() => setQuotaEditing(null)} className="text-lg cursor-pointer" style={{ color: 'rgba(0,0,0,0.25)' }}>✕</button>
            </div>
            <p className="text-xs mb-3" style={{ color: 'rgba(0,0,0,0.40)' }}>
              留空 = 按名下卡密套餐计算（推荐）；填写 = 管理员直接指定上限
            </p>
            <div className="space-y-3">
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>设备上限</label>
                <input type="number" min={0} value={deviceLimit} onChange={e => setDeviceLimit(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="留空按卡算" />
              </div>
              <div>
                <label className="text-xs block mb-1" style={{ color: 'rgba(0,0,0,0.40)' }}>账号上限</label>
                <input type="number" min={0} value={accountLimit} onChange={e => setAccountLimit(e.target.value)}
                  className="w-full rounded-lg px-3 py-2 text-sm outline-none"
                  style={{ background: 'rgba(255,255,255,0.40)', border: '1px solid rgba(0,0,0,0.12)' }}
                  placeholder="留空按卡算" />
              </div>
              {msg && (
                <div className={`text-xs py-2 px-3 rounded ${msg.includes('✅') ? 'bg-green-50 text-green-600' : 'bg-red-50 text-red-500'}`}>
                  {msg}
                </div>
              )}
              <div className="flex gap-2">
                <button onClick={() => setQuotaEditing(null)}
                  className="flex-1 py-2 rounded-lg text-sm font-medium cursor-pointer"
                  style={{ background: 'rgba(0,0,0,0.05)', color: 'rgba(0,0,0,0.50)' }}>
                  取消
                </button>
                <button onClick={handleSetQuota} disabled={submitting}
                  className="flex-1 py-2 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50"
                  style={{ background: '#1677FF', color: '#fff' }}>
                  {submitting ? '保存中...' : '保存'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
