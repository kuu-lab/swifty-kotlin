// Scratch proposal only. Not type-checked or executed.
#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImportedMemberSetterRoutingTests {
    private func setterCalls(_ body: [KIRInstruction], symbol: SymbolID) -> Int {
        body.filter { instruction in
            if case let .call(calleeSymbol, _, _, _, _, _, _, _) = instruction {
                return calleeSymbol == symbol
            }
            return false
        }.count
    }

    @Test func sourceSetterPredicatePreservesPlainAndBackingStorage() throws {
        let context = makeContextFromSource("""
        class Box {
            var value: Int = 0
                set(v) { field = v * 2 }
            var plain: Int = 0
        }
        fun main() {}
        """)
        try runToKIR(context)
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let value = try #require(sema.symbols.lookup(fqName: ["Box", "value"].map(context.interner.intern)))
        let plain = try #require(sema.symbols.lookup(fqName: ["Box", "plain"].map(context.interner.intern)))
        let backing = try #require(sema.symbols.backingFieldSymbol(for: value))
        let driver = KIRLoweringDriver(ctx: KIRLoweringContext())
        #expect(driver.callLowerer.memberPropertyUsesSetterAccessor(value, ast: ast, sema: sema))
        #expect(!driver.callLowerer.memberPropertyUsesSetterAccessor(plain, ast: ast, sema: sema))
        #expect(!driver.callLowerer.memberPropertyUsesSetterAccessor(backing, ast: ast, sema: sema))
        #expect(sema.symbols.symbol(backing)?.kind == .backingField)
    }

    @Test func sourceSetterOnlyBareWritesUseAccessorIndependentlyOfGetter() throws {
        let context = makeContextFromSource("""
        class Box {
            var value: Int = 0
                set(v) { field = v * 2 }
            var plain: Int = 0
            fun write() {
                value = 1
                value += 1
                value--
                plain = 4
            }
        }
        fun main() {}
        """)
        try runToKIR(context)
        let module = try #require(context.kir)
        let sema = try #require(context.sema)
        let property = try #require(sema.symbols.lookup(fqName: ["Box", "value"].map(context.interner.intern)))
        let setter = sema.symbols.extensionPropertySetterAccessor(for: property)
            ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: property)
        let body = try findKIRFunctionBody(named: "write", in: module, interner: context.interner)
        #expect(setterCalls(body, symbol: setter) == 3,
                "=, += and -- must all run the setter even with a default getter")
        #expect(body.contains { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return context.interner.resolve(callee) == "kk_array_set"
            }
            return false
        }, "the plain var must retain its direct field write")
    }

    @Test func importedSetterGuardRejectsMissingLinkAndNonpropertyKinds() throws {
        let context = makeContextFromSource("fun main() {}")
        try runToKIR(context)
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let driver = KIRLoweringDriver(ctx: KIRLoweringContext())
        let cases: [(SymbolKind, Bool, String?, Bool)] = [
            (.property, true, "fixture_set", true),
            (.property, true, "", false),
            (.property, true, nil, false),
            (.property, false, "fixture_set", false),
            (.field, true, "fixture_set", false),
            (.backingField, true, "fixture_set", false),
        ]
        for (index, entry) in cases.enumerated() {
            let (kind, imported, link, expected) = entry
            let name = context.interner.intern("p\(index)")
            let property = sema.symbols.define(
                kind: kind, name: name, fqName: [name], declSite: nil,
                visibility: .public, flags: imported ? [.importedLibrary] : []
            )
            let setterName = context.interner.intern("set\(index)")
            let setter = sema.symbols.define(
                kind: .function, name: setterName, fqName: [setterName],
                declSite: nil, visibility: .public
            )
            sema.symbols.setExtensionPropertySetterAccessor(setter, for: property)
            if let link { sema.symbols.setExternalLinkName(link, for: setter) }
            #expect(driver.callLowerer.memberPropertyUsesSetterAccessor(property, ast: ast, sema: sema) == expected)
        }
    }

    @Test func actualImportedMetadataRoutesSetterOnlyBareAndExplicitWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = """
        {"formatVersion":1,"moduleName":"SetterFixture","metadata":"metadata.bin"}
        """
        let metadata = """
        symbols=3
        class _ fq=fixture.Box schema=v1 fields=2 layoutWords=2 fieldOffsets=fixture.Box.value@0,fixture.Box.plain@1
        property _ fq=fixture.Box.value schema=v1 sig=I mutable=1 setterLink=fixture_box_value_set
        property _ fq=fixture.Box.plain schema=v1 sig=I mutable=1
        """
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let source = """
        fun fixture.Box.bare() {
            value = 1
            value += 1
            value--
            plain = 4
        }
        fun explicit(box: fixture.Box) {
            box.value = 1
            box.value += 1
            box.value--
            box.plain = 4
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], searchPaths: [directory.path])
            try runToKIR(context)
            let module = try #require(context.kir)
            let sema = try #require(context.sema)
            let property = try #require(sema.symbols.lookup(fqName: ["fixture", "Box", "value"].map(context.interner.intern)))
            let setter = try #require(sema.symbols.extensionPropertySetterAccessor(for: property))
            #expect(sema.symbols.externalLinkName(for: setter) == "fixture_box_value_set")
            #expect(sema.symbols.extensionPropertyGetterAccessor(for: property) == nil)
            #expect(sema.symbols.symbol(property)?.flags.contains(.importedLibrary) == true)
            #expect(!SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(setter),
                    "imported metadata accessor is an ordinary registered symbol")
            for name in ["bare", "explicit"] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: context.interner)
                #expect(setterCalls(body, symbol: setter) == 3,
                        "\(name): =, += and -- must each use the imported setter")
            }
            try LoweringPhase().run(context)
            let loweredBody = try findKIRFunctionBody(named: "bare", in: module, interner: context.interner)
            let calls = loweredBody.compactMap { instruction -> Bool? in
                if case let .call(symbol, _, _, _, canThrow, _, _, _) = instruction, symbol == setter {
                    return canThrow
                }
                return nil
            }
            #expect(calls.count == 3)
            #expect(calls.allSatisfy { $0 }, "source-backed imported setter must retain the thrown ABI")
        }
    }
}
#endif
