import { useState, useEffect, useCallback } from 'react'

interface PublicUser {
  id: number
  aweme_id: string
  nickname: string
  avatar_url: string
  gender: string
  country: string
  followers: number
  following_count: number
  age: number
  videos_count: number
  signature: string
  keyword: string
  ai_tagged: number
  created_at: string
}

interface Stats {
  total: number
  tagged: number
  by_gender: Record<string, number>
  by_country: Record<string, number>
}

const genderLabels: Record<string, string> = { male: '男', female: '女', unknown: '未知' }

const genderBadge: Record<string, string> = {
  male: 'bg-blue-50 text-blue-500',
  female: 'bg-pink-50 text-pink-500',
  unknown: 'bg-gray-50 text-gray-400',
}

export default function PublicLibrary({ token }: { token: string }) {
  const [data, setData] = useState<PublicUser[]>([])
  const [stats, setStats] = useState<Stats>({ total: 0, tagged: 0, by_gender: {}, by_country: {} })
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')

  // 筛选
  const [search, setSearch] = useState('')
  const [gender, setGender] = useState('')
  const [country, setCountry] = useState('')
  const [keyword, setKeyword] = useState('')
  const [taggedOnly, setTaggedOnly] = useState('')
  const [ageMin, setAgeMin] = useState('')
  const [ageMax, setAgeMax] = useState('')

  // 选中
  const [selected, setSelected] = useState<number[]>([])
  const [groupName, setGroupName] = useState('未分组')
  const [showFeedModal, setShowFeedModal] = useState(false)
  const [feedCount, setFeedCount] = useState(200)
  const [feedAvatar, setFeedAvatar] = useState(true)

  const api = (path: string, opts: RequestInit = {}) =>
    fetch(path, {
      ...opts,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${token}`,
        ...(opts.headers || {}),
      },
    })

  const loadStats = useCallback(async () => {
    try {
      const res = await api('/api/biz/v2/public-users/stats/')
      if (res.ok) setStats(await res.json())
    } catch { /* ignore */ }
  }, [])

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const params = new URLSearchParams()
      if (gender) params.set('gender', gender)
      if (country) params.set('country', country)
      if (keyword) params.set('keyword', keyword)
      if (taggedOnly) params.set('ai_tagged', taggedOnly)
      if (search) params.set('search', search)
      params.set('limit', '50')
      const res = await api(`/api/biz/v2/public-users/?${params.toString()}`)
      if (res.ok) {
        const json = await res.json()
        setData(json.results ?? [])
      }
    } catch { /* ignore */ } finally {
      setLoading(false)
    }
  }, [gender, country, keyword, taggedOnly, search])

  useEffect(() => { loadData(); loadStats() }, [loadData, loadStats])

  const flash = (msg: string) => { setMessage(msg); setTimeout(() => setMessage(''), 4000) }

  const doFeed = async () => {
    const res = await api('/api/biz/v2/public-users/feed/', {
      method: 'POST',
      body: JSON.stringify({ require_avatar: feedAvatar, max_count: feedCount }),
    })
    const json = await res.json()
    flash(json.message || '投喂完成')
    setShowFeedModal(false)
    loadData(); loadStats()
  }

  const doTag = async () => {
    const res = await api('/api/biz/v2/public-users/tag/', {
      method: 'POST',
      body: JSON.stringify({ limit: 10 }),
    })
    if (res.status === 400) {
      const json = await res.json()
      flash(json.detail || '打标失败')
    } else {
      const json = await res.json()
      flash(json.message || '打标完成')
    }
    loadData(); loadStats()
  }

  const doCopy = async () => {
    if (selected.length === 0) { flash('请先勾选要复制的公共用户'); return }
    const res = await api('/api/biz/v2/public-users/copy/', {
      method: 'POST',
      body: JSON.stringify({ ids: selected, group_name: groupName }),
    })
    const json = await res.json()
    flash(json.message || '复制完成')
    setSelected([])
  }

  const toggle = (id: number) =>
    setSelected(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id])

  const toggleAll = () =>
    setSelected(prev => prev.length === data.length ? [] : data.map(d => d.id))

  // 年龄区间筛选（客户端过滤当前已加载数据；后端暂不支持 age_min/age_max 参数）
  const minAge = ageMin === '' ? null : Number(ageMin)
  const maxAge = ageMax === '' ? null : Number(ageMax)
  const visibleData = data.filter(u => {
    const a = u.age ?? 0
    if (minAge !== null && a < minAge) return false
    if (maxAge !== null && a > maxAge) return false
    return true
  })

  return (
    <div className="space-y-6">
      <h3 className="text-sm font-medium text-gray-700">公共用户库</h3>

      {message && (
        <div className="text-xs px-4 py-2 rounded-lg bg-blue-50 text-blue-600 border border-blue-100">
          {message}
        </div>
      )}

      {/* 统计 */}
      <div className="grid grid-cols-4 gap-4">
        {[
          { label: '公共库总数', val: stats.total, icon: '🌐', bg: 'bg-blue-50 text-blue-600' },
          { label: '已AI打标', val: stats.tagged, icon: '🏷️', bg: 'bg-purple-50 text-purple-600' },
          { label: '男性', val: stats.by_gender?.male ?? 0, icon: '👨', bg: 'bg-blue-50 text-blue-600' },
          { label: '女性', val: stats.by_gender?.female ?? 0, icon: '👩', bg: 'bg-pink-50 text-pink-600' },
        ].map(s => (
          <div key={s.label} className={`${s.bg} bg-opacity-50 rounded-xl p-4 border border-gray-100 shadow-sm`}>
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xs text-gray-500">{s.label}</div>
                <div className="text-xl font-bold mt-1">{s.val}</div>
              </div>
              <span className="text-2xl">{s.icon}</span>
            </div>
          </div>
        ))}
      </div>

      {/* 筛选 */}
      <div className="flex flex-wrap items-center gap-2">
        <input type="text" value={search} onChange={e => setSearch(e.target.value)}
          className="w-40 border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
          placeholder="🔍 昵称搜索..." />
        <select value={gender} onChange={e => setGender(e.target.value)}
          className="border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none">
          <option value="">全部性别</option>
          <option value="male">男</option>
          <option value="female">女</option>
          <option value="unknown">未知</option>
        </select>
        <input type="text" value={country} onChange={e => setCountry(e.target.value)}
          className="w-32 border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
          placeholder="国家" />
        <input type="text" value={keyword} onChange={e => setKeyword(e.target.value)}
          className="w-40 border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
          placeholder="关键词(如 颜值)" />
        <select value={taggedOnly} onChange={e => setTaggedOnly(e.target.value)}
          className="border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none">
          <option value="">全部打标状态</option>
          <option value="1">已打标</option>
          <option value="0">未打标</option>
        </select>
        <input type="number" value={ageMin} onChange={e => setAgeMin(e.target.value)}
          className="w-20 border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
          placeholder="年龄≥" />
        <input type="number" value={ageMax} onChange={e => setAgeMax(e.target.value)}
          className="w-20 border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
          placeholder="年龄≤" />
      </div>

      {/* 操作栏 */}
      <div className="flex flex-wrap items-center gap-3">
        <button onClick={() => setShowFeedModal(true)}
          className="px-4 py-2 rounded-lg bg-blue-500 text-white text-sm hover:bg-blue-600 cursor-pointer">
          ⬆️ 投喂公共库
        </button>
        <button onClick={doTag}
          className="px-4 py-2 rounded-lg bg-purple-500 text-white text-sm hover:bg-purple-600 cursor-pointer">
          🏷️ AI 头像打标
        </button>
        <input type="text" value={groupName} onChange={e => setGroupName(e.target.value)}
          className="w-36 border border-gray-200 rounded-lg px-3 py-2 text-sm outline-none focus:border-blue-400"
          placeholder="目标分组" />
        <button onClick={doCopy}
          className={`px-4 py-2 rounded-lg text-sm cursor-pointer ${
            selected.length ? 'bg-green-500 text-white hover:bg-green-600' : 'bg-gray-100 text-gray-400'
          }`}>
          📥 复制到我的分组 ({selected.length})
        </button>
      </div>

      {/* 表格 */}
      <div className="xx-card rounded-xl">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700">公共用户</span>
          <span className="text-xs text-gray-400">共 {visibleData.length} 条</span>
        </div>
        {loading ? (
          <div className="flex items-center justify-center py-16">
            <div className="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : visibleData.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-gray-50 flex items-center justify-center mb-3 text-2xl">🌐</div>
            <p className="text-sm text-gray-400">公共库暂无数据，点「投喂公共库」从采集数据导入</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-400 text-xs border-b border-gray-50">
                  <th className="pb-2 pt-3 px-3 w-8 font-medium">
                    <input type="checkbox" checked={selected.length === data.length && data.length > 0}
                      onChange={toggleAll} className="accent-blue-500" />
                  </th>
                  <th className="pb-2 pt-3 px-3 font-medium">头像</th>
                  <th className="pb-2 pt-3 px-3 font-medium">昵称</th>
                  <th className="pb-2 pt-3 px-3 font-medium">抖音号</th>
                  <th className="pb-2 pt-3 px-3 font-medium">性别</th>
                  <th className="pb-2 pt-3 px-3 font-medium">国家</th>
                  <th className="pb-2 pt-3 px-3 font-medium">粉丝数</th>
                  <th className="pb-2 pt-3 px-3 font-medium">关注数</th>
                  <th className="pb-2 pt-3 px-3 font-medium">年龄</th>
                  <th className="pb-2 pt-3 px-3 font-medium">AI标签</th>
                  <th className="pb-2 pt-3 px-3 font-medium">状态</th>
                </tr>
              </thead>
              <tbody>
                {visibleData.map(u => (
                  <tr key={u.id} className="border-b border-gray-50 text-gray-700 hover:bg-gray-50/50">
                    <td className="py-3 px-3">
                      <input type="checkbox" checked={selected.includes(u.id)}
                        onChange={() => toggle(u.id)} className="accent-blue-500" />
                    </td>
                    <td className="py-3 px-3">
                      {u.avatar_url ? (
                        <img src={u.avatar_url} alt="" className="w-9 h-9 rounded-full object-cover"
                          onError={e => { (e.target as HTMLImageElement).style.display = 'none' }} />
                      ) : (
                        <div className="w-9 h-9 rounded-full bg-gray-100 flex items-center justify-center text-gray-300">👤</div>
                      )}
                    </td>
                    <td className="py-3 px-3 max-w-[120px] truncate">{u.nickname || '—'}</td>
                    <td className="py-3 px-3 text-gray-400 text-xs max-w-[140px] truncate">{u.aweme_id || '—'}</td>
                    <td className="py-3 px-3">
                      <span className={`text-xs px-2 py-0.5 rounded ${genderBadge[u.gender] || 'bg-gray-50 text-gray-400'}`}>
                        {genderLabels[u.gender] || u.gender || '—'}
                      </span>
                    </td>
                    <td className="py-3 px-3 text-xs">{u.country || '—'}</td>
                    <td className="py-3 px-3">{u.followers?.toLocaleString() || '0'}</td>
                    <td className="py-3 px-3">{u.following_count?.toLocaleString() || '0'}</td>
                    <td className="py-3 px-3">{u.age || '—'}</td>
                    <td className="py-3 px-3 max-w-[200px]">
                      <span className="text-xs text-purple-500">{u.keyword || '—'}</span>
                    </td>
                    <td className="py-3 px-3">
                      {u.ai_tagged ? (
                        <span className="text-xs px-2 py-0.5 rounded bg-purple-50 text-purple-500">🏷️ 已打标</span>
                      ) : (
                        <span className="text-xs px-2 py-0.5 rounded bg-gray-50 text-gray-400">未打标</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* 投喂弹窗 */}
      {showFeedModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30"
          onClick={() => setShowFeedModal(false)}>
          <div className="bg-white rounded-2xl p-6 w-96 shadow-xl" onClick={e => e.stopPropagation()}>
            <h4 className="text-sm font-semibold text-gray-800 mb-4">⬆️ 投喂公共库</h4>
            <p className="text-xs text-gray-500 mb-4">从你的采集数据导入公共库（去标识化，只保留公开资料，按抖音号全局去重）</p>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-600">投喂数量上限</span>
                <input type="number" value={feedCount} onChange={e => setFeedCount(Number(e.target.value))}
                  className="w-28 border border-gray-200 rounded-lg px-3 py-1.5 text-sm outline-none" min={1} max={2000} />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-600">仅投喂有头像的（供AI打标）</span>
                <input type="checkbox" checked={feedAvatar} onChange={e => setFeedAvatar(e.target.checked)}
                  className="w-4 h-4 accent-blue-500" />
              </div>
            </div>
            <div className="flex gap-3 mt-6">
              <button onClick={doFeed}
                className="flex-1 px-4 py-2 rounded-lg bg-blue-500 text-white text-sm hover:bg-blue-600 cursor-pointer">
                确认投喂
              </button>
              <button onClick={() => setShowFeedModal(false)}
                className="px-4 py-2 rounded-lg bg-gray-100 text-gray-600 text-sm hover:bg-gray-200 cursor-pointer">
                取消
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
