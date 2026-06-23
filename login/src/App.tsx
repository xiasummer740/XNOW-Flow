import { useState } from 'react'
import Dashboard from './Dashboard'

function App() {
  const [username, setUsername] = useState('yk0417')
  const [password, setPassword] = useState('123456')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [token, setToken] = useState('')
  const [loggedIn, setLoggedIn] = useState(false)
  const [userInfo, setUserInfo] = useState<any>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    try {
      const res = await fetch('/api/auth/login/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      })

      if (!res.ok) {
        const text = await res.text()
        throw new Error(text || '登录失败，请检查账号密码')
      }

      const data = await res.json()
      setToken(data.token)
      setUserInfo(data.user)
      setLoggedIn(true)
    } catch (err: any) {
      setError(err.message || '网络错误')
    } finally {
      setLoading(false)
    }
  }

  if (loggedIn) {
    return <Dashboard user={userInfo} token={token} onLogout={() => { setLoggedIn(false); setUserInfo(null); setToken('') }} />
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 login-page">
      {/* 发光覆盖层 */}
      <div className="xx-glow-overlay" />

      {/* 登录卡片 — 磨砂玻璃 */}
      <div className="login-card w-full max-w-md p-8 md:p-10">
        {/* 品牌 Logo */}
        <div className="text-center mb-8">
          <svg viewBox="0 0 48 48" fill="none" className="w-14 h-14 mx-auto"
            style={{ filter: 'drop-shadow(0 0 10px rgba(168,85,247,0.4))' }}>
            <defs>
              <linearGradient id="loginLogoGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#a855f7" />
                <stop offset="50%" stop-color="#3b82f6" />
                <stop offset="100%" stop-color="#14b8a6" />
              </linearGradient>
            </defs>
            <path d="M34 6H28.5C25.18 6 22 8.46 22 12.5V22H16v6h6v14h6V28h5l1-6h-6v-8.5c0-1.38 0.88-2.5 2.5-2.5H34V6z" fill="url(#loginLogoGrad)" />
          </svg>
          <h1 className="xx-brand-text text-2xl font-bold mt-3">XNOW 云控</h1>
          <p className="text-sm mt-1" style={{ color: 'rgba(0,0,0,0.45)' }}>多设备批量管理 · 智能任务调度</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <div className="flex items-center gap-3 px-3 py-2.5 rounded-lg"
              style={{ background: 'rgba(255,255,255,0.25)', backdropFilter: 'blur(4px)', border: '1px solid rgba(255,255,255,0.30)' }}>
              <svg className="w-5 h-5 shrink-0" style={{ color: 'rgba(0,0,0,0.35)' }} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                <circle cx="12" cy="7" r="4" />
              </svg>
              <input
                type="text"
                value={username}
                onChange={e => setUsername(e.target.value)}
                placeholder="请输入用户名"
                className="w-full bg-transparent outline-none text-sm"
                style={{ color: 'rgba(0,0,0,0.75)', background: 'transparent !important', border: 'none !important', boxShadow: 'none !important' }}
              />
            </div>
          </div>

          <div>
            <div className="flex items-center gap-3 px-3 py-2.5 rounded-lg"
              style={{ background: 'rgba(255,255,255,0.25)', backdropFilter: 'blur(4px)', border: '1px solid rgba(255,255,255,0.30)' }}>
              <svg className="w-5 h-5 shrink-0" style={{ color: 'rgba(0,0,0,0.35)' }} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
              <input
                type="password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                placeholder="请输入密码"
                className="w-full bg-transparent outline-none text-sm"
                style={{ color: 'rgba(0,0,0,0.75)', background: 'transparent !important', border: 'none !important', boxShadow: 'none !important' }}
              />
            </div>
          </div>

          {error && (
            <div className="text-red-500 text-xs text-center py-2 rounded"
              style={{ background: 'rgba(239,68,68,0.10)', backdropFilter: 'blur(4px)' }}>
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="xx-btn-primary w-full py-2.5 rounded-lg text-sm font-medium cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading ? '登录中...' : '登 录'}
          </button>

          <p className="text-xs text-center" style={{ color: 'rgba(0,0,0,0.35)' }}>
            测试账号: yk0417 / 123456
          </p>
        </form>
      </div>

      <p className="absolute bottom-4 text-xs" style={{ color: 'rgba(0,0,0,0.30)' }}>
        XNOW Cloud Control © 2026
      </p>
    </div>
  )
}

export default App
