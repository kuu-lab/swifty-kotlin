#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LambdaOverloadDeclaredReturnExpectationTests {
    @Test
    func expectedReturnOverridePreservesDeclaredTypeParamForErasedBoundaryCheck() throws {
        let ctx = try semaContext(from: """
        @Suppress("UNCHECKED_CAST")
        private fun <T> Any?.uncheckedCast(): T = this as T

        private class Marker

        private fun <T> invokeBlock(block: () -> T): T = block()

        fun check(): Any? {
            val value: Any? = invokeBlock { Marker().uncheckedCast<Int?>() }
            return value
        }
        """, includeStdlib: false)
        let sema = try #require(ctx.sema)
        #expect(!sema.bindings.lambdaDeclaredExpectedReturnTypes.isEmpty)
        let hasTypeParamClaim = sema.bindings.genericCallConsumerTypes.values.contains { typeID in
            if case .typeParam = sema.types.kind(of: typeID) {
                return true
            }
            return false
        }
        #expect(hasTypeParamClaim)
    }
}
#endif
