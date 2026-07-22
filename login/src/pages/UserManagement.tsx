import { useState, useEffect } from 'react'

export default function UserManagement({ token }: { token: string }) {
  const [users, setUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showCreate, setShowCreate] = useState(false)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [creating, setCreating] = useState(false)
  const [msg, setMsg] = useState('')

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
              </tr>
            </thead>
            <tbody>
              {users.map(u => (
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
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
