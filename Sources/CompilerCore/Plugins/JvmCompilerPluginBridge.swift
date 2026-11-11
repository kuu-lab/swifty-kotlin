import Foundation

/// Describes a configuration option accepted by a kotlinc compiler plugin JAR.
public struct JvmPluginOption: Codable, Sendable {
    public let name: String
    public let description: String
    public let required: Bool

    public init(name: String, description: String, required: Bool) {
        self.name = name
        self.description = description
        self.required = required
    }
}

/// Metadata extracted from a kotlinc compiler plugin JAR by the JVM host.
public struct JvmPluginInspectionResult: Codable, Sendable {
    public let pluginId: String
    public let commandLineProcessor: String
    public let registrar: String
    public let options: [JvmPluginOption]

    public init(
        pluginId: String,
        commandLineProcessor: String,
        registrar: String,
        options: [JvmPluginOption]
    ) {
        self.pluginId = pluginId
        self.commandLineProcessor = commandLineProcessor
        self.registrar = registrar
        self.options = options
    }
}

/// Errors occurring during JVM compiler plugin hosting and inspection.
public enum JvmPluginError: Error, LocalizedError, Sendable {
    case javaNotFound
    case hostRunnerNotFound
    case executionFailed(exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .javaNotFound:
            return "Java runtime (java) was not found in PATH or JAVA_HOME."
        case .hostRunnerNotFound:
            return "JvmPluginHost.java was not found."
        case let .executionFailed(exitCode, message):
            return "JVM plugin host failed with exit code \(exitCode): \(message)"
        }
    }
}

// MARK: - IPC Payloads for Phase 2 & 3

public struct JvmSemaClassPayload: Codable, Sendable {
    public let fqName: String
    public let annotations: [String]
    public let members: [JvmSemaMemberPayload]
    public let ctorParamCounts: [Int]

    public init(fqName: String, annotations: [String], members: [JvmSemaMemberPayload], ctorParamCounts: [Int]) {
        self.fqName = fqName
        self.annotations = annotations
        self.members = members
        self.ctorParamCounts = ctorParamCounts
    }
}

public struct JvmSemaMemberPayload: Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct JvmSemaTransformRequest: Codable, Sendable {
    public let options: [String: [String]]
    public let classes: [JvmSemaClassPayload]

    public init(options: [String: [String]], classes: [JvmSemaClassPayload]) {
        self.options = options
        self.classes = classes
    }
}

public struct JvmSyntheticConstructorPlan: Codable, Sendable {
    public let classFqName: String
    public let runsInitializers: Bool

    public init(classFqName: String, runsInitializers: Bool) {
        self.classFqName = classFqName
        self.runsInitializers = runsInitializers
    }
}

public struct JvmKIRInstructionPlan: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case returnUnit
        case returnInt
        case returnString
        case returnBoolean
    }

    public let kind: Kind
    public let intValue: Int?
    public let stringValue: String?
    public let boolValue: Bool?

    public init(kind: Kind, intValue: Int? = nil, stringValue: String? = nil, boolValue: Bool? = nil) {
        self.kind = kind
        self.intValue = intValue
        self.stringValue = stringValue
        self.boolValue = boolValue
    }
}

public struct JvmSyntheticMethodParam: Codable, Sendable {
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public struct JvmSyntheticMethodPlan: Codable, Sendable {
    public let classFqName: String
    public let name: String
    public let returnType: String
    public let defaultIntReturn: Int?
    public let params: [JvmSyntheticMethodParam]?
    public let instructions: [JvmKIRInstructionPlan]?

    public init(
        classFqName: String,
        name: String,
        returnType: String,
        defaultIntReturn: Int? = nil,
        params: [JvmSyntheticMethodParam]? = nil,
        instructions: [JvmKIRInstructionPlan]? = nil
    ) {
        self.classFqName = classFqName
        self.name = name
        self.returnType = returnType
        self.defaultIntReturn = defaultIntReturn
        self.params = params
        self.instructions = instructions
    }
}

public struct JvmSemaTransformPlan: Codable, Sendable {
    public let classesToOpen: [String]
    public let membersToOpen: [String]
    public let syntheticConstructors: [JvmSyntheticConstructorPlan]
    public let syntheticMethods: [JvmSyntheticMethodPlan]
    public let serializableClasses: [String]?
    public let samWithReceiverInterfaces: [String]?
    public let assignmentOverloadTargets: [String]?
    public let powerAssertFunctions: [String]?
    public let lombokEnabled: Bool?
    public let lombokConfigPaths: [String]?
    public let composeEnabled: Bool?

