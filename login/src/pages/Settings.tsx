import { useState, useEffect } from 'react'

export default function Settings({ token, user }: { token: string; user?: any }) {
  const [oldPwd, setOldPwd] = useState('')
  const [newPwd, setNewPwd] = useState('')
  const [confirmPwd, setConfirmPwd] = useState('')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState('')
  const [quota, setQuota] = useState<any>(null)

  useEffect(() => {
    if (user?.role === 'admin') return
    fetch('/api/biz/v2/quota/', {
      headers: { Authorization: `Token ${token}` },
    })
      .then(r => r.ok ? r.json() : null)
      .then(d => setQuota(d))
      .catch(() => {})
  }, [token, user?.role])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (newPwd !== confirmPwd) { setMsg('两次密码不一致'); return }
    if (newPwd.length < 6) { setMsg('密码至少6位'); return }
    setSaving(true)
    setMsg('')
    try {
      const r = await fetch('/api/auth/password/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Token ${token}` },
        body: JSON.stringify({ old_password: oldPwd, new_password: newPwd }),
      })
      if (!r.ok) throw new Error(await r.text() || '修改失败')
      setMsg('密码修改成功')
      setOldPwd(''); setNewPwd(''); setConfirmPwd('')
    } catch (err: any) {
      setMsg(err.message || '网络错误')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="max-w-lg">
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100">
          <h3 className="text-sm font-medium text-gray-700">安全设置</h3>
        </div>
        <div className="p-5">
          <div className="mb-5">
            <label className="text-xs text-gray-400 block mb-1">当前账号</label>
            <p className="text-sm text-gray-700">{user?.username || '—'}</p>
          </div>
          <div className="mb-5 p-3 rounded-lg" style={{ background: 'rgba(108,92,231,0.08)' }}>
            <label className="text-xs text-gray-400 block mb-1">API ID（绑定手机用）</label>
            <p className="text-sm font-mono font-bold" style={{ color: '#6c5ce7' }}>{user?.api_id || '—'}</p>
            <p className="text-xs mt-1" style={{ color: 'rgba(0,0,0,0.35)' }}>每台手机绑定时填入此 API ID 即可关联到您的账号</p>
          </div>

          {quota && (
            <div className="mb-5 p-3 rounded-lg" style={{ background: 'rgba(22,119,255,0.06)' }}>
              <label className="text-xs text-gray-400 block mb-2">商用配额</label>
              <div className="flex items-center gap-2 mb-1.5">
                <span className="text-xs" style={{ color: 'rgba(0,0,0,0.45)' }}>设备</span>
                <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: 'rgba(0,0,0,0.06)' }}>
                  <div className="h-full rounded-full" style={{
                    width: `${quota.device_limit ? Math.min(100, (quota.device_used / quota.device_limit) * 100) : 0}%`,
                    background: (quota.device_used ?? 0) >= (quota.device_limit ?? 0) ? '#dc2626' : '#1677FF',
                  }} />
                </div>
                <span className="text-xs font-mono" style={{ color: 'rgba(0,0,0,0.65)' }}>
                  {quota.device_used ?? 0}/{quota.device_limit ?? 0}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs" style={{ color: 'rgba(0,0,0,0.45)' }}>账号</span>
                <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: 'rgba(0,0,0,0.06)' }}>
                  <div className="h-full rounded-full" style={{
                    width: `${quota.account_limit ? Math.min(100, (quota.account_used / quota.account_limit) * 100) : 0}%`,
                    background: (quota.account_used ?? 0) >= (quota.account_limit ?? 0) ? '#dc2626' : '#16a34a',
                  }} />
                </div>
                <span className="text-xs font-mono" style={{ color: 'rgba(0,0,0,0.65)' }}>
                  {quota.account_used ?? 0}/{quota.account_limit ?? 0}
                </span>
              </div>
              {!quota.licensed && (
                <p className="text-xs mt-2" style={{ color: '#dc2626' }}>
                  ⚠️ 未激活卡密，请先在手机上输入卡密激活
                </p>
              )}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="text-xs text-gray-400 block mb-1">原密码</label>
              <input type="password" value={oldPwd} onChange={e => setOldPwd(e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 transition-colors"
                placeholder="请输入原密码" />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">新密码</label>
              <input type="password" value={newPwd} onChange={e => setNewPwd(e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 transition-colors"
                placeholder="请输入新密码" />
            </div>
            <div>
              <label className="text-xs text-gray-400 block mb-1">确认新密码</label>
              <input type="password" value={confirmPwd} onChange={e => setConfirmPwd(e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400 transition-colors"
                placeholder="请再次输入新密码" />
            </div>

            {msg && (
              <div className={`text-xs py-2 px-3 rounded ${msg.includes('成功') ? 'bg-green-50 text-green-600' : 'bg-red-50 text-red-500'}`}>
                {msg}
              </div>
            )}

            <button type="submit" disabled={saving || !oldPwd || !newPwd || !confirmPwd}
              className="px-6 py-2 bg-[#1677FF] hover:bg-blue-600 active:bg-blue-700 disabled:bg-blue-300 text-white rounded-lg text-sm font-medium transition-colors cursor-pointer disabled:cursor-not-allowed">
              {saving ? '保存中...' : '修改密码'}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
