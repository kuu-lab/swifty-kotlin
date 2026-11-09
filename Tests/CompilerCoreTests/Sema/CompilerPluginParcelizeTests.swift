#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// Built-in compiler plugins (`org.jetbrains.kotlin.parcelize`):
/// The Parcelize plugin synthesizes `describeContents(): Int` and
/// `writeToParcel(dest: Parcel, flags: Int): Unit` on `@Parcelize` classes
/// that implement `android.os.Parcelable`.
@Suite
struct CompilerPluginParcelizeTests {

    private let parcelableStubSource = """
    package android.os

    interface Parcelable
    class Parcel
    """

    private let parcelizeStubSource = """
    package kotlinx.parcelize

    annotation class Parcelize
    """

    private let validParcelizeSource = """
    package com.example

    import android.os.Parcelable
    import android.os.Parcel
    import kotlinx.parcelize.Parcelize

    @Parcelize
    class User(val name: String, val age: Int) : Parcelable
    """

    private func findMethodSymbols(
        named name: String,
        className: String = "User",
        in ctx: CompilationContext
    ) throws -> [SymbolID] {
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let classFQName = [
            interner.intern("com"), interner.intern("example"), interner.intern(className),
        ]
        guard let classSymbol = sema.symbols.lookup(fqName: classFQName) else {
            return []
        }
        let targetName = interner.intern(name)
        return sema.symbols.lookupAll(fqName: classFQName + [targetName]).filter {
            sema.symbols.parentSymbol(for: $0) == classSymbol
                && sema.symbols.symbol($0)?.kind == .function
        }
    }