    public init(
        classesToOpen: [String] = [],
        membersToOpen: [String] = [],
        syntheticConstructors: [JvmSyntheticConstructorPlan] = [],
        syntheticMethods: [JvmSyntheticMethodPlan] = [],
        serializableClasses: [String]? = nil,
        samWithReceiverInterfaces: [String]? = nil,
        assignmentOverloadTargets: [String]? = nil,
        powerAssertFunctions: [String]? = nil,
        lombokEnabled: Bool? = nil,
        lombokConfigPaths: [String]? = nil,
        composeEnabled: Bool? = nil
    ) {
        self.classesToOpen = classesToOpen
        self.membersToOpen = membersToOpen
        self.syntheticConstructors = syntheticConstructors
        self.syntheticMethods = syntheticMethods
        self.serializableClasses = serializableClasses
        self.samWithReceiverInterfaces = samWithReceiverInterfaces
        self.assignmentOverloadTargets = assignmentOverloadTargets
        self.powerAssertFunctions = powerAssertFunctions
        self.lombokEnabled = lombokEnabled
        self.lombokConfigPaths = lombokConfigPaths
        self.composeEnabled = composeEnabled
    }
}

// MARK: - Client

/// Client that manages communication with the external JVM plugin host runner.
public final class JvmPluginHostClient: @unchecked Sendable {
    public static let shared = JvmPluginHostClient()

    private init() {}

