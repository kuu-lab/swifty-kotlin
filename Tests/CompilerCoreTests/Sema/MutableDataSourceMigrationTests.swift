#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MutableDataSourceMigrationTests {
    @Test
    func testMutableDataConstructorIsSourceBackedWithKotlin2310Contract() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected bundled MutableData source to type-check, got: " + String(describing: errors))
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let mutableDataFQName = ["kotlin", "native", "concurrent", "MutableData"].map(interner.intern)
            let mutableDataSymbol = try #require(sema.symbols.lookup(fqName: mutableDataFQName))
            let mutableDataInfo = try #require(sema.symbols.symbol(mutableDataSymbol))
            #expect(mutableDataInfo.kind == .class)
            #expect(mutableDataInfo.visibility == .public)
            #expect(!mutableDataInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(mutableDataSymbol))

            let sourceFileID = try #require(sema.symbols.sourceFileID(for: mutableDataSymbol))
            let expectedSourcePath = "__bundled_kotlin/native/concurrent/MutableData.kt"
            #expect(ctx.sourceManager.path(of: sourceFileID) == expectedSourcePath)

            let mutableDataType = sema.types.make(.classType(ClassType(
                classSymbol: mutableDataSymbol,
                args: [],
                nullability: .nonNull
            )))
            let constructor = try #require(
                sema.symbols.lookupAll(fqName: mutableDataFQName + [interner.intern("<init>")]).first {
                    sema.symbols.symbol($0)?.kind == .constructor
                }
            )
            let constructorInfo = try #require(sema.symbols.symbol(constructor))
            let signature = try #require(sema.symbols.functionSignature(for: constructor))
            #expect(constructorInfo.visibility == .public)
            #expect(!constructorInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(constructor))
            #expect(signature.receiverType == mutableDataType)
            #expect(signature.parameterTypes == [sema.types.intType])
            #expect(signature.returnType == mutableDataType)
            #expect(signature.valueParameterHasDefaultValues == [true])
            let parameterNames = signature.valueParameterSymbols.compactMap { parameterSymbol in
                sema.symbols.symbol(parameterSymbol)?.name
            }.map { interner.resolve($0) }
            #expect(parameterNames == ["capacity"])
            #expect(sema.symbols.externalLinkName(for: constructor) == nil)

            let annotations = sema.symbols.annotations(for: mutableDataSymbol)
            #expect(annotations.contains { $0.annotationFQName == "Deprecated" })
            #expect(
                annotations.contains {
                    $0.annotationFQName == "DeprecatedSinceKotlin"
                        && $0.arguments.contains { $0.contains("errorSince") && $0.contains("2.1") }
                }
            )
        }
    }

    @Test
    func testMutableDataMembersAreSourceBackedWithKotlin2310Contract() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected bundled MutableData members to type-check, got: " + String(describing: errors))
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let mutableDataFQName = ["kotlin", "native", "concurrent", "MutableData"].map(interner.intern)
            let mutableDataSymbol = try #require(sema.symbols.lookup(fqName: mutableDataFQName))
            let mutableDataType = sema.types.make(.classType(ClassType(
                classSymbol: mutableDataSymbol,
                args: [],
                nullability: .nonNull
            )))
            let byteArraySymbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"), interner.intern("ByteArray"),
            ]))
            let byteArrayType = sema.types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
            let opaquePointerAlias = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlinx"), interner.intern("cinterop"), interner.intern("COpaquePointer"),
            ]))
            let opaquePointerType = try #require(sema.symbols.typeAliasUnderlyingType(for: opaquePointerAlias))

            func member(named name: String, parameterTypes: [TypeID]) throws -> (SymbolID, FunctionSignature) {
                let candidates = sema.symbols.lookupAll(fqName: mutableDataFQName + [interner.intern(name)])
                    .compactMap { symbolID -> (SymbolID, FunctionSignature)? in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              signature.receiverType == mutableDataType,
                              signature.parameterTypes == parameterTypes
                        else {
                            return nil
                        }
                        return (symbolID, signature)
                    }
                let match = try #require(
                    candidates.first,
                    Comment(rawValue: "Missing MutableData.\(name) with parameter types \(parameterTypes)")
                )
                let symbol = try #require(sema.symbols.symbol(match.0))
                #expect(!symbol.flags.contains(.synthetic), "MutableData.\(name) must not remain synthetic")
                #expect(sema.symbols.isSourceBackedSymbol(match.0))
                #expect(sema.symbols.externalLinkName(for: match.0) == nil)
                return match
            }

            let int = sema.types.intType
            _ = try member(named: "append", parameterTypes: [mutableDataType])
            _ = try member(named: "append", parameterTypes: [sema.types.makeNullable(opaquePointerType), int])
            _ = try member(named: "append", parameterTypes: [byteArrayType, int, int])
            _ = try member(named: "copyInto", parameterTypes: [byteArrayType, int, int, int])
            let (_, getSignature) = try member(named: "get", parameterTypes: [int])
            #expect(getSignature.returnType == sema.types.byteType)
            _ = try member(named: "reset", parameterTypes: [])

            let size = try #require(
                sema.symbols.lookupAll(fqName: mutableDataFQName + [interner.intern("size")]).first {
                    sema.symbols.symbol($0)?.kind == .property
                },
                "Missing MutableData.size"
            )
            let sizeInfo = try #require(sema.symbols.symbol(size))
            #expect(!sizeInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(size))
            #expect(sema.symbols.externalLinkName(for: size) == nil)
            #expect(sema.symbols.propertyType(for: size) == int)

            for (name, blockParameterTypes) in [
                ("withBufferLocked", [byteArrayType, int]),
                ("withPointerLocked", [opaquePointerType, int]),
            ] {
                let candidates = sema.symbols.lookupAll(fqName: mutableDataFQName + [interner.intern(name)])
                    .filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              signature.receiverType == mutableDataType,
                              signature.parameterTypes.count == 1,
                              signature.typeParameterSymbols.count == 1,
                              case let .functionType(functionType) = sema.types.kind(of: signature.parameterTypes[0])
                        else {
                            return false
                        }
                        return functionType.params == blockParameterTypes
                    }
                let symbolID = try #require(
                    candidates.first,
                    "Missing MutableData.\(name) generic block signature"
                )
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(!symbol.flags.contains(.synthetic))
                #expect(sema.symbols.isSourceBackedSymbol(symbolID))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            }
        }
    }
}
#endif
