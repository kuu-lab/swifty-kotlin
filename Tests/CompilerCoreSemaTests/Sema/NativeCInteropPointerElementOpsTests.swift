@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// KUU-4028: `CPointer`/`CArrayPointer` element write (`set` operator),
/// pointer arithmetic (`plus`), `CPointer.getPointer(scope)`, the `Long`
/// index `get`, `rawValue`, and `CPointerVarOf` element `set`/`plus` must
/// resolve against the synthetic kotlinx.cinterop surface.
@Suite(.serialized)
struct NativeCInteropPointerElementOpsTests {
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
    func arrayPointerSetPlusAndGetPointerResolve(library: Bool) throws {
        let ctx = try context("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.*
        fun main() {
            memScoped {
                val arr = allocArray<IntVar>(3)
                arr[0] = 10
                arr[1] = 20
                val read: Int = arr[0].value
                val p = arr.getPointer(this)
                val advanced = arr + 1
                val viaLongIndex: Int = arr[0L].value
                val stepped = arr + 2L
            }
        }
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true])
    func primitiveVarKindsAcceptSetAndPlus(library: Bool) throws {
        let ctx = try context("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.*
        fun main() {
            memScoped {
                val bools = allocArray<BooleanVar>(1)
                bools[0] = true
                val bytes = allocArray<ByteVar>(1)
                bytes[0] = 65
                val shorts = allocArray<ShortVar>(1)
                shorts[0] = -30000
                val ints = allocArray<IntVar>(1)
                ints[0] = 7
                val uints = allocArray<UIntVar>(1)
                uints[0] = 9u
                val longs = allocArray<LongVar>(1)
                longs[0] = 1234567890123L
                val ulongs = allocArray<ULongVar>(1)
                ulongs[0] = 9uL
                val floats = allocArray<FloatVar>(1)
                floats[0] = 1.5f
                val doubles = allocArray<DoubleVar>(1)
                doubles[0] = -2.5
                val ushorts = allocArray<UShortVar>(1)
                ushorts[0] = 3u.toUShort()
                val ubytes = allocArray<UByteVar>(1)
                ubytes[0] = 4u.toUByte()
                val next = ints + 1
                val raw = ints.rawValue
            }
        }
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true])
    func pointerElementArraySetAndPlusResolve(library: Bool) throws {
        let ctx = try context("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.*
        fun main() {
            memScoped {
                val ints = allocArray<IntVar>(2)
                val ptrs = allocArray<CPointerVarOf<CPointer<IntVar>>>(2)
                ptrs[0] = ints
                ptrs[1] = ints + 1
                ptrs[0] = null
                val next = ptrs + 1
                val element = ptrs[0]
            }
        }
        """, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
