@testable import CompilerCore
import Foundation
import RuntimeABI
import Testing
@testable import CompilerTestSupport

@Suite
struct SingletonKClassMetadataTests {
    @Test
    func eagerSingletonInitializersRegisterTheirOwnClassifierMetadata() throws {
        let source = """
        package singletonmetadata
        object Token
        private object Hidden
        interface Marker
        class Holder {
            object Nested : Marker
            companion object Named
        }
        """
        let path = "/virtual/singleton-metadata.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        for name in ["Token", "Hidden", "Holder.Nested", "Holder.Named"] {
            let fqName = "singletonmetadata." + name
            let symbol = try #require(sema.symbols.lookup(fqName: fqName.split(separator: ".").map {
                ctx.interner.intern(String($0))
            }))
            let initializer = try #require(findAllKIRFunctions(in: module).first {
                let initializerName = ctx.interner.resolve($0.name)
                return initializerName == "__object_init_\(symbol.rawValue)"
                    || (initializerName.hasPrefix("__companion_init_")
                        && initializerName.hasSuffix("_\(symbol.rawValue)"))
            })
            let calls = kirCalls(in: initializer.body)
            let typeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: symbol, sema: sema, interner: ctx.interner
            )
            let token = RuntimeTypeCheckToken.encode(
                base: RuntimeTypeCheckToken.nominalBase, nullable: false, payload: typeID
            )
            let metadata = try #require(calls.first {
                ctx.interner.resolve($0.callee) == "__kk_kclass_register_metadata"
                    && $0.arguments.first.map { module.arena.expr($0) == .intLiteral(token) } == true
            }, "Missing eager metadata for \(fqName)")
            let abi = try #require(RuntimeABISpec.allFunctions.first {
                $0.name == ctx.interner.resolve(metadata.callee)
            })
            #expect(metadata.arguments.count == abi.parameters.count)
            #expect(abi.parameters.allSatisfy { $0.type == .intptr })
            #expect(!metadata.canThrow)
            #expect(metadata.thrownResult == nil)
            #expect(module.arena.expr(metadata.arguments[1]) == .stringLiteral(ctx.interner.intern(fqName)))
            #expect(module.arena.expr(metadata.arguments[2]) == .stringLiteral(ctx.interner.intern(String(name.split(separator: ".").last!))))
        }
    }
}
