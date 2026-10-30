@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite(.serialized)
struct AppleNestedNumericConversionInferenceTests {
    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test(arguments: [false, true])
    func namedOverloadsAndSiblingArgumentsSupplyPrimitiveTypes(library: Bool) throws {
        let ctx = try context("""
        import kotlinx.cinterop.convert
        import kotlin.test.assertEquals
        fun select(bytes: Int, length: ULong) {}
        fun select(text: String, options: ULong) {}
        fun main() {
            select(bytes = 0, length = 2.convert())
            assertEquals(2uL.convert(), 2L)
            val negative: Long = (-1).convert()
            assertEquals(-1L, negative)
        }
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true])
    func invalidNestedCallsKeepTheirDiagnostics(library: Bool) throws {
        let ctx = try context("""
        import kotlinx.cinterop.convert
        import kotlin.test.assertEquals
        fun select(bytes: Int, length: ULong) {}
        fun select(text: String, options: ULong) {}
        fun main() {
            select(bytes = 0, length = missingConversion())
            assertEquals(2uL.convert<String>(), 2L)
        }
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty)
        #expect(errors.contains { $0.message.contains("missingConversion") })

        let bounds = try context("""
        fun <R : Number> Int.number(): R = throw IllegalArgumentException()
        fun <T> same(first: T, second: T) {}
        fun main() { same(0.number(), 0uL) }
        """, library: library)
        let boundErrors = bounds.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!boundErrors.isEmpty, "An unsigned expectation cannot satisfy the Number bound")

        let ambiguity = try context("""
        import kotlinx.cinterop.convert
        fun select(length: Long) {}
        fun select(length: ULong) {}
        fun main() { select(length = 2.convert()) }
        """, library: library)
        let ambiguityCodes = ambiguity.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
        #expect(ambiguityCodes.contains("KSWIFTK-SEMA-0003"), "\(ambiguityCodes)")
    }

    @Test(arguments: [false, true])
    func byteArrayEmptinessKeepsItsBooleanType(library: Bool) throws {
        let ctx = try context("""
        fun check(bytes: ByteArray): Boolean = bytes.isNotEmpty()
        fun main() {
            val empty: Boolean = check(byteArrayOf())
            val nonempty: Boolean = check(byteArrayOf(1, 2))
        }
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true])
    func invalidArrayAllocationCountsAndElementsRemainRejected(library: Bool) throws {
        for call in ["allocArray<ByteVar>(2.5)", "allocArray<String>(3)"] {
            let ctx = try context("""
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            import kotlinx.cinterop.*
            fun main() = memScoped { \(call) }
            """, library: library)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(!errors.isEmpty, "\(call) must remain invalid")
        }
    }

    @Test(arguments: [false, true])
    func bytePointersReturnValuesAndGenericPointersKeepVariables(library: Bool) throws {
        let ctx = try context("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.*
        fun first(pointer: CPointer<ByteVar>): Byte = pointer[0]
        fun second(pointer: CPointer<ByteVar>): Byte = pointer.get(1)
        fun integerVariable(pointer: CPointer<IntVar>): IntVar = pointer[0]
        fun <T : CPointed> variable(pointer: CPointer<T>): T = pointer[0]
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let duplicateCodes = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }.map(\.code)
        #expect(duplicateCodes.isEmpty)
    }
}
