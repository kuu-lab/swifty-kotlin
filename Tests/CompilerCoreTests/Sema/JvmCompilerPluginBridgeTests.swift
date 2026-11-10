#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Tests dynamic loading, inspection, Sema transformations (Phase 2),
/// and Lowering/IR transformations (Phase 3) of real kotlinc compiler plugin JARs
/// via `JvmPluginHostClient` and `JvmCompilerPlugin`.
@Suite
struct JvmCompilerPluginBridgeTests {

    private let allOpenJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/allopen-compiler-plugin.jar"
    private let noArgJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/noarg-compiler-plugin.jar"
    private let parcelizeJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/parcelize-compiler.jar"
    private let serializationJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/kotlinx-serialization-compiler-plugin.jar"

    // MARK: - Phase 1: Inspection & Option Validation

    @Test
    func testHostInspectsAllOpenJar() throws {
        guard FileManager.default.fileExists(atPath: allOpenJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: allOpenJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlin.allopen")
        #expect(result.commandLineProcessor == "org.jetbrains.kotlin.allopen.AllOpenCommandLineProcessor")
        #expect(result.registrar == "org.jetbrains.kotlin.allopen.AllOpenComponentRegistrar")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("annotation"))
        #expect(optionNames.contains("preset"))
    }

    @Test
    func testHostInspectsNoArgJar() throws {
        guard FileManager.default.fileExists(atPath: noArgJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: noArgJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlin.noarg")
        #expect(result.commandLineProcessor == "org.jetbrains.kotlin.noarg.NoArgCommandLineProcessor")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("annotation"))
        #expect(optionNames.contains("invokeInitializers"))
    }

    @Test
    func testHostInspectsParcelizeJar() throws {
        guard FileManager.default.fileExists(atPath: parcelizeJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: parcelizeJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlin.parcelize")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("additionalAnnotation"))
    }

    @Test
    func testDynamicPluginWarnsOnUnknownOptionInSema() throws {
        guard FileManager.default.fileExists(atPath: allOpenJarPath) else {
            return
        }
        let source = """
        package com.example

        class Hello
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(allOpenJarPath)",
                "plugin:org.jetbrains.kotlin.allopen:unknownOption=value",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let warnings = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PLUGIN-0001" }
            #expect(!warnings.isEmpty, "expected warning KSWIFTK-PLUGIN-0001 for unknown option")
        }
    }

    // MARK: - Phase 2: Sema Dynamic Transformation

    @Test
    func testDynamicAllOpenTransformsSema() throws {
        guard FileManager.default.fileExists(atPath: allOpenJarPath) else {
            return
        }
        let source = """
        package com.example

        annotation class OpenMe

        @OpenMe
        class Service {
            fun doWork(): Int = 42
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(allOpenJarPath)",
                "plugin:org.jetbrains.kotlin.allopen:annotation=com.example.OpenMe",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            let serviceSymbolID = try #require(lookupSymbol(named: "Service", in: sema, interner: ctx.interner))
            let serviceSymbol = try #require(sema.symbols.symbol(serviceSymbolID))
            #expect(serviceSymbol.flags.contains(.openType), "Class annotated with @OpenMe should become open")

            let doWorkSymbolID = try #require(lookupMember(named: "doWork", on: serviceSymbolID, in: sema, interner: ctx.interner))
            let doWorkSymbol = try #require(sema.symbols.symbol(doWorkSymbolID))
            #expect(doWorkSymbol.flags.contains(.openType), "Member of @OpenMe class should become open")
        }
    }

    // MARK: - Phase 3: Lowering & Synthetic Generation

    @Test
    func testDynamicNoArgTransformsSemaAndKIR() throws {
        guard FileManager.default.fileExists(atPath: noArgJarPath) else {
            return
        }
        let source = """
        package com.example

        annotation class MyEntity

        @MyEntity
        class User(val id: Int)
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(noArgJarPath)",
                "plugin:org.jetbrains.kotlin.noarg:annotation=com.example.MyEntity",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let kir = try #require(ctx.kir)

            let userSymbolID = try #require(lookupSymbol(named: "User", in: sema, interner: ctx.interner))
            let ctors = sema.symbols.lookupAll(
                fqName: sema.symbols.symbol(userSymbolID)!.fqName + [ctx.interner.intern("<init>")]
            ).filter {
                sema.symbols.symbol($0)?.kind == .constructor && sema.symbols.parentSymbol(for: $0) == userSymbolID
            }

            // Expect explicit primary constructor plus synthetic zero-arg constructor
            let zeroArgCtor = ctors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
            }
            #expect(zeroArgCtor != nil, "Expected synthetic zero-arg constructor in Sema symbol table")

            if let zeroArgCtor {
                // In KIR, functions contain implicit receiver param; zero-arg ctor has params.count == 1
                let fn = kir.arena.function(for: zeroArgCtor)
                #expect(fn != nil, "Expected synthesized zero-arg constructor in KIR arena")
                if let fn {
                    #expect(fn.params.count == 1)
                }
            }
        }
    }

    @Test
    func testDynamicParcelizeTransformsSemaAndKIR() throws {
        guard FileManager.default.fileExists(atPath: parcelizeJarPath) else {
            return
        }
        let stub = """
        package kotlinx.parcelize

        annotation class Parcelize
        """
        let source = """
        package com.example

        import kotlinx.parcelize.Parcelize

        @Parcelize
        class Record(val id: Int)
        """
        try withTemporaryFiles(contents: [stub, source]) { paths in
            let flags = [
                "-Xplugin=\(parcelizeJarPath)",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let kir = try #require(ctx.kir)

            let recordSymbolID = try #require(lookupSymbol(named: "Record", in: sema, interner: ctx.interner))
            let describeContentsID = lookupMember(named: "describeContents", on: recordSymbolID, in: sema, interner: ctx.interner)
            #expect(describeContentsID != nil, "Expected synthetic describeContents in SymbolTable")

            if let describeContentsID {
                let kirFn = kir.arena.function(for: describeContentsID)
                #expect(kirFn != nil, "Expected describeContents in KIR arena")
                if let kirFn {
                    #expect(!kirFn.body.isEmpty, "Expected lowered return instruction in describeContents")
                }
            }
        }
    }

    @Test
    func testDynamicPluginInstructionPlanLowersCustomMethod() throws {
        CompilerPluginRegistry.clearDynamicPluginsCache()
        defer { CompilerPluginRegistry.clearDynamicPluginsCache() }
        guard FileManager.default.fileExists(atPath: parcelizeJarPath) else {
            return
        }
        let source = """
        package com.example

        class CustomService
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(parcelizeJarPath)",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            // Inject an arbitrary instruction plan to verify the generic IR generation engine
            let serviceID = try #require(lookupSymbol(named: "CustomService", in: sema, interner: ctx.interner))
            let methodName = ctx.interner.intern("greeting")
            let methodSym = sema.symbols.define(
                kind: .function,
                name: methodName,
                fqName: sema.symbols.symbol(serviceID)!.fqName + [methodName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(serviceID, for: methodSym)
            let methodType = sema.types.make(.classType(ClassType(classSymbol: serviceID, args: [], nullability: .nonNull)))
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: methodType,
                    parameterTypes: [],
                    returnType: sema.types.stringType,
                    valueParameterSymbols: [],
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: methodSym
            )

            // Find the dynamic plugin and register the plan
            let plugins = CompilerPluginRegistry.plugins(for: ctx.options)
            let dynamicPlugin = plugins.first(where: { $0 is JvmCompilerPlugin }) as? JvmCompilerPlugin
            let planBox = try #require(dynamicPlugin?.planBox)
            planBox.syntheticMethodSymbols[methodSym] = JvmSyntheticMethodPlan(
                classFqName: "com.example.CustomService",
                name: "greeting",
                returnType: "kotlin.String",
                instructions: [
                    JvmKIRInstructionPlan(kind: .returnString, stringValue: "Hello from dynamic IR!")
                ]
            )

            try BuildKIRPhase().run(ctx)
            try LoweringPhase().run(ctx)
            let kir = try #require(ctx.kir)
            let fn = kir.arena.function(for: methodSym)
            #expect(fn != nil, "Custom method must be lowered into KIR")
            if let fn {
                #expect(!fn.body.isEmpty, "Custom method must have generated instructions")
                let hasStringReturn = fn.body.contains { instr in
                    switch instr {
                    case let .constValue(_, val):
                        if case let .stringLiteral(interned) = val {
                            return ctx.interner.resolve(interned) == "Hello from dynamic IR!"
                        }
                    case let .returnValue(expr):
                        let idx = Int(expr.rawValue)
                        if idx >= 0 && idx < kir.arena.expressions.count,
                           case let .stringLiteral(interned) = kir.arena.expressions[idx] {
                            return ctx.interner.resolve(interned) == "Hello from dynamic IR!"
                        }
                    default:
                        break
                    }
                    return false
                }
                #expect(hasStringReturn, "Custom method body must contain the string literal from instruction plan")
            }
        }
    }

    @Test
    func testHostInspectsSerializationJar() throws {
        guard FileManager.default.fileExists(atPath: serializationJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: serializationJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlinx.serialization")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("disableIntrinsic"))
    }

    @Test
    func testDynamicSerializationTransformsSema() throws {
        guard FileManager.default.fileExists(atPath: serializationJarPath) else {
            return
        }
        let stub = """
        package kotlinx.serialization

        annotation class Serializable
        interface KSerializer<T>
        """
        let source = """
        package com.example

        import kotlinx.serialization.Serializable

        @Serializable
        class DynamicPayload(val name: String)
        """
        try withTemporaryFiles(contents: [stub, source]) { paths in
            let flags = [
                "-Xplugin=\(serializationJarPath)",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let payloadID = try #require(lookupSymbol(named: "DynamicPayload", in: sema, interner: ctx.interner))
            let info = try #require(sema.serializationClasses[payloadID])
            #expect(info.companionObjectSymbol != nil)
            #expect(info.companionSerializerMethod != nil)
            #expect(info.generatedSerializerClass != nil)
        }
    }

    // MARK: - Helpers

    private func lookupSymbol(named name: String, in sema: SemaModule, interner: StringInterner) -> SymbolID? {
        let interned = interner.intern(name)
        return sema.symbols.allSymbols().first { sym in
            sym.name == interned && !sym.flags.contains(.importedLibrary)
        }?.id
    }

    private func lookupMember(named name: String, on parentID: SymbolID, in sema: SemaModule, interner: StringInterner) -> SymbolID? {
        let interned = interner.intern(name)
        return sema.symbols.declaredChildren(of: parentID).first { childID in
            sema.symbols.symbol(childID)?.name == interned
        }
    }
}
#endif
