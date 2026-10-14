@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendUsePinnedNonLocalReturnTests {
    @Test(arguments: ["source", "stdlib", "producer"], [0, 2])
    func returnsAndCleanupAcrossCompilationRoutes(route: String, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = route == "source" ? nil : try StdlibArtifactRegressionTests.buildStdlibArtifact()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let producer = directory.appendingPathComponent("producer.kt")
        let consumer = directory.appendingPathComponent("consumer.kt")
        try Self.producer.write(to: producer, atomically: true, encoding: .utf8)
        try Self.consumer.write(to: consumer, atomically: true, encoding: .utf8)
        let libraryBase = directory.appendingPathComponent("PinnedProducer").path
        if route == "producer" {
            let options = CompilerOptions(
                moduleName: "PinnedProducer", inputs: [producer.path], outputPath: libraryBase,
                emit: .library, target: defaultTargetTriple(), optLevel: optLevel,
                stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(options: options, sourceManager: SourceManager(),
                                         diagnostics: DiagnosticEngine(), interner: StringInterner())
            try runToKIR(ctx)
            try Self.instrumentUnpin(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            #expect(FileManager.default.fileExists(atPath: libraryBase + ".kklib/metadata.bin"))
        }
        let executable = directory.appendingPathComponent("consumer").path
        let options = CompilerOptions(
            moduleName: "PinnedConsumer",
            inputs: route == "producer" ? [consumer.path] : [producer.path, consumer.path],
            outputPath: executable, emit: .executable,
            searchPaths: route == "producer" ? [libraryBase + ".kklib"] : [],
            target: defaultTargetTriple(), optLevel: optLevel,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )
        let ctx = CompilationContext(options: options, sourceManager: SourceManager(),
                                     diagnostics: DiagnosticEngine(), interner: StringInterner())
        try runToKIR(ctx)
        if route != "producer" { try Self.instrumentUnpin(ctx) }
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: executable, arguments: [], timeout: 20)
        #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == Self.expected, Comment(rawValue: "\(route) O\(optimization):\n\(result.stdout)"))
    }

    /// Count actual cleanup executions, then forward to the real runtime unpin.
    /// Runtime unpin is idempotent, so probing a disposed handle alone cannot
    /// distinguish exactly one cleanup from an accidental double cleanup.
    private static func instrumentUnpin(_ ctx: CompilationContext) throws {
        let sema = try #require(ctx.sema)
        let kir = try #require(ctx.kir)
        let unpin = try #require(sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "Pinned", "unpin"].map(ctx.interner.intern)))
        let audit = try #require(sema.symbols.lookup(fqName: ["pinned2057", "auditedUnpin"].map(ctx.interner.intern)))
        #expect(sema.symbols.externalLinkName(for: unpin) == "kk_unpin_object")
        let auditName = try #require(sema.symbols.symbol(audit)?.name)
        var count = 0
        kir.arena.transformFunctions { original in
            var function = original
            let body = original.body.map { instruction -> KIRInstruction in
                guard case let .call(symbol, _, arguments, result, canThrow, thrown, isSuper, qualifiedSuperType) = instruction,
                      symbol == unpin else { return instruction }
                count += 1
                return .call(symbol: audit, callee: auditName, arguments: arguments, result: result,
                             canThrow: canThrow, thrownResult: thrown, isSuperCall: isSuper, qualifiedSuperType: qualifiedSuperType)
            }
            function.replaceBody(body, locations: original.instructionLocations)
            return function
        }
        #expect(count >= 9)
    }

    private static let producer = """
    @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlin.native.runtime.NativeRuntimeApi::class)
    package pinned2057
    import kotlinx.cinterop.Pinned
    import kotlinx.cinterop.usePinned
    import kotlin.internal.KsSymbolName
    import kotlin.native.runtime.GC

    var unpins = 0
    var rootsValid = true
    var lastHandle: Pinned<ByteArray>? = null
    @KsSymbolName("kk_unpin_object")
    external fun rawUnpin(handle: Pinned<ByteArray>): Long
    @KsSymbolName("kk_pinned_get")
    external fun rawGet(handle: Pinned<ByteArray>): Long
    fun auditedUnpin(handle: Pinned<ByteArray>) {
        rootsValid = rootsValid && rawGet(handle) != 0L
        unpins += 1
        lastHandle = handle
        rawUnpin(handle)
        rootsValid = rootsValid && rawGet(handle) == 0L
    }
    fun first(bytes: ByteArray): Byte {
        bytes.usePinned { return bytes[0] }
    }
    fun control(bytes: ByteArray): Byte {
        return bytes.usePinned { bytes[0] }
    }
    fun captured(bytes: ByteArray, offset: Int): Int {
        bytes.usePinned { pinned ->
            GC.collect()
            return pinned.get()[0].toInt() + offset
        }
    }
    fun nested(bytes: ByteArray): Int {
        try {
            bytes.usePinned { outer ->
                try {
                    bytes.usePinned { inner ->
                        try {
                            GC.collect()
                            return outer.get()[0].toInt() + inner.get()[0].toInt()
                        } finally { println("inner:$unpins") }
                    }
                } finally { println("between:$unpins") }
            }
        } finally { println("outer:$unpins") }
    }
    fun throwing(bytes: ByteArray) {
        try {
            bytes.usePinned { throw IllegalStateException("boom") }
        } finally { println("exception-finally:$unpins") }
    }
    fun local(bytes: ByteArray): Byte = bytes.usePinned { return@usePinned bytes[0] }
    fun conditional(bytes: ByteArray, early: Boolean): Byte {
        bytes.usePinned {
            if (early) return bytes[0]
            println("fallthrough")
        }
        return (-1).toByte()
    }
    fun safe(bytes: ByteArray?): Byte {
        bytes?.usePinned { return it.get()[0] }
        return (-2).toByte()
    }
    fun replacedReturn(bytes: ByteArray): Byte {
        bytes.usePinned {
            try { return bytes[0] } finally { return 44.toByte() }
        }
    }
    fun replacedByThrow(bytes: ByteArray): Byte {
        try {
            bytes.usePinned {
                try { return bytes[0] } finally { throw IllegalArgumentException("replacement") }
            }
        } finally { println("replacement-finally:$unpins") }
    }
    class Box {
        fun usePinned(block: () -> Int): Int {
            println("member")
            return block() + 1
        }
    }
    """

    private static let consumer = """
    @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
    import pinned2057.*
    fun main() {
        val bytes = byteArrayOf(41)
        println(first(bytes))
        println(control(bytes))
        println(captured(bytes, 2))
        println(nested(bytes))
        try { throwing(bytes) } catch (e: IllegalStateException) { println("caught:$unpins") }
        println(local(bytes))
        println(conditional(bytes, false))
        println(conditional(bytes, true))
        println(safe(null))
        println(safe(bytes))
        println(replacedReturn(bytes))
        try { replacedByThrow(bytes) } catch (e: IllegalArgumentException) { println("replacement-caught:$unpins") }
        println(Box().usePinned { 10 })
        println("unpins:$unpins")
        println("roots:$rootsValid")
        println("disposed:${rawGet(lastHandle!!) == 0L}")
    }
    """

    private static let expected = """
    41
    41
    43
    inner:3
    between:4
    outer:5
    82
    exception-finally:6
    caught:6
    41
    fallthrough
    -1
    41
    -2
    41
    44
    replacement-finally:12
    replacement-caught:12
    member
    11
    unpins:12
    roots:true
    disposed:true

    """
}
