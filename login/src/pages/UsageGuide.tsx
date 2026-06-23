import { useState } from 'react'

interface GuideSection {
  id: string
  title: string
  icon: string
  content: { title: string; desc: string; steps?: string[] }[]
}

const guideData: GuideSection[] = [
  {
    id: 'quickstart', title: '快速入门', icon: '🚀',
    content: [
      { title: '1. 登录系统', desc: '使用管理员账号登录 XNOW 云控系统后台。', steps: ['打开浏览器访问系统地址', '输入用户名和密码', '点击"登录"进入 Dashboard'] },
      { title: '2. 添加设备', desc: '在"设备管理"中添加需要控制的设备。', steps: ['点击"设备管理"菜单', '点击"添加设备"按钮', '按提示安装客户端并绑定'] },
      { title: '3. 配置账号', desc: '在"账号管理"中绑定需要操作的平台账号。', steps: ['进入"账号管理"页面', '点击"添加账号"', '选择平台并输入账号信息'] },
      { title: '4. 创建任务', desc: '在"批量任务"中创建并下发任务到设备。', steps: ['进入"批量任务"', '选择任务类型（关注/私信/评论）', '选择设备和账号', '设置任务参数并下发'] },
    ],
  },
  {
    id: 'device', title: '设备管理', icon: '💻',
    content: [
      { title: '设备状态说明', desc: '了解不同设备状态的含义。', steps: ['在线：设备正常运行中', '离线：设备未连接服务器', '空闲：在线但无任务执行', '执行中：正在执行任务', '锁定：被管理员暂停使用'] },
      { title: '客户端安装', desc: '在设备上安装 XNOW 客户端。', steps: ['下载对应平台的客户端安装包', '按指引完成安装', '输入绑定码完成关联'] },
    ],
  },
  {
    id: 'task', title: '任务管理', icon: '📋',
    content: [
      { title: '批量任务', desc: '批量执行关注、私信、评论等操作。', steps: ['选择任务类型', '选择目标设备和账号', '设置执行参数（数量/频率）', '点击"开始执行"'] },
      { title: '定时任务', desc: '设置定时自动执行的任务。', steps: ['进入"定时任务"', '点击"新建定时任务"', '填写 CRON 表达式', '选择任务类型并保存'] },
      { title: '执行统计', desc: '查看任务执行的历史数据和趋势。', steps: ['进入"执行统计"', '选择时间范围（7天/30天/90天）', '查看各类型任务的执行情况'] },
    ],
  },
  {
    id: 'data', title: '数据采集', icon: '📡',
    content: [
      { title: '采集功能', desc: '从平台采集用户、视频、评论等数据。', steps: ['进入"采集数据"页面', '选择采集目标和平台', '设置采集参数', '查看采集结果'] },
      { title: '数据导出', desc: '将采集到的数据导出为文件。', steps: ['在采集列表中选择数据', '点击"导出"按钮', '选择导出格式（CSV）', '下载导出的文件'] },
    ],
  },
  {
    id: 'account', title: '账号安全', icon: '🔒',
    content: [
      { title: '修改密码', desc: '定期修改登录密码确保账号安全。', steps: ['进入"设置中心"', '输入原密码', '设置新密码并确认', '点击"修改密码"保存'] },
      { title: '账号管理', desc: '管理绑定的平台账号。', steps: ['进入"账号管理"', '查看账号状态（正常/风控/封禁）', '可以添加或移除账号'] },
      { title: '安全建议', desc: '推荐的安全实践。', steps: ['定期修改密码', '不要将账号借予他人', '发现异常及时联系管理员'] },
    ],
  },
]

export default function UsageGuide({ token: _token }: { token: string }) {
  const [activeSection, setActiveSection] = useState('quickstart')
  const [expandedItem, setExpandedItem] = useState<string | null>(null)

  const section = guideData.find(s => s.id === activeSection) || guideData[0]

  return (
    <div className="flex gap-6">
      {/* 左侧导航 */}
      <div className="w-44 shrink-0">
        <div className="xx-card rounded-xl sticky top-6">
          <div className="px-4 py-3 border-b border-gray-100">
            <h4 className="text-xs font-medium text-gray-700">使用教程</h4>
          </div>
          <nav className="p-2 space-y-0.5">
            {guideData.map(s => (
              <button key={s.id}
                onClick={() => setActiveSection(s.id)}
                className={`w-full text-left px-3 py-2 rounded-lg text-xs transition-colors cursor-pointer ${
                  activeSection === s.id
                    ? 'bg-blue-50 text-blue-600 font-medium'
                    : 'text-gray-500 hover:text-gray-700 hover:bg-gray-50'
                }`}>
                <span className="mr-1.5">{s.icon}</span>
                {s.title}
              </button>
            ))}
          </nav>
        </div>
      </div>

      {/* 右侧内容 */}
      <div className="flex-1 min-w-0 space-y-4">
        <div className="xx-card rounded-xl">
          <div className="px-5 py-4 border-b border-gray-100">
            <h3 className="text-sm font-medium text-gray-700">{section.icon} {section.title}</h3>
          </div>
          <div className="p-5 space-y-4">
            {section.content.map((item, i) => {
              const key = `${section.id}-${i}`
              const isOpen = expandedItem === key
              return (
                <div key={key}
                  className="border border-gray-100 rounded-xl overflow-hidden">
                  <button onClick={() => setExpandedItem(isOpen ? null : key)}
                    className="w-full text-left px-4 py-3 flex items-center justify-between hover:bg-gray-50/50 transition-colors cursor-pointer">
                    <div>
                      <h4 className="text-sm font-medium text-gray-700">{item.title}</h4>
                      <p className="text-xs text-gray-400 mt-0.5">{item.desc}</p>
                    </div>
                    <span className={`text-gray-300 text-sm transition-transform ${isOpen ? 'rotate-180' : ''}`}>
                      ▼
                    </span>
                  </button>
                  {isOpen && item.steps && (
                    <div className="px-4 pb-4 pt-0 border-t border-gray-50">
                      <ol className="mt-3 space-y-2">
                        {item.steps.map((step, si) => (
                          <li key={si} className="flex items-start gap-2 text-sm text-gray-600">
                            <span className="w-5 h-5 rounded-full bg-blue-50 text-blue-500 text-xs flex items-center justify-center shrink-0 mt-0.5">
                              {si + 1}
                            </span>
                            <span>{step}</span>
                          </li>
                        ))}
                      </ol>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}
