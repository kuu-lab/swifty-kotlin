#if os(macOS)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import TestStdlibCache
import Testing

/// KUU-4028: end-to-end coverage for `kotlinx.cinterop` pointer element
/// operators — `CArrayPointer<T>[i] = v` (`set`), `ptr + index` (`plus`),
/// `CPointer.getPointer(scope)`, the `Long` index `get`, `rawValue`, and
/// `CPointerVarOf` element `set`/`plus`. Kotlin/Native-only API, so this
/// verifies `kswiftc` compile+run behavior rather than kotlinc parity.
@Suite(.serialized)
struct CInteropPointerElementOpsExecutionTests {
    @Test(arguments: [false, true])
    func pointerElementOpsCompileAndRun(library: Bool) throws {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let source = directory.appendingPathComponent("main.kt")
        try """
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.*

        fun main() {
            memScoped {
                val arr = allocArray<IntVar>(3)
                arr[0] = 10
                arr[1] = 20
                arr[2] = 30
                println(arr[0].value)
                println(arr[2].value)
                val p = arr.getPointer(this)
                println(p[1].value)
                val q = arr + 1
                println(q!![0].value)
                println(q!![1].value)
                arr[0] = 99
                println(arr[0L].value)
                val r = arr + 2L
                println(r!![0].value)
                println(arr.reinterpret<LongVar>()[0].value)

                val bytes = allocArray<ByteVar>(2)
                bytes[0] = 65
                bytes[1] = -1
                println(bytes[0])
                println(bytes[1])
                val byteNext = bytes + 1
                println(byteNext!![0])

                val shorts = allocArray<ShortVar>(2)
                shorts[0] = -30000
                shorts[1] = 123
                println(shorts[0].value)
                println(shorts[1].value)

                val longs = allocArray<LongVar>(2)
                longs[0] = 1234567890123L
                longs[1] = -5L
                println(longs[0].value)
                println(longs[1].value)
                val lp = longs + 1
                println(lp!![0].value)

                val dbls = allocArray<DoubleVar>(2)
                dbls[0] = 3.14
                dbls[1] = -2.5
                println(dbls[0].value)
                println(dbls[1].value)

                println(arr.rawValue.toLong() != 0L)

                val ints = allocArray<IntVar>(2)
                ints[0] = 11
                ints[1] = 22
                val ptrs = allocArray<CPointerVarOf<CPointer<IntVar>>>(2)
                ptrs[0] = ints + 0
                ptrs[1] = ints + 1
                println(ptrs[0].value.toLong() == ints.toLong())
                println(ptrs[1].value.toLong() == (ints + 1)!!.toLong())
                println(ptrs[0].value.pointed.value)
                println(ptrs[0].value[1].value)
                println((ptrs[0].value + 1)!![0].value)
                val pp = ptrs + 1
                println(pp!![0].value.toLong() == (ints + 1)!!.toLong())
                ptrs[0] = null
                println(ptrs[1].value.toLong() == (ints + 1)!!.toLong())

                arr.pointed.value = 7
                println(arr[0].value)
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("main")
        let ctx = try runCodegenPipeline(
            inputPath: source.path, moduleName: "CInteropPointerElementOps", outputPath: executable.path,
            optLevel: .O0,
            allowDefaultStdlibLibrary: false, stdlibLibraryPath: artifact
        )
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: executable.path, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == """
        10
        30
        20
        20
        30
        99
        30
        85899346019
        65
        -1
        -1
        -30000
        123
        1234567890123
        -5
        -5
        3.14
        -2.5
        true
        true
        true
        11
        22
        22
        true
        true
        7

        """)
    }
}
#endif
