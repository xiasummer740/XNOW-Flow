export default function Placeholder({ title }: { title: string }) {
  return (
    <div className="bg-white rounded-xl p-12 border border-gray-100 shadow-sm flex flex-col items-center justify-center text-center">
      <div className="w-16 h-16 rounded-full bg-gray-50 flex items-center justify-center mb-4">
        <span className="text-2xl">🚧</span>
      </div>
      <h3 className="text-base font-medium text-gray-700 mb-2">{title}</h3>
      <p className="text-sm text-gray-400">功能开发中，敬请期待...</p>
    </div>
  )
}
