@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ForwardObjectComputedPropertyInferenceTests {
    @Test
    func issueReproducerResolvesComputedPropertyBeforeConsumer() throws {
        let ctx = makeContext(["""
        class Consumer { fun read(): Int = Chain.value }
        object Chain { val value = Later.value + 1 }
        object Later { val value = 41 }
        fun main() { println(Consumer().read()) }
        // Keep the Sema fixture independent of bundled stdlib checking.
        fun println(value: Int) {}
        """])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for owner in ["Chain", "Later"] {
            let property = try #require(sema.symbols.lookup(
                fqName: [owner, "value"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.propertyType(for: property) == sema.types.intType)
        }
    }

    @Test(arguments: [true, false])
    func computedObjectChainResolvesAcrossFileOrders(consumerFirst: Bool) throws {
        let use = """
        import model.Chain
        fun read(): Int = Chain.value
        fun text(): String = Chain.text
        """
        let chain = """
        package model
        object Chain {
            val value = Middle.value + 1
            val text = Later.text + "!"
        }
        object Middle { val value = Later.value + 1 }
        """
        let later = """
        package model
        object Later {
            val value = 40
            val text = "forward"
        }
        """
        let ctx = makeContext(consumerFirst ? [use, chain, later] : [later, chain, use])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for (name, type) in [("value", sema.types.intType), ("text", sema.types.stringType)] {
            let property = try #require(sema.symbols.lookup(
                fqName: ["model", "Chain", name].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.propertyType(for: property) == type)
        }
    }

    @Test
    func constructorParameterShadowsObjectName() throws {
        let ctx = makeContext(["""
        class Payload(val value: String)
        class Holder(Later: Payload) { val value = Later.value + "!" }
        object Later { val value = 41 }
        fun read(holder: Holder): String = holder.value
        """])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(
            fqName: ["Holder", "value"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.propertyType(for: property) == sema.types.stringType)
    }

    @Test
    func wrongConsumerTypeKeepsTypeDiagnostic() throws {
        let ctx = makeContext(["""
        fun read(): String = Chain.value
        object Chain { val value = Later.value + 1 }
        object Later { val value = 41 }
        """])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0469" })
    }

    @Test
    func cyclicObjectPropertiesDoNotFabricateIntegerType() throws {
        let ctx = makeContext(["""
        fun read(): Int = Chain.value
        object Chain { val value = Later.value }
        object Later { val value = Chain.value }
        """])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0469" })
        let sema = try #require(ctx.sema)
        for owner in ["Chain", "Later"] {
            let property = try #require(sema.symbols.lookup(
                fqName: [owner, "value"].map(ctx.interner.intern)
            ))
            #expect(sema.symbols.propertyType(for: property) != sema.types.intType)
        }
    }

    private func makeContext(_ sources: [String]) -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = sources.indices.map { directory.appendingPathComponent("input\($0).kt").path }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        return ctx
    }
}
