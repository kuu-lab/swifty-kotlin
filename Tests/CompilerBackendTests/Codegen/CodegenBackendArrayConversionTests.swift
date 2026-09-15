#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// RF-LOWER-CALL-013: end-to-end counterpart of `SourceBackedCallPreservationPolicyTests`'
/// array-conversion set-shape assertions.
///
/// `toMutableList()` on `LongArray`/`ULongArray` used to redirect through the
/// generic `kk_array_toMutableList` runtime bridge, which boxed every element
/// as a plain word: `Long.MIN_VALUE`'s bit pattern collides with the runtime's
/// null sentinel (read back as `null`), and unsigned values were boxed as
/// signed (`ULong.MAX_VALUE` read back as `-1`). `toMutableList` is now a
/// bundled Kotlin declaration (`ArrayConversions.kt` / `UArrays.kt`) that
/// delegates to the already-correct `toList()`, and the two rewrite files
/// that used to intercept it unconditionally are deleted. These tests pin
/// the fixed runtime behavior so a future redirect regresses loudly instead
/// of silently corrupting edge-case elements.
@Suite
struct CodegenBackendArrayConversionTests {
    /// `kk_array_toMutableList` (the generic bridge this task's bug fix
    /// stopped redirecting to) and `__kk_array_copyOf` (the generic-Array
    /// `toTypedArray` bridge the deleted `+VirtualCallRewrite.swift` branch
    /// used to redirect to unconditionally). `__kk_array_toList` is
    /// deliberately not in this list: it is also the private `@KsSymbolName`
    /// bridge `Array<out T>.toList()`'s own source body calls
    /// (`ArrayConversions.kt`), so it is expected to appear as a real call
    /// site here — a legitimate use this test must not flag.
    private static let legacyArrayConversionIRCallees = [
        "@kk_array_toMutableList(", "@__kk_array_copyOf(",
    ]

    /// Codegen declares the full runtime ABI surface up front regardless of
    /// use (unlike the fully-deleted `kk_map_*` symbols `CodegenBackendMapHOFTests`
    /// checks for), so a still-live bridge always appears as a bare `declare`
    /// — only a `call ... @name(` site would mean a redirect fired.
    private func expectNoLegacyArrayConversionIR(_ ir: String) {
        for legacy in Self.legacyArrayConversionIRCallees {
            #expect(!ir.contains("call i64 \(legacy)"), "the legacy rewrite \(legacy) must not be called from codegen")
        }
    }

    // MARK: - no redirect to the deleted rewrite files' runtime bridges

    @Test
    func arrayConversionsKeepSourceCalleesThroughStdlibArtifact() throws {
        let source = """
        fun main() {
            val ints = intArrayOf(1, 2, 3)
            val longs = longArrayOf(1L, 2L, 3L)
            val generic = arrayOf(1, 2, 3)
            println(ints.toList())
            println(ints.toMutableList())
            println(longs.toMutableList())
            println(generic.toMutableList())
            println(ints.sliceArray(0..1).toList())
            println(ints.reversedArray().toList())
            println(ints.asList())
            println(ints.copyOf().toList())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "ArrayConversionArtifactIR",
                emit: .llvmIR,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let llvmPath = try #require(ctx.generatedLLVMIRPath)
            expectNoLegacyArrayConversionIR(try String(contentsOfFile: llvmPath, encoding: .utf8))
        }
    }

    // MARK: - the actual bug: Long/ULong/UInt/UByte/UShort element correctness

    /// `Long.MIN_VALUE`'s bit pattern used to be misread as the runtime's
    /// null sentinel through the generic bridge.
    @Test
    func longArrayToMutableListPreservesMinValueInsteadOfNull() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = longArrayOf(Long.MIN_VALUE, 5L)
                println(a.toMutableList())
            }
            """,
            moduleName: "LongArrayToMutableListMinValue",
            expected: "[-9223372036854775808, 5]\n"
        )
    }

    /// Unsigned values used to be boxed as signed through the generic bridge
    /// (`ULong.MAX_VALUE` printed as `-1`).
    @Test
    func ulongArrayToMutableListPreservesMaxValueUnsigned() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = ulongArrayOf(ULong.MAX_VALUE, 5uL)
                println(a.toMutableList())
            }
            """,
            moduleName: "ULongArrayToMutableListMaxValue",
            expected: "[18446744073709551615, 5]\n"
        )
    }

    @Test
    func uintArrayToMutableListPreservesMaxValueUnsigned() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = uintArrayOf(UInt.MAX_VALUE, 5u)
                println(a.toMutableList())
            }
            """,
            moduleName: "UIntArrayToMutableListMaxValue",
            expected: "[4294967295, 5]\n"
        )
    }

    @Test
    func ubyteArrayToMutableListPreservesMaxValueUnsigned() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = ubyteArrayOf(UByte.MAX_VALUE, 5u)
                println(a.toMutableList())
            }
            """,
            moduleName: "UByteArrayToMutableListMaxValue",
            expected: "[255, 5]\n"
        )
    }

    @Test
    func ushortArrayToMutableListPreservesMaxValueUnsigned() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = ushortArrayOf(UShort.MAX_VALUE, 5u)
                println(a.toMutableList())
            }
            """,
            moduleName: "UShortArrayToMutableListMaxValue",
            expected: "[65535, 5]\n"
        )
    }

    /// Generic `Array<T>.toMutableList()` was always correct (its receiver
    /// already stores boxed elements), but is now routed through the same
    /// source declaration as the primitive/unsigned overloads above.
    @Test
    func genericArrayToMutableListStillWorks() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = arrayOf("x", "y", "z")
                val m = a.toMutableList()
                m.add("w")
                println(m)
            }
            """,
            moduleName: "GenericArrayToMutableListRuntime",
            expected: "[x, y, z, w]\n"
        )
    }

    // MARK: - view vs. copy: asList aliases storage, toMutableList/toList do not

    /// `asList()` is a *view* backed by the same storage: mutating the
    /// original array through an index write is visible through the view.
    /// `toMutableList()` is a *copy*: the same mutation must not leak into an
    /// already-taken snapshot.
    @Test
    func asListViewsStorageWhileToMutableListCopiesIt() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val a = intArrayOf(1, 2, 3)
                val view = a.asList()
                val copy = a.toMutableList()
                a[0] = 99
                println(view)
                println(copy)
            }
            """,
            moduleName: "ArrayAsListViewVsToMutableListCopy",
            expected: """
            [99, 2, 3]
            [1, 2, 3]

            """
        )
    }
}
#endif
