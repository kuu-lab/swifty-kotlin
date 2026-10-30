import Foundation

private enum RuntimeThreadLifecycle {
    static let condition = NSCondition()
    nonisolated(unsafe) static var nonDaemonCount = 0
}

@_cdecl("__kk_thread_non_daemon_start")
public func __kk_thread_non_daemon_start() -> Int {
    RuntimeThreadLifecycle.condition.lock()
    RuntimeThreadLifecycle.nonDaemonCount += 1
    RuntimeThreadLifecycle.condition.unlock()
    return 0
}

@_cdecl("__kk_thread_non_daemon_finish")
public func __kk_thread_non_daemon_finish() -> Int {
    RuntimeThreadLifecycle.condition.lock()
    RuntimeThreadLifecycle.nonDaemonCount -= 1
    if RuntimeThreadLifecycle.nonDaemonCount == 0 {
        RuntimeThreadLifecycle.condition.broadcast()
    }
    RuntimeThreadLifecycle.condition.unlock()
    return 0
}

@_cdecl("__kk_thread_wait_non_daemon")
public func __kk_thread_wait_non_daemon() -> Int {
    RuntimeThreadLifecycle.condition.lock()
    while RuntimeThreadLifecycle.nonDaemonCount > 0 {
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        RuntimeThreadLifecycle.condition.wait()
        // A collector may be waiting for this mutator to resume. Do not hold
        // the lifecycle lock while waiting for the collection to finish.
        RuntimeThreadLifecycle.condition.unlock()
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        RuntimeThreadLifecycle.condition.lock()
    }
    RuntimeThreadLifecycle.condition.unlock()
    return 0
}

@_cdecl("__kk_thread_report_uncaught")
public func __kk_thread_report_uncaught(_ exception: Int) -> Int {
    runtimeReportUncaughtException(exception)
    return 0
}
