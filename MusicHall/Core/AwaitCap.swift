import Foundation

/// 「最多等这么久」。
///
/// 下拉刷新（`.refreshable`）的菊花会一直转到闭包返回为止。我们的请求在弱网下
/// 可能被 `waitsForConnectivity` 与重试一起拖到一分钟以上，界面就表现成
/// 「刷新图标一直转」。这里给一个硬上限：到点让调用方先返回，
/// 真正的工作继续在后台跑，结果回来直接写进状态，界面照样会更新。
enum AwaitCap {
    /// 等一个已经起跑的任务，最多等 `seconds` 秒。
    static func value<T: Sendable>(of task: Task<T, Never>, within seconds: Double) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                let nanos = UInt64(max(0.2, seconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }
            let first: T? = (await group.next()) ?? nil
            group.cancelAll()
            return first
        }
    }

    /// 直接等一段工作（主线程上跑），超时就先返回。
    @MainActor
    static func run(within seconds: Double, _ work: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in await work() }
        _ = await value(of: task, within: seconds)
    }
}
