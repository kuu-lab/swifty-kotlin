#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct AnonymousObjectFinalInheritanceTests {

    private func compile(_ source: String, usesLibraryArtifact: Bool = false) throws -> CompilationContext {
        if usesLibraryArtifact {
            TestStdlibCache.shared.prepare()
        }

        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let libraryPath: String?
            if usesLibraryArtifact {
                guard let path = CompilerOptions.defaultStdlibLibraryPath else {
                    throw CompilerPipelineError.invalidInput("Expected TestStdlibCache to prepare a .kklib")
                }
                libraryPath = path
            } else {
                libraryPath = nil
            }
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: usesLibraryArtifact ? .executable : .kirDump,
                stdlibLibraryPath: libraryPath,
                allowDefaultStdlibLibrary: usesLibraryArtifact
            )
            try runSema(ctx)
            result = ctx
        }
        return try #require(result)
    }

    @Test
    func namedAndAnonymousGenericTypeAliasInheritancesKeepFinalDiagnostics() throws {
        let ctx = try compile("""
        class FinalBase<T>
        typealias FinalAlias<T> = FinalBase<T>

        class Named : FinalAlias<String>()
        fun anonymous() = object : FinalAlias<String>() {}
        """)

        let finalDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-FINAL"
        }
        #expect(
            finalDiagnostics.count == 2,
            "Expected the named-class and anonymous-object checks, got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            finalDiagnostics.allSatisfy {
                $0.message == "Cannot inherit from final class 'FinalBase'. Mark it as 'open' to allow subclassing."
            }
        )
    }

    @Test
    func directAnonymousObjectCannotInheritFinalClass() throws {
        let ctx = try compile("""
        class A
        fun directAnonymous() = object : A() {}
        """)

        let finalDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-FINAL"
        }
        #expect(
            finalDiagnostics.count == 1,
            "Expected the direct object-literal reproduction to be rejected, got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            finalDiagnostics.first?.message
                == "Cannot inherit from final class 'A'. Mark it as 'open' to allow subclassing."
        )
    }

    @Test
    func namedAndAnonymousDataClassInheritancesAreRejected() throws {
        let ctx = try compile("""
        data class DataBase(val value: Int)

        class Named : DataBase(1)
        fun anonymous() = object : DataBase(2) {}
        """)

        let dataDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-DATA-INHERIT"
        }
        #expect(
            dataDiagnostics.count == 2,
            "Expected the named-class and anonymous-object checks, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func objectLiteralsAllowOpenAbstractInterfaceAndAnySupertypes() throws {
        let ctx = try compile("""
        open class OpenBase<T>
        typealias OpenAlias<T> = OpenBase<T>
        abstract class AbstractBase {
            fun implemented(): Int = 1
        }
        interface Contract

        fun allowed() {
            val open = object : OpenAlias<String>() {}
            val abstract = object : AbstractBase() {}
            val contract = object : Contract {}
            val any = object : Any() {}
        }
        """)

        #expect(
            !ctx.diagnostics.hasError,
            "Unexpected diagnostics for subclassable supertypes: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func objectLiteralStillRejectsMultipleConcreteClassSupertypes() throws {
        let ctx = try compile("""
        open class FirstBase
        open class SecondBase

        fun invalid() = object : FirstBase(), SecondBase() {}
        """)

        let multipleClassDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0170"
        }
        #expect(
            multipleClassDiagnostics.count == 1,
            "Expected the existing multiple-class diagnostic, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test(arguments: [false, true])
    func bundledFinalDeepRecursiveFunctionIsRejectedInBothStdlibModes(usesLibraryArtifact: Bool) throws {
        let ctx = try compile(
            """
            fun illegal() =
                object : kotlin.DeepRecursiveFunction<Int, Int>({ n -> n * 2 }) {}
            """,
            usesLibraryArtifact: usesLibraryArtifact
        )

        let finalDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-FINAL"
        }
        #expect(
            finalDiagnostics.count == 1,
            "Expected KSWIFTK-SEMA-FINAL with stdlib artifact=\(usesLibraryArtifact), got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            finalDiagnostics.first?.message
                == "Cannot inherit from final class 'kotlin.DeepRecursiveFunction'. Mark it as 'open' to allow subclassing."
        )
    }
}
#endif
