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

    /// KUU-3857: `Host.compExtVar = v` writes must resolve through the same
    /// companion-scope receiver reads use — for a class with no `companion
    /// object`, the `companion var` extension binds against the owner
    /// nominal itself.
    @Test
    func companionExtensionVarWritesResolveForClassWithoutCompanion() throws {
        let source = """
        class Host
        companion var Host.compExtVar: Int = 1
        fun main() {
            Host.compExtVar = 2
            Host.compExtVar += 3
            Host.compExtVar++
            Host.compExtVar -= 1
            Host.compExtVar--
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let ast = try #require(context.ast)
            let property = try #require(sema.symbols.lookup(fqName: [
                context.interner.intern("compExtVar"),
            ]))
            let writeExprs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                switch ast.arena.expr(id) {
                case .memberAssign, .memberCompoundAssign:
                    return id
                default:
                    return nil
                }
            }
            #expect(writeExprs.count == 5)
            for exprID in writeExprs {
                #expect(
                    sema.bindings.identifierSymbol(for: exprID) == property,
                    "Expected the write to bind Host.compExtVar's property symbol"
                )
            }
        }
    }

    /// KUU-3857: the same write must resolve when the class declares a
    /// source `companion object` — the qualifier denotes the companion
    /// scope, and the `companion var` extension is still the bound member.
    @Test
    func companionExtensionVarWritesResolveForClassWithCompanionObject() throws {
        let source = """
        class Host { companion object }
        companion var Host.compExtVarObj: Int = 10
        fun main() {
            Host.compExtVarObj = 20
            Host.compExtVarObj += 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    /// KUU-3857: `companion { }` block members are stored on the hidden
    /// `$CompanionBlocks` object; `Host.blockVar = v` writes must resolve
    /// through that companion scope.
    @Test
    func companionBlockVarWritesResolveThroughClassName() throws {
        let source = """
        class Host {
            companion {
                var blockVar = 0
            }
        }
        fun main() {
            Host.blockVar = 2
            Host.blockVar += 3
            Host.blockVar++
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let ast = try #require(context.ast)
            let blockObject = try #require(sema.symbols.companionBlockObjectSymbol(
                for: sema.symbols.lookup(fqName: [context.interner.intern("Host")])!,
                interner: context.interner
            ))
            let blockVar = try #require(sema.symbols.lookup(fqName: [
                context.interner.intern("Host"),
                context.interner.intern("$CompanionBlocks"),
                context.interner.intern("blockVar"),
            ]))
            #expect(sema.symbols.parentSymbol(for: blockVar) == blockObject)
            let writeExprs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                switch ast.arena.expr(id) {
                case .memberAssign, .memberCompoundAssign:
                    return id
                default:
                    return nil
                }
            }
            #expect(writeExprs.count == 3)
            for exprID in writeExprs {
                #expect(
                    sema.bindings.identifierSymbol(for: exprID) == blockVar,
                    "Expected the write to bind the $CompanionBlocks member"
                )
            }
        }
    }

    /// KUU-3857: a `companion val` still rejects assignment, and a plain
    /// (non-`companion`) `var` extension is not reachable through the class
    /// name — Kotlin reports both as unresolved.
    @Test
    func companionScopeWriteRejectsValAndNonCompanionExtensions() throws {
        let valSource = """
        class Host
        companion val Host.compExtVal: Int = 1
        fun main() { Host.compExtVal = 2 }
        """
        try withTemporaryFile(contents: valSource) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.hasError)
        }
        let plainSource = """
        class Host
        var Host.plainExtVar: Int = 1
        fun main() { Host.plainExtVar = 2 }
        """
        try withTemporaryFile(contents: plainSource) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.hasError)
        }
    }
}
#endif
