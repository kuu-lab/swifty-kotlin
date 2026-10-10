#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct BundledInternalTypeVisibilityTests {
    private func context(_ source: String) -> CompilationContext {
        let userPath = "/tmp/visibility-user-\(UUID().uuidString).kt"
        let libraryPath = "/tmp/visibility-bundled-\(UUID().uuidString).kt"
        let ctx = makeCompilationContext(inputs: [userPath, libraryPath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: userPath, contents: Data(source.utf8))
        _ = ctx.sourceManager.addFile(
            path: libraryPath,
            contents: Data("""
            package library
            internal interface Hidden
            internal fun own(value: Hidden?): Hidden? = value
            class Owner {
                private class PrivateType
                protected class ProtectedType
                private fun ownPrivate(value: PrivateType?): PrivateType? = value
                protected fun ownProtected(value: ProtectedType?): ProtectedType? = value
            }
            """.utf8),
            origin: .bundledStdlib
        )
        return ctx
    }

    @Test(arguments: [
        "fun main() { val value: library.Hidden? = null }",
        "class Box<T>; fun main() { val value: Box<library.Hidden?>? = null }",
        "fun main() { val value: (() -> library.Hidden?)? = null }",
        "fun inspect(value: library.Hidden?) {}",
        "fun inspect(): library.Hidden? = null",
        "class Box<T>; fun inspect(value: Box<library.Hidden?>?) {}",
        "typealias HiddenAlias = library.Hidden",
        "class Probe { fun inspect(value: library.Hidden?) {} }",
        "class Probe { fun inspect(): library.Hidden? = null }",
        "class Probe { val value: library.Hidden? = null }",
        "class Probe(val value: library.Hidden?)",
        "class Probe<T : library.Hidden>",
        "fun <T : library.Hidden> inspect() {}",
        "class Probe { typealias HiddenAlias = library.Hidden }",
    ])
    func bundledInternalTypesAreRejectedInAnnotations(_ source: String) throws {
        let ctx = context(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains("Hidden")
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func sameModuleInternalTypesAndBundledOwnUseRemainAccessible() throws {
        let ctx = context("""
        internal interface Local
        class Box<T>
        internal fun inspect(value: Box<Local?>?): (() -> Local?)? = null
        internal class Probe(val value: Local?) { fun inspect(): Local? = value }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
