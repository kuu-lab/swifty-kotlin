#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct DynamicITableDefaultFallbackLinkTests {
    /// Regression test for dynamic itable default-implementation fallbacks:
    /// compiling and linking against the prelinked stdlib `.kklib` must resolve
    /// real `kk_fn_*` symbols (such as `List.indexOf`/`lastIndexOf` and
    /// `ContinuationInterceptor.get`/`minusKey`) rather than emitting
    /// `ptrtoint` references to dummy `__v` indirect-call carrier declarations.
    @Test func prelinkedStdlibLinksAndExecutesListSearchAndCoroutineContextDefaults() throws {
        let source = """
        import kotlin.coroutines.ContinuationInterceptor
        import kotlin.coroutines.EmptyCoroutineContext

        fun <T : List<String>> dynamicIndexOf(list: T, target: String): Int = list.indexOf(target)
        fun <T : List<String>> dynamicLastIndexOf(list: T, target: String): Int = list.lastIndexOf(target)

        fun main() {
            val items = listOf("a", "b", "a")
            println(dynamicIndexOf(items, "a"))
            println(dynamicLastIndexOf(items, "a"))
            val ctx = EmptyCoroutineContext
            println(ctx[ContinuationInterceptor] == null)
            println(ctx.minusKey(ContinuationInterceptor) === EmptyCoroutineContext)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DynamicITableDefaultFallbackLink",
            expected: "0\n2\ntrue\ntrue\n"
        )
    }
}
#endif
