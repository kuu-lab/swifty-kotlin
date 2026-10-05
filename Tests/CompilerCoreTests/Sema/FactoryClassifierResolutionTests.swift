@testable import CompilerCore
import Testing

@Suite
struct FactoryClassifierResolutionTests {
    @Test(arguments: ["wildcard", "explicit", "alias", "default"])
    func qualifiedClassifierSurvivesSameNamedFunctions(importKind: String) throws {
        let importedPackage = importKind == "default" ? "kotlin" : "selected"
        let typeName = importKind == "alias" ? "Chosen" : "Sink"
        let importLine: String
        switch importKind {
        case "wildcard": importLine = "import selected.*"
        case "explicit": importLine = "import selected.Sink"
        case "alias": importLine = "import selected.Sink as Chosen"
        default: importLine = ""
        }
        let sources = [
            "package competing\ninterface Sink { class Nested }",
            """
            package \(importedPackage)
            interface Sink {
                class Nested
                class WithArg(val value: Int)
                companion object { fun marker(): Int = 13 }
            }
            """,
            """
            package pkg
            \(importLine)
            fun \(typeName)(): Int = 7
            fun create(): \(typeName).Nested = \(typeName).Nested()
            fun withArg(): \(typeName).WithArg = \(typeName).WithArg(42)
            fun companion(): Int = \(typeName).marker()
            fun factory(): Int = \(typeName)()
            fun localFunction(): \(typeName).Nested {
                fun \(typeName)(): Int = 8
                return \(typeName).Nested()
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let sink = try #require(sema.symbols.lookup(
                fqName: [importedPackage, "Sink"].map { ctx.interner.intern($0) }
            ))
            let memberCalls = allExprIDs(in: ast, path: paths[2], ctx: ctx) { _, expr in
                if case .memberCall = expr { return true }
                return false
            }
            #expect(memberCalls.count == 4)
            for call in memberCalls {
                guard case let .memberCall(receiver, name, _, _, _) = ast.arena.expr(call) else { continue }
                #expect(sema.bindings.identifierSymbol(for: receiver) == sink)
                let binding = try #require(sema.bindings.callBinding(for: call))
                let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
                let memberName = ctx.interner.resolve(name)
                if memberName == "marker" {
                    #expect(sema.symbols.parentSymbol(for: callee.id) == sema.symbols.companionObjectSymbol(for: sink))
                } else {
                    #expect(callee.kind == .constructor)
                    #expect(callee.fqName.map { ctx.interner.resolve($0) } == [importedPackage, "Sink", memberName, "<init>"])
                }
            }
            let factoryCall = try #require(firstExprID(in: ast, path: paths[2], ctx: ctx) { _, expr in
                if case .call = expr { return true }
                return false
            })
            let factoryBinding = try #require(sema.bindings.callBinding(for: factoryCall))
            let factory = try #require(sema.symbols.symbol(factoryBinding.chosenCallee))
            #expect(factory.kind == .function)
            #expect(factory.fqName.map { ctx.interner.resolve($0) } == ["pkg", typeName])
        }
    }

    @Test(arguments: ["parameter", "local", "property", "member", "callable"])
    func valuesStillShadowImportedClassifier(shadowKind: String) throws {
        let use: String
        switch shadowKind {
        case "parameter": use = "fun use(Sink: Value): Int = Sink.Nested()"
        case "local": use = "fun use(): Int { val Sink = Value(); return Sink.Nested() }"
        case "property": use = "val Sink = Value()\nfun use(): Int = Sink.Nested()"
        case "member": use = "class Owner(val Sink: Value) { fun use(): Int = Sink.Nested() }"
        default: use = "fun use(): Int { val Sink: () -> Int = { 5 }; return Sink.invoke() }"
        }
        let sources = [
            "package selected\ninterface Sink { class Nested }",
            """
            package pkg
            import selected.*
            fun Sink(): Int = 7
            class Value { fun Nested(): Int = 21 }
            \(use)
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: paths[1], ctx: ctx) { _, expr in
                if case .memberCall = expr { return true }
                return false
            })
            #expect(sema.bindings.exprType(for: call) == sema.types.intType)
            if shadowKind != "callable" {
                let binding = try #require(sema.bindings.callBinding(for: call))
                let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(callee.kind == .function)
                #expect(callee.fqName.map { ctx.interner.resolve($0) } == ["pkg", "Value", "Nested"])
            }
        }
    }

    @Test
    func nonCallableValueDoesNotFallBackToNestedConstructor() throws {
        let sources = [
            "package selected\ninterface Sink { class Nested }",
            """
            package pkg
            import selected.*
            fun Sink(): Int = 7
            fun use(Sink: Int) = Sink.Nested()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: paths[1], ctx: ctx) { _, expr in
                if case .memberCall = expr { return true }
                return false
            })
            #expect(sema.bindings.callBinding(for: call) == nil)
        }
    }

    @Test
    func samePackageQualifierStillShadowsWildcardImport() throws {
        let sources = [
            "package selected\ninterface Sink { class Nested }",
            """
            package pkg
            import selected.*
            interface Sink { class Nested }
            fun Sink(): Int = 7
            fun create(): Sink.Nested = Sink.Nested()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: paths[1], ctx: ctx) { _, expr in
                if case .memberCall = expr { return true }
                return false
            })
            let binding = try #require(sema.bindings.callBinding(for: call))
            let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(callee.fqName.map { ctx.interner.resolve($0) } == ["pkg", "Sink", "Nested", "<init>"])
        }
    }

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
