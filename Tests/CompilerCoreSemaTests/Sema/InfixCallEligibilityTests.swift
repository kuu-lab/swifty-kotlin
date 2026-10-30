@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct InfixCallEligibilityTests {
    @Test
    func infixCalleeGateAcceptsSimpleIdentifierKeywordsOnly() {
        #expect(TokenKind.keyword(.infix).isLabelName)
        #expect(!TokenKind.keyword(.as).isLabelName)
        #expect(!TokenKind.keyword(.in).isLabelName)
        #expect(!TokenKind.keyword(.is).isLabelName)
    }

    @Test
    func resolvesFunctionNamedInfixAsInfixCallee() throws {
        let source = """
        class A {
            infix fun infix(s: String): String = "O" + s
        }
        fun box(): String = A() infix "K"
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = ast.arena.snapshot().infixCallExpressions
            #expect(calls.count == 1)
            let call = try #require(calls.first)
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(call) else {
                Issue.record("Expected the soft-keyword callee to remain an infix member call")
                return
            }
            #expect(ctx.interner.resolve(callee) == "infix")
            let binding = try #require(sema.bindings.callBinding(for: call))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(ctx.interner.resolve(symbol.name) == "infix")
        }
    }

    @Test(arguments: [false, true])
    func selectsEligibleExtensionsBeforeOrdinaryMembers(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let libraryPath = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        class Token { fun select(other: Token): String = "member" }
        infix fun Token.select(other: Token): String = "extension"
        class InfixToken { infix fun select(other: InfixToken): String = "member" }
        infix fun InfixToken.select(other: InfixToken): String = "extension"
        class ExtensionToken
        infix fun ExtensionToken.select(other: ExtensionToken): String = "extension"
        fun minimal(): String = Token() select Token()
        fun explicit(): String = Token().select(Token())
        fun member(): String = InfixToken() select InfixToken()
        fun extensionOnly(): String = ExtensionToken() select ExtensionToken()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: libraryPath)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let selected = sema.bindings.callBindings.compactMap { id, binding -> (Int, String)? in
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      let symbol = sema.symbols.symbol(binding.chosenCallee),
                      ctx.interner.resolve(symbol.name) == "select"
                else { return nil }
                return (range.start.offset, symbol.fqName.map(ctx.interner.resolve).joined(separator: "."))
            }.sorted { $0.0 < $1.0 }.map { $0.1 }
            #expect(selected == ["select", "Token.select", "InfixToken.select", "select"])
        }
    }

    @Test
    func nonInfixLocalAndDispatchExtensionsDoNotHideEligibleOuterExtensions() throws {
        let source = """
        class Token { fun select(other: Token): String = "member" }
        infix fun Token.select(other: Token): String = "outer"
        fun local(): String {
            fun Token.select(other: Token): String = "local"
            return Token() select Token()
        }
        class Scope {
            fun Token.select(other: Token): String = "dispatch"
            fun sample(): String = Token() select Token()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            for id in ast.arena.snapshot().infixCallExpressions {
                let binding = try #require(sema.bindings.callBinding(for: id))
                let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["select"])
                #expect(!symbol.flags.contains(.localFunction))
            }
        }
    }

    @Test(arguments: [
        "class Other; infix fun Other.select(other: Token): String = \"wrong receiver\"",
        "infix fun Token.select(other: Int): String = \"wrong argument\"",
        "interface Allowed; infix fun <T : Allowed> Token.select(other: T): String = \"bound\""
    ])
    func rejectsInapplicableOrAmbiguousInfixExtensions(extensionDeclaration: String) throws {
        let source = """
        class Token { fun select(other: Token): String = "member" }
        \(extensionDeclaration)
        fun sample() { Token() select Token() }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(ast.arena.snapshot().infixCallExpressions.first)
            #expect(sema.bindings.exprType(for: call) == sema.types.errorType)
        }
    }

    @Test
    func ambiguousEligibleExtensionsRemainAmbiguous() throws {
        let source = """
        interface Left
        interface Right
        class Token : Left, Right { fun select(other: Token): String = "member" }
        infix fun Left.select(other: Token): String = "left"
        infix fun Right.select(other: Token): String = "right"
        fun sample() { Token() select Token() }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0003")
        }
    }

    /// KUU-3795: the statement after a call-receiver infix line
    /// (`f() op operand`) used to be merged into the infix's statement
    /// group and dropped from the function body entirely. The local was
    /// never registered, so later references cascaded into
    /// `SEMA-0022` unresolved-reference or `SEMA-0309` reports that
    /// resolved to a same-named member function. The failing initializer
    /// must leave the following local in scope and only report the
    /// primary error.
    @Test
    func localAfterCallReceiverInfixStaysInScopeThroughInitializerErrors() throws {
        let source = """
        class B {
            private fun rootSize() = 0
            fun g(): Int {
                val leafCount = rootSize() shr LOG
                val iter = leafBufferIterator(leafCount)
                return iter
            }
            private fun leafBufferIterator(index: Int): Int = index
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.contains { $0.message.contains("'LOG'") },
                    "Expected the primary unresolved-LOG diagnostic, got: \(errors)")
            #expect(!errors.contains { $0.message.contains("'iter'") },
                    "iter must stay in scope after the failing initializer, got: \(errors)")
            #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0309" },
                    "Following locals must not collapse onto member functions, got: \(errors)")
        }
    }

    /// Same KUU-3795 boundary with the following local shadowing a member
    /// function name: `val leafBufferIterator` was swallowed, so
    /// `return leafBufferIterator` fell back to the member function and
    /// produced `SEMA-0309` instead of returning the local's value.
    @Test
    func shadowingLocalAfterCallReceiverInfixDoesNotResolveToMemberFunction() throws {
        let source = """
        class B {
            private fun rootSize() = 0
            fun g(): Int {
                val leafCount = rootSize() shr LOG
                val leafBufferIterator = leafBufferIterator(1)
                return leafBufferIterator
            }
            private fun leafBufferIterator(index: Int): Int = index
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.contains { $0.message.contains("'LOG'") },
                    "Expected the primary unresolved-LOG diagnostic, got: \(errors)")
            #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0309" },
                    "leafBufferIterator must resolve to the local, not the member function, got: \(errors)")
            #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0022" && $0.message.contains("'leafBufferIterator'") },
                    "leafBufferIterator must be a visible local, got: \(errors)")
        }
    }

    @Test
    func privateInfixExtensionRemainsInaccessibleAcrossFiles() throws {
        try withTemporaryFile(contents: """
        class Token { fun select(other: Token): String = "member" }
        private infix fun Token.select(other: Token): String = "extension"
        """) { declarations in
            try withTemporaryFile(contents: "fun sample() { Token() select Token() }") { usage in
                let ctx = makeCompilationContext(inputs: [declarations, usage], includeStdlib: false)
                try runSema(ctx)
                #expect(ctx.diagnostics.hasError)
            }
        }
    }
}
