@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SourceReferenceVarargArtifactABITests {
    @Test(arguments: [false, true], ["legacyReference", "arrayReference", "legacyPrimitive", "runtimeReference", "legacyReified", "arrayReified"])
    func storageCompatibilityAndReifiedArity(indexed: Bool, family: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = family.hasPrefix("array")
        let reified = family.hasSuffix("Reified")
        let runtimeBridge = family == "runtimeReference"
        let primitive = family == "legacyPrimitive"
        let link = runtimeBridge ? "__kk_abi_test_reference" : "kk_fn_abi_probe"
        var manifest: [String: Any] = ["formatVersion": 1, "moduleName": "VarargABI", "metadata": "metadata.bin"]
        if current { manifest["sourceVarargStorageABI"] = "array-v1" }
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        let record = MetadataRecord(
            kind: .function, mangledName: "_KK_abi_probe", fqName: "abi.probe", arity: 1,
            typeSignature: reified ? "F1<T0,Lkotlin_String;>" : primitive ? "F1<I,I>" : "F1<Lkotlin_String;,I>",
            callableTypeParameterSignatures: reified ? ["T0"] : [],
            valueParameterIsVararg: [!reified], valueParameterHasDefaultValues: [reified],
            valueParameterNames: ["values"], reifiedTypeParameterIndices: reified ? [0] : [],
            defaultStubExternalLinkName: reified ? "kk_fn_abi_probe_default" : nil,
            externalLinkName: link
        )
        let encoder = MetadataEncoder()
        let metadata = indexed ? encoder.serializeIndexed([record]) : encoder.serialize([record])
        try metadata.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let source = reified ? "import abi.probe\nfun explicit() = probe<String>(\"x\")\nfun omitted() = probe<String>()"
            : primitive ? "import abi.probe\nfun caller() = probe(1)" : "import abi.probe\nfun caller() = probe(\"x\")"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
            if family == "legacyReference" {
                try runSema(ctx)
                #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0034" })
                return
            }
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let symbol = try #require(sema.symbols.lookup(fqName: ["abi", "probe"].map(ctx.interner.intern)))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.valueParameterIsVararg == [!reified], "public metadata retains the declaration element and vararg flag")
            if reified {
                #expect(signature.returnType == sema.types.stringType, "Lkotlin_String; decodes String, never Short")
            } else {
                #expect(signature.parameterTypes == [primitive ? sema.types.intType : sema.types.stringType])
            }
            #expect(sema.symbols.symbol(symbol)?.flags.contains(.legacyReifiedClassTokenABI) == !current)
            if runtimeBridge {
                let module = try #require(ctx.kir)
                let caller = try findKIRFunction(named: "caller", in: module, interner: ctx.interner)
                #expect(extractCallees(from: caller.body, interner: ctx.interner).contains("__kk_array_toList"),
                        "Normal runtime reference-vararg calls retain their List payload conversion")
            }
            if reified {
                let module = try #require(ctx.kir)
                for (name, target, count) in [("explicit", link, current ? 3 : 2), ("omitted", "kk_fn_abi_probe_default", current ? 4 : 3)] {
                    let function = try findKIRFunction(named: name, in: module, interner: ctx.interner)
                    let calls = function.body.compactMap { instruction -> [KIRExprID]? in
                        guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else { return nil }
                        return ctx.interner.resolve(callee) == target || ctx.interner.resolve(callee) == (name == "omitted" ? "probe$default" : "probe") ? arguments : nil
                    }
                    try #require(calls.count == 1)
                    #expect(calls[0].count == count, "legacy class-only versus new class/component, mask stays last")
                    if name == "omitted" { #expect(module.arena.expr(try #require(calls[0].last)) == .intLiteral(1)) }
                }
                let stub = SyntheticSymbolScheme.defaultStubSymbol(for: symbol)
                #expect(sema.symbols.functionSignature(for: stub)?.parameterTypes.count == (current ? 4 : 3))
            }
        }
    }

    @Test(arguments: [false, true], [1, 2])
    func inlineArtifactRetainsEveryRawHiddenSlotAndPackedValueType(current: Bool, reifiedCount: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        let inline = directory.appendingPathComponent("inline-kir")
        try FileManager.default.createDirectory(at: inline, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var manifest: [String: Any] = ["formatVersion": 1, "moduleName": "InlineArrayABI", "metadata": "metadata.bin", "inlineKIRDir": "inline-kir"]
        if current { manifest["sourceVarargStorageABI"] = "array-v1" }
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        let record = MetadataRecord(
            kind: .function, mangledName: "InlineTokens", fqName: "abi.inlineTokens", arity: current ? 1 : 0, isInline: true,
            typeSignature: current ? "F1<Lkotlin_String;,U>" : "F0<U>",
            callableTypeParameterSignatures: (0..<reifiedCount).map { "T\($0)" },
            valueParameterIsVararg: current ? [true] : [],
            reifiedTypeParameterIndices: Set(0..<reifiedCount), externalLinkName: "kk_fn_abi_inlineTokens"
        )
        try MetadataEncoder().serialize([record]).write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let hidden = reifiedCount * (current ? 2 : 1)
        let count = hidden + (current ? 1 : 0)
        let parameterSymbols = (0..<count).map { String(100 + $0) }.joined(separator: ",")
        let artifact = "version=2\nparams=\(count)\nparamSymbols=\(parameterSymbols)\nbody:\nreturnUnit\n"
        try artifact.write(to: inline.appendingPathComponent(MetadataEncoder.inlineKIRFileName(for: record.mangledName)), atomically: true, encoding: .utf8)
        let arguments = reifiedCount == 1 ? "String" : "String, Int"
        let values = current ? "\"x\"" : ""
        try withTemporaryFile(contents: "import abi.inlineTokens\nfun caller() { inlineTokens<\(arguments)>(\(values)) }") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
            try runSema(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let symbol = try #require(sema.symbols.lookup(fqName: ["abi", "inlineTokens"].map(ctx.interner.intern)))
            let function = try #require(sema.importedInlineFunctions.function(for: symbol, arena: KIRArena()))
            #expect(function.params.count == count)
            #expect(function.params.suffix(hidden).allSatisfy { $0.type == sema.types.intType }, "every class/component descriptor stays a raw word")
            if current {
                guard case let .classType(array) = sema.types.kind(of: function.params[0].type) else {
                    Issue.record("new source reference-vararg body parameter must be Array storage")
                    return
                }
                #expect(sema.symbols.symbol(array.classSymbol)?.fqName.map(ctx.interner.resolve) == ["kotlin", "Array"])
            }
        }
    }


    @Test(arguments: [false, true], ["reference", "twoReified", "legacyPrimitive"])
    func inlineDefaultStubKeepsLeadingPackedValuesAndExplicitHiddenWords(memberExtension: Bool, family: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        let inline = directory.appendingPathComponent("inline-kir")
        try FileManager.default.createDirectory(at: inline, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let primitive = family == "legacyPrimitive"
        let reifiedCount = family == "twoReified" ? 2 : 0
        var manifest: [String: Any] = ["formatVersion": 1, "moduleName": "DefaultArrayABI", "metadata": "metadata.bin", "inlineKIRDir": "inline-kir"]
        if !primitive { manifest["sourceVarargStorageABI"] = "array-v1" }
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        let name = memberExtension ? "abi.Host.words" : "abi.words"
        let defaultLink = "kk_fn_abi_words_default"
        let record = MetadataRecord(
            kind: .function, mangledName: "DefaultWords", fqName: name, arity: 1, isInline: true,
            isMemberExtension: memberExtension, receiverOwnerFQName: memberExtension ? "kotlin.String" : nil,
            typeSignature: primitive ? "F1<I,U>" : "F1<Lkotlin_String;,U>",
            callableTypeParameterSignatures: (0..<reifiedCount).map { "T\($0)" },
            valueParameterIsVararg: [true], valueParameterHasDefaultValues: [true],
            reifiedTypeParameterIndices: Set(0..<reifiedCount),
            defaultStubExternalLinkName: defaultLink, externalLinkName: "kk_fn_abi_words"
        )
        var records = [record]
        if memberExtension { records.insert(MetadataRecord(kind: .class, mangledName: "Host", fqName: "abi.Host"), at: 0) }
        try MetadataEncoder().serializeIndexed(records).write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let leading = memberExtension ? 2 : 0
        let hiddenAndMask = reifiedCount * 2 + 1
        let count = leading + 1 + hiddenAndMask
        let parameterSymbols = (0..<count).map { String(200 + $0) }.joined(separator: ",")
        let artifact = "version=2\nparams=\(count)\nparamSymbols=\(parameterSymbols)\nbody:\nreturnUnit\n"
        try artifact.write(to: inline.appendingPathComponent(MetadataEncoder.inlineKIRFileName(for: defaultLink)), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun caller() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let symbol = try #require(sema.symbols.lookup(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) }))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let stub = SyntheticSymbolScheme.defaultStubSymbol(for: symbol)
            let stubSignature = try #require(sema.symbols.functionSignature(for: stub))
            let function = try #require(sema.importedInlineFunctions.function(for: stub, arena: KIRArena()))
            #expect(function.params.count == count)
            #expect(function.params.suffix(hiddenAndMask).allSatisfy { $0.type == sema.types.intType })
            if memberExtension {
                #expect(stubSignature.receiverType == nil)
                #expect(function.params[0].type == stubSignature.parameterTypes[0], "leading dispatch receiver retains its class type")
                #expect(function.params[1].type == signature.receiverType, "leading extension receiver retains its type")
            }
            guard case let .classType(array) = sema.types.kind(of: function.params[leading].type) else {
                Issue.record("default inline body vararg must retain physical array storage")
                return
            }
            #expect(sema.symbols.symbol(array.classSymbol)?.fqName.map(ctx.interner.resolve) == ["kotlin", primitive ? "IntArray" : "Array"])
        }
    }

}
