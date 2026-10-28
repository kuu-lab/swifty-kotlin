@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct InfixCallModifierTests {
    @Test(arguments: [false, true])
    func rejectsNonInfixFunctionsAfterResolution(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let libraryPath = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        class N(val v: Int) { fun add(o: N) = N(v + o.v) }
        fun Int.join(other: Int): Int = this + other
        fun join(a: Int, b: Int): Int = a + b
        fun rejected() {
            N(2) add N(3)
            2 join 3
            setOf(1) plus 2
            2 plus 3
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: libraryPath)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 4, "Unexpected diagnostics: \(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0307" })
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for id in ast.arena.snapshot().infixCallExpressions {
                guard ctx.sourceManager.path(of: try #require(ast.arena.exprRange(id)).start.file) == path else { continue }
                #expect(sema.bindings.exprType(for: id) == sema.types.errorType)
            }
        }
    }

    @Test(arguments: [false, true])
    func acceptsInfixDeclarationsOverridesAndOrdinaryCalls(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let libraryPath = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        open class Base { open infix fun add(n: Int): Int = n }
        class Derived : Base() { override fun add(n: Int): Int = n + 1 }
        class N { fun add(n: Int): Int = n }
        infix fun Int.join(other: Int): Int = this + other
        fun accepted() {
            Derived() add 2
            2 join 3
            N().add(3)
            setOf(1).plus(2)
            2.plus(3)
            1 and 2
            1 shl 2
            1u xor 2u
            true and false
            val anonymous = object : Base() { override fun add(n: Int): Int = n }
            anonymous add 2
            1 to 2
            setOf(1) union setOf(2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: libraryPath)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let data = try JSONEncoder().encode(ast.arena.snapshot())
            let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: data))
            #expect(restored.snapshot().infixCallExpressions == ast.arena.snapshot().infixCallExpressions)
        }
    }

    @Test
    func unsignedPrimitiveCompareToAllowsInfixAndOrdinaryCalls() throws {
        let source = """
        infix fun UInt.sameAs(other: UInt): Boolean = this == other
        fun accepted(ui: UInt, ul: ULong) {
            ui compareTo 1u
            ul compareTo 1uL
            ui compareTo ul
            ul compareTo ui
            ui.compareTo(1u)
            ul.compareTo(1uL)
            ui sameAs 1u
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let infixCalls = ast.arena.snapshot().infixCallExpressions.filter {
                guard let range = ast.arena.exprRange($0) else { return false }
                return ctx.sourceManager.path(of: range.start.file) == path
            }
            #expect(infixCalls.count == 5)
            for id in infixCalls {
                guard case let .memberCall(receiverID, calleeName, _, _, _) = ast.arena.expr(id),
                      ctx.interner.resolve(calleeName) == "compareTo"
                else { continue }
                let receiverType = sema.bindings.exprType(for: receiverID)
                #expect(
                    receiverType == sema.types.uintType || receiverType == sema.types.ulongType,
                    "Unexpected infix compareTo receiver type: \(receiverType.map { sema.types.kind(of: $0) } as Any)"
                )
                #expect(sema.bindings.exprType(for: id) == sema.types.intType)
            }
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(diagnosticsForPath(path, in: ctx))")
        }
    }

    @Test
    func primitiveCompareToInfixEligibilityRemainsNarrow() throws {
        let source = """
        fun rejected(value: Int, small: UByte, ui: UInt, ul: ULong) {
            value compareTo 1
            small compareTo 1.toUByte()
            ui compareTo "not unsigned"
            ui.compareTo("not unsigned")
            ul compareTo "not unsigned"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 5, "Unexpected diagnostics: \(errors)")
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 2)
            #expect(errors.filter { $0.code != "KSWIFTK-SEMA-0307" }.count == 3)
        }
    }

    @Test
    func topLevelFunctionsRemainRejected() throws {
        let source = """
        fun join(a: Int, b: Int): Int = a + b
        fun rejected() { 2 join 3 }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test
    func softKeywordNamedFunctionStillRequiresInfixModifier() throws {
        let source = """
        class A { fun infix(s: String): String = s }
        fun rejected() { A() infix "K" }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0307")
        }
    }

    @Test
    func memberExtensionsRequireInfix() throws {
        let source = """
        class Scope {
            fun Int.combine(n: Int): Int = this + n
            infix fun Int.merge(n: Int): Int = this + n
            fun sample() {
                1 combine 2
                1 merge 2
                1.combine(2)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0307")
        }
    }

    @Test
    func localExtensionsPreserveInfixModifier() throws {
        let source = """
        fun sample() {
            infix fun Int.merge(n: Int): Int = this + n
            fun Int.combine(n: Int): Int = this + n
            1 merge 2
            1 combine 2
            1.combine(2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0307")
        }
    }

    @Test
    func anonymousOverridesInheritOnlyFromMatchingOverloads() throws {
        let source = """
        open class Base {
            open infix fun add(n: Int): Int = n
            open fun add(n: String): String = n
        }
        fun sample() {
            val anonymous = object : Base() {
                override fun add(n: Int): Int = n
                override fun add(n: String): String = n
            }
            anonymous add 2
            anonymous add "text"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0002")
        }
    }

    @Test
    func excludesNonInfixOverloadsBeforeApplicability() throws {
        let source = """
        class N {
            infix fun add(n: Int): Int = n
            fun add(n: String): String = n
        }
        fun accepted(n: N) { n add 1 }
        fun rejected(n: N) { n add "text" }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1)
            #expect(errors.first?.code == "KSWIFTK-SEMA-0002")
        }
    }
}
