#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

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