    public func findJavaExecutable() -> String? {
        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            let candidate = (javaHome as NSString).appendingPathComponent("bin/java")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        let commonPaths = [
            "/opt/homebrew/bin/java",
            "/usr/bin/java",
            "/usr/local/bin/java",
        ]
        for p in commonPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = (String(dir) as NSString).appendingPathComponent("java")
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    public func findKotlinCompilerJar() -> String? {
        if let env = ProcessInfo.processInfo.environment["KSWIFTK_KOTLIN_COMPILER_JAR"],
           FileManager.default.fileExists(atPath: env) {
            return env
        }
        let commonCandidates = [
            "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/kotlin-compiler.jar",
            "/usr/local/Cellar/kotlin/2.4.21/libexec/lib/kotlin-compiler.jar",
            "/opt/homebrew/opt/kotlin/libexec/lib/kotlin-compiler.jar",
            "/usr/local/opt/kotlin/libexec/lib/kotlin-compiler.jar",
        ]
        for c in commonCandidates {
            if FileManager.default.fileExists(atPath: c) {
                return c
            }
        }
        return nil
    }

    public func findJvmPluginHostSource() -> String? {
        if let env = ProcessInfo.processInfo.environment["KSWIFTK_JVM_PLUGIN_HOST"],
           FileManager.default.fileExists(atPath: env) {
            return env
        }

        let relativeHostPath = "Scripts/jvm_plugin_host/JvmPluginHost.java"
        let searchRoots: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle.main.bundleURL,
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
        ]
        for root in searchRoots {
            var current = root
            for _ in 0 ..< 8 {
                let candidate = current.appendingPathComponent(relativeHostPath).path
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
        return nil
    }

    public func inspectPlugin(pluginJarPath: String) throws -> JvmPluginInspectionResult {
        guard let javaBin = findJavaExecutable() else {
            throw JvmPluginError.javaNotFound
        }
        guard let hostSource = findJvmPluginHostSource() else {
            throw JvmPluginError.hostRunnerNotFound
        }
        let compilerJar = findKotlinCompilerJar() ?? "-"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaBin)
        process.arguments = [
            hostSource,
            "inspect",
            pluginJarPath,
            compilerJar,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw JvmPluginError.executionFailed(exitCode: process.terminationStatus, message: errMsg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(JvmPluginInspectionResult.self, from: data)
    }

    public func transformSema(
        pluginJarPath: String,
        options: [String: [String]],
        classes: [JvmSemaClassPayload]
    ) throws -> JvmSemaTransformPlan {
        guard let javaBin = findJavaExecutable() else {
            throw JvmPluginError.javaNotFound
        }
        guard let hostSource = findJvmPluginHostSource() else {
            throw JvmPluginError.hostRunnerNotFound
        }
        let compilerJar = findKotlinCompilerJar() ?? "-"

        let request = JvmSemaTransformRequest(options: options, classes: classes)
        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(request)
        guard let payloadJson = String(data: payloadData, encoding: .utf8) else {
            throw JvmPluginError.executionFailed(exitCode: 1, message: "Failed to encode request payload")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaBin)
        process.arguments = [
            hostSource,
            "transformSema",
            pluginJarPath,
            compilerJar,
            payloadJson,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw JvmPluginError.executionFailed(exitCode: process.terminationStatus, message: errMsg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(JvmSemaTransformPlan.self, from: data)
    }
}

// MARK: - JvmCompilerPlugin

final class JvmPluginPlanBox: @unchecked Sendable {
    var plan: JvmSemaTransformPlan?
    var syntheticMethodSymbols: [SymbolID: JvmSyntheticMethodPlan] = [:]
}

/// Adapter wrapping an external kotlinc compiler plugin JAR as a KSwiftK `CompilerPlugin`.
final class JvmCompilerPlugin: CompilerPlugin, @unchecked Sendable {
    let id: String
    let jarPath: String
    let descriptor: JvmPluginInspectionResult
    let planBox = JvmPluginPlanBox()

    init(jarPath: String, descriptor: JvmPluginInspectionResult) {
        self.jarPath = jarPath
        self.descriptor = descriptor
        self.id = descriptor.pluginId.isEmpty ? (jarPath as NSString).lastPathComponent : descriptor.pluginId
    }

    func applySemaTransform(_ context: CompilerPluginSemaContext) {
        // Validate configured options against declared CommandLineProcessor options
        validateConfiguredOptions(context)

        // Query JVM host for Phase 2 transformation plan
        let plan = fetchOrComputePlan(context)

        // Apply classesToOpen and membersToOpen
        applyOpenPlan(plan, context: context)

        // Apply synthetic methods (e.g. describeContents, writeToParcel)
        applySyntheticMethods(plan, context: context)

        // Apply sam-with-receiver interfaces
        applySamWithReceiverInterfaces(plan, context: context)

        // Apply assignment overload targets
        applyAssignmentOverloadTargets(plan, context: context)

        // Apply power-assert target functions
        applyPowerAssertFunctions(plan, context: context)

        if plan.composeEnabled == true {
            ComposePlugin.applyCompose(context: context)
        }
    }

    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {
        let plan = fetchOrComputePlan(context)
        applySyntheticConstructors(plan, context: context)
        applySerializableClasses(plan, context: context)
        if plan.lombokEnabled == true {
            LombokPlugin.applyLombok(configPaths: plan.lombokConfigPaths ?? [], context: context)
        }
    }

    var loweringPasses: [any LoweringPass] {
        [JvmPluginLoweringPass(pluginId: id, planBox: planBox)]
    }

    // MARK: - Private Helpers

    private func validateConfiguredOptions(_ context: CompilerPluginSemaContext) {
        let knownOptions = Set(descriptor.options.map(\.name))
        guard !knownOptions.isEmpty else { return }

        if let configured = context.pluginConfig.values[id] {
            for key in configured.keys {
                if !knownOptions.contains(key) {
                    context.diagnostics.warning(
                        "KSWIFTK-PLUGIN-0001",
                        "Plugin '\(id)' does not recognize option '\(key)'. Available options: \(descriptor.options.map(\.name).joined(separator: ", "))",
                        range: nil
                    )
                }
            }
        }
    }

    private func fetchOrComputePlan(_ context: CompilerPluginSemaContext) -> JvmSemaTransformPlan {
        if let existing = planBox.plan {
            return existing
        }

        let symbols = context.symbols
        let interner = context.interner

        var classPayloads: [JvmSemaClassPayload] = []
        for symbol in symbols.allSymbols() {
            guard (symbol.kind == .class || symbol.kind == .object || symbol.kind == .interface),
                  !symbol.flags.contains(.importedLibrary),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic)
            else { continue }

            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            let annotations = symbols.annotations(for: symbol.id).map(\.annotationFQName)

            var members: [JvmSemaMemberPayload] = []
            var ctorParamCounts: [Int] = []

            for childID in symbols.declaredChildren(of: symbol.id) {
                guard let child = symbols.symbol(childID) else { continue }
                if child.kind == .constructor {
                    let paramCount = symbols.functionSignature(for: childID)?.parameterTypes.count ?? 0
                    ctorParamCounts.append(paramCount)
                } else if child.kind == .function || child.kind == .property {
                    members.append(JvmSemaMemberPayload(name: interner.resolve(child.name)))
                }
            }

            classPayloads.append(JvmSemaClassPayload(
                fqName: fqName,
                annotations: annotations,
                members: members,
                ctorParamCounts: ctorParamCounts
            ))
        }

        let optionsMap = context.pluginConfig.values[id] ?? [:]
        let plan = (try? JvmPluginHostClient.shared.transformSema(
            pluginJarPath: jarPath,
            options: optionsMap,
            classes: classPayloads
        )) ?? JvmSemaTransformPlan()

        planBox.plan = plan
        return plan
    }

    private func applyOpenPlan(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard !plan.classesToOpen.isEmpty || !plan.membersToOpen.isEmpty else { return }
        let symbols = context.symbols
        let interner = context.interner

        let classesToOpenSet = Set(plan.classesToOpen)
        let membersToOpenSet = Set(plan.membersToOpen)

        for symbol in symbols.allSymbols() {
            guard symbol.kind == .class else { continue }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            if classesToOpenSet.contains(fqName) {
                symbols.insertFlags(.openType, for: symbol.id)
                for childID in symbols.declaredChildren(of: symbol.id) {
                    guard let child = symbols.symbol(childID),
                          child.kind == .function || child.kind == .property,
                          child.visibility != .private,
                          !child.flags.contains(.finalMember),
                          !child.flags.contains(.synthetic),
                          !child.flags.contains(.importedLibrary)
                    else { continue }
                    symbols.insertFlags(.openType, for: childID)
                }
            } else if !membersToOpenSet.isEmpty {
                for childID in symbols.declaredChildren(of: symbol.id) {
                    guard let child = symbols.symbol(childID) else { continue }
                    let memberFqName = fqName + "." + interner.resolve(child.name)
                    if membersToOpenSet.contains(memberFqName) {
                        symbols.insertFlags(.openType, for: childID)
                    }
                }
            }
        }
    }

    private func applySyntheticMethods(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard !plan.syntheticMethods.isEmpty else { return }
        let symbols = context.symbols
        let interner = context.interner
        let types = context.types

        for methodPlan in plan.syntheticMethods {
            let classParts = methodPlan.classFqName.split(separator: ".").map { interner.intern(String($0)) }
            guard let classSymbol = symbols.lookup(fqName: classParts),
                  let classInfo = symbols.symbol(classSymbol)
            else { continue }

            let methodName = interner.intern(methodPlan.name)
            let methodFQName = classInfo.fqName + [methodName]

            let returnTypeID: TypeID
            if methodPlan.returnType == "kotlin.Int" {
                returnTypeID = types.intType
            } else if methodPlan.returnType == "kotlin.String" {
                returnTypeID = types.stringType
            } else if methodPlan.returnType == "kotlin.Boolean" {
                returnTypeID = types.booleanType
            } else if methodPlan.returnType == "kotlin.Unit" {
                returnTypeID = types.unitType
            } else {
                returnTypeID = types.unitType
            }

            let ownTypeParams = types.nominalTypeParameterSymbols(for: classSymbol)
            let enclosingTypeParams = types.enclosingTypeParameterSymbols(for: classSymbol)
            let selfArgs: (own: [TypeArg], enclosing: [TypeArg]) = (
                own: ownTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) },
                enclosing: enclosingTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) }
            )
            let classType = types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: selfArgs.own,
                enclosingTypeArgs: selfArgs.enclosing,
                nullability: .nonNull
            )))

