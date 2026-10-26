@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite
struct CoroutineProduceArgumentApplicabilityTests {
    @Test(arguments: [false, true])
    func nearerCallableTypesKeepTheirPriority(fromArtifact: Bool) throws {
        if fromArtifact { TestStdlibCache.shared.prepare() }
        let cases: [(String, String)] = [
            ("fun CoroutineScope.produce(block: () -> Int): Int = block() + 10", "val result: Int = produce { 3 }; println(result)"),
            ("fun interface IntBlock { fun get(): Int }; fun CoroutineScope.produce(block: IntBlock): Int = block.get() + 20", "val result: Int = produce { 3 }; println(result)"),
            ("fun <T> CoroutineScope.produce(block: () -> T): T = block()", "val result: Int = produce { 5 }; println(result)"),
            ("fun <T> CoroutineScope.produce(value: T): T = value", "val result = produce { 5 }; println(result())"),
            ("fun CoroutineScope.produce(value: Any): Int = 9", "val result: Int = produce { 3 }; println(result)"),
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputs = try cases.enumerated().map { index, entry in
            let (declaration, call) = entry
            let path = directory.appendingPathComponent("Near\(index).kt")
            try """
            package nearcases\(index)
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            \(declaration)
            fun main() { runBlocking { \(call) } }
            """.write(to: path, atomically: true, encoding: .utf8)
            return path.path
        }
        let ctx = makeCompilationContext(
            inputs: inputs, emit: .executable, allowDefaultStdlibLibrary: fromArtifact
        )
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError,
                Comment(rawValue: ctx.diagnostics.diagnostics.map(\.message).joined(separator: "\n")))
        let sema = try #require(ctx.sema)
        for index in cases.indices {
            let localName = [ctx.interner.intern("nearcases\(index)"), ctx.interner.intern("produce")]
            #expect(sema.bindings.callBindings.values.contains {
                sema.symbols.symbol($0.chosenCallee)?.fqName == localName
            }, "The nearer callable must remain selected")
        }
    }

    @Test(arguments: [false, true])
    func inapplicableNearerOverloadDoesNotSupplyAnUnimportedBuilder(fromArtifact: Bool) throws {
        if fromArtifact { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.CoroutineScope
        import kotlinx.coroutines.runBlocking
        fun CoroutineScope.produce(required: String): Int = required.length
        fun main() { runBlocking { val channel = produce { send(7) }; println(channel) } }
        """, emit: .executable, allowDefaultStdlibLibrary: fromArtifact)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "The unimported builder must remain unavailable")
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }
}
