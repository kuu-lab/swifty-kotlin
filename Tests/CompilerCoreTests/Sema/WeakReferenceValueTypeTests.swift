@testable import CompilerCore
import Testing
import TestStdlibCache

/// KUU-1666: `.value` must retain the receiver's generic referent type while
/// the legacy extension import and star projection remain source-compatible.
@Suite
struct WeakReferenceValueTypeTests {
    @Test(arguments: [false, true])
    func valuePropertyKeepsReferentType(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }

        try withTemporaryFile(contents: """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        class Box(val n: Int)

        fun readBox(reference: WeakReference<Box>): Int? = reference.value?.n
        fun readString(reference: WeakReference<String>): String? = reference.value
        fun readStarProjected(reference: WeakReference<*>): Any? = reference.value
        fun readGenericGet(reference: WeakReference<String>): String? = reference.get()
        """) { path in
            let context = makeCompilationContext(
                inputs: [path],
                emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