            let methodSymbol = symbols.define(
                kind: .function,
                name: methodName,
                fqName: methodFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: methodSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: classType,
                    parameterTypes: [],
                    returnType: returnTypeID,
                    valueParameterSymbols: [],
                    typeParameterSymbols: ownTypeParams,
                    classTypeParameterCount: ownTypeParams.count
                ),
                for: methodSymbol
            )
            planBox.syntheticMethodSymbols[methodSymbol] = methodPlan

            if methodPlan.name == "describeContents" {
                context.sema.parcelizeClasses[classSymbol, default: ParcelizeClassInfo()].describeContentsMethod = methodSymbol
            } else if methodPlan.name == "writeToParcel" {
                context.sema.parcelizeClasses[classSymbol, default: ParcelizeClassInfo()].writeToParcelMethod = methodSymbol
            }
        }
    }

    private func applySyntheticConstructors(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard !plan.syntheticConstructors.isEmpty else { return }
        let symbols = context.symbols
        let interner = context.interner
        let types = context.types
        let initName = interner.intern("<init>")

        for ctorPlan in plan.syntheticConstructors {
            let classParts = ctorPlan.classFqName.split(separator: ".").map { interner.intern(String($0)) }
            guard let classSymbol = symbols.lookup(fqName: classParts),
                  let classInfo = symbols.symbol(classSymbol)
            else { continue }

            let ctorFQName = classInfo.fqName + [initName]

            // Super constructor delegation
            var superCtor: SymbolID? = nil
            var supertypeTypeArguments: [TypeArg] = []
            if let edgeSupertype = symbols.directSupertypes(for: classSymbol).first(where: {
                let kind = symbols.symbol($0)?.kind
                return kind == .class || kind == .enumClass
            }) {
                var superclassSymbol = edgeSupertype
                if let actual = symbols.actualSymbol(for: edgeSupertype),
                   let edgeKind = symbols.symbol(edgeSupertype)?.kind,
                   symbols.symbol(actual)?.kind == edgeKind
                {
                    superclassSymbol = actual
                }
                supertypeTypeArguments = symbols.supertypeTypeArgs(for: classSymbol, supertype: edgeSupertype)
                if supertypeTypeArguments.isEmpty {
                    supertypeTypeArguments = symbols.supertypeTypeArgs(for: classSymbol, supertype: superclassSymbol)
                }
                if let superclassInfo = symbols.symbol(superclassSymbol) {
                    let candidates = symbols.lookupAll(fqName: superclassInfo.fqName + [initName]).filter {
                        symbols.symbol($0)?.kind == .constructor && symbols.parentSymbol(for: $0) == superclassSymbol
                    }
                    let applicable = candidates.filter { ctor in
                        guard let signature = symbols.functionSignature(for: ctor) else { return false }
                        if signature.parameterTypes.isEmpty { return true }
                        return signature.parameterTypes.indices.allSatisfy {
                            signature.valueParameterHasDefaultValues.indices.contains($0)
                                && signature.valueParameterHasDefaultValues[$0]
                        }
                    }
                    superCtor = applicable.min { lhs, rhs in
                        let l = symbols.functionSignature(for: lhs)?.parameterTypes.count ?? .max
                        let r = symbols.functionSignature(for: rhs)?.parameterTypes.count ?? .max
                        return l < r
                    }
                }
            }

            let ownTypeParams = types.nominalTypeParameterSymbols(for: classSymbol)
            let enclosingTypeParams = types.enclosingTypeParameterSymbols(for: classSymbol)
            let typeParamSymbols = enclosingTypeParams + ownTypeParams
            let selfArgs: (own: [TypeArg], enclosing: [TypeArg]) = (
                own: ownTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) },
                enclosing: enclosingTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) }
            )
            let classType = types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: selfArgs.own,
                enclosingTypeArgs: selfArgs.enclosing,
                nullability: .nonNull
            )))

            let ctorSymbol = symbols.define(
                kind: .constructor,
                name: classInfo.name,
                fqName: ctorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: ctorSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: classType,
                    parameterTypes: [],
                    returnType: classType,
                    valueParameterSymbols: [],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: ctorSymbol
            )

            if let superCtor {
                let substitutedTypeArguments = supertypeTypeArguments.map { arg -> TypeID in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type):
                        return type
                    case .star:
                        return types.anyType
                    }
                }
                context.bindings.bindConstructorDelegationCall(
                    ctorSymbol,
                    binding: CallBinding(
                        chosenCallee: superCtor,
                        substitutedTypeArguments: substitutedTypeArguments,
                        parameterMapping: [:]
                    )
                )
            }

            symbols.setAnnotations(
                [MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["level=HIDDEN"]
                )],
                for: ctorSymbol
            )
            context.sema.pluginGeneratedConstructors[ctorSymbol] = PluginGeneratedConstructorInfo(
                runsInitializers: ctorPlan.runsInitializers
            )
        }
    }

    private func applySerializableClasses(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard let serializable = plan.serializableClasses, !serializable.isEmpty else { return }
        let symbols = context.symbols
        let interner = context.interner
        for fqName in serializable {
            let parts = fqName.split(separator: ".").map { interner.intern(String($0)) }
            guard let symbolID = symbols.lookup(fqName: parts),
                  let symbolInfo = symbols.symbol(symbolID),
                  symbolInfo.kind == .class || symbolInfo.kind == .object,
                  !symbolInfo.flags.contains(.innerClass)
            else { continue }
            KotlinxSerializationPlugin.synthesizeSerializationMembers(for: symbolInfo, context: context)
        }
    }

    private func applySamWithReceiverInterfaces(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard let interfaces = plan.samWithReceiverInterfaces, !interfaces.isEmpty else { return }
        let symbols = context.symbols
        let interner = context.interner
        for fqName in interfaces {
            let parts = fqName.split(separator: ".").map { interner.intern(String($0)) }
            guard let symbolID = symbols.lookup(fqName: parts),
                  let symbolInfo = symbols.symbol(symbolID),
                  symbolInfo.kind == .interface,
                  symbolInfo.flags.contains(.funInterface)
            else { continue }
            context.sema.samWithReceiverInterfaces.insert(symbolID)
        }
    }

    private func applyAssignmentOverloadTargets(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard let targets = plan.assignmentOverloadTargets, !targets.isEmpty else { return }
        let symbols = context.symbols
        let interner = context.interner
        for fqName in targets {
            let parts = fqName.split(separator: ".").map { interner.intern(String($0)) }
            guard let symbolID = symbols.lookup(fqName: parts),
                  let symbolInfo = symbols.symbol(symbolID)
            else { continue }
            switch symbolInfo.kind {
            case .class, .interface, .object, .enumClass:
                context.sema.assignmentOverloadTypes.insert(symbolID)
            case .property, .field:
                context.sema.assignmentOverloadProperties.insert(symbolID)
            default:
                break
            }
        }
    }

    private func applyPowerAssertFunctions(_ plan: JvmSemaTransformPlan, context: CompilerPluginSemaContext) {
        guard let functions = plan.powerAssertFunctions, !functions.isEmpty else { return }
        context.sema.powerAssertFunctions.formUnion(functions)
    }
}

