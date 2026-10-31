@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct NestedTypeAliasResolutionTests {
    private func context(_ sources: [String], includeStdlib: Bool = false) throws -> CompilationContext {
        let paths = sources.indices.map { "/nested-typealias/input\($0).kt" }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: includeStdlib)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runSema(ctx)
        return ctx
    }

    private func expectAlias(
        _ aliasPath: [String], target targetPath: [String],
        in ctx: CompilationContext, nullability: Nullability = .nonNull
    ) throws -> ClassType {
        let sema = try #require(ctx.sema)
        let alias = try #require(sema.symbols.lookup(fqName: aliasPath.map(ctx.interner.intern)))
        let underlying = try #require(sema.symbols.typeAliasUnderlyingType(for: alias))
        guard case let .classType(classType) = sema.types.kind(of: underlying) else {
            Issue.record("Expected nominal alias, got \(sema.types.kind(of: underlying))")
            throw CompilerPipelineError.invalidInput("Expected nominal alias")
        }
        #expect(sema.symbols.symbol(classType.classSymbol)?.fqName == targetPath.map(ctx.interner.intern))
        #expect(classType.nullability == nullability)
        #expect(sema.symbols.lookupAll(fqName: targetPath.map(ctx.interner.intern)).count == 1)
        return classType
    }

    @Test(arguments: [true, false])
    func aliasAndConstructorResolveRegardlessOfDeclarationOrder(aliasFirst: Bool) throws {
        let owner = "class Outer { class Nested { fun f(): String = \"n\" } }"
        let alias = "typealias Alias = Outer.Nested"
        let source = (aliasFirst ? [alias, owner] : [owner, alias]).joined(separator: "\n")
            + "\nfun result(): String = Alias().f()"
        let ctx = try context([source])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        _ = try expectAlias(["Alias"], target: ["Outer", "Nested"], in: ctx)
    }

    @Test(arguments: [true, false])
    func importedNestedTypesResolveAcrossFiles(ownerFirst: Bool) throws {
        let owner = """
        package model
        class Outer { class Middle { class Nested<T>(val value: T) } }
        """
        let user = """
        package user
        import model.Outer as Renamed
        typealias Alias<T> = Renamed.Middle.Nested<T>
        typealias Nullable = model.Outer.Middle.Nested<String>?
        fun make(): Alias<String> = Alias("n")
        fun nullable(x: Nullable): Nullable = x
        """
        let ctx = try context(ownerFirst ? [owner, user] : [user, owner])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let generic = try expectAlias(["user", "Alias"], target: ["model", "Outer", "Middle", "Nested"], in: ctx)
        #expect(generic.args.count == 1)
        _ = try expectAlias(["user", "Nullable"], target: ["model", "Outer", "Middle", "Nested"], in: ctx, nullability: .nullable)
    }

    @Test(arguments: ["import model.Outer", "import model.*", ""])
    func packageAndImportQualificationResolve(importLine: String) throws {
        let owner = "package model; class Outer { class Nested }"
        let package = importLine.isEmpty ? "model" : "user"
        let ctx = try context([
            "package \(package)\n\(importLine)\ntypealias Alias = Outer.Nested\nfun make(): Alias = Alias()",
            owner,
        ])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        _ = try expectAlias([package, "Alias"], target: ["model", "Outer", "Nested"], in: ctx)
    }

    @Test func interfaceObjectEnumAndCompanionOwnersResolve() throws {
        let ctx = try context(["""
        typealias InInterface = Holder.Nested
        typealias InObject = Singleton.Nested
        typealias NestedObject = Singleton.Item
        typealias InEnum = Choice.Nested
        typealias InCompanion = Outer.Companion.Nested
        typealias InNamedCompanion = Named.Factory.Nested
        interface Holder { class Nested }
        object Singleton { class Nested; object Item }
        enum class Choice { ONLY; class Nested }
        class Outer { companion object { class Nested } }
        class Named { companion object Factory { class Nested } }
        """], includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        for (alias, target) in [
            ("InInterface", ["Holder", "Nested"]),
            ("InObject", ["Singleton", "Nested"]),
            ("NestedObject", ["Singleton", "Item"]),
            ("InEnum", ["Choice", "Nested"]),
            ("InCompanion", ["Outer", "Companion", "Nested"]),
            ("InNamedCompanion", ["Named", "Factory", "Nested"]),
        ] {
            _ = try expectAlias([alias], target: target, in: ctx)
        }
    }

    @Test func missingQualifierDoesNotBindSameShortName() throws {
        let ctx = try context(["""
        class Other { class Nested }
        class Outer
        typealias Alias = Outer.Nested
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })
    }

    @Test func duplicateNestedDeclarationsRemainErrors() throws {
        let ctx = try context(["class Outer { class Nested; class Nested }"])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
    }

    @Test func nestedConstructorsDoNotLeakIntoFileScope() throws {
        let ctx = try context(["""
        class Outer { class Nested }
        fun wrong() = Nested()
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    // MARK: - Member-declared and function-local typealiases (KUU-3840)

    @Test func memberTypeAliasResolvesInClassBody() throws {
        let ctx = try context(["""
        class Local2<T>(val p: T)
        open class Local {
            typealias LocalTAtoLocal = Local
            typealias LocalTAtoLocal2<K> = Local2<K>
            fun test() = LocalTAtoLocal2("OK").p
        }
        fun main() = Local().test()
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        _ = try expectAlias(["Local", "LocalTAtoLocal"], target: ["Local"], in: ctx)
        let generic = try expectAlias(["Local", "LocalTAtoLocal2"], target: ["Local2"], in: ctx)
        #expect(generic.args.count == 1)
    }

    @Test func memberTypeAliasSupportsQualifiedConstructorAndTypePositions() throws {
        let ctx = try context(["""
        class Local2<T>(val p: T)
        open class Local {
            typealias LocalTAtoLocal = Local
            typealias LocalTAtoLocal2<K> = Local2<K>
        }
        val x: Local.LocalTAtoLocal = Local.LocalTAtoLocal()
        val y: Local.LocalTAtoLocal2<Int> = Local.LocalTAtoLocal2(1)
        """])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        _ = try expectAlias(["Local", "LocalTAtoLocal2"], target: ["Local2"], in: ctx)
    }

    @Test func functionLocalTypeAliasResolvesInBody() throws {
        let ctx = try context(["""
        open class Local { fun test() = "OK" }
        fun main() {
            typealias TAtoLocal = Local
            println(TAtoLocal().test())
        }
        """], includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func typeAliasInsideLocalClassResolvesThroughMemberScope() throws {
        let ctx = try context(["""
        fun f(): String {
            class Local2<T>(val p: T)
            open class Local {
                typealias LocalTAtoLocal = Local
                typealias LocalTAtoLocal2<K> = Local2<K>
                fun test() = LocalTAtoLocal2("OK").p
            }
            typealias TAtoLocal = Local
            val qualified: Local.LocalTAtoLocal = Local.LocalTAtoLocal()
            return Local().test() + qualified.test() + TAtoLocal().test()
        }
        """], includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func localTypeAliasToInnerClassConstructsWithReceiver() throws {
        let ctx = try context(["""
        open class Generic<K>(val k: K) {
            inner class Inner<K2>(val k2: K2)
        }
        fun f(): String {
            typealias TAtoInner<K, L> = Generic<K>.Inner<L>
            val genericObj = Generic<Int>(42)
            return genericObj.TAtoInner<Int, String>("OK").k2
        }
        """], includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func qualifiedInnerAliasStillRequiresContainingReceiver() throws {
        let ctx = try context(["""
        class Outer {
            inner class Inner(val x: Int)
            typealias TAtoInner = Inner
        }
        fun bad() = Outer.TAtoInner(1)
        """])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0437" })
    }

    @Test func localTypeAliasCallableReferenceResolves() throws {
        let ctx = try context(["""
        open class Local { fun test() = "OK" }
        fun f(): String {
            typealias TAtoLocal = Local
            val callable = ::TAtoLocal
            return callable().test()
        }
        """], includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
