@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

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
            #expect(errors.first?.code == "KSWIFTK-SEMA-0307")
        }
    }

    @Test
    func checksChosenOverloadRatherThanName() throws {
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
            #expect(errors.first?.code == "KSWIFTK-SEMA-0307")
        }
    }
}
