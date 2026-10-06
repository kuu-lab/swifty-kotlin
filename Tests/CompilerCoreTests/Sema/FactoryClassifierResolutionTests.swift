@testable import CompilerCore
import Testing

@Suite
struct FactoryClassifierResolutionTests {
    @Test(arguments: ["wildcard", "explicit"], [(false, false), (false, true), (true, false), (true, true)])
    func importedTypeAnnotationsIgnorePackageFactoryOrder(
        importKind: String, placement: (factoryFirst: Bool, separateFile: Bool)
    ) throws {
        let (factoryFirst, separateFile) = placement
        let importLine = importKind == "wildcard" ? "import lib.*" : "import lib.Thing\nimport lib.Impl"
        let factory = "public fun Thing(x: Int = 0): Impl = Impl()"
        let uses = """
        public fun useType(t: Thing) {}
        public fun Thing.ext() {}
        public fun makeIt(): Thing = Thing()
        """
        let header = "package app\n\(importLine)\n"
        let declarations = "package lib\npublic interface Thing\npublic class Impl : Thing"
        let ordered = factoryFirst ? [factory, uses] : [uses, factory]
        let sources = separateFile
            ? [declarations] + ordered.map { header + $0 }
            : [declarations, header + ordered.joined(separator: "\n")]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let thing = try #require(sema.symbols.lookup(
                fqName: ["lib", "Thing"].map(ctx.interner.intern)
            ))
            for name in ["useType", "ext", "makeIt"] {
                let function = try #require(sema.symbols.lookup(
                    fqName: ["app", name].map(ctx.interner.intern)
                ))
                let signature = try #require(sema.symbols.functionSignature(for: function))
                let type: TypeID
                switch name {
                case "useType": type = try #require(signature.parameterTypes.first)
                case "ext": type = try #require(signature.receiverType)
                default: type = signature.returnType
                }
                guard case let .classType(nominal) = sema.types.kind(of: type) else {
                    Issue.record("Expected imported Thing in \(name)")
                    continue
                }
                #expect(nominal.classSymbol == thing)
            }
            let ast = try #require(ctx.ast)
            let usesPath = paths[separateFile && factoryFirst ? 2 : 1]
            let call = try #require(firstExprID(in: ast, path: usesPath, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee) else { return false }
                return name == ctx.interner.intern("Thing")
            })
            let binding = try #require(sema.bindings.callBinding(for: call))
            let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(callee.kind == .function)
            #expect(callee.fqName == ["app", "Thing"].map(ctx.interner.intern))
        }
    }

    @Test(arguments: [false, true])
    func sameNamedFactoryDoesNotMakeInstanceMembersStatic(factoryFirst: Bool) throws {
        let classifier = "class Foo(val x: Int) { fun tag() = x }"
        let factory = "fun Foo() = 0"
        let declarations = factoryFirst ? factory + "\n" + classifier : classifier + "\n" + factory
        try withTemporaryFile(contents: "package dup\n" + declarations + "\nfun invalid() = dup.Foo.tag()") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

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

    @Test(arguments: ["wildcard", "explicit"])
    func importedClassifierResolvesAcrossAllTypePositions(importKind: String) throws {
        let importLine = importKind == "wildcard"
            ? "import lib.*"
            : "import lib.Thing\nimport lib.Impl\nimport lib.Box"
        let sources = [
            """
            package lib
            public interface Thing
            public class Impl : Thing
            public class Box<T>(val value: T)
            """,
            """
            package app
            \(importLine)

            public fun Thing(x: Int = 0): Impl = Impl()
            public fun f1(t: Thing?) {}
            public fun f2(t: Box<Thing>) {}
            public fun f3(cb: (Thing) -> Unit) {}
            public fun <T : Thing> f4(t: T) {}
            public fun f5(t: Thing = Thing()) {}
            public typealias Alias = Thing
            public fun f6(a: Alias) {}
            public class Sub : Thing
            public object Obj : Thing
            public fun f7(x: Any): Thing? = if (x is Thing) x else null
            public fun f8(x: Any): Thing = x as Thing
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let thing = try #require(sema.symbols.lookup(
                fqName: ["lib", "Thing"].map(ctx.interner.intern)
            ))
            let box = try #require(sema.symbols.lookup(
                fqName: ["lib", "Box"].map(ctx.interner.intern)
            ))
            func signature(of name: String) throws -> FunctionSignature {
                let function = try #require(sema.symbols.lookup(
                    fqName: ["app", name].map(ctx.interner.intern)
                ))
                return try #require(sema.symbols.functionSignature(for: function))
            }
            func expectThing(_ type: TypeID, _ label: String) {
                guard case let .classType(nominal) = sema.types.kind(of: type) else {
                    Issue.record("Expected imported Thing in \(label)")
                    return
                }
                #expect(nominal.classSymbol == thing)
            }
            expectThing(try signature(of: "f1").parameterTypes[0], "f1")
            guard case let .classType(boxNominal) = sema.types.kind(
                of: try signature(of: "f2").parameterTypes[0]
            ), boxNominal.classSymbol == box, case let .invariant(boxArg) = boxNominal.args.first else {
                Issue.record("Expected Box<Thing> in f2")
                return
            }
            expectThing(boxArg, "f2 Box<T> argument")
            guard case let .functionType(functionType) = sema.types.kind(
                of: try signature(of: "f3").parameterTypes[0]
            ), let functionParam = functionType.params.first else {
                Issue.record("Expected (Thing) -> Unit in f3")
                return
            }
            expectThing(functionParam, "f3 function type parameter")
            expectThing(
                try #require(try signature(of: "f4").typeParameterUpperBounds.first ?? nil),
                "f4 type parameter bound"
            )
            expectThing(try signature(of: "f5").parameterTypes[0], "f5")
            expectThing(try signature(of: "f6").parameterTypes[0], "f6 typealias")
            for name in ["Sub", "Obj"] {
                let nominal = try #require(sema.symbols.lookup(
                    fqName: ["app", name].map(ctx.interner.intern)
                ))
                #expect(
                    sema.symbols.directSupertypes(for: nominal).contains(thing),
                    "Expected lib.Thing supertype on \(name)"
                )
            }
        }
    }

    @Test(arguments: ["wildcard", "explicit"])
    func sameNamedPackagePropertyDoesNotShadowImportedClassifier(importKind: String) throws {
        let importLine = importKind == "wildcard" ? "import lib.*" : "import lib.Thing\nimport lib.Impl"
        let sources = [
            """
            package lib
            public interface Thing
            public class Impl : Thing
            """,
            """
            package app
            \(importLine)

            public val Thing: Impl get() = Impl()
            public fun useType(t: Thing) {}
            public fun Thing.ext() {}
            public fun makeIt(): Thing = Thing
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let thing = try #require(sema.symbols.lookup(
                fqName: ["lib", "Thing"].map(ctx.interner.intern)
            ))
            for name in ["useType", "ext", "makeIt"] {
                let function = try #require(sema.symbols.lookup(
                    fqName: ["app", name].map(ctx.interner.intern)
                ))
                let signature = try #require(sema.symbols.functionSignature(for: function))
                let type: TypeID
                switch name {
                case "useType": type = try #require(signature.parameterTypes.first)
                case "ext": type = try #require(signature.receiverType)
                default: type = signature.returnType
                }
                guard case let .classType(nominal) = sema.types.kind(of: type) else {
                    Issue.record("Expected imported Thing in \(name)")
                    continue
                }
                #expect(nominal.classSymbol == thing)
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
