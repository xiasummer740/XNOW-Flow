import { useState } from 'react'

export default function Settings({ token, user }: { token: string; user?: any }) {
  const [oldPwd, setOldPwd] = useState('')
  const [newPwd, setNewPwd] = useState('')
  const [confirmPwd, setConfirmPwd] = useState('')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState('')

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
