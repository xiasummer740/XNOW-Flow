// DeviceControl.tsx — 设备控制台（移植自 control.html，接入 React 后台）
// 支持基本操作/修改资料/发视频/私信/注册/养号/快捷指令/采集/批量/账号操作/自定义指令

import { useEffect, useRef, useState } from 'react'
import type { InputHTMLAttributes, SelectHTMLAttributes, ReactNode } from 'react'

interface Props {
  token: string
  user?: any
}

interface Device {
  id: number
  name: string
  device_id?: string
  is_online?: boolean
  app_version?: string
}

const baseHeaders = (token: string) => ({
  Authorization: `Token ${token}`,
  'Content-Type': 'application/json',
})

export default function DeviceControl({ token, user }: Props) {
  const [devices, setDevices] = useState<Device[]>([])
  const [deviceId, setDeviceId] = useState<string>('')
  const [logs, setLogs] = useState<string[]>([])
  const logRef = useRef<HTMLDivElement>(null)
  const isAdmin = user?.role === 'admin'

  // 表单状态
  const [nickname, setNickname] = useState('')
  const [signature, setSignature] = useState('')
  const [videoUrl, setVideoUrl] = useState('')
  const [videoTitle, setVideoTitle] = useState('')
  const [dmTarget, setDmTarget] = useState('')
  const [dmContent, setDmContent] = useState('')
  const [regEmail, setRegEmail] = useState('')
  const [regPhone, setRegPhone] = useState('')
  const [regPassword, setRegPassword] = useState('')
  const [nurtureName, setNurtureName] = useState('')
  const [nurtureMin, setNurtureMin] = useState(2)
  const [nurtureMax, setNurtureMax] = useState(5)
  const [nurtureLike, setNurtureLike] = useState(0.2)
  const [nurtureFollow, setNurtureFollow] = useState(0.05)
  const [nurtureMinutes, setNurtureMinutes] = useState(2)
  const [qcName, setQcName] = useState('')
  const [qcAction, setQcAction] = useState('')
  const [qcParams, setQcParams] = useState('')
  const [qcDesc, setQcDesc] = useState('')
  const [kw, setKw] = useState('')
  const [uid, setUid] = useState('')
  const [avid, setAvid] = useState('')
  const [filterGender, setFilterGender] = useState('')
  const [filterRegion, setFilterRegion] = useState('')
  const [filterGroup, setFilterGroup] = useState('')
  const [customAction, setCustomAction] = useState('')
  const [customParams, setCustomParams] = useState('')
  const [udidList, setUdidList] = useState<string>('')
  const [nurtureStatus, setNurtureStatus] = useState('创建后点「开始养号」立即下发 nurture_tick')
  const [qcStatus, setQcStatus] = useState('保存后即可一键下发给当前选中设备')

  function pushLog(msg: string) {
    setLogs(prev => [`${new Date().toLocaleTimeString()} ${msg}`, ...prev].slice(0, 40))
  }

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = 0
  }, [logs])

  async function api(path: string, opts: RequestInit = {}) {
    const resp = await fetch(path, { ...opts, headers: { ...baseHeaders(token), ...(opts.headers || {}) } })
    if (resp.status === 401) {
      pushLog('⚠️ 登录已失效，请重新登录')
      throw new Error('unauthorized')
    }
    return resp.json()
  }

  async function loadDevices() {
    try {
      const d = await api('/api/biz/v2/device-bindings/?limit=100')
      const list = d.results || []
      setDevices(list)
      if (!deviceId && list.length) setDeviceId(String(list[0].id))
    } catch (e: any) {
      pushLog('加载设备失败: ' + e.message)
    }
  }

  useEffect(() => {
    loadDevices()
    const t = setInterval(loadDevices, 5000)
    return () => clearInterval(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token])

  const selectedDevice = () => devices.find(d => String(d.id) === deviceId)

  async function cmd(action: string, params: any = {}) {
    if (!deviceId) { pushLog('⚠️ 请先选择设备'); return }
    pushLog(`⏳ 发送指令: ${action} → 设备#${deviceId}`)
    try {
      const r = await api('/api/biz/v2/device-bindings/batch/dispatch/', {
        method: 'POST',
        body: JSON.stringify({ device_ids: [parseInt(deviceId)], action, params }),
      })
      pushLog('✅ ' + (r.message || JSON.stringify(r)))
    } catch (e: any) { pushLog('❌ ' + e.message) }
  }

  const devCode = selectedDevice()?.name || ''

  async function createVideoPost() {
    if (!devCode) { pushLog('⚠️ 请先选择设备'); return }
    if (!videoUrl && !videoTitle) { pushLog('⚠️ 视频URL 和标题至少填一个'); return }
    try {
      const r = await api('/api/biz/v2/video-posts/', {
        method: 'POST',
        body: JSON.stringify({ device_id: devCode, video_url: videoUrl, title: videoTitle }),
      })
      pushLog('✅ 已创建视频任务 #' + r.id + '（' + r.status + '），可点「立即发布」')
    } catch (e: any) { pushLog('❌ 创建失败: ' + e.message) }
  }

  async function dispatchLatestVideoPost() {
    if (!devCode) { pushLog('⚠️ 请先选择设备'); return }
    try {
      const d = await api('/api/biz/v2/video-posts/?device_id=' + encodeURIComponent(devCode) + '&status=pending&limit=5')
      const rows = d.results || []
      if (!rows.length) { pushLog('📋 该设备暂无视频任务，请先「创建视频发布任务」'); return }
      const r = await api('/api/biz/v2/video-posts/' + rows[0].id + '/dispatch/', { method: 'POST', body: '{}' })
      pushLog('✅ ' + (r.message || JSON.stringify(r)))
    } catch (e: any) { pushLog('❌ 下发失败: ' + e.message) }
  }

  async function createDmTask() {
    if (!devCode) { pushLog('⚠️ 请先选择设备'); return }
    if (!dmContent) { pushLog('⚠️ 私信内容不能为空'); return }
    try {
      const r = await api('/api/biz/v2/dm-tasks/', {
        method: 'POST',
        body: JSON.stringify({ device_id: devCode, target_username: dmTarget, content: dmContent }),
      })
      pushLog('✅ 已创建私信任务 #' + r.id + '（' + r.status + '），可点「立即发送」')
    } catch (e: any) { pushLog('❌ 创建失败: ' + e.message) }
  }

  async function dispatchLatestDm() {
    if (!devCode) { pushLog('⚠️ 请先选择设备'); return }
    try {
      const d = await api('/api/biz/v2/dm-tasks/?device_id=' + encodeURIComponent(devCode) + '&status=pending&limit=5')
      const rows = d.results || []
      if (!rows.length) { pushLog('📋 该设备暂无待发私信，请先「创建私信任务」'); return }
      const r = await api('/api/biz/v2/dm-tasks/' + rows[0].id + '/dispatch/', { method: 'POST', body: '{}' })
      pushLog('✅ ' + (r.message || JSON.stringify(r)))
    } catch (e: any) { pushLog('❌ 下发失败: ' + e.message) }
  }

  async function createNurturePlan() {
    if (!devCode) { pushLog('⚠️ 请先选择设备'); return }
    try {
      const r = await api('/api/biz/v2/nurture-plans/', {
        method: 'POST',
        body: JSON.stringify({
          name: nurtureName || ('养号计划-' + Date.now()),
          device_ids: [devCode],
          account_ids: [],
          daily_actions: {
            min_scrolls: nurtureMin, max_scrolls: nurtureMax,
            like_probability: nurtureLike || 0.2, follow_probability: nurtureFollow || 0.05,
            comment_probability: 0.02, browse_minutes: nurtureMinutes,
          },
        }),
      })
      setNurtureStatus('已创建计划 #' + r.id + '，可点「开始养号」')
      pushLog('✅ 已创建养号计划 #' + r.id)
    } catch (e: any) { pushLog('❌ 创建失败: ' + e.message) }
  }

  async function _latestNurturePlanId(): Promise<number | null> {
    try {
      const d = await api('/api/biz/v2/nurture-plans/?limit=50')
      const rows = (d.results || []).filter((p: any) => !devCode || (p.device_ids || []).includes(devCode))
      return rows.length ? rows[0].id : null
    } catch (e) { return null }
  }

  async function startNurturePlan() {
    const pid = await _latestNurturePlanId()
    if (!pid) { pushLog('⚠️ 还没有养号计划，请先「创建养号计划」'); return }
    try {
      const r = await api('/api/biz/v2/nurture-plans/' + pid + '/start/', { method: 'POST', body: '{}' })
      pushLog('✅ ' + (r.message || JSON.stringify(r)))
    } catch (e: any) { pushLog('❌ 开始失败: ' + e.message) }
  }

  async function pauseNurturePlan() {
    const pid = await _latestNurturePlanId()
    if (!pid) { pushLog('⚠️ 还没有养号计划'); return }
    try {
      const r = await api('/api/biz/v2/nurture-plans/' + pid + '/pause/', { method: 'POST', body: '{}' })
      pushLog('✅ ' + (r.message || JSON.stringify(r)))
    } catch (e: any) { pushLog('❌ 暂停失败: ' + e.message) }
  }

  async function saveQuickCommand() {
    if (!qcAction) { pushLog('⚠️ 请输入 Action'); return }
    let params: any = {}
    try { params = JSON.parse(qcParams || '{}') } catch (e) { pushLog('❌ Params 不是合法 JSON'); return }
    try {
      const r = await api('/api/biz/v2/quick-commands/', {
        method: 'POST',
        body: JSON.stringify({ name: qcName || qcAction, action: qcAction, params, description: qcDesc }),
      })
      setQcStatus('已保存指令 #' + r.id + '：' + qcAction)
      pushLog('✅ 已保存快捷指令 #' + r.id)
    } catch (e: any) { pushLog('❌ 保存失败: ' + e.message) }
  }

  async function dispatchLatestQuickCommand() {
    if (!devCode) { pushLog('⚠️ 请先选择设备'); return }
    try {
      const d = await api('/api/biz/v2/quick-commands/?limit=1')
      const rows = d.results || []
      if (!rows.length) { pushLog('⚠️ 还没有快捷指令，请先「保存快捷指令」'); return }
      const r = await api('/api/biz/v2/quick-commands/' + rows[0].id + '/dispatch/', {
        method: 'POST', body: JSON.stringify({ device_id: devCode }),
      })
      pushLog('✅ ' + (r.message || JSON.stringify(r)))
    } catch (e: any) { pushLog('❌ 下发失败: ' + e.message) }
  }

  async function viewCollectedData() {
    const params = new URLSearchParams()
    params.set('limit', '50')
    if (filterGender) params.set('gender', filterGender)
    if (filterRegion) params.set('region', filterRegion)
    if (filterGroup) params.set('group_name', filterGroup)
    try {
      const d = await api('/api/biz/v2/collected-data/?' + params.toString())
      const rows = d.results || []
      if (!rows.length) { pushLog('📋 没有匹配的采集数据'); return }
      let out = `📋 采集数据 (共 ${d.count} 条):\n`
      rows.forEach((r: any) => {
        out += `• ${r.author || r.content || '#' + r.id} [${r.gender || '未知'}/${r.region || '未知'}] 粉丝:${r.followers || 0} 组:${r.group_name || '未分组'} (${r.source_type || ''})\n`
      })
      pushLog(out)
    } catch (e: any) { pushLog('❌ 查看采集数据失败: ' + e.message) }
  }

  async function loadUdidRequests() {
    try {
      const d = await api('/api/biz/v2/udid/admin/?limit=50')
      const rows = d.results || []
      if (!rows.length) { setUdidList('暂无申请'); return }
      setUdidList(rows.map((r: any) => `• ${r.udid} [${r.device_name || ''}] 状态:${r.status}`).join('\n'))
    } catch (e: any) { pushLog('❌ 加载UDID失败: ' + e.message) }
  }

  const Btn = ({ children, onClick, primary, danger }: { children: ReactNode; onClick?: () => void; primary?: boolean; danger?: boolean }) => (
    <button
      onClick={onClick}
      className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${danger ? 'bg-red-600 hover:bg-red-500 text-white' : primary ? 'bg-blue-600 hover:bg-blue-500 text-white' : 'bg-gray-700 hover:bg-gray-600 text-gray-100'}`}
    >{children}</button>
  )
  const Card = ({ title, children }: { title: string; children: ReactNode }) => (
    <div className="bg-gray-800/60 rounded-lg p-4 mb-4">
      <h3 className="text-sm font-semibold text-gray-300 mb-3">{title}</h3>
      {children}
    </div>
  )
  const Label = ({ children }: { children: ReactNode }) => <label className="block text-xs text-gray-400 mb-1">{children}</label>
  const Input = (props: InputHTMLAttributes<HTMLInputElement>) => (
    <input {...props} className="w-full px-3 py-2 mb-2 rounded-md bg-gray-700 border border-gray-600 text-sm text-gray-100 focus:outline-none focus:border-blue-500" />
  )
  const Select = (props: SelectHTMLAttributes<HTMLSelectElement>) => (
    <select {...props} className="w-full px-3 py-2 mb-2 rounded-md bg-gray-700 border border-gray-600 text-sm" />
  )

  const dev = selectedDevice()

  return (
    <div className="p-4 max-w-3xl">
      <h2 className="text-lg font-semibold mb-3">🎮 设备控制台</h2>

      {/* 设备选择 */}
      <Card title="选择设备（机器码）">
        <Select value={deviceId} onChange={e => setDeviceId(e.target.value)}>
          <option value="">加载中...</option>
          {devices.map(d => (
            <option key={d.id} value={String(d.id)}>
              {d.device_id || d.name} {d.is_online ? '●在线' : '○离线'}
            </option>
          ))}
        </Select>
        <div className="text-xs">
          {dev
            ? <span className={dev.is_online ? 'text-green-400' : 'text-red-400'}>
                {dev.is_online ? '● 在线' : '○ 离线'} 设备:{dev.device_id || dev.name} App:{dev.app_version || '—'}
              </span>
            : '请选择设备'}
        </div>
      </Card>

      {/* 基本操作 */}
      <Card title="🎮 基本操作">
        <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
          <Btn primary onClick={() => cmd('scroll_down')}>⬇️ 下滑</Btn>
          <Btn primary onClick={() => cmd('scroll_up')}>⬆️ 上滑</Btn>
          <Btn onClick={() => cmd('like')}>❤️ 点赞</Btn>
          <Btn onClick={() => cmd('follow')}>➕ 关注</Btn>
          <Btn onClick={() => cmd('comment', { text: '赞！' })}>💬 评论</Btn>
          <Btn onClick={() => cmd('collect')}>⭐ 收藏</Btn>
          <Btn onClick={() => cmd('screenshot')}>📸 截图</Btn>
          <Btn onClick={() => cmd('smart_browse', { min_scrolls: 5, max_scrolls: 12 })}>🌐 智能浏览</Btn>
          <Btn onClick={() => cmd('go_back')}>↩️ 返回</Btn>
          <Btn onClick={() => cmd('go_home')}>🏠 首页</Btn>
          <Btn onClick={() => cmd('open_tab', { tab: 'discover' })}>🔍 发现页</Btn>
          <Btn onClick={() => cmd('open_tab', { tab: 'inbox' })}>✉️ 消息页</Btn>
          <Btn onClick={() => cmd('open_tab', { tab: 'profile' })}>👤 我的页</Btn>
          <Btn onClick={() => cmd('open_search')}>🔎 搜索</Btn>
          <Btn onClick={() => cmd('refresh')}>🔄 刷新</Btn>
          <Btn onClick={() => cmd('share')}>📤 分享</Btn>
          <Btn onClick={() => cmd('save_video')}>💾 保存视频</Btn>
        </div>
      </Card>

      {/* 修改资料 */}
      <Card title="✏️ 修改资料">
        <Label>新昵称</Label>
        <Input value={nickname} onChange={e => setNickname(e.target.value)} placeholder="如: 某某品牌" />
        <Label>新签名</Label>
        <Input value={signature} onChange={e => setSignature(e.target.value)} placeholder="如: 欢迎关注" />
        <Btn primary onClick={() => cmd('edit_profile', { nickname, signature })}>✏️ 修改资料</Btn>
      </Card>

      {/* 自动发视频 */}
      <Card title="🎬 自动发视频">
        <Label>视频 URL（素材/上传后的链接）</Label>
        <Input value={videoUrl} onChange={e => setVideoUrl(e.target.value)} placeholder="如 https://.../uploads/xxx.mp4" />
        <Label>标题 / 文案</Label>
        <Input value={videoTitle} onChange={e => setVideoTitle(e.target.value)} placeholder="如 这个视频太赞了" />
        <div className="flex gap-2">
          <Btn primary onClick={createVideoPost}>📝 创建视频发布任务</Btn>
          <Btn primary onClick={dispatchLatestVideoPost}>🚀 立即发布</Btn>
        </div>
      </Card>

      {/* 自动私信 */}
      <Card title="💬 自动私信">
        <Label>目标用户名（可空，空则进消息页）</Label>
        <Input value={dmTarget} onChange={e => setDmTarget(e.target.value)} placeholder="如 1234567890" />
        <Label>私信内容 / 话术</Label>
        <Input value={dmContent} onChange={e => setDmContent(e.target.value)} placeholder="如 你好，合作了解一下" />
        <div className="flex gap-2">
          <Btn primary onClick={createDmTask}>📝 创建私信任务</Btn>
          <Btn primary onClick={dispatchLatestDm}>🚀 立即发送</Btn>
        </div>
      </Card>

      {/* 注册账号 */}
      <Card title="📝 注册账号">
        <Label>邮箱（优先）</Label>
        <Input value={regEmail} onChange={e => setRegEmail(e.target.value)} placeholder="如 newuser@example.com" />
        <Label>手机号（邮箱为空时用）</Label>
        <Input value={regPhone} onChange={e => setRegPhone(e.target.value)} placeholder="如 +8613800000000" />
        <Label>密码（可空）</Label>
        <Input value={regPassword} onChange={e => setRegPassword(e.target.value)} placeholder="如 Xnow@123456" />
        <Btn primary onClick={() => cmd('register_account', { email: regEmail, phone: regPhone, password: regPassword })}>📝 注册账号</Btn>
        <div className="text-xs text-yellow-500 mt-2">⚠️ 纯 UI 自动化 best-effort；滑块/验证码需人工或专用打码工具</div>
      </Card>

      {/* 养号计划 */}
      <Card title="🌱 养号计划">
        <Label>计划名称</Label>
        <Input value={nurtureName} onChange={e => setNurtureName(e.target.value)} placeholder="如 新号养号计划" />
        <div className="grid grid-cols-2 gap-2">
          <div><Label>滑动 min</Label><Input type="number" value={nurtureMin} onChange={e => setNurtureMin(parseInt(e.target.value) || 2)} /></div>
          <div><Label>滑动 max</Label><Input type="number" value={nurtureMax} onChange={e => setNurtureMax(parseInt(e.target.value) || 5)} /></div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div><Label>点赞概率</Label><Input type="number" step="0.05" value={nurtureLike} onChange={e => setNurtureLike(parseFloat(e.target.value) || 0.2)} /></div>
          <div><Label>关注概率</Label><Input type="number" step="0.05" value={nurtureFollow} onChange={e => setNurtureFollow(parseFloat(e.target.value) || 0.05)} /></div>
        </div>
        <Label>浏览时长（分钟）</Label>
        <Input type="number" value={nurtureMinutes} onChange={e => setNurtureMinutes(parseInt(e.target.value) || 2)} />
        <div className="flex gap-2">
          <Btn primary onClick={createNurturePlan}>📝 创建养号计划</Btn>
          <Btn primary onClick={startNurturePlan}>▶️ 开始养号</Btn>
          <Btn danger onClick={pauseNurturePlan}>⏸ 暂停养号</Btn>
        </div>
        <div className="text-xs text-gray-500 mt-2">{nurtureStatus}</div>
      </Card>

      {/* 快捷指令 */}
      <Card title="🚀 快捷指令">
        <Label>指令名称</Label>
        <Input value={qcName} onChange={e => setQcName(e.target.value)} placeholder="如 批量点赞10个" />
        <Label>Action</Label>
        <Input value={qcAction} onChange={e => setQcAction(e.target.value)} placeholder="如 batch_like" />
        <Label>Params（JSON，可空）</Label>
        <Input value={qcParams} onChange={e => setQcParams(e.target.value)} placeholder='如 {"count":10,"interval":1}' />
        <Label>描述（可空）</Label>
        <Input value={qcDesc} onChange={e => setQcDesc(e.target.value)} placeholder="如 快速给10个视频点赞" />
        <div className="flex gap-2">
          <Btn primary onClick={saveQuickCommand}>💾 保存快捷指令</Btn>
          <Btn primary onClick={dispatchLatestQuickCommand}>🚀 下发到当前设备</Btn>
        </div>
        <div className="text-xs text-gray-500 mt-2">{qcStatus}</div>
      </Card>

      {/* 打开指定内容 */}
      <Card title="🔗 打开指定内容">
        <Label>搜索关键词</Label>
        <Input value={kw} onChange={e => setKw(e.target.value)} placeholder="如 美食 或 用户名" />
        <Btn onClick={() => cmd('search_keyword', { keyword: kw })}>搜索关键词</Btn>
        <Label>用户 UID / unique_id</Label>
        <Input value={uid} onChange={e => setUid(e.target.value)} placeholder="如 1234567890" />
        <Btn onClick={() => cmd('open_user', { uid })}>打开用户主页</Btn>
        <Label>视频 aweme_id</Label>
        <Input value={avid} onChange={e => setAvid(e.target.value)} placeholder="如 7123456789012345678" />
        <Btn onClick={() => cmd('open_video', { aweme_id: avid })}>打开视频</Btn>
      </Card>

      {/* 采集 */}
      <Card title="📊 采集">
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
          <Btn onClick={() => cmd('collect_fans', { count: 20 })}>👥 采集粉丝</Btn>
          <Btn onClick={() => cmd('collect_videos', { count: 10 })}>🎬 采集视频</Btn>
          <Btn onClick={() => cmd('collect_comments', { count: 20 })}>💬 采集评论用户</Btn>
          <Btn onClick={() => cmd('collect_live_users', { count: 20 })}>📺 采集直播用户</Btn>
          <Btn onClick={() => cmd('get_account_info')}>👤 获取账号信息</Btn>
          <Btn onClick={() => cmd('check_health')}>💓 健康检查</Btn>
        </div>
      </Card>

      {/* 数据筛选 */}
      <Card title="🔍 数据筛选">
        <Label>性别</Label>
        <Select value={filterGender} onChange={e => setFilterGender(e.target.value)}>
          <option value="">全部</option>
          <option value="male">男</option>
          <option value="female">女</option>
          <option value="unknown">未知</option>
        </Select>
        <Label>地区</Label>
        <Input value={filterRegion} onChange={e => setFilterRegion(e.target.value)} placeholder="如 广东 / US" />
        <Label>分组</Label>
        <Input value={filterGroup} onChange={e => setFilterGroup(e.target.value)} placeholder="如 未分组" />
        <Btn primary onClick={viewCollectedData}>📋 查看采集数据</Btn>
      </Card>

      {/* 批量操作 */}
      <Card title="🔄 批量操作">
        <div className="grid grid-cols-3 gap-2">
          <Btn onClick={() => cmd('batch_like', { count: 10, interval: 1 })}>批量点赞(10)</Btn>
          <Btn onClick={() => cmd('batch_follow', { count: 5, interval: 1 })}>批量关注(5)</Btn>
          <Btn onClick={() => cmd('batch_comment', { count: 5, interval: 2, text: '不错' })}>批量评论</Btn>
        </div>
      </Card>

      {/* 账号操作 */}
      <Card title="👤 账号操作">
        <div className="grid grid-cols-3 gap-2">
          <Btn onClick={() => cmd('switch_account', { aweme_id: '' })}>🔄 切换账号</Btn>
          <Btn danger onClick={() => cmd('logout')}>🚪 退出登录</Btn>
          <Btn onClick={() => cmd('report_account')}>📮 上报账号</Btn>
        </div>
      </Card>

      {/* UDID 签名管理（admin 专属） */}
      {isAdmin && (
        <Card title="🆔 UDID 签名管理">
          <Btn onClick={loadUdidRequests}>刷新 UDID 申请</Btn>
          <pre className="mt-2 text-xs whitespace-pre-wrap text-gray-400">{udidList}</pre>
        </Card>
      )}

      {/* 自定义指令 */}
      <Card title="⚙️ 参数指令（自定义 JSON）">
        <Label>Action</Label>
        <Input value={customAction} onChange={e => setCustomAction(e.target.value)} placeholder="如 switch_account" />
        <Label>Params（JSON）</Label>
        <Input value={customParams} onChange={e => setCustomParams(e.target.value)} placeholder='如 {"aweme_id":"123456"}' />
        <Btn danger onClick={() => {
          if (!customAction) { pushLog('⚠️ 请输入 Action'); return }
          let params: any = {}
          try { params = JSON.parse(customParams || '{}') } catch (e) { pushLog('❌ Params 不是合法 JSON'); return }
          cmd(customAction, params)
        }}>发送自定义指令</Btn>
      </Card>

      {/* 执行结果 */}
      <Card title="📋 执行结果">
        <div ref={logRef} className="bg-gray-950 rounded-md p-3 text-xs text-blue-300 h-48 overflow-y-auto whitespace-pre-wrap">
          {logs.length ? logs.join('\n') : '等待操作...'}
        </div>
      </Card>
    </div>
  )
}