// MARK: - Phase 3 Lowering Pass

final class JvmPluginLoweringPass: LoweringPass {
    static let name = "JvmPluginLowering"
    static let requiredStage: KIRStage = .raw
    static let producedStage: KIRStage = .raw

    let pluginId: String
    private let planBox: JvmPluginPlanBox

    init(pluginId: String, planBox: JvmPluginPlanBox) {
        self.pluginId = pluginId
        self.planBox = planBox
    }

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        planBox.plan != nil && !planBox.syntheticMethodSymbols.isEmpty
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        // 1. Synthesize KIRFunctions for synthetic methods that were not emitted during class lowering
        for (symbol, plan) in planBox.syntheticMethodSymbols {
            if module.arena.function(for: symbol) == nil {
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      let classSymbol = sema.symbols.parentSymbol(for: symbol)
                else { continue }

                var instructions: [KIRInstruction] = []
                buildInstructions(for: plan, instructions: &instructions, sema: sema, arena: module.arena, interner: ctx.interner)

                let receiverType = signature.receiverType ?? sema.types.anyType
                var params: [KIRParameter] = [
                    KIRParameter(symbol: classSymbol, type: receiverType)
                ]
                for (idx, paramType) in signature.parameterTypes.enumerated() {
                    let paramSym = signature.valueParameterSymbols.indices.contains(idx)
                        ? signature.valueParameterSymbols[idx]
                        : classSymbol
                    params.append(KIRParameter(symbol: paramSym, type: paramType))
                }

                let methodName = ctx.interner.intern(plan.name)
                let kirFunc = KIRFunction(
                    symbol: symbol,
                    name: methodName,
                    params: params,
                    returnType: signature.returnType,
                    body: instructions,
                    isSuspend: false,
                    isInline: false
                )
                _ = module.arena.appendDecl(.function(kirFunc))
            }
        }

