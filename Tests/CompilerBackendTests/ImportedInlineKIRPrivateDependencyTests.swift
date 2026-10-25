@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct ImportedInlineKIRPrivateDependencyTests {
    @Test
    func metadataKeepsContextSupertypeArgumentsAndValueClassDependencies() {
        let (sema, symbols, types, interner) = makeSemaModule()
        func nominal(_ name: String, flags: SymbolFlags = []) -> SymbolID {
            symbols.define(kind: .class, name: interner.intern(name), fqName: [interner.intern(name)],
                           declSite: nil, visibility: .private, flags: flags)
        }
        func type(_ symbol: SymbolID) -> TypeID { types.make(.classType(ClassType(classSymbol: symbol))) }
        let context = nominal("ContextOnly")
        let base = nominal("Base")
        let argument = nominal("SupertypeArgument")
        let derived = nominal("Derived")
        let underlying = nominal("UnderlyingOnly")
        let wrapper = nominal("Wrapper", flags: [.valueType])
        let unused = nominal("Unused")
        symbols.setDirectSupertypes([base], for: derived)
        types.setNominalSupertypeTypeArgs([.invariant(type(argument))], for: derived, supertype: base)
        symbols.setValueClassUnderlyingType(type(underlying), for: wrapper)
        let helper = symbols.define(kind: .function, name: interner.intern("helper"),
                                    fqName: [interner.intern("helper")], declSite: nil, visibility: .private, flags: [])
        symbols.setFunctionSignature(FunctionSignature(
            receiverType: type(wrapper), contextReceiverTypes: [type(context)],
            parameterTypes: [], returnType: type(derived)
        ), for: helper)
        let arena = KIRArena()
        _ = arena.appendDecl(.function(KIRFunction(
            symbol: SymbolID(rawValue: -999_999), name: interner.intern("public$default"),
            params: [], returnType: types.unitType,
            body: [.call(symbol: helper, callee: interner.intern("helper"), arguments: [],
                         result: nil, canThrow: false)],
            isSuspend: false, isInline: true
        )))
        let required = InlineMetadataDependencies.collect(module: KIRModule(files: [], arena: arena), sema: sema)
        let records = MetadataEncoder().buildRecords(
            symbols: symbols, types: types, moduleName: "DependencyMetadata", interner: interner,
            functionLinkNames: [:], requiredNonPublicSymbols: required
        )
        for symbol in [context, base, argument, derived, underlying, wrapper, helper] {
            let name = symbols.symbol(symbol)?.fqName.map(interner.resolve).joined(separator: ".")
            #expect(records.contains { $0.fqName == name && $0.visibility == .private })
        }
        #expect(!records.contains { $0.fqName == interner.resolve(symbols.symbol(unused)!.name) })
    }

    @Test
    func defaultGlobalAndPrivateNominalDependenciesRemainImplementationDetails() throws {
        let producer = """
        package dependencies
        private open class Base(val text: String)
        private class Hidden(text: String) : Base(text)
        private fun hiddenSeed(): Hidden = Hidden("hidden")
        private var counter: Int = 1
        @PublishedApi internal fun labelSeed(): String = "default"
        fun usesHidden(action: () -> Unit): String { action(); return hiddenSeed().text }
        inline fun usesDefault(label: String = labelSeed(), action: () -> Unit): String {
            action()
            return label
        }
        fun usesGlobal(action: () -> Int): Int { counter += action(); return counter }
        """
        try withCompiledLibrary(source: producer, moduleName: "InlineDependencies") { libraryPath in
            let data = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
            let metadata = try #require(IndexedMetadataFile(data: data))
            for name in ["Base", "Hidden", "hiddenSeed", "counter", "labelSeed"] {
                let record = try #require(metadata.entries.first { $0.record.fqName == "dependencies.\(name)" }?.record)
                #expect(record.visibility == (name == "labelSeed" ? .internal : .private))
            }
            try withTemporaryFile(contents: """
            import dependencies.*
            fun main() {
                var calls = 0
                println(usesHidden { calls++ })
                println(usesDefault { calls++ })
                println(usesGlobal { calls++; 2 })
                println(usesGlobal { calls++; 4 })
                println(calls)
            }
            """) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output, searchPaths: [libraryPath]
                )
                try runToLowering(context)
                try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == "hidden\ndefault\n3\n7\n4\n")
            }
            for access in ["Hidden(\"x\")", "hiddenSeed()", "counter", "labelSeed()"] {
                try withTemporaryFile(contents: """
                import dependencies.*
                fun invalid() { println(\(access)) }
                """) { path in
                    let context = makeCompilationContext(inputs: [path], searchPaths: [libraryPath])
                    try runSema(context)
                    #expect(context.diagnostics.hasError, "Implementation dependencies must remain inaccessible")
                }
            }
        }
    }

    @Test
    func privateStringReturningHelperKeepsItsABIAndVisibility() throws {
        let producer = """
        package privateabi
        private fun render(value: Any?): String = when (value) {
            null -> "null"
            is Int -> "Int:" + value
            is Unit -> "Unit"
            else -> "other"
        }
        private fun unused(): Int = 99
        fun exposed(action: () -> Int): String = render(action())
        fun exposedUnit(action: () -> Unit): String = render(action())
        """
        try withCompiledLibrary(source: producer, moduleName: "PrivateInlineDependency") { libraryPath in
            let data = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
            let metadata = try #require(IndexedMetadataFile(data: data))
            let helper = try #require(metadata.entries.first { $0.record.fqName == "privateabi.render" }?.record)
            #expect(helper.visibility == .private)
            #expect(!metadata.entries.contains { $0.record.fqName == "privateabi.unused" })
            try withTemporaryFile(contents: """
            import privateabi.exposed
            import privateabi.exposedUnit
            fun main() {
                var calls = 0
                println(exposed { calls++; 0 })
                println(exposedUnit { calls++ })
                println(calls)
            }
            """) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output, searchPaths: [libraryPath]
                )
                try runToLowering(context)
                try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == "Int:0\nUnit\n2\n")
            }
            try withTemporaryFile(contents: """
            import privateabi.render
            fun invalid(): String = render(0)
            """) { path in
                let context = makeCompilationContext(inputs: [path], searchPaths: [libraryPath])
                try runSema(context)
                #expect(context.diagnostics.hasError, "The helper must remain inaccessible to source consumers")
            }
        }
    }
}
