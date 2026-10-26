#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BuildKIRRegressionTests {
    // KUU-3589: a user-defined List must keep ordinary member-property resolution.
    @Test func testUserDefinedListMemberPropertyAccessDoesNotUseCollectionFallback() throws {
        try withTemporaryFile(contents: """
        class List<T>(val head: T, val tail: List<T>? = null)
        fun <T> List<T>.mapHead(f: (T) -> T): List<T> = List<T>(f(head), null)
        fun main() { val head = List<Int>(1).mapHead { it * 2 }.head }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
        }
    }
}
#endif