        // 2. For any pre-existing function declarations whose body is empty, populate instructions
        module.arena.transformFunctions { function in
            guard let plan = self.planBox.syntheticMethodSymbols[function.symbol],
                  function.body.isEmpty
            else { return function }

            var updated = function
            var instructions: [KIRInstruction] = []
            self.buildInstructions(for: plan, instructions: &instructions, sema: sema, arena: module.arena, interner: ctx.interner)
            updated.replaceBody(instructions, locations: Array(repeating: nil, count: instructions.count))
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func buildInstructions(
        for plan: JvmSyntheticMethodPlan,
        instructions: inout [KIRInstruction],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        if let instructionPlans = plan.instructions, !instructionPlans.isEmpty {
            for instr in instructionPlans {
                switch instr.kind {
                case .returnUnit:
                    instructions.append(.returnUnit)
                case .returnInt:
                    let val = instr.intValue ?? 0
                    let expr = arena.appendExpr(.intLiteral(Int64(val)), type: sema.types.intType)
                    instructions.append(.constValue(result: expr, value: .intLiteral(Int64(val))))
                    instructions.append(.returnValue(expr))
                case .returnString:
                    let val = instr.stringValue ?? ""
                    let internedStr = interner.intern(val)
                    let expr = arena.appendExpr(.stringLiteral(internedStr), type: sema.types.stringType)
                    instructions.append(.constValue(result: expr, value: .stringLiteral(internedStr)))
                    instructions.append(.returnValue(expr))
                case .returnBoolean:
                    let val = instr.boolValue ?? false
                    let expr = arena.appendExpr(.boolLiteral(val), type: sema.types.booleanType)
                    instructions.append(.constValue(result: expr, value: .boolLiteral(val)))
                    instructions.append(.returnValue(expr))
                }
            }
        } else if let intRet = plan.defaultIntReturn {
            let constExpr = arena.appendExpr(.intLiteral(Int64(intRet)), type: sema.types.intType)
            instructions.append(.constValue(result: constExpr, value: .intLiteral(Int64(intRet))))
            instructions.append(.returnValue(constExpr))
        } else {
            instructions.append(.returnUnit)
        }
    }
}
