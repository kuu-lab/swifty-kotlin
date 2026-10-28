#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct CodegenBackendGenericClassInterfaceDelegationTests {
    // KUU-3606: a generic forwarding method must preserve its return ABI when
    // the interface delegate comes from an unchecked cast.
    @Test func uncheckedCastDelegatePreservesGenericReturnDispatch() throws {
        try compileAndRunKotlin(
            """
            open class Content { override fun toString() = "OK" }
            interface Box<E> { fun get(): E }
            interface ContentBox<T : Content> : Box<T>
            object Impl : ContentBox<Content> { override fun get(): Content = Content() }
            class D<T : Content> : ContentBox<T> by (Impl as ContentBox<T>)
            fun main() { println(D<Content>().get().toString()) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3606GenericClassInterfaceDelegation"
        )
    }
}
#endif