    @Test
    func testGeneratesDescribeContentsAndWriteToParcel() throws {
        try withTemporaryFiles(contents: [parcelableStubSource, parcelizeStubSource, validParcelizeSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "parcelize plugin must not produce errors for valid @Parcelize: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let descMethods = try findMethodSymbols(named: "describeContents", in: ctx)
            #expect(descMethods.count == 1, "expected exactly one describeContents method")

            let writeMethods = try findMethodSymbols(named: "writeToParcel", in: ctx)
            #expect(writeMethods.count == 1, "expected exactly one writeToParcel method")

            let sema = try #require(ctx.sema)
            let descSig = try #require(sema.symbols.functionSignature(for: descMethods[0]))
            #expect(descSig.parameterTypes.isEmpty)
            #expect(descSig.returnType == sema.types.intType)

            let writeSig = try #require(sema.symbols.functionSignature(for: writeMethods[0]))
            #expect(writeSig.parameterTypes.count == 2)
            #expect(writeSig.returnType == sema.types.unitType)
        }
    }

    @Test
    func testGeneratedMethodsReachKIR() throws {
        try withTemporaryFiles(contents: [parcelableStubSource, parcelizeStubSource, validParcelizeSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runToKIR(ctx)
            let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "KIR lowering must succeed: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let kir = try #require(ctx.kir)
            let descMethods = try findMethodSymbols(named: "describeContents", in: ctx)
            #expect(descMethods.count == 1)
            let descFunc = try #require(kir.arena.function(for: descMethods[0]))
            // describeContents returns 0
            let hasZeroConst = descFunc.body.contains { instr in
                if case let .constValue(_, val) = instr, val == .intLiteral(0) {
                    return true
                }
                return false
            }
            #expect(hasZeroConst, "describeContents must emit constValue 0")

            let writeMethods = try findMethodSymbols(named: "writeToParcel", in: ctx)
            #expect(writeMethods.count == 1)
            let writeFunc = try #require(kir.arena.function(for: writeMethods[0]))
            #expect(writeFunc.body.contains { $0 == .returnUnit }, "writeToParcel must emit returnUnit")
        }
    }

    @Test
    func testWithoutAnnotationNoSyntheticMethods() throws {
        let plainSource = """
        package com.example

        import android.os.Parcelable

        class User(val name: String, val age: Int) : Parcelable
        """
        try withTemporaryFiles(contents: [parcelableStubSource, plainSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let descMethods = try findMethodSymbols(named: "describeContents", in: ctx)
            #expect(descMethods.isEmpty)
            let writeMethods = try findMethodSymbols(named: "writeToParcel", in: ctx)
            #expect(writeMethods.isEmpty)
        }
    }

    @Test
    func testMissingParcelableSupertypeErrors() throws {
        let missingSuperSource = """
        package com.example

        import kotlinx.parcelize.Parcelize

        @Parcelize
        class User(val name: String, val age: Int)
        """
        try withTemporaryFiles(contents: [parcelizeStubSource, missingSuperSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0484" },
                "expected KSWIFTK-SEMA-0484 for missing Parcelable supertype, got: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }

    @Test
    func testUnsupportedKindErrors() throws {
        let invalidKindSource = """
        package com.example

        import android.os.Parcelable
        import kotlinx.parcelize.Parcelize

        @Parcelize
        interface Foo : Parcelable

        @Parcelize
        enum class Bar : Parcelable { A, B }
        """
        try withTemporaryFiles(contents: [parcelableStubSource, parcelizeStubSource, invalidKindSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
            let kindErrors = errors.filter { $0.code == "KSWIFTK-SEMA-0485" }
            #expect(kindErrors.count >= 2, "expected KSWIFTK-SEMA-0485 for non-class declarations, got: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")
        }
    }

    @Test
    func testInnerClassErrors() throws {
        let innerSource = """
        package com.example

        import android.os.Parcelable
        import kotlinx.parcelize.Parcelize

        class Outer {
            @Parcelize
            inner class InnerUser(val x: Int) : Parcelable
        }
        """
        try withTemporaryFiles(contents: [parcelableStubSource, parcelizeStubSource, innerSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.contains { $0.code == "KSWIFTK-SEMA-0486" },
                "expected KSWIFTK-SEMA-0486 for inner class, got: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }

    @Test
    func testUserDeclaredMethodSkipped() throws {
        let userDeclaredSource = """
        package com.example

        import android.os.Parcelable
        import android.os.Parcel
        import kotlinx.parcelize.Parcelize

        @Parcelize
        class User(val name: String) : Parcelable {
            fun describeContents(): Int = 42
        }
        """
        try withTemporaryFiles(contents: [parcelableStubSource, parcelizeStubSource, userDeclaredSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "errors: \(errors.map { "\($0.code): \($0.message)" }.joined(separator: " | "))")

            let descMethods = try findMethodSymbols(named: "describeContents", in: ctx)
            #expect(descMethods.count == 1)
            let sema = try #require(ctx.sema)
            // The method should be the user-declared one, not synthetic
            #expect(!sema.symbols.symbol(descMethods[0])!.flags.contains(.synthetic))

            // writeToParcel should still be synthesized
            let writeMethods = try findMethodSymbols(named: "writeToParcel", in: ctx)
            #expect(writeMethods.count == 1)
            #expect(sema.symbols.symbol(writeMethods[0])!.flags.contains(.synthetic))
        }
    }

    @Test
    func testAdditionalAnnotationConfig() throws {
        let customSource = """
        package com.example

        import android.os.Parcelable

        annotation class MyCustomParcelize

        @MyCustomParcelize
        class CustomUser(val id: Int) : Parcelable
        """
        let customFlag = "plugin:org.jetbrains.kotlin.parcelize:additionalAnnotation=com.example.MyCustomParcelize"
        try withTemporaryFiles(contents: [parcelableStubSource, customSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [customFlag]
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty)

            let descMethods = try findMethodSymbols(named: "describeContents", className: "CustomUser", in: ctx)
            #expect(descMethods.count == 1)
            let writeMethods = try findMethodSymbols(named: "writeToParcel", className: "CustomUser", in: ctx)
            #expect(writeMethods.count == 1)
        }
    }
}
#endif
