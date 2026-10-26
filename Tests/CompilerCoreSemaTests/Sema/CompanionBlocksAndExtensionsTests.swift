#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct CompanionBlocksAndExtensionsTests {
    @Test
    func companionBlockMembersResolveThroughClassNameWithoutCreatingCompanionObject() throws {
        let source = """
        class Host {
            companion {
                val greeting = "hello"
                fun greet(name: String) = greeting + name
            }
        }
        fun result() = Host.greet("!") + Host.greeting
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let host = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Host")]))
            #expect(sema.symbols.companionObjectSymbol(for: host) == nil)
            let block = try #require(sema.symbols.companionBlockObjectSymbol(for: host, interner: context.interner))
            let blockName = try #require(sema.symbols.symbol(block)).fqName
            #expect(sema.symbols.lookup(fqName: blockName + [context.interner.intern("greeting")]) != nil)
            #expect(sema.symbols.lookup(fqName: blockName + [context.interner.intern("greet")]) != nil)
            #expect(sema.symbols.lookup(fqName: [
                context.interner.intern("Host"), context.interner.intern("Companion"),
            ]) == nil)
        }
    }

    @Test
    func companionExtensionCanResolveBlockMembers() throws {
        let source = """
        class Host {
            companion {
                val suffix = "!"
                fun prefix() = "hello"
            }
        }
        companion fun Host.greet() = prefix() + suffix
        companion val Host.composed: String get() = prefix() + suffix
        fun result() = Host.greet() + Host.composed
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func companionExtensionsResolveForClassWithoutCompanionObject() throws {
        let source = """
        class Host
        companion val Host.greeting = "hello"
        companion fun Host.greet(name: String = "!") = greeting + name
        fun result() = Host.greet() + Host.greeting
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func companionModifierStillRequiresAFileScopeExtension() throws {
        let source = """
        companion fun notAnExtension() = "invalid"
        class Host {
            companion fun memberFunction() = "invalid"
            companion val memberProperty = "invalid"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.hasError)
            #expect(context.diagnostics.diagnostics.filter { $0.message.contains("modifier 'companion'") }.count == 3)
        }
    }

    @Test
    func companionBlockInvokeIsCallableThroughTheClassName() throws {
        let source = """
        class Callable {
            companion {
                operator fun invoke(value: String) = value
            }
        }
        fun result() = Callable("OK")
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let ast = try #require(context.ast)
            let call = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      context.interner.resolve(name) == "Callable"
                else {
                    return nil
                }
                return id
            }.last)
            let binding = try #require(sema.bindings.callBinding(for: call))
            let owner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
            #expect(context.interner.resolve(try #require(sema.symbols.symbol(owner)).name) == "$CompanionBlocks")
            #expect(sema.bindings.isInvokeOperatorCall(call))
        }
    }

    @Test
    func companionExtensionInvokeIsCallableThroughTheClassName() throws {
        let source = """
        class Callable
        companion operator fun Callable.invoke(value: String) = value
        fun result() = Callable("OK")
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            let ast = try #require(context.ast)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let call = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      context.interner.resolve(name) == "Callable"
                else {
                    return nil
                }
                return id
            }.last)
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.operatorFunction) == true)
            #expect(sema.bindings.isInvokeOperatorCall(call))
        }
    }

    @Test
    func companionBlockAndExtensionCallableReferencesBindToClassNames() throws {
        let source = """
        class BlockTarget {
            companion {
                fun value() = "block"
                val text = "block property"
            }
        }
        class ExtensionTarget
        companion fun ExtensionTarget.value() = "extension"

        companion val ExtensionTarget.text = "extension property"
        inline fun consume(value: () -> String) = value()
        fun result() = consume(BlockTarget::value) + consume(ExtensionTarget::value) + consume(BlockTarget::text) + consume(ExtensionTarget::text)
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func companionBlocksCoexistWithSourceCompanionAndMultipleBlocks() throws {
        let source = """
        class Host {
            companion {
                fun selected() = first()
            }
            companion object {
                fun selected() = 1
                fun objectOnly() = "companion"
            }
            companion {
                fun first() = "block"
            }
            fun selectedFromClassBody(): String = selected()
        }
        fun result(): String = Host.selected() + Host.Companion.objectOnly()
        fun sourceCompanionResult(): Int = Host.Companion.selected()
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func companionBlockMembersFollowClassInheritance() throws {
        let source = """
        open class Base {
            companion {
                fun foo() = "parent"
                fun bar() = "bar"
                fun baz() = "baz"
            }
        }
        class Derived : Base() {
            fun fromParentBlock() = baz() + " called"
            companion {
                fun foo() = "child"
                fun fromParentBlock() = bar() + " called"
            }
        }
        fun result() = Derived.foo() + Derived.fromParentBlock() + Derived().fromParentBlock()
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func shadowedCompanionCallableReferencesStayBoundAfterOverloadReinference() throws {
        // KUU-3820: `Type::member` references are re-inferred per overload
        // candidate. A first, expected-type-less pass binds the instance
        // member as an unbound `(C, Int) -> Unit` reference; the winning
        // overload then re-binds the shadowed companion member as a bound
        // reference. The stale unbound mark must be cleared, or KIR lowering
        // drops the captured receiver and the call crashes at runtime.
        let source = """
        class C {
            fun baz(x: Int) {}
            fun fooExt(x: Int) {}
            companion {
                fun baz(s: String) = s
            }
        }
        companion fun C.fooExt(s: String) = s
        inline fun consume(value: (String) -> String) = value("OK")
        inline fun consume(value: () -> String) = "none"
        fun result() = consume(C::baz) + consume(C::fooExt)
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let ast = try #require(context.ast)
            let interner = context.interner
            var boundTargets: [String: SymbolID] = [:]
            var checked = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard case let .callableRef(_, member, _) = ast.arena.expr(id) else {
                    continue
                }
                let name = interner.resolve(member)
                #expect(
                    !sema.bindings.isUnboundCallableRef(id),
                    "\(name) must stay bound after overload re-inference"
                )
                boundTargets[name] = sema.bindings.identifierSymbol(for: id)
                checked += 1
            }
            #expect(checked == 2)
            let baz = try #require(boundTargets["baz"])
            let bazParentName = sema.symbols.parentSymbol(for: baz)
                .flatMap { sema.symbols.symbol($0)?.name }
                .map { interner.resolve($0) }
            #expect(bazParentName == "$CompanionBlocks")
            let fooExt = try #require(boundTargets["fooExt"])
            let signature = try #require(sema.symbols.functionSignature(for: fooExt))
            // The bound companion extension `fooExt(String)` — not the
            // shadowing instance member `fooExt(Int)` — wins the overload.
            #expect(signature.parameterTypes == [sema.types.stringType])
        }
    }

    @Test
    func innerClassMayDeclareCompanionBlockAndSeeOuterBlockMembers() throws {
        let source = """
        class Outer {
            companion {
                val outerValue = "outer"
                fun outerFunction() = "function"
            }
            inner class Inner {
                companion {
                    val innerValue = "inner"
                }
                fun result() = outerValue + outerFunction() + innerValue
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
#endif
