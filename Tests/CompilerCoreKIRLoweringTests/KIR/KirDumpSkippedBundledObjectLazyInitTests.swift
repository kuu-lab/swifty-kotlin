#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KirDumpSkippedBundledObjectLazyInitTests {
    /// `.kirDump` skips bundled stdlib bodies, so a user default argument that
    /// mentions a skipped bundled object must not leave an unresolved lazy-init
    /// guard behind (kotlinx.html's `measureTime(timeSource = TimeSource.Monotonic)`).
    @Test
    func kirDumpDropsLazyInitGuardForSkippedBundledObject() throws {
        _ = try loweringContext(from: """
        import kotlin.time.TimeSource

        fun defaultTimeSource(timeSource: TimeSource = TimeSource.Monotonic): TimeSource = timeSource

        fun main() { defaultTimeSource() }
        """)
    }
}
#endif
