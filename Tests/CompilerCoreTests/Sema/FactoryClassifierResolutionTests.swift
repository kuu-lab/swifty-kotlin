@testable import CompilerCore
import Testing

@Suite
struct FactoryClassifierResolutionTests {
    @Test(arguments: ["wildcard", "explicit", "alias", "default"])
    func importedClassifierSurvivesSameNamedPackageFactory(importKind: String) throws {
        let importedPackage = importKind == "default" ? "kotlin" : "selected"
        let typeName = importKind == "alias" ? "Chosen" : "Sink"
        let importLine: String
        switch importKind {
        case "wildcard": importLine = "import selected.*"
        case "explicit": importLine = "import selected.Sink\nimport selected.Buffer"
        case "alias": importLine = "import selected.Sink as Chosen\nimport selected.Buffer"
        default: importLine = ""
        }
        let sources = [
            """
            package competing
            interface Sink { class Nested }
            """,
            """
            package \(importedPackage)
            interface Sink {
                fun marker(): Int
                class Nested
            }
            class Buffer : Sink {
                override fun marker(): Int = 7
            }
            """,
            """
            package pkg
            \(importLine)
            fun \(typeName)(): Buffer = Buffer()
            fun \(typeName)(value: Int): Buffer = Buffer()
            fun \(typeName).preview(): Int = marker()
            fun sameFile(value: \(typeName)): \(typeName) = value
            """,
            """
            package pkg
            \(importLine)
            fun use(value: \(typeName), nestedValue: \(typeName).Nested): Int {
                val typed: \(typeName) = value
                val casted = value as \(typeName)
                val nested: \(typeName).Nested = nestedValue
                return typed.marker() + casted.marker() + \(typeName)().marker()
            }
            fun nested(value: \(typeName).Nested): \(typeName).Nested = value
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let sink = try #require(sema.symbols.lookup(
                fqName: [importedPackage, "Sink"].map { ctx.interner.intern($0) }
            ))
            let nested = try #require(sema.symbols.lookup(
                fqName: [importedPackage, "Sink", "Nested"].map { ctx.interner.intern($0) }
            ))
            for name in ["sameFile", "use", "preview", "nested"] {
                let function = try #require(sema.symbols.lookupAll(
                    fqName: ["pkg", name].map { ctx.interner.intern($0) }
                ).first)
                let signature = try #require(sema.symbols.functionSignature(for: function))
                let type = try #require(name == "preview" ? signature.receiverType : signature.parameterTypes.first)
                guard case let .classType(nominal) = sema.types.kind(of: type) else {
                    Issue.record("Expected imported classifier in \(name)")
                    continue
                }
                #expect(nominal.classSymbol == (name == "nested" ? nested : sink))
            }
        }
    }

    @Test
    func samePackageClassifierStillShadowsWildcardImport() throws {
        let sources = [
            "package imported\ninterface Sink",
            """
            package pkg
            import imported.*
            interface Sink { fun marker(): Int }
            class Buffer : Sink { override fun marker(): Int = 9 }
            fun Sink(): Buffer = Buffer()
            fun use(value: Sink): Int {
                val typed: Sink = value
                return typed.marker()
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let sink = try #require(sema.symbols.lookupAll(
                fqName: ["pkg", "Sink"].map { ctx.interner.intern($0) }
            ).first { sema.symbols.symbol($0)?.kind == .interface })
            let use = try #require(sema.symbols.lookup(
                fqName: ["pkg", "use"].map { ctx.interner.intern($0) }
            ))
            let signature = try #require(sema.symbols.functionSignature(for: use))
            guard case let .classType(parameter) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected same-package classifier")
                return
            }
            #expect(parameter.classSymbol == sink)
        }
    }
}
