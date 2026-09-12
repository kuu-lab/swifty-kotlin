#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testNativeCpuArchitectureUsesSourceOrderAndGeneratedEnumAPIs() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.CpuArchitecture

        fun main() {
            println(CpuArchitecture.entries.size)
            println(CpuArchitecture.values().size)
            println(CpuArchitecture.valueOf("ARM64"))
            println(CpuArchitecture.ARM64.bitness)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "CpuArchitecture enum APIs should lower without diagnostics"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let cpuArchitectureFQName = [
                interner.intern("kotlin"),
                interner.intern("native"),
                interner.intern("CpuArchitecture"),
            ]
            let cpuArchitectureSymbol = try #require(sema.symbols.lookup(fqName: cpuArchitectureFQName))
            #expect(sema.symbols.isSourceBackedSymbol(cpuArchitectureSymbol))

            let entryNames = sema.symbols.children(ofFQName: cpuArchitectureFQName)
                .compactMap { symbolID -> SemanticSymbol? in
                    guard let symbol = sema.symbols.symbol(symbolID), symbol.kind == .field else {
                        return nil
                    }
                    return symbol
                }
                .sorted { $0.id.rawValue < $1.id.rawValue }
                .map { interner.resolve($0.name) }
            #expect(
                entryNames == ["UNKNOWN", "ARM32", "ARM64", "X86", "X64", "MIPS32", "MIPSEL32", "WASM32"],
                "CpuArchitecture entries must retain Kotlin 2.3.10 source order"
            )

            let bitnessSymbol = try #require(
                sema.symbols.lookup(fqName: cpuArchitectureFQName + [interner.intern("bitness")])
            )
            #expect(sema.symbols.isSourceBackedSymbol(bitnessSymbol))
            #expect(sema.symbols.propertyType(for: bitnessSymbol) == sema.types.intType)

            let module = try #require(ctx.kir)
            #expect(
                module.arena.declarations.contains { declaration in
                    guard case let .nominalType(nominal) = declaration else { return false }
                    return nominal.symbol == cpuArchitectureSymbol
                },
                "CpuArchitecture must retain its source-backed nominal identity in KIR"
            )

            // `ARM64.bitness` emits a `$enumConstructorProperty$` placeholder
            // call that must resolve to the synthesized helper even though the
            // bundled stdlib file was skipped from output lowering.
            let helperDecl = module.arena.declarations.contains { declaration in
                guard case let .function(function) = declaration else { return false }
                return interner.resolve(function.name) == "$enumConstructorProperty$bitness"
            }
            #expect(
                helperDecl,
                "Skipped bundled enum must still get its constructor-property helper synthesized"
            )
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: interner)
            for instruction in mainBody {
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      interner.resolve(callee).hasPrefix("$enumConstructorProperty$")
                else {
                    continue
                }
                #expect(symbol != nil, "enum constructor-property call must carry the helper symbol")
            }
        }
    }

    @Test
    func testNativeCpuArchitectureNominalIsRetainedForPlatformPropertyType() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun main() {
            val cpuArchitecture = Platform.cpuArchitecture
            println(cpuArchitecture)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Platform.cpuArchitecture should lower without diagnostics"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let cpuArchitectureFQName = [
                interner.intern("kotlin"),
                interner.intern("native"),
                interner.intern("CpuArchitecture"),
            ]
            let cpuArchitectureSymbol = try #require(sema.symbols.lookup(fqName: cpuArchitectureFQName))
            #expect(sema.symbols.isSourceBackedSymbol(cpuArchitectureSymbol))

            let module = try #require(ctx.kir)
            #expect(
                module.arena.declarations.contains { declaration in
                    guard case let .nominalType(nominal) = declaration else { return false }
                    return nominal.symbol == cpuArchitectureSymbol
                },
                "Platform.cpuArchitecture must retain the source-backed CpuArchitecture nominal in consumer KIR"
            )
        }
    }
}
#endif
