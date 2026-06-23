import { useState } from 'react'
import Dashboard from './Dashboard'

function App() {
  const [username, setUsername] = useState('yk0417')
  const [password, setPassword] = useState('123456')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
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
      setUserInfo(data.user)
      setLoggedIn(true)
    } catch (err: any) {
      setError(err.message || '网络错误')
    } finally {
      setLoading(false)
    }
  }

  if (loggedIn) {
    return <Dashboard user={userInfo} onLogout={() => { setLoggedIn(false); setUserInfo(null) }} />
  }

  return (
    <div className="min-h-screen flex bg-[#0F1923] font-sans">
      {/* 左侧品牌区 */}
      <div className="hidden lg:flex w-1/2 relative overflow-hidden items-center justify-center bg-gradient-to-br from-[#0F1923] via-[#152232] to-[#1a2b3d]">
        <div className="absolute -top-40 -right-40 w-96 h-96 rounded-full bg-blue-500/5 blur-3xl" />
        <div className="absolute top-1/3 -left-20 w-64 h-64 rounded-full bg-purple-500/5 blur-3xl" />
        <div className="absolute bottom-20 right-1/4 w-48 h-48 rounded-full bg-cyan-500/5 blur-2xl" />

        <div className="relative z-10 text-center px-16">
          <div className="w-16 h-16 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-blue-500 to-cyan-400 flex items-center justify-center shadow-lg shadow-blue-500/20">
            <svg viewBox="0 0 48 48" fill="none" className="w-8 h-8">
              <path d="M34 6H28.5C25.18 6 22 8.46 22 12.5V22H16v6h6v14h6V28h5l1-6h-6v-8.5c0-1.38 0.88-2.5 2.5-2.5H34V6z" fill="white" />
            </svg>
          </div>
          <h1 className="text-3xl font-bold text-white mb-3">XNOW 云控系统</h1>
          <p className="text-gray-400 text-sm mb-10">
            多设备批量管理 · 智能任务调度 · 数据采集分析
          </p>

          <div className="space-y-4 text-left max-w-xs mx-auto">
            {[
              '批量关注 / 私信 / 评论',
              '多账号矩阵管理',
              '实时数据采集与分析',
            ].map((item, i) => (
              <div key={i} className="flex items-center gap-3">
                <span className="w-1.5 h-1.5 rounded-full bg-blue-400 shrink-0" />
                <span className="text-gray-300 text-sm">{item}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* 右侧登录区 */}
      <div className="w-full lg:w-1/2 flex items-center justify-center p-8 bg-gray-50">
        <div className="w-full max-w-sm">
          {/* 移动端品牌 */}
          <div className="lg:hidden text-center mb-10">
            <div className="w-12 h-12 mx-auto mb-4 rounded-xl bg-gradient-to-br from-blue-500 to-cyan-400 flex items-center justify-center shadow-lg">
              <svg viewBox="0 0 48 48" fill="none" className="w-6 h-6">
                <path d="M34 6H28.5C25.18 6 22 8.46 22 12.5V22H16v6h6v14h6V28h5l1-6h-6v-8.5c0-1.38 0.88-2.5 2.5-2.5H34V6z" fill="white" />
              </svg>
            </div>
            <h1 className="text-xl font-bold text-gray-900">XNOW 云控系统</h1>
            <p className="text-gray-500 text-sm mt-1">多设备批量管理</p>
          </div>

          {/* 登录卡片 */}
          <div className="bg-white rounded-2xl p-8 shadow-sm border border-gray-100">
            <div className="text-center mb-8">
              <h2 className="text-xl font-semibold text-gray-900">欢迎登录</h2>
              <p className="text-gray-500 text-sm mt-1">请使用管理员账号登录后台</p>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              <div>
                <div className="flex items-center gap-3 border-b border-gray-200 pb-2 px-1 focus-within:border-blue-500 transition-colors">
                  <svg className="w-5 h-5 text-gray-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                    <circle cx="12" cy="7" r="4" />
                  </svg>
                  <input
                    type="text"
                    value={username}
                    onChange={e => setUsername(e.target.value)}
                    placeholder="请输入用户名"
                    className="w-full bg-transparent outline-none text-gray-700 placeholder-gray-400 text-sm py-1"
                  />
                </div>
              </div>

              <div>
                <div className="flex items-center gap-3 border-b border-gray-200 pb-2 px-1 focus-within:border-blue-500 transition-colors">
                  <svg className="w-5 h-5 text-gray-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                  </svg>
                  <input
                    type="password"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    placeholder="请输入密码"
                    className="w-full bg-transparent outline-none text-gray-700 placeholder-gray-400 text-sm py-1"
                  />
                </div>
              </div>

              {error && (
                <div className="text-red-500 text-xs text-center bg-red-50 py-2 rounded">
                  {error}
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full py-2.5 bg-[#1677FF] hover:bg-blue-600 active:bg-blue-700 disabled:bg-blue-300 text-white rounded-lg text-sm font-medium transition-colors cursor-pointer disabled:cursor-not-allowed"
              >
                {loading ? '登录中...' : '登 录'}
              </button>

              <p className="text-xs text-gray-400 text-center">
                测试账号: yk0417 / 123456
              </p>
            </form>
          </div>

          <p className="text-center text-gray-400 text-xs mt-6">
            XNOW Cloud Control © 2026
          </p>
        </div>
      </div>
    </div>
  )
}

export default App
