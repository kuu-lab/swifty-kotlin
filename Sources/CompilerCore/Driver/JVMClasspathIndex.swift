import Foundation

/// Classpath lookup follows the caller's entry order. ZIP decoding is shared
/// with KLIB, including bounded entry reads and CRC validation.
final class JVMClasspathIndex {
    static let composeIntrinsicPath = "<kswiftk-jvm-import>/compose-intrinsics.kt"
    var classes: [String: JVMClassInfo] = [:]
    var sourceClasses: [FileID: JVMClassInfo] = [:]
    var methods: [SymbolID: JVMForeignMethod] = [:]
    var extensionSymbols: Set<SymbolID> = []
    var importedDefaultMethods: [SymbolID: JVMForeignMethod] = [:]
    var importedComposableParameters: [SymbolID: Set<Int>] = [:]
    var importedTopLevelGetters: [SymbolID: JVMForeignMethod] = [:]
    private var kotlinFacadeMethods: [FileID: [JVMForeignMethod]] = [:]
    private var kotlinFacadeGetters: [FileID: [JVMForeignMethod]] = [:]
    var composeStaticContracts: [FileID: (method: JVMForeignMethod, composable: JVMCompose.ImportedCall?)] = [:]
    var importedComposeCalls: [SymbolID: JVMCompose.ImportedCall] = [:]
    var composeContentSymbols: Set<SymbolID> = []
    private(set) var fallbackClassFiles: [(String, Data)] = []
    /// Classes kept indexed for signature mapping and d8 input while
    /// `inject(into:)` emits Kotlin stubs only for the subset reachable from
    /// user sources. Explicitly lazy entries (Android framework jars or
    /// selected JDK module packages) and oversized classpaths use this so
    /// importing every framework/library class cannot exhaust the symbol table.
    private(set) var lazyClassNames: Set<String> = []
    private var hierarchyClasses: [String: JVMClassInfo] = [:]
    private var innerClassMetadata: [String: JVMInnerClassInfo] = [:]
    /// Covered names for the `inject(into:)` run in progress; supertypes that
    /// resolve to bundled/synthetic Kotlin declarations rather than stubs.
    private var activeCoveredNames: Set<String> = []
    private(set) var hasComposeRuntime = false
    private(set) var metroDeclarationsFile: FileID?
    private var hasMetroRuntime: Bool {
        classes[JVMMetro.facade] != nil
            && classes[JVMMetro.package + "DependencyGraph"]?.isAnnotation == true
            && classes[JVMMetro.package + "DependencyGraph$Factory"]?.isAnnotation == true
    }

    private func detectsComposeRuntime() -> Bool {
        guard let composer = classes[JVMCompose.composer], composer.isInterface,
              classes[ComposePlugin.composableFQName.replacingOccurrences(of: ".", with: "/")]?.isAnnotation == true
        else { return false }
        return composer.methods.contains { $0.name == JVMCompose.begin && $0.descriptor == "(I)V" && !$0.isStatic }
            && composer.methods.contains { $0.name == JVMCompose.end && $0.descriptor == "()V" && !$0.isStatic }
    }

    private static let defaultAutomaticLazyClasspathMemberLimit = 20_000

    static func load(
        _ paths: [String], lazilyInjecting lazyPaths: Set<String> = [],
        fallbackClassFiles: [(String, Data)] = [],
        automaticLazyClasspathMemberLimit: Int = defaultAutomaticLazyClasspathMemberLimit
    ) throws -> JVMClasspathIndex {
        let result = JVMClasspathIndex()
        var seen: Set<String> = []
        func insert(_ bytes: [UInt8], path: String) throws {
            var reader = JVMClassReader(bytes: bytes)
            let info: JVMClassInfo
            do {
                info = try reader.read()
            } catch {
                throw JVMFrontendError(message: "Cannot read JVM class \(path) at offset \(reader.offset)/\(bytes.count): \(error)")
            }
            guard info.name + ".class" == path else { throw JVMFrontendError(message: "JVM class name does not match entry path: \(info.name) in \(path)") }
            guard seen.insert(info.name).inserted else { return }
            result.hierarchyClasses[info.name] = info
        }
        for path in paths {
            let isLazy = lazyPaths.contains(URL(fileURLWithPath: path).standardizedFileURL.path)
            let priorKeys = isLazy ? Set(result.hierarchyClasses.keys) : []
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else {
                throw JVMFrontendError(message: "JVM classpath entry does not exist: \(path)")
            }
            if directory.boolValue {
                let base = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
                guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { throw JVMClassReader.Invalid() }
                let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "class" }.sorted { $0.path < $1.path }
                for file in files {
                    let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(base.pathComponents.count).joined(separator: "/")
                    guard !relative.hasPrefix("META-INF/"), !relative.hasSuffix("module-info.class"), !relative.hasSuffix("package-info.class") else { continue }
                    try insert(Array(Data(contentsOf: file)), path: relative)
                }
            } else {
                let archive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: path)))
                for entry in archive.entries.sorted(by: { $0.name < $1.name }) {
                    guard entry.name.hasSuffix(".class"), !entry.name.hasPrefix("META-INF/"),
                          !entry.name.hasSuffix("module-info.class"), !entry.name.hasSuffix("package-info.class") else { continue }
                    try insert(archive.contents(of: entry), path: entry.name)
                }
            }
            if isLazy {
                result.lazyClassNames.formUnion(
                    result.hierarchyClasses.keys.filter { !priorKeys.contains($0) }
                )
            }
        }
        // Preserve an explicitly supplied resource class, including when its
        // JAR will be dexed along with the application.
        for (path, data) in fallbackClassFiles where !seen.contains(String(path.dropLast(".class".count))) {
            try insert(Array(data), path: path)
            result.fallbackClassFiles.append((path, data))
        }
        result.linkKotlinMultifileFacades()
        result.indexInnerClasses()
        for info in result.hierarchyClasses.values where result.isImportableClassifier(info.name, visited: []) {
            result.classes[info.name] = info
        }
        result.hasComposeRuntime = result.detectsComposeRuntime()
        if result.hasComposeRuntime {
            result.lazyClassNames.formUnion(result.classes.keys.filter { $0.hasPrefix("androidx/compose/") })
        }
        if result.hasMetroRuntime {
            result.lazyClassNames.formUnion(result.classes.keys.filter { $0.hasPrefix(JVMMetro.package) })
        }
        let eagerClasspathMemberCount = result.classes.values.reduce(0) { count, info in
            result.lazyClassNames.contains(info.name) ? count : count + 1 + info.methods.count + info.fields.count
        }
        if eagerClasspathMemberCount >= automaticLazyClasspathMemberLimit {
            // Eager stubs for a classpath this large can exhaust the synthetic
            // symbol band. Keep every class indexed, but emit only the classes
            // reachable from user sources and eager signatures. Explicitly
            // supplied fallback classes are not classpath entries and stay eager.
            let fallbackClassNames = Set(result.fallbackClassFiles.map {
                String($0.0.dropLast(".class".count))
            })
            result.lazyClassNames.formUnion(Set(result.hierarchyClasses.keys).subtracting(fallbackClassNames))
        }
        result.importInheritedMembers()
        return result
    }

    private func linkKotlinMultifileFacades() {
        for (name, var facade) in hierarchyClasses where !facade.kotlinMultifileParts.isEmpty {
            var methods: [String: JVMForeignMethod] = [:]
            for partName in facade.kotlinMultifileParts {
                guard let part = hierarchyClasses[partName], part.isKotlinMultifilePart else { continue }
                for method in part.methods where method.isStatic && (method.kotlinFunction != nil || method.kotlinSuspendFunction != nil) {
                    methods[method.name + method.descriptor] = method
                }
                for (source, method) in part.kotlinTopLevelProperties {
                    if let getter = facade.methods.first(where: {
                        $0.isStatic && $0.name == method.name && $0.descriptor == method.descriptor
                    }) {
                        facade.kotlinTopLevelProperties.append((source, getter))
                    }
                }
            }
            for index in facade.methods.indices where facade.methods[index].isStatic {
                let method = facade.methods[index]
                guard let part = methods[method.name + method.descriptor] else { continue }
                facade.methods[index].kotlinFunction = part.kotlinFunction
                facade.methods[index].kotlinSuspendFunction = part.kotlinSuspendFunction
            }
            hierarchyClasses[name] = facade
        }
    }

    private func indexInnerClasses() {
        var ownersWithAuthoritativeMetadata: Set<String> = []
        for info in hierarchyClasses.values where info.hasInnerClassesAttribute {
            ownersWithAuthoritativeMetadata.insert(info.name)
            for entry in info.innerClasses where entry.outerName == info.name {
                innerClassMetadata[entry.name] = entry
            }
        }
        for info in hierarchyClasses.values {
            guard let selfEntry = info.innerClasses.first(where: { $0.name == info.name }),
                  let outer = selfEntry.outerName,
                  !ownersWithAuthoritativeMetadata.contains(outer),
                  innerClassMetadata[selfEntry.name] == nil else { continue }
            innerClassMetadata[selfEntry.name] = selfEntry
        }
    }

    private func isImportableClassifier(_ name: String, visited: Set<String>) -> Bool {
        guard !visited.contains(name), let info = hierarchyClasses[name],
              info.flags & 0x1000 == 0, !info.hasEnclosingMethod, !info.isKotlinMultifilePart,
              !JVMMetro.hidesFromSource(info) else { return false }
        if let entry = innerClassMetadata[name] {
            guard let outer = entry.outerName, let shortName = entry.innerName,
                  [UInt16(1), UInt16(4)].contains(entry.access & 0x0007), entry.access & 0x1000 == 0,
                  JVMProgramBuilder.isIdentifier(shortName), name.hasPrefix(outer + "$"),
                  isImportableClassifier(outer, visited: visited.union([name])) else { return false }
            return true
        }
        guard info.flags & 1 != 0, !name.contains("$"),
              name.split(separator: "/").allSatisfy({ JVMProgramBuilder.isIdentifier(String($0)) }) else { return false }
        return true
    }

    private func kotlinCompanion(of owner: JVMClassInfo) -> JVMClassInfo? {
        let name = owner.name + "$Companion"
        guard owner.isKotlinFileFacade == false, let companion = classes[name],
              companion.isKotlinFileFacade == false,
              owner.fields.contains(where: {
                  $0.name == "Companion" && $0.isStatic && $0.isPublic && $0.descriptor == "L\(name);"
              }) else { return nil }
        return companion
    }

    private func nestedClassDeclarations(of owner: String, indentation: String = "    ") -> String {
        let children = innerClassMetadata.values
            .filter { $0.outerName == owner && classes[$0.name] != nil }
            .sorted { ($0.innerName ?? "") < ($1.innerName ?? "") }
        var source = ""
        for entry in children {
            guard let name = entry.innerName, let info = classes[entry.name],
                  classes[owner].flatMap(kotlinCompanion)?.name != entry.name else { continue }
            let typeParameters = info.classTypeParameterNames.isEmpty
                ? ""
                : "<" + info.classTypeParameterNames.map { "`\($0)`" }.joined(separator: ", ") + ">"
            let visibility = entry.access & 0x0007 == 0x0004 ? "protected " : ""
            if info.flags & 0x2000 != 0 {
                source += annotationClassDeclaration(info, short: name, visibility: visibility, indentation: indentation)
                continue
            }
            if info.flags & 0x4000 != 0 {
                source += enumDeclaration(info, name: name, visibility: visibility, indentation: indentation)
                continue
            }
            let isSealedObject = info.isKotlinObject
                && classes[owner].map { sealedInterfaceSubclasses(of: $0).contains(info.name) } == true
                && !info.methods.contains { $0.isStatic && isExposed($0) }
            if isSealedObject {
                source += indentation + visibility + "object `\(name)`"
            } else if info.isInterface {
                source += indentation + visibility + interfaceKeyword(info) + " `\(name)`" + typeParameters
            } else {
                let classKind = info.flags & 0x0400 != 0 ? "abstract class " : (info.flags & 0x0010 != 0 ? "class " : "open class ")
                let isInner = entry.access & 0x0008 == 0
                source += indentation + visibility + (isInner ? "inner " : "") + classKind + "`\(name)`\(typeParameters) private constructor()"
            }
            var parents: [String] = []
            if !info.isInterface, let base = info.superclass, classes[base] != nil,
               let mapped = supertypeReference(base, childParams: info.classTypeParameterNames) {
                parents.append(mapped + "()")
            }
            parents += info.interfaces.filter {
                classes[$0] != nil || info.kotlinReadOnlyCollectionSupertypes[$0] != nil
            }.compactMap { supertypeReference($0, child: info) }
            if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
            source += " {\n"
            // Kotlin forbids companion objects inside inner (non-static
            // member) classes; their statics are unreachable anyway.
            source += memberDeclarations(info: info, members: info.methods,
                                         allowsCompanion: !isSealedObject && entry.access & 0x0008 != 0)
            source += nestedClassDeclarations(of: entry.name, indentation: indentation + "    ")
            source += indentation + "}\n"
        }
        return source
    }

    private func sealedInterfaceSubclasses(of info: JVMClassInfo) -> [String] {
        // The owner stub emits its nested subclasses together. Only that
        // complete set can establish exhaustiveness without loading other stubs.
        let children = info.kotlinSealedInterfaceSubclasses
        return children.allSatisfy { innerClassMetadata[$0]?.outerName == info.name && classes[$0] != nil } ? children : []
    }

    private func interfaceKeyword(_ info: JVMClassInfo) -> String {
        if !sealedInterfaceSubclasses(of: info).isEmpty { return "sealed interface" }
        if !info.kotlinReadOnlyCollectionSupertypes.isEmpty { return "interface" }
        return isSAM(info.name) ? "fun interface" : "interface"
    }

    private func enumDeclaration(_ info: JVMClassInfo, name: String, visibility: String = "", indentation: String = "") -> String {
        let entries = info.fields.filter {
            $0.access & 0x4009 == 0x4009 && $0.descriptor == "L\(info.name);" && JVMProgramBuilder.isIdentifier($0.name)
        }.map { "`\($0.name)`" }
        let autoGeneratedMethods = [
            "values()[L\(info.name);",
            "valueOf(Ljava/lang/String;)L\(info.name);",
            "getEntries()Lkotlin/enums/EnumEntries;",
        ]
        let members = info.methods.filter {
            !$0.isConstructor && (!($0.isStatic && autoGeneratedMethods.contains($0.name + $0.descriptor)))
        }
        let parents = info.interfaces.filter { classes[$0] != nil }.compactMap { supertypeReference($0, child: info) }
        var source = indentation + visibility + "enum class `\(name)`"
        if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
        source += " {\n"
        source += indentation + "    " + entries.joined(separator: ", ") + ";\n"
        source += memberDeclarations(info: info, members: members)
        source += nestedClassDeclarations(of: info.name, indentation: indentation + "    ")
        return source + indentation + "}\n"
    }

    private func importInheritedMembers() {
        func key(_ method: JVMForeignMethod) -> String {
            method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
        }
        func accessibleMethod(_ method: JVMForeignMethod, on info: JVMClassInfo) -> JVMForeignMethod {
            var result = JVMForeignMethod(owner: info.name, name: method.name, descriptor: method.descriptor, parameters: method.parameters,
                                          result: method.result, isStatic: method.isStatic, isInterface: info.isInterface, isAbstract: method.isAbstract)
            result.isFinal = method.isFinal; result.isSpecial = method.isSpecial; result.isSuspend = method.isSuspend
            result.isProtected = method.isProtected
            result.annotations = method.annotations
            result.annotationDefault = method.annotationDefault
            result.kotlinSuspendFunction = method.kotlinSuspendFunction
            result.isVarargs = method.isVarargs
            result.genericResultParameter = method.genericResultParameter
            result.kotlinFunction = method.kotlinFunction
            return result
        }
        func interfaceInherits(_ subtype: String, _ supertype: String, visited: Set<String> = []) -> Bool {
            if subtype == supertype { return true }
            guard !visited.contains(subtype), let info = hierarchyClasses[subtype] else { return false }
            return info.interfaces.contains { interfaceInherits($0, supertype, visited: visited.union([subtype])) }
        }
        for info in classes.values {
            var methods = info.methods
            var bridges = info.bridgeMethods
            var interfaces: [String] = []
            var inheritedInterfaces = info.interfaces
            var interfaceVisited: Set<String> = []
            var interfaceMethods: [String: JVMForeignMethod] = [:]
            func inheritInterface(_ name: String) {
                guard interfaceVisited.insert(name).inserted else { return }
                if classes[name] != nil || info.kotlinReadOnlyCollectionSupertypes[name] != nil {
                    interfaces.append(name)
                    return
                }
                guard let base = hierarchyClasses[name] else { return }
                bridges += base.bridgeMethods
                for method in base.methods where !method.isStatic && !method.isConstructor {
                    let signature = key(method)
                    if !methods.contains(where: { key($0) == signature }),
                       interfaceMethods[signature].map({ interfaceInherits(method.owner, $0.owner) }) ?? true {
                        // The most specific interface wins independently of the
                        // order of redundant interfaces in the classfile.
                        interfaceMethods[signature] = method
                    }
                }
                for parent in base.interfaces { inheritInterface(parent) }
            }
            var visited: Set<String> = [info.name]
            var next = info.superclass
            var superclass: String?
            var hiddenSegment = true
            while let name = next, visited.insert(name).inserted, let base = hierarchyClasses[name] {
                let visible = classes[name] != nil
                if visible && superclass == nil { superclass = name; hiddenSegment = false }
                for method in base.methods where !method.isConstructor && (method.isStatic || hiddenSegment) {
                    if !methods.contains(where: { key($0) == key(method) }) {
                        // A method reference must name an accessible class even
                        // when its implementation is inherited from a hidden base.
                        methods.append(visible ? method : accessibleMethod(method, on: info))
                    }
                }
                if hiddenSegment {
                    bridges += base.bridgeMethods
                    inheritedInterfaces += base.interfaces
                }
                next = base.superclass
            }
            for name in inheritedInterfaces { inheritInterface(name) }
            methods += interfaceMethods.keys.sorted().map { accessibleMethod(interfaceMethods[$0]!, on: info) }
            var abstractMethods: Set<String> = []
            var abstractVisited: Set<String> = []
            func collectAbstract(_ name: String) {
                guard abstractVisited.insert(name).inserted, let base = hierarchyClasses[name] else { return }
                for method in base.methods where method.isAbstract { abstractMethods.insert(key(method)) }
                for parent in base.interfaces { collectAbstract(parent) }
                if let parent = base.superclass { collectAbstract(parent) }
            }
            for name in interfaces { collectAbstract(name) }
            if let superclass { collectAbstract(superclass) }
            // Erased imports need a real bridge when an inherited raw method
            // has different parameters from the specialized implementation.
            for bridge in bridges where abstractMethods.contains(key(bridge)) && !methods.contains(where: { key($0) == key(bridge) }) {
                methods.append(accessibleMethod(bridge, on: info))
            }
            var imported = JVMClassInfo(name: info.name, flags: info.flags, superclass: superclass, interfaces: interfaces, methods: methods, fields: info.fields)
            imported.bridgeMethods = bridges
            imported.defaultArgumentMethods = info.defaultArgumentMethods
            imported.classTypeParameterNames = info.classTypeParameterNames
            imported.genericSignature = info.genericSignature
            imported.innerClasses = info.innerClasses
            imported.hasInnerClassesAttribute = info.hasInnerClassesAttribute
            imported.hasEnclosingMethod = info.hasEnclosingMethod
            imported.isKotlinFileFacade = info.isKotlinFileFacade
            imported.kotlinSealedInterfaceSubclasses = info.kotlinSealedInterfaceSubclasses
            imported.isKotlinObject = info.isKotlinObject
            imported.kotlinReadOnlyCollectionSupertypes = info.kotlinReadOnlyCollectionSupertypes
            imported.annotations = info.annotations
            imported.kotlinStaticProperties = info.kotlinStaticProperties
            imported.kotlinMemberProperties = info.kotlinMemberProperties
            imported.kotlinTopLevelProperties = info.kotlinTopLevelProperties
            classes[info.name] = imported
        }
    }
    func expose(_ type: JVMValueType) -> Bool {
        guard let name = type.referenceName else { return true }
        // Erased function interfaces require Kotlin function-type metadata;
        // their raw Java signatures are not importable declarations.
        if name.hasPrefix("kotlin/jvm/functions/Function") { return false }
        if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 { return expose(element) }
        return name == "java/lang/String" || name == "java/lang/Object" || name == "java/lang/Class"
            || name == "kotlin/coroutines/Continuation" || classes[name] != nil
    }

    private func exposeSuspendType(_ type: JVMValueType) -> Bool {
        guard let name = type.referenceName else { return true }
        if name.hasPrefix("kotlin/jvm/functions/Function") { return false }
        if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 {
            return exposeSuspendType(element)
        }
        return expose(type) || activeCoveredNames.contains(name) || Self.jdkToKotlinTypeNames[name] != nil
            || name == "kotlin/Unit" || name == "kotlin/Nothing"
    }

    private func isExposed(_ method: JVMForeignMethod) -> Bool {
        let exposedName = method.kotlinFunction?.name ?? method.kotlinSuspendFunction?.name ?? method.name
        // Exclude generated static forwarders. The companion's instance method
        // can still implement a user-declared factory interface.
        if method.isStatic, method.annotations.contains(where: { $0.descriptor == JVMMetro.invoke }) { return false }
        guard method.isConstructor || JVMProgramBuilder.isIdentifier(exposedName) else { return false }
        if let function = method.kotlinFunction {
            if function.valueOperatorParameterDescriptors != nil {
                return method.parameters.allSatisfy(exposeSuspendType) && exposeSuspendType(method.result)
            }
            if function.isSuspend {
                guard let suspend = method.kotlinSuspendFunction else { return false }
                let composable = function.composableParameters
                guard composable.isEmpty || hasComposableLambdaFactory else { return false }
                return method.sourceParameters.enumerated().allSatisfy { index, type in
                    if composable.contains(index - function.leadingParameterCount) {
                        return type.referenceName?.hasPrefix("kotlin/jvm/functions/Function") == true
                    }
                    return exposeSuspendType(type)
                } && exposeSuspendType(suspend.result)
            }
            if method.kotlinComposeABI != nil { return hasComposeRuntime }
            guard function.parameters.count + function.leadingParameterCount == method.parameters.count
            else { return false }
            if function.receiver?.contains("->") == true || function.result.contains("->")
                || function.parameters.contains(where: { $0.sourceType.contains("->") }) { return true }
            return method.parameters.allSatisfy(exposeSuspendType) && exposeSuspendType(method.result)
        }
        if let suspend = method.kotlinSuspendFunction {
            return JVMProgramBuilder.isIdentifier(suspend.name)
                && method.sourceParameters.allSatisfy(exposeSuspendType) && exposeSuspendType(suspend.result)
        }
        return method.parameters.allSatisfy(expose) && expose(method.result)
    }
    func hasClassFile(_ name: String) -> Bool { hierarchyClasses[name] != nil }

    func metroFactoryInstance(_ factory: String) -> JVMField? {
        let name = factory + "$Impl"
        guard hierarchyClasses[factory]?.annotations.contains(where: { $0.descriptor == JVMMetro.factory }) == true,
              let impl = hierarchyClasses[name], impl.flags & 1 != 0, impl.interfaces.contains(factory),
              impl.annotations.contains(where: { $0.descriptor == JVMMetro.implementation }) else { return nil }
        return metroSingleton(in: impl, named: "INSTANCE", type: name)
    }

    func metroGraphInvoker(_ graph: String) -> (JVMField, JVMForeignMethod)? {
        let companion = graph + "$Companion"
        guard let info = hierarchyClasses[graph],
              info.annotations.contains(where: { $0.descriptor == JVMMetro.graph }),
              let field = metroSingleton(in: info, named: "Companion", type: companion),
              let owner = hierarchyClasses[companion], owner.flags & 1 != 0,
              let method = owner.methods.first(where: {
                  $0.name == "invoke" && $0.descriptor == "()L" + graph + ";" && !$0.isStatic && !$0.isProtected
                      && $0.annotations.contains(where: { $0.descriptor == JVMMetro.invoke })
              }) else { return nil }
        return (field, method)
    }

    private func metroSingleton(in owner: JVMClassInfo, named name: String, type: String) -> JVMField? {
        guard let field = owner.fields.first(where: {
            $0.name == name && $0.descriptor == "L" + type + ";" && $0.isPublic && $0.isStatic
        }) else { return nil }
        return JVMField(owner: owner.name, name: name, type: .reference(type, nullable: false), access: field.access)
    }
    func kotlinType(_ type: JVMValueType) -> String {
        switch type {
        case .byte: return "kotlin.Byte"
        case .short: return "kotlin.Short"
        case .char: return "kotlin.Char"
        case .uint: return "kotlin.UInt"
        case .ulong: return "kotlin.ULong"
        case .ubyte: return "kotlin.UByte"
        case .ushort: return "kotlin.UShort"
        case let .unsignedArray(p, nullable): return "kotlin." + p.kotlinName + "Array" + (nullable ? "?" : "")
        case .int: return "kotlin.Int"
        case .long: return "kotlin.Long"
        case .float: return "kotlin.Float"
        case .double: return "kotlin.Double"
        case .boolean: return "kotlin.Boolean"
        case .unit: return "kotlin.Unit"
        case .string: return "kotlin.String"
        case let .reference(name, _, _):
            let base: String
            if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 {
                if let primitive = Self.primitiveArrays.first(where: { $0.value == element }) { return "kotlin." + primitive.key }
                return "kotlin.Array<" + kotlinType(element) + ">"
            }
            switch name {
            case "java/lang/String": return "kotlin.String"
            case "java/lang/Object": return "kotlin.Any"
            case "kotlin/coroutines/Continuation": return "kotlin.coroutines.Continuation<*>"
            // Erased Java Class references are wildcard Class<*> in Kotlin; this keeps
            // generic Class<T> extensions usable on Java classpath receivers (KUU-4524).
            case "java/lang/Class": return "java.lang.Class<*>"
            default:
                // Mirror kotlinc's JDK->Kotlin mapped types so foreign
                // signatures render as the Kotlin declarations users expect
                // (and so lazy classpath entries don't need java.* stubs for
                // types the Kotlin standard library already covers).
                if let mapped = Self.jdkToKotlinTypeNames[name] { return mapped }
                base = Self.dottedTypeName(name)
            }
            // Classfiles do not retain Kotlin nullability without metadata. Use
            // non-null source declarations as the current platform-type approximation.
            return base
        }
    }
    /// Supertype positions keep the erased JDK name: Kotlin mapped types
    /// declare property-style members that Java method stubs cannot satisfy,
    /// so `extends`/`implements` clauses must name the interface the
    /// classfile actually declares. Only `java.lang.Object`/`String` still
    /// collapse to their Kotlin aliases, and `Enum`/`Record` cannot be
    /// extended directly.
    func kotlinSupertypeName(_ name: String) -> String? {
        switch name {
        case "java/lang/Object": return "kotlin.Any"
        case "java/lang/String": return "kotlin.String"
        case "java/lang/Enum", "java/lang/Record": return nil
        default:
            // Covered classes get no stub, so an erased `java.*` supertype
            // would not resolve. When the JDK->Kotlin mapped-type table names
            // a provided Kotlin counterpart (kotlin.Number, kotlin.text
            // .Appendable, ...), emit that instead; generic arguments are
            // appended by `supertypeReference`.
            if activeCoveredNames.contains(name),
               let mapped = Self.jdkToKotlinTypeNames[name] {
                return mapped.split(separator: "<").first.map(String.init) ?? mapped
            }
            return Self.dottedTypeName(name)
        }
    }
    /// Binary names use `$` for nested classes; Kotlin source spells them
    /// with dots (`a/b/C$D` -> `a.b.C.D`).
    private static func dottedTypeName(_ name: String) -> String {
        name.split(separator: "/").flatMap { $0.split(separator: "$") }
            .map { "`\($0)`" }.joined(separator: ".")
    }
    /// Supertype reference with type arguments: classfiles erase generic
    /// arguments, so the child's own type parameters are reused when the
    /// arity matches (the usual Java convention) and `kotlin.Any` fills the
    /// rest. `Any` keeps erased bridge members (e.g. `compare(Object, Object)`)
    /// valid overrides, unlike star projections whose captured types cannot
    /// be overridden at all.
    private func supertypeReference(_ name: String, childParams: [String]) -> String? {
        guard let base = kotlinSupertypeName(name) else { return nil }
        let arity = hierarchyClasses[name]?.classTypeParameterNames.count ?? 0
        guard arity > 0 else { return base }
        let args = arity == childParams.count && arity > 0
            ? childParams
            : Array(repeating: "kotlin.Any", count: arity)
        return base + "<" + args.joined(separator: ", ") + ">"
    }

    private func supertypeReference(_ name: String, child: JVMClassInfo) -> String? {
        if let collection = child.kotlinReadOnlyCollectionSupertypes[name] { return collection }
        if name == "kotlin/coroutines/CoroutineContext$Key", let signature = child.genericSignature,
           let prefix = signature.range(of: "L" + name + "<L"),
           let end = signature[prefix.upperBound...].range(of: ";>;") {
            let argument = String(signature[prefix.upperBound..<end.lowerBound])
            if classes[argument] != nil {
                return Self.dottedTypeName(name) + "<" + Self.dottedTypeName(argument) + ">"
            }
        }
        return supertypeReference(name, childParams: child.classTypeParameterNames)
    }
    private func isSAM(_ name: String) -> Bool {
        var members: [String: JVMForeignMethod] = [:], visited: Set<String> = []
        func visit(_ name: String) {
            guard visited.insert(name).inserted, let info = classes[name] else { return }
            for parent in info.interfaces { visit(parent) }
            for method in info.methods where !method.isStatic && !method.isConstructor {
                if ["equals(Ljava/lang/Object;)Z", "hashCode()I", "toString()Ljava/lang/String;"].contains(method.name + method.descriptor) { continue }
                let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
                members[key] = method
            }
        }
        visit(name)
        let abstracts = members.values.filter(\.isAbstract)
        guard abstracts.count == 1, let sam = abstracts.first,
              JVMProgramBuilder.isIdentifier(sam.name), sam.parameters.allSatisfy(expose), expose(sam.result)
        else { return false }
        // Getter-shaped members are also emitted as `val` properties; when
        // the single abstract member has that shape the `fun interface`
        // form is rejected, so emit a plain interface instead.
        if sam.parameters.isEmpty,
           (sam.name.hasPrefix("get") && sam.name.count > 3
               || sam.name.hasPrefix("is") && sam.name.count > 2 && sam.result == .boolean) {
            return false
        }
        return true
    }
    func annotationElements(of info: JVMClassInfo) -> [(name: String, type: JVMValueType, defaultValue: JVMAnnotationValue?)] {
        info.methods.compactMap { method in
            guard method.isAbstract, !method.isStatic, !method.isConstructor,
                  method.parameters.isEmpty, method.name != "annotationType",
                  method.result != .unit, JVMProgramBuilder.isIdentifier(method.name)
            else { return nil }
            return (method.name, method.result, method.annotationDefault)
        }
    }

    private func annotationElementKotlinType(_ type: JVMValueType) -> String? {
        switch type {
        case .unit:
            return nil
        case .string, .int, .long, .float, .double, .boolean, .byte, .short, .char:
            return kotlinType(type)
        case let .reference(name, _, _):
            if name == "java/lang/Class" { return "kotlin.reflect.KClass<*>" }
            if name.hasPrefix("[") {
                guard let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 else { return nil }
                if element.isNumeric || element == .boolean { return kotlinType(type) }
                guard let elementName = element.referenceName else { return nil }
                let elementType = elementName == "java/lang/Class" ? "kotlin.reflect.KClass<*>" : kotlinType(element)
                return "kotlin.Array<" + elementType + ">"
            }
            return kotlinType(type)
        default:
            return nil
        }
    }

    private func annotationClassDeclaration(_ info: JVMClassInfo, short: String, visibility: String = "", indentation: String = "") -> String {
        var lines: [String] = []
        lines.append("@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.\(javaAnnotationRetention(info.annotations)))")
        if info.repeatableAnnotationContainer != nil {
            lines.append("@kotlin.annotation.Repeatable")
        }
        if let targets = javaAnnotationTargets(info.annotations), !targets.isEmpty {
            lines.append("@kotlin.annotation.Target(" + targets.map { "kotlin.annotation.AnnotationTarget." + $0 }.joined(separator: ", ") + ")")
        }
        let parameters = annotationElements(of: info).enumerated().compactMap { index, element -> String? in
            guard let type = annotationElementKotlinType(element.type) else { return nil }
            let name = JVMProgramBuilder.isIdentifier(element.name) ? "`\(element.name)`" : "p\(index)"
            var parameter = "val \(name): \(type)"
            if let value = element.defaultValue, let rendered = annotationValueSource(value, type: element.type) {
                parameter += " = \(rendered)"
            }
            return parameter
        }.joined(separator: ", ")
        lines.append(visibility + "annotation class `\(short)`(" + parameters + ")")
        return lines.map { indentation + $0 }.joined(separator: "\n") + "\n"
    }

    private func javaAnnotationRetention(_ annotations: [JVMAnnotation]) -> String {
        guard let retention = annotations.first(where: { $0.descriptor == "Ljava/lang/annotation/Retention;" }),
              case let .enumEntry(_, policy)? = retention.values.first(where: { $0.0 == "value" })?.1
        else { return "BINARY" }
        switch policy {
        case "RUNTIME": return "RUNTIME"
        case "SOURCE": return "SOURCE"
        default: return "BINARY"
        }
    }

    private func javaAnnotationTargets(_ annotations: [JVMAnnotation]) -> [String]? {
        guard let target = annotations.first(where: { $0.descriptor == "Ljava/lang/annotation/Target;" }) else { return nil }
        let mapping: [String: [String]] = [
            "TYPE": ["CLASS"],
            "ANNOTATION_TYPE": ["ANNOTATION_CLASS"],
            "METHOD": ["FUNCTION", "PROPERTY_GETTER", "PROPERTY_SETTER"],
            "CONSTRUCTOR": ["CONSTRUCTOR"],
            "FIELD": ["FIELD"],
            "LOCAL_VARIABLE": ["LOCAL_VARIABLE"],
            "PARAMETER": ["VALUE_PARAMETER"],
            "TYPE_PARAMETER": ["TYPE_PARAMETER"],
            "TYPE_USE": ["TYPE"],
        ]
        var names: [String] = []
        func add(_ value: JVMAnnotationValue) {
            switch value {
            case let .enumEntry(_, name):
                for mapped in mapping[name] ?? [] where !names.contains(mapped) { names.append(mapped) }
            case let .array(elements):
                for element in elements { add(element) }
            default:
                break
            }
        }
        for (_, value) in target.values { add(value) }
        return names.isEmpty ? nil : names
    }

    private func annotationValueSource(_ value: JVMAnnotationValue, type: JVMValueType, depth: Int = 0) -> String? {
        guard depth < 64 else { return nil }
        switch value {
        case let .constant(.int(number)):
            return type == .long ? "\(number)L" : "\(number)"
        case let .constant(.long(number)):
            return number == Int64.min ? "kotlin.Long.MIN_VALUE" : "\(number)L"
        case let .constant(.float(number)):
            guard number.isFinite else { return nil }
            return kotlinFloatLiteral(number)
        case let .constant(.double(number)):
            guard number.isFinite else { return nil }
            return kotlinDoubleLiteral(number)
        case let .constant(.boolean(flag)):
            return flag ? "true" : "false"
        case let .constant(.string(string)):
            return kotlinStringLiteral(string)
        case .constant(.null):
            return nil
        case let .integral(number, tag):
            if tag == 67 { return kotlinCharLiteral(number) }
            return "\(number)"
        case let .enumEntry(descriptor, name):
            guard let typeName = annotationDescriptorTypeName(descriptor) else { return nil }
            return typeName + "." + (JVMProgramBuilder.isIdentifier(name) ? name : "`\(name)`")
        case let .classType(descriptor):
            guard let typeName = kotlinClassLiteralType(descriptor) else { return nil }
            return typeName + "::class"
        case let .annotation(annotation):
            return annotationInstanceSource(annotation, depth: depth + 1)
        case let .array(elements):
            guard let elementType = annotationArrayElementType(type) else { return nil }
            var rendered: [String] = []
            for element in elements {
                guard let source = annotationValueSource(element, type: elementType, depth: depth + 1) else { return nil }
                rendered.append(source)
            }
            return "[" + rendered.joined(separator: ", ") + "]"
        }
    }

    private func annotationArrayElementType(_ type: JVMValueType) -> JVMValueType? {
        guard let name = type.referenceName, name.hasPrefix("["),
              let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1
        else { return nil }
        return element
    }

    private func annotationInstanceSource(_ annotation: JVMAnnotation, depth: Int) -> String? {
        guard depth < 64, let typeName = annotationDescriptorTypeName(annotation.descriptor) else { return nil }
        let internalName = String(annotation.descriptor.dropFirst().dropLast())
        let elementTypes = classes[internalName].map { info in
            Dictionary(uniqueKeysWithValues: annotationElements(of: info).map { ($0.name, $0.type) })
        } ?? [:]
        var arguments: [String] = []
        for (name, value) in annotation.values {
            let elementType = elementTypes[name] ?? .reference("java/lang/Object", nullable: false)
            guard let rendered = annotationValueSource(value, type: elementType, depth: depth + 1) else { return nil }
            arguments.append(name + " = " + rendered)
        }
        return typeName + "(" + arguments.joined(separator: ", ") + ")"
    }

    private func annotationDescriptorTypeName(_ descriptor: String) -> String? {
        guard descriptor.hasPrefix("L"), descriptor.hasSuffix(";") else { return nil }
        return Self.dottedTypeName(String(descriptor.dropFirst().dropLast()))
    }

    private func kotlinClassLiteralType(_ descriptor: String) -> String? {
        if descriptor.hasPrefix("L"), descriptor.hasSuffix(";") {
            let name = String(descriptor.dropFirst().dropLast())
            if name == "java/lang/Class" { return "kotlin.reflect.KClass<*>" }
            return kotlinType(.reference(name, nullable: false))
        }
        if descriptor.hasPrefix("[") { return kotlinType(.reference(descriptor, nullable: false)) }
        switch descriptor {
        case "B": return "kotlin.Byte"
        case "C": return "kotlin.Char"
        case "D": return "kotlin.Double"
        case "F": return "kotlin.Float"
        case "I": return "kotlin.Int"
        case "J": return "kotlin.Long"
        case "S": return "kotlin.Short"
        case "Z": return "kotlin.Boolean"
        default: return nil
        }
    }

    private func kotlinFloatLiteral(_ value: Float) -> String {
        let rendered = String(value)
        return rendered + (rendered.contains(".") || rendered.contains("e") || rendered.contains("E") ? "f" : ".0f")
    }

    private func kotlinDoubleLiteral(_ value: Double) -> String {
        let rendered = String(value)
        return rendered.contains(".") || rendered.contains("e") || rendered.contains("E") ? rendered : rendered + ".0"
    }

    private func kotlinStringLiteral(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\0": result += "\\u0000"
            case "$": result += "${'$'}"
            default:
                if scalar.value < 32 || scalar.value == 127 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.append(Character(scalar))
                }
            }
        }
        return result + "\""
    }

    private func kotlinCharLiteral(_ value: Int32) -> String? {
        guard let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: value)) else { return nil }
        switch scalar {
        case "'": return "'\\''"
        case "\\": return "'\\\\'"
        case "\n": return "'\\n'"
        case "\r": return "'\\r'"
        case "\t": return "'\\t'"
        case "\0": return "'\\u0000'"
        default:
            if scalar.value < 32 || scalar.value == 127 { return nil }
            return "'" + String(Character(scalar)) + "'"
        }
    }

    /// Binary class names the frontend already provides: bundled JVM stdlib
    /// sources (which include the JDK platform declarations, scanned after
    /// they are injected) plus synthetic java.* compatibility decls that
    /// `nominalNames` cannot see. java.lang.Object is covered because Kotlin
    /// maps it to Any; java.lang.String stays importable as a classifier while
    /// method signatures still map to kotlin.String. kotlin.*-mapped JDK names
    /// are deliberately NOT covered: the Kotlin declarations are compile-time
    /// views, so the erased classfile still has to come from a stub.
    private func coveredClassNames(in ctx: CompilationContext) throws -> Set<String> {
        var covered = try JVMStdlibCatalog.nominalNames(in: ctx)
        covered.formUnion(Self.syntheticJavaNames)
        covered.insert("java/lang/Object")
        // kotlin.CharSequence is the mapped-type counterpart of
        // java.lang.CharSequence; covering it keeps stub signatures and
        // supertypes on the same Kotlin nominal.
        covered.insert("java/lang/CharSequence")
        // The frontend's CoroutineDispatcher contract already models its
        // CoroutineContext supertypes. An erased stub cannot reconstruct
        // the key passed to AbstractCoroutineContextElement or its generic overrides.
        covered.insert("kotlinx/coroutines/CoroutineDispatcher")
        return covered
    }

    private func isCovered(_ name: String, covered: Set<String>) -> Bool {
        name.hasPrefix("kotlin/") || covered.contains(name)
    }

    func inject(into ctx: CompilationContext) throws {
        let covered = try coveredClassNames(in: ctx)
        activeCoveredNames = covered
        injectComposeUIContracts(into: ctx)
        let projectedComposeMethods = Set(composeStaticContracts.values.map { entry in
            entry.method.owner + "." + entry.method.name + entry.method.descriptor
        })
        if hasMetroRuntime {
            metroDeclarationsFile = ctx.sourceManager.addFile(
                path: JVMMetro.sourcePath, contents: Data(JVMMetro.source.utf8), origin: .residualStdlib
            )
        }
        let neededLazy = lazyClassNames.isEmpty ? nil : referencedLazyClasses(into: ctx, covered: covered)
        let hasIntStateContract = composeIntStateFactory != nil
        for info in classes.values.sorted(by: { $0.name < $1.name }) {
            guard innerClassMetadata[info.name] == nil else { continue }
            // The frontend's Kotlin/JDK mapped declarations carry generic source
            // types. Importing the same erased class again would shadow them.
            if isCovered(info.name, covered: covered) { continue }
            let isLazy = lazyClassNames.contains(info.name)
            let isComposer = hasComposeRuntime && info.name == JVMCompose.composer
            let isIntState = hasIntStateContract && info.name == Self.mutableIntState
            let isGenericState = info.name == Self.mutableState && composeStateFactory != nil
            if isLazy, !isComposer, neededLazy?.contains(info.name) != true { continue }
            let parts = info.name.split(separator: "/").map(String.init)
            guard let short = parts.last else { throw JVMClassReader.Invalid() }
            let package = parts.dropLast().map { "`\($0)`" }.joined(separator: ".")
            var source = package.isEmpty ? "" : "package \(package)\n"
            let own = info.methods.filter(isExposed)
            let statics = own.filter {
                $0.isStatic && !projectedComposeMethods.contains($0.owner + "." + $0.name + $0.descriptor)
            }
            let topLevelProperties = info.kotlinTopLevelProperties.filter {
                $0.getter.parameters.allSatisfy(exposeSuspendType) && exposeSuspendType($0.getter.result)
            }
            let isFileFacade = info.isKotlinFileFacade ?? short.hasSuffix("Kt")
            if info.isAnnotation && own.allSatisfy(\.isStatic) {
                source += "annotation class `\(short)`\n"
            } else if info.flags & 0x4000 != 0 {
                source += enumDeclaration(info, name: short)
            } else if isComposer {
                // The lowering uses the two group operations directly. Keep
                // Composer's implementation types out of the source closure.
                source += "interface `\(short)` {\n"
                for method in info.methods where [JVMCompose.begin, JVMCompose.end].contains(method.name) {
                    source += functionDeclaration(method) + "\n"
                }
                source += "}\n"
            } else if isIntState {
                source += "interface `\(short)` { var intValue: Int }\n"
            } else if isGenericState {
                source += "interface `\(short)`<T> { var value: T }\n"
            } else if isFileFacade {
                // The facade class itself stays importable: `import api.HelloKt`
                // resolves the nominal and `HelloKt.member(...)` reaches its
                // statics through the companion, matching Kotlin/JVM.
                source += "class `\(short)` private constructor() {\n"
                if !statics.isEmpty {
                    source += "companion object {\n"
                    for method in statics {
                        source += "external " + functionDeclaration(method, asFacadeMember: true) + "\n"
                    }
                    source += "}\n"
                }
                source += "}\n"
                for method in statics {
                    if let suspend = method.kotlinSuspendFunction {
                        source += "external " + functionDeclaration(method, asExtension: suspend.receiverIsNullable != nil) + "\n"
                        continue
                    }
                    let composeABI = method.kotlinComposeABI
                    let defaults = composeABI?.defaults == 1
                        || info.isKotlinFileFacade == true && defaultArgumentMethod(for: method, in: info) != nil
                    let annotation = composeABI == nil ? "" : "@androidx.compose.runtime.Composable "
                    source += annotation + "external " + functionDeclaration(method, acceptsDefaults: defaults) + "\n"
                    // Preserve extension syntax for Java-authored facade
                    // shims, where there is no Kotlin receiver metadata.
                    if info.isKotlinFileFacade == nil, method.kotlinFunction == nil,
                       let receiver = method.parameters.first,
                       case .reference = receiver, receiver.referenceName?.hasPrefix("[") != true {
                        let rest = method.parameters.dropFirst().enumerated().map {
                            "p\($0.offset): " + kotlinType($0.element)
                        }.joined(separator: ", ")
                        source += "external fun \(kotlinType(receiver)).`\(method.name)`(\(rest)): \(kotlinType(method.result))\n"
                    }
                }
                for (property, _) in topLevelProperties {
                    let receiver = property.receiver.map { $0 + "." } ?? ""
                    source += "val \(receiver)`\(property.name)`: \(property.result) get() = null!!\n"
                }
            } else {
                if info.flags & 0x2000 != 0 {
                    source += annotationClassDeclaration(info, short: short)
                } else {
                if info.isInterface {
                    source += interfaceKeyword(info) + " `\(short)`"
                    if !info.classTypeParameterNames.isEmpty {
                        source += "<" + info.classTypeParameterNames.map { "`\($0)`" }.joined(separator: ", ") + ">"
                    }
                }
                else {
                    source += info.flags & 0x0400 != 0 ? "abstract class " : (info.flags & 0x0010 != 0 ? "class " : "open class ")
                    source += "`\(short)`"
                    if !info.classTypeParameterNames.isEmpty {
                        source += "<" + info.classTypeParameterNames.map { "`\($0)`" }.joined(separator: ", ") + ">"
                    }
                    source += " "
                    source += own.contains(where: { $0.isConstructor && $0.parameters.isEmpty && !$0.isProtected })
                        ? "()" : "protected constructor()"
                }
                var parents: [String] = []
                if !info.isInterface, let base = info.superclass, classes[base] != nil,
                   let mapped = supertypeReference(base, childParams: info.classTypeParameterNames) {
                    parents.append(mapped + "()")
                }
                parents += info.interfaces.filter {
                    classes[$0] != nil || info.kotlinReadOnlyCollectionSupertypes[$0] != nil
                }.compactMap { supertypeReference($0, child: info) }
                if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
                source += " {\n"
                source += memberDeclarations(info: info, members: info.methods)
                if info.name == Self.compositionLocal, compositionLocalGetter != nil,
                   let type = info.classTypeParameterNames.first {
                    source += "@get:androidx.compose.runtime.Composable val current: `\(type)` get() = null!!\n"
                }
                if info.name == Self.composeView, composeContentMethod != nil {
                    source += "external fun setContent(content: @androidx.compose.runtime.Composable () -> Unit): Unit\n"
                }
                source += nestedClassDeclarations(of: info.name)
                source += "}\n"
                }
            }
            let path = "<kswiftk-jvm-import>/" + info.name + ".kt"
            guard !ctx.sourceManager.containsFile(path: path) else { throw JVMClassReader.Invalid() }
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            if info.isKotlinFileFacade == true {
                kotlinFacadeMethods[file] = statics
                if !topLevelProperties.isEmpty {
                    kotlinFacadeGetters[file] = topLevelProperties.map(\.getter)
                }
            }
        }
        if hasComposeRuntime,
           classes["androidx/compose/runtime/ComposablesKt"]?.methods.contains(where: {
               $0.name == "getCurrentComposer" && $0.isStatic
                   && $0.descriptor == "(L\(JVMCompose.composer);I)L\(JVMCompose.composer);"
           }) == true {
            let source = """
                package androidx.compose.runtime
                val currentComposer: Composer get() = null!!
                """
            _ = ctx.sourceManager.addFile(path: Self.composeIntrinsicPath, contents: Data(source.utf8), origin: .residualStdlib)
        }
    }

    /// Member declarations shared by top-level stubs and nested-class shells:
    /// constructors, methods, synthesized properties, and the statics
    /// companion. Emitted without indentation; Kotlin is brace-delimited.
    private func memberDeclarations(info: JVMClassInfo, members: [JVMForeignMethod], allowsCompanion: Bool = true) -> String {
        let own = members.filter { $0.kotlinSuspendFunction?.receiverIsNullable == nil && isExposed($0) }
        let statics = own.filter { $0.isStatic && $0.kotlinFunction?.valueOperatorParameterDescriptors == nil }
        // Covered Java supertypes render as Kotlin mapped types whose
        // member names differ from the erased classfile signatures; bridge
        // the differences explicitly (see kotlinSupertypeName).
        let numberBridged = !info.isInterface && inheritsJavaType(info, "java/lang/Number")
        let charSequenceBridged = inheritsJavaType(info, "java/lang/CharSequence")
        let appendableBridged = inheritsJavaType(info, "java/lang/Appendable")
        /// kotlin.CharSequence's `get(index: Int): Char` member: either the
        /// classfile's own `get(int)` or a synthesized delegate over `charAt`.
        func isCharSequenceGet(_ method: JVMForeignMethod) -> Bool {
            method.name == "get" && method.parameters.count == 1
                && kotlinType(method.parameters[0]) == "kotlin.Int"
                && kotlinType(method.result) == "kotlin.Char"
        }
        /// The three kotlin.text.Appendable members, matched on erased
        /// parameter types so unrelated `append` overloads stay plain.
        func isAppendableMember(_ method: JVMForeignMethod) -> Bool {
            let types = method.parameters.map { kotlinType($0) }
            return (types.count == 1 && ["kotlin.Char", "kotlin.CharSequence"].contains(types[0]))
                || (types.count == 3 && types[0] == "kotlin.CharSequence" && types[1] == "kotlin.Int" && types[2] == "kotlin.Int")
        }
        /// JavaBeans accessor shape: `getX()` -> property `x` with candidate
        /// setter `setX`; `isX()` -> property `isX` (no setter pairing, matching
        /// the val-only emission below).
        func propertyShape(_ method: JVMForeignMethod) -> (name: String, setterName: String?)? {
            guard method.kotlinSuspendFunction == nil, method.genericResultParameter == nil else { return nil }
            if method.name.hasPrefix("get"), method.name.count > 3 {
                let suffix = String(method.name.dropFirst(3))
                return (String(suffix.prefix(1)).lowercased() + suffix.dropFirst(),
                        "set" + String(suffix.prefix(1)).uppercased() + suffix.dropFirst())
            }
            if method.name.hasPrefix("is"), method.name.count > 2, method.result == .boolean {
                return (method.name, nil)
            }
            return nil
        }
        /// Pairs Java `getX()`/`setX(v)` methods into Kotlin `var` properties.
        /// The JVM emitter binds accesses to the classfile methods directly.
        func memberKey(_ method: JVMForeignMethod) -> String { method.name + method.descriptor }
        // Kotlin exposes array getters paired with Java varargs setters as
        // read-only properties. The varargs method remains callable directly.
        func matchesSetter(_ method: JVMForeignMethod, name: String, type: String) -> Bool {
            method.kotlinSuspendFunction == nil && !method.isConstructor && !method.isStatic && !method.isVarargs && method.name == name
                && method.parameters.count == 1 && kotlinType(method.parameters[0]) == type
        }
        var pairedGetters: Set<String> = []
        for getter in own where !getter.isConstructor && !getter.isStatic
            && getter.parameters.isEmpty {
            guard let setterName = propertyShape(getter)?.setterName else { continue }
            if own.contains(where: {
                matchesSetter($0, name: setterName, type: kotlinType(getter.result))
            }) {
                pairedGetters.insert(memberKey(getter))
            }
        }
        // Interface stubs render every accessor pair as an abstract property,
        // so concrete classes must implement each one — including members the
        // classfile simply lacks (android.jar's java.time stubs are
        // incomplete). Collect the transitive interface property requirements;
        // the getter loop consults them for mutability and a later pass emits
        // `override` stubs for properties nothing implements.
        struct PropertyRequirement { var type: String; var isVar: Bool }
        var requiredProps: [String: PropertyRequirement] = [:]
        var requiredVisited: Set<String> = []
        func collectRequiredProperties(_ interfaceName: String) {
            guard requiredVisited.insert(interfaceName).inserted,
                  let iinfo = classes[interfaceName] else { return }
            for method in iinfo.methods where !method.isStatic && !method.isConstructor
                && method.parameters.isEmpty && expose(method.result)
                && JVMProgramBuilder.isIdentifier(method.name) {
                guard let shape = propertyShape(method) else { continue }
                let isVar = shape.setterName.map { setterName in
                    iinfo.methods.contains {
                        matchesSetter($0, name: setterName, type: kotlinType(method.result))
                    }
                } ?? false
                if var existing = requiredProps[shape.name] {
                    existing.isVar = existing.isVar || isVar
                    requiredProps[shape.name] = existing
                } else {
                    requiredProps[shape.name] = PropertyRequirement(type: kotlinType(method.result), isVar: isVar)
                }
            }
            for parent in iinfo.interfaces { collectRequiredProperties(parent) }
        }
        if !info.isInterface {
            for interfaceName in info.interfaces { collectRequiredProperties(interfaceName) }
        }
        func ancestorHasSetter(_ setterName: String, type: String, startingAt owner: String? = nil) -> Bool {
            var visited: Set<String> = [info.name]
            var next = owner ?? info.superclass
            while let name = next, visited.insert(name).inserted, let sup = classes[name] {
                if sup.methods.contains(where: {
                    matchesSetter($0, name: setterName, type: type)
                }) { return true }
                next = sup.superclass
            }
            return false
        }
        /// Java can narrow a getter's return type while keeping the inherited
        /// setter. Keep the inherited Kotlin property type and the narrower
        /// Java method signature available independently.
        func inheritsWiderMutableProperty(
            _ getter: JVMForeignMethod, propertyName: String, setterName: String, type: String
        ) -> Bool {
            var visited: Set<String> = [info.name]
            var next = info.superclass
            while let name = next, visited.insert(name).inserted, let parent = classes[name] {
                next = parent.superclass
                guard !isCovered(name, covered: activeCoveredNames),
                      !parent.methods.contains(where: { !$0.isStatic && $0.name == propertyName }),
                      let inherited = parent.methods.first(where: {
                          !$0.isStatic && $0.name == getter.name && $0.parameters.isEmpty
                              && expose($0.result) && propertyShape($0) != nil
                      }) else { continue }
                let inheritedType = kotlinType(inherited.result)
                if inheritedType != type, ancestorHasSetter(setterName, type: inheritedType, startingAt: name) {
                    return true
                }
            }
            return false
        }
        var source = ""
        let kotlinProperties = info.kotlinMemberProperties.filter { exposeSuspendType($0.value.getter.result) }
        let instanceFields = info.fields.compactMap { field -> (JVMForeignField, JVMValueType)? in
            guard info.isRuntimeInstanceField(field), JVMProgramBuilder.isIdentifier(field.name),
                  let type = try? JVMDescriptor.parse("()" + field.descriptor).1, exposeSuspendType(type)
            else { return nil }
            return (field, type)
        }
        let instanceFieldNames = Set(instanceFields.map { $0.0.name })
        for method in own where method.isConstructor && !method.parameters.isEmpty {
            source += (method.isProtected ? "protected " : "") + "constructor(" + parameters(method) + ") : this() {}\n"
        }
        for method in own where method.kotlinFunction?.valueOperatorParameterDescriptors != nil {
            source += "external " + functionDeclaration(method) + "\n"
        }
        for method in own where !method.isConstructor && !method.isStatic {
            if let getter = kotlinProperties[method.name]?.getter, getter.descriptor == method.descriptor {
                continue
            }
            var overrides = overridesParent(method, in: info, visited: [])
            if charSequenceBridged, method.name == "subSequence" { overrides = true }
            if charSequenceBridged, isCharSequenceGet(method) { overrides = true }
            if appendableBridged, isAppendableMember(method) { overrides = true }
            if method.isProtected { source += "protected " }
            if !info.isInterface && method.isFinal { source += "final " }
            source += overrides ? "override " : ""
            if !info.isInterface { source += overrides || method.isFinal ? "" : "open " }
            if method.sourceName == "get", method.sourceParameters.count == 1, method.kotlinFunction?.isOperator != true {
                source += "operator "
            }
            if !info.isInterface { source += "external " }
            source += functionDeclaration(method)
            if info.isInterface, !method.isAbstract {
                source += method.sourceResult == .unit ? " {}" : " = null!!"
                // A default method with a primitive result still has a
                // Nothing-typed stub body; it is never emitted or executed.
            }
            source += "\n"
        }
        for getter in own where !getter.isConstructor && !getter.isStatic && getter.parameters.isEmpty {
            guard let shape = propertyShape(getter) else { continue }
            let propertyName = shape.name
            guard JVMProgramBuilder.isIdentifier(propertyName),
                  kotlinProperties[propertyName] == nil,
                  !instanceFieldNames.contains(propertyName),
                  !own.contains(where: { !$0.isStatic && !$0.isConstructor && $0.name == propertyName }) else { continue }
            let propertyType = kotlinType(getter.result)
            if let setterName = shape.setterName,
               inheritsWiderMutableProperty(getter, propertyName: propertyName, setterName: setterName, type: propertyType) {
                continue
            }
            var modifiers = ""
            if getter.isProtected && !info.isInterface { modifiers += "protected " }
            if !info.isInterface && getter.isFinal { modifiers += "final " }
            if overridesParent(getter, in: info, visited: []) { modifiers += "override " }
            else if !info.isInterface && !getter.isFinal { modifiers += "open " }
            if info.isInterface {
                // Abstract: a concrete interface property would make every
                // diamond inherit two implementations (KSWIFTK-SEMA-0171).
                source += modifiers + (pairedGetters.contains(memberKey(getter)) ? "var" : "val")
                    + " `\(propertyName)`: \(propertyType)\n"
                continue
            }
            // Accessors are declarations for Sema. Placeholder bodies avoid
            // re-resolving Java calls throughout generated SDK stubs.
            let isVar = pairedGetters.contains(memberKey(getter))
                || shape.setterName.map { ancestorHasSetter($0, type: propertyType) } == true
                || requiredProps[propertyName]?.isVar == true
            if isVar {
                source += modifiers + "var `\(propertyName)`: \(propertyType) get() = null!! set(value) {}\n"
            } else {
                source += modifiers + "val `\(propertyName)`: \(propertyType) get() = null!!\n"
            }
        }
        for (name, property) in kotlinProperties.sorted(by: { $0.key < $1.key }) {
            let getter = property.getter
            if !getter.isStatic, overridesParent(getter, in: info, visited: []) {
                source += getter.isFinal ? "final override " : "override "
            } else if !info.isInterface && !getter.isFinal {
                source += "open "
            }
            source += "val `\(name)`: \(property.sourceType)" + (info.isInterface ? "\n" : " get() = null!!\n")
        }
        for (field, type) in instanceFields {
            let setter = field.isFinal ? "" : " set(value) {}"
            // Preserve the existing override relationship when this field
            // replaces a projected accessor on the same class.
            let overrides = own.contains {
                !$0.isStatic && $0.parameters.isEmpty && $0.result.descriptor == field.descriptor
                    && propertyShape($0)?.name == field.name && overridesParent($0, in: info, visited: [])
            }
            source += (overrides ? "override " : "") + (field.isFinal ? "val" : "var")
                + " `\(field.name)`: \(kotlinType(type)) get() = null!!" + setter + "\n"
        }
        // Concrete classes must implement every abstract property the
        // transitive interfaces declare; classfiles occasionally omit the
        // accessor (android.jar java.time), so emit a stub override.
        if !info.isInterface, info.flags & 0x0400 == 0, !requiredProps.isEmpty {
            var implemented = Set<String>()
            func collect(_ methods: [JVMForeignMethod]) {
                for method in methods where !method.isConstructor && !method.isStatic
                    && method.parameters.isEmpty && expose(method.result) {
                    if let shape = propertyShape(method) { implemented.insert(shape.name) }
                }
            }
            collect(own)
            var visitedSup: Set<String> = [info.name]
            var nextSup = info.superclass
            while let supName = nextSup, visitedSup.insert(supName).inserted,
                  let sup = classes[supName] {
                collect(sup.methods)
                nextSup = sup.superclass
            }
            for name in requiredProps.keys.sorted() where !implemented.contains(name) {
                let requirement = requiredProps[name]!
                source += "override " + (requirement.isVar ? "var" : "val")
                    + " `\(name)`: \(requirement.type) get() = null!!"
                if requirement.isVar { source += " set(value) {}" }
                source += "\n"
            }
        }
        if charSequenceBridged, !own.contains(where: { isCharSequenceGet($0) && !$0.isStatic }),
           let charAt = own.first(where: {
               $0.name == "charAt" && $0.parameters.count == 1 && !$0.isStatic
           }) {
            source += "override operator fun `get`(" + parameters(charAt) + "): "
                + kotlinType(charAt.result) + " = `charAt`(p0)\n"
        }
        if charSequenceBridged {
            let hasLengthProperty = own.contains {
                ($0.name == "getLength" || $0.name == "isLength")
                    && $0.parameters.isEmpty && !$0.isStatic
            }
            if !hasLengthProperty, own.contains(where: {
                $0.name == "length" && $0.parameters.isEmpty && !$0.isStatic && kotlinType($0.result) == "kotlin.Int"
            }) {
                source += "override val `length`: kotlin.Int get() = `length`()\n"
            }
        }
        if numberBridged {
            // kotlin.Number spells Java's *Value methods as to*(); each
            // Kotlin member delegates to its erased classfile counterpart.
            let bridges: [(String, String, String)] = [
                ("toByte", "byteValue", "kotlin.Byte"),
                ("toShort", "shortValue", "kotlin.Short"),
                ("toInt", "intValue", "kotlin.Int"),
                ("toLong", "longValue", "kotlin.Long"),
                ("toFloat", "floatValue", "kotlin.Float"),
                ("toDouble", "doubleValue", "kotlin.Double"),
            ]
            for (toName, javaName, returnType) in bridges {
                let hasJavaMethod = own.contains {
                    $0.name == javaName && $0.parameters.isEmpty && !$0.isStatic
                }
                source += "override fun `\(toName)`(): \(returnType) = "
                    + (hasJavaMethod ? "`\(javaName)`()" : "null!!") + "\n"
            }
        }
        /// `static final` fields with a `ConstantValue` attribute render as
        /// Kotlin `const val`s inside the companion object, matching how
        /// kotlinc exposes Java constants (e.g. `LinearLayout.VERTICAL`).
        func constantField(_ field: JVMForeignField) -> String? {
            guard field.isStatic, field.isFinal, field.isPublic,
                  field.constantValue != nil, JVMProgramBuilder.isIdentifier(field.name),
                  let type = try? JVMDescriptor.parse("()" + field.descriptor).1,
                  expose(type) else { return nil }
            let kotlin = kotlinType(type)
            let literal: String
            switch (field.constantValue!, kotlin) {
            case (.int(let v), "kotlin.Boolean"): literal = v != 0 ? "true" : "false"
            case (.int(let v), "kotlin.Char"): literal = String(format: "'\\u%04X'", UInt32(bitPattern: v))
            case (.int(let v), let t) where ["kotlin.Byte", "kotlin.Short", "kotlin.Int"].contains(t):
                literal = String(v)
            case (.long(let v), "kotlin.Long"):
                // The magnitude of Int64.min cannot be parsed as a signed literal.
                literal = v == Int64.min ? "kotlin.Long.MIN_VALUE" : String(v)
            case (.float(let v), "kotlin.Float") where v.isFinite:
                literal = "\(v)f"
            case (.double(let v), "kotlin.Double") where v.isFinite:
                literal = "\(v)"
            case (.string(let s), "kotlin.String"):
                var escaped = "\""
                for scalar in s.unicodeScalars {
                    switch scalar {
                    case "\\": escaped += "\\\\"
                    case "\"": escaped += "\\\""
                    case "\n": escaped += "\\n"
                    case "\r": escaped += "\\r"
                    case "\t": escaped += "\\t"
                    case "$": escaped += "\\$"
                    default: escaped.unicodeScalars.append(scalar)
                    }
                }
                literal = escaped + "\""
            default: return nil
            }
            return "const val `\(field.name)`: \(kotlin) = \(literal)\n"
        }
        let constantFields = info.fields.compactMap(constantField)
        let runtimeFields = info.fields.compactMap { field -> String? in
            guard let type = runtimeStaticFieldType(field, in: info) else { return nil }
            let keyword = field.isFinal ? "val" : "var"
            let setter = field.isFinal ? "" : " set(value) {}"
            return "\(keyword) `\(field.name)`: \(kotlinType(type)) get() = null!!\(setter)\n"
        }
        let companion = allowsCompanion ? kotlinCompanion(of: info) : nil
        if allowsCompanion, companion != nil || !statics.isEmpty || !constantFields.isEmpty || !runtimeFields.isEmpty {
            source += "companion object"
            if let companion {
                let parents = companion.interfaces.filter { classes[$0] != nil }.compactMap {
                    supertypeReference($0, child: companion)
                }
                if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
            }
            source += " {\n"
            for declaration in constantFields { source += declaration }
            for declaration in runtimeFields { source += declaration }
            for (name, property) in info.kotlinStaticProperties.sorted(by: { $0.key < $1.key })
                where isExposed(property.getter) {
                let type = kotlinType(property.getter.result) + (property.isNullable ? "?" : "")
                source += "val `\(name)`: \(type) get() = null!!\n"
            }
            for method in statics {
                source += "external " + functionDeclaration(method) + "\n"
            }
            if let companion {
                for (name, property) in companion.kotlinMemberProperties.sorted(by: { $0.key < $1.key })
                    where exposeSuspendType(property.getter.result) && info.kotlinStaticProperties[name] == nil {
                    source += "val `\(name)`: \(property.sourceType) get() = null!!\n"
                }
                for method in companion.methods where !method.isStatic && !method.isConstructor && isExposed(method) {
                    if statics.contains(where: { $0.name == method.name && $0.descriptor == method.descriptor })
                        && !overridesParent(method, in: companion, visited: []) { continue }
                    if companion.kotlinMemberProperties.values.contains(where: {
                        $0.getter.name == method.name && $0.getter.descriptor == method.descriptor
                    }) { continue }
                    if overridesParent(method, in: companion, visited: [])
                        || ["toString()Ljava/lang/String;", "hashCode()I", "equals(Ljava/lang/Object;)Z"].contains(method.name + method.descriptor) {
                        source += "override "
                    }
                    source += "external " + functionDeclaration(method) + "\n"
                }
            }
            source += "}\n"
        }
        return source
    }

    private func runtimeStaticFieldType(_ field: JVMForeignField, in info: JVMClassInfo) -> JVMValueType? {
        guard info.isRuntimeStaticField(field), JVMProgramBuilder.isIdentifier(field.name),
              let type = try? JVMDescriptor.parse("()" + field.descriptor).1, expose(type) else { return nil }
        return type
    }

    // MARK: - Lazy classpath injection

    /// Packages Kotlin auto-imports on the JVM. Lazy classpath entries can
    /// live in any package, but unqualified lookup only needs these; explicit
    /// imports, star imports, and same-package references are matched separately.
    private static let autoImportedPackages: Set<String> = [
        "java.lang", "kotlin.jvm",
    ]

    /// JDK binary names that Kotlin maps onto standard-library declarations,
    /// matching kotlinc's mapped types (java.util.List <-> kotlin.collections.List
    /// etc.). Generic targets use star projections because classfiles carry no
    /// type arguments. Only types whose Kotlin counterpart is provided by the
    /// frontend's stdlib catalog belong here.
    private static let jdkToKotlinTypeNames: [String: String] = [
        "java/lang/CharSequence": "kotlin.CharSequence",
        "java/lang/Comparable": "kotlin.Comparable<*>",
        "java/lang/Cloneable": "kotlin.Cloneable",
        "java/lang/Throwable": "kotlin.Throwable",
        "java/lang/Exception": "kotlin.Exception",
        "java/lang/RuntimeException": "kotlin.RuntimeException",
        "java/lang/Error": "kotlin.Error",
        "java/lang/Integer": "kotlin.Int",
        "java/lang/Long": "kotlin.Long",
        "java/lang/Double": "kotlin.Double",
        "java/lang/Float": "kotlin.Float",
        "java/lang/Boolean": "kotlin.Boolean",
        "java/lang/Byte": "kotlin.Byte",
        "java/lang/Short": "kotlin.Short",
        "java/lang/Character": "kotlin.Char",
        "java/lang/Void": "kotlin.Unit",
        "java/lang/Number": "kotlin.Number",
        "java/lang/StringBuilder": "kotlin.text.StringBuilder",
        "java/lang/Appendable": "kotlin.text.Appendable",
        "java/lang/Deprecated": "kotlin.Deprecated",
        "java/lang/Enum": "kotlin.Enum<*>",
        "java/lang/Iterable": "kotlin.collections.Iterable<*>",
        "java/util/Iterator": "kotlin.collections.Iterator<*>",
        "java/util/Collection": "kotlin.collections.Collection<*>",
        "java/util/List": "kotlin.collections.List<*>",
        "java/util/Set": "kotlin.collections.Set<*>",
        "java/util/Map": "kotlin.collections.Map<*, *>",
        "java/util/ListIterator": "kotlin.collections.ListIterator<*>",
        "java/util/Map$Entry": "kotlin.collections.Map.Entry<*, *>",
        // SequencedCollection.reversed() covariantly returns List while its
        // own signature erases to SequencedCollection; mapping the erased
        // name to Collection keeps the stub override return-compatible.
        "java/util/SequencedCollection": "kotlin.collections.Collection<*>",
        "java/util/SequencedSet": "kotlin.collections.Set<*>",
    ]

    /// java.* classpath entries that the frontend already provides through
    /// synthetic HeaderHelpers declarations rather than bundled sources, so
    /// `nominalNames` cannot see them. Injecting stubs for these would
    /// redeclare the same nominal and fail semantic analysis.
    private static let syntheticJavaNames: Set<String> = [
        // java.io stream/file surface synthesized for kotlin.io interop
        // (HeaderHelpers+SyntheticJavaIOStreamStubs).
        "java/io/Closeable", "java/io/File", "java/io/InputStream",
        "java/io/OutputStream", "java/io/ByteArrayInputStream",
        "java/io/ByteArrayOutputStream", "java/io/BufferedInputStream",
        "java/io/BufferedReader", "java/io/BufferedWriter",
        "java/io/Reader", "java/io/SequenceInputStream", "java/io/Writer",
        // java.lang compatibility anchors.
        "java/lang/AutoCloseable", "java/lang/ClassLoader",
        // java.math/java.util anchors from the String/Char stub registrations.
        "java/math/BigDecimal", "java/util/Locale",
        // java.util.concurrent.atomic scalar/reference/array family
        // (HeaderHelpers+SyntheticAtomicResidualRegistry).
        "java/util/concurrent/atomic/AtomicInteger",
        "java/util/concurrent/atomic/AtomicLong",
        "java/util/concurrent/atomic/AtomicBoolean",
        "java/util/concurrent/atomic/AtomicReference",
        "java/util/concurrent/atomic/AtomicReferenceArray",
        "java/util/concurrent/atomic/AtomicIntegerArray",
        "java/util/concurrent/atomic/AtomicLongArray",
        // java.lang names that would shadow Kotlin declarations through the
        // java.lang auto-import or same-package resolution. Other java.lang
        // classes (CharSequence, Comparable, exceptions, ...) are still
        // injected: stubs need them as resolvable supertypes, and Kotlin's
        // own declarations win unqualified lookups.
        "java/lang/Boolean", "java/lang/Byte", "java/lang/Short",
        "java/lang/Integer", "java/lang/Long", "java/lang/Float",
        "java/lang/Double", "java/lang/Void", "java/lang/Number",
        "java/lang/StringBuilder", "java/lang/Appendable",
        "java/lang/Deprecated",
    ]

    private static let identifierPattern = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#)
    private static let dottedPattern = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+"#)
    private static let starImportPattern = try! NSRegularExpression(pattern: #"import\s+([A-Za-z_][A-Za-z0-9_.]*?)\.\*"#)
    private static let packagePattern = try! NSRegularExpression(pattern: #"^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)"#, options: [.anchorsMatchLines])

    /// Computes the set of lazy classpath classes that must be injected:
    /// classes named by user sources (imports, qualified references,
    /// star/auto/same-package lookups) and fully-qualified references in
    /// injected JVM stdlib sources, plus the transitive closure over
    /// supertypes and emitted method signature types.
    private func referencedLazyClasses(into ctx: CompilationContext, covered: Set<String>) -> Set<String> {
        // normalized dotted name -> binary class names ("a.b.C.D" may come
        // from either a/b/C$D or a/b/C/D, so keep every candidate).
        var normalizedToBinary: [String: [String]] = [:]
        var lazyTopLevelByPackage: [String: [(short: String, name: String)]] = [:]
        var facadesByCallable: [String: [String]] = [:]
        var lazyCallablesByPackage: [String: [(short: String, name: String)]] = [:]
        for name in lazyClassNames {
            let normalized = name.split(separator: "/")
                .map(String.init).joined(separator: ".")
                .replacingOccurrences(of: "$", with: ".")
            normalizedToBinary[normalized, default: []].append(name)
            let parts = name.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let package = parts.dropLast().joined(separator: ".")
            let short = parts.last!.split(separator: "$").last.map(String.init) ?? parts.last!
            if !name.contains("$") {
                lazyTopLevelByPackage[package, default: []].append((short, name))
            }
            // Imports name Kotlin callables by package, not their JVM facade.
            if let info = classes[name], info.isKotlinFileFacade == true, !isCovered(name, covered: covered) {
                let functions = Set(info.methods.filter { $0.isStatic && isExposed($0) }.map(\.sourceName)
                    + info.kotlinTopLevelProperties.map { $0.source.name })
                for function in functions {
                    facadesByCallable[package + "." + function, default: []].append(name)
                    lazyCallablesByPackage[package, default: []].append((function, name))
                }
            }
        }

        var matched = Set<String>()
        func matchTokenPrefixes(_ token: String, includeCallables: Bool = false) {
            let parts = token.split(separator: ".").map(String.init)
            for end in 1...parts.count {
                let prefix = parts.prefix(end).joined(separator: ".")
                if let binaries = normalizedToBinary[prefix] { matched.formUnion(binaries) }
                if includeCallables, let facades = facadesByCallable[prefix] { matched.formUnion(facades) }
            }
        }
        func identifierMatches(identifiers: Set<String>, packages: Set<String>, includeCallables: Bool) {
            for package in packages {
                for entry in lazyTopLevelByPackage[package] ?? [] where identifiers.contains(entry.short) {
                    matched.insert(entry.name)
                }
                if includeCallables {
                    for entry in lazyCallablesByPackage[package] ?? [] where identifiers.contains(entry.short) {
                        matched.insert(entry.name)
                    }
                }
            }
        }

        // Projected Compose calls can name a scope that the app only uses as
        // an implicit lambda receiver, so their signatures also seed the closure.
        for file in ctx.sourceManager.fileIDs() {
            let origin = ctx.sourceManager.origin(of: file)
            let isComposeContract = composeStaticContracts[file] != nil
            guard isComposeContract || origin == .residualStdlib
                || (origin == .user && !ctx.sourceManager.path(of: file).hasPrefix("<kswiftk-jvm>/"))
            else { continue }
            let text = String(decoding: ctx.sourceManager.contents(of: file), as: UTF8.self)
            let range = NSRange(text.startIndex..., in: text)
            if origin == .residualStdlib, !isComposeContract {
                // Bundled JVM declarations reference JDK types by FQN; the
                // identifier/same-package heuristics would mistake stdlib
                // declarations for classpath references.
                for match in Self.dottedPattern.matches(in: text, range: range) {
                    if let r = Range(match.range, in: text) { matchTokenPrefixes(String(text[r])) }
                }
                continue
            }
            var identifiers = Set<String>()
            for match in Self.identifierPattern.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { identifiers.insert(String(text[r])) }
            }
            let includeCallables = origin == .user
            var starPackages = Self.autoImportedPackages
            if let match = Self.packagePattern.firstMatch(in: text, range: range),
               let r = Range(match.range(at: 1), in: text) {
                starPackages.insert(String(text[r]))
            }
            for match in Self.starImportPattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) { starPackages.insert(String(text[r])) }
            }
            for match in Self.dottedPattern.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { matchTokenPrefixes(String(text[r]), includeCallables: includeCallables) }
            }
            identifierMatches(identifiers: identifiers, packages: starPackages, includeCallables: includeCallables)
        }

        // Map every matched name (inner classes included) to its top-level
        // owner; only top-level classes are emitted by inject(into:).
        var needed = Set<String>()
        var queue: [String] = []
        func isInjected(_ name: String) -> Bool {
            guard let info = classes[name] else { return false }
            return !isCovered(info.name, covered: covered)
        }
        func markNeeded(_ name: String) {
            var top = name
            while let outer = innerClassMetadata[top]?.outerName { top = outer }
            if lazyClassNames.contains(top), isInjected(top), needed.insert(top).inserted { queue.append(top) }
        }
        for name in matched { markNeeded(name) }
        func signatureNames(_ type: JVMValueType) -> [String] {
            guard let name = type.referenceName else { return [] }
            var n = name
            while n.hasPrefix("[") { n.removeFirst() }
            if n.hasPrefix("L"), n.hasSuffix(";") { n = String(n.dropFirst().dropLast()) }
            return n.contains("/") ? [n] : []
        }
        var edgeProcessed = Set<String>()
        func processEdges(_ name: String) {
            guard edgeProcessed.insert(name).inserted, let info = classes[name] else { return }
            if info.isAnnotation && info.methods.allSatisfy(\.isStatic) || hasComposeRuntime && name == JVMCompose.composer { return }
            for parent in [info.superclass].compactMap({ $0 }) + info.interfaces {
                // Covered supertypes render as Kotlin/platform names and need
                // no stub; every other lazy supertype joins the closure.
                if lazyClassNames.contains(parent), isInjected(parent) {
                    markNeeded(parent)
                }
            }
            for field in info.fields {
                if let type = runtimeStaticFieldType(field, in: info)
                    ?? (info.isRuntimeInstanceField(field) ? try? JVMDescriptor.parse("()" + field.descriptor).1 : nil) {
                    for ref in signatureNames(type) { markNeeded(ref) }
                }
            }
            func markSourceTypes(_ types: [String]) {
                for type in types {
                    let range = NSRange(type.startIndex..., in: type)
                    for match in Self.dottedPattern.matches(in: type, range: range) {
                        guard let token = Range(match.range, in: type) else { continue }
                        for name in normalizedToBinary[String(type[token])] ?? [] { markNeeded(name) }
                    }
                }
            }
            for (property, _) in info.kotlinTopLevelProperties {
                markSourceTypes([property.result] + [property.receiver].compactMap { $0 })
            }
            markSourceTypes(info.kotlinMemberProperties.values.map(\.sourceType))
            for method in info.methods where isExposed(method) {
                for type in method.sourceParameters + [method.sourceResult] {
                    for ref in signatureNames(type)
                    where lazyClassNames.contains(ref) && isInjected(ref) {
                        markNeeded(ref)
                    }
                }
                // Kotlin metadata can name types erased from the descriptor,
                // such as a parameter of a Compose receiver lambda.
                if let function = method.kotlinFunction {
                    let sourceTypes = (function.contextParameters + function.parameters).map(\.sourceType)
                        + [function.result] + [function.receiver].compactMap { $0 }
                    markSourceTypes(sourceTypes)
                }
                if let function = method.kotlinSuspendFunction {
                    markSourceTypes(function.parameters.compactMap(\.sourceType))
                }
            }
            // Nested classes are emitted inside their owner's stub but are
            // not worklist items themselves; their signature types still
            // need to join the closure.
            for entry in innerClassMetadata.values where entry.outerName == name {
                if classes[entry.name] != nil { processEdges(entry.name) }
            }
        }
        // Every eagerly injected class can reference lazy types in its own
        // emitted signatures, so their edges seed the closure as well.
        for name in classes.keys where !lazyClassNames.contains(name) && isInjected(name) {
            processEdges(name)
        }
        while let name = queue.popLast() { processEdges(name) }
        return needed
    }

    /// Whether a classpath parent renders as a Kotlin declaration rather
    /// than an injected stub, i.e. `kotlinSupertypeName` maps it onto a
    /// provided kotlin.* nominal. Such parents' members cannot be matched
    /// against erased classfile signatures for `override` purposes.
    private func resolvesToKotlinDecl(_ name: String) -> Bool {
        activeCoveredNames.contains(name) && Self.jdkToKotlinTypeNames[name] != nil
    }

    /// Whether `info` inherits the given Java class through its superclass
    /// or interface chain (erased classfile names).
    private func inheritsJavaType(_ info: JVMClassInfo, _ target: String) -> Bool {
        var visited = Set<String>()
        var queue = [info.superclass].compactMap { $0 } + info.interfaces
        while let name = queue.popLast() {
            if name == target { return true }
            guard visited.insert(name).inserted, let parent = hierarchyClasses[name] else { continue }
            queue.append(contentsOf: [parent.superclass].compactMap { $0 } + parent.interfaces)
        }
        return false
    }

    private func defaultArgumentMethod(for method: JVMForeignMethod, in info: JVMClassInfo) -> JVMForeignMethod? {
        guard method.isStatic, let function = method.kotlinFunction, !function.isSuspend,
              function.contextParameters.isEmpty,
              function.parameters.contains(where: \.hasDefaultValue),
              method.parameters.count == function.parameters.count + function.leadingParameterCount
        else { return nil }
        let masks = String(repeating: "I", count: (function.parameters.count + 31) / 32)
        let descriptor = "(" + method.parameters.map(\.descriptor).joined() + masks + "Ljava/lang/Object;)" + method.result.descriptor
        return info.defaultArgumentMethods.first {
            $0.isStatic && $0.name == method.name + "$default" && $0.descriptor == descriptor
        }
    }

    private func functionDeclaration(_ method: JVMForeignMethod, asExtension: Bool = false, asFacadeMember: Bool = false, acceptsDefaults: Bool = false) -> String {
        if let function = method.kotlinFunction {
            return kotlinFunctionDeclaration(function, asFacadeMember: asFacadeMember, acceptsDefaults: acceptsDefaults)
        }
        let suspend = method.kotlinSuspendFunction
        var receiver = ""
        if asExtension, let type = method.sourceParameters.first {
            receiver = kotlinType(type) + (suspend?.receiverIsNullable == true ? "?." : ".")
        }
        let result = method.genericResultParameter.map { "`\($0.name)`" }
            ?? (kotlinType(method.sourceResult) + (suspend != nil && method.sourceResult.isNullable ? "?" : ""))
        let generic = method.genericResultParameter.map { parameter -> String in
            let resultType = kotlinType(method.result)
            let bound = resultType == "kotlin.Any" ? "kotlin.Any?" : resultType
            return "<`\(parameter.name)`: \(bound)> "
        } ?? ""
        let modifier = suspend == nil ? "" : "suspend "
        return modifier + "fun " + generic + "\(receiver)`\(method.sourceName)`(" + parameters(method, droppingReceiver: asExtension) + "): " + result
    }

    private func kotlinFunctionDeclaration(_ function: JVMKotlinFunction, asFacadeMember: Bool, acceptsDefaults: Bool) -> String {
        // Parenthesize function types so the dot binds to the entire receiver.
        let receiver = asFacadeMember ? "" : function.receiver.map { $0.contains("->") ? "(\($0))." : $0 + "." } ?? ""
        let context = function.contextParameters.enumerated().map { index, parameter in
            let name = parameter.name.flatMap { JVMProgramBuilder.isIdentifier($0) ? $0 : nil } ?? "context\(index)"
            return "`\(name)`: " + parameter.sourceType
        }
        let prefix = asFacadeMember || context.isEmpty ? "" : "context(" + context.joined(separator: ", ") + ") "
        let receiverParameter = asFacadeMember ? context + (function.receiver.map { ["p\(context.count): " + $0] } ?? []) : []
        let parameters = receiverParameter + function.parameters.enumerated().map { index, parameter in
            let fallback = "p\(index + receiverParameter.count)"
            let name = receiverParameter.isEmpty ? parameter.name.map { JVMProgramBuilder.isIdentifier($0) ? "`\($0)`" : fallback } ?? fallback : fallback
            // Sema only needs the presence of a default. The classfile
            // helper evaluates its actual value at the call site.
            let defaultValue = acceptsDefaults && parameter.hasDefaultValue ? " = null!!" : ""
            let inlineModifier = function.hasInlineContextCallback && !asFacadeMember
                ? (parameter.isCrossinline ? "crossinline " : parameter.isNoinline ? "noinline " : "") : ""
            return inlineModifier + (parameter.isVararg ? "vararg " : "") + name + ": " + parameter.sourceType + defaultValue
        }
        let typeNames = function.typeParameters.map { "`\($0.name)`" }
        let generics = typeNames.isEmpty ? "" : "<" + typeNames.joined(separator: ", ") + "> "
        let bounds = function.typeParameters.flatMap { parameter in
            parameter.bounds.map { "`\(parameter.name)`: " + $0 }
        }
        let whereClause = bounds.isEmpty ? "" : " where " + bounds.joined(separator: ", ")
        let inline = function.hasInlineContextCallback && !asFacadeMember ? "inline " : ""
        let operatorModifier = function.isOperator && !asFacadeMember ? "operator " : ""
        let infix = function.isInfix && !asFacadeMember ? "infix " : ""
        return prefix + inline + operatorModifier + infix + (function.isSuspend ? "suspend " : "") + "fun \(generics)\(receiver)`\(function.name)`("
            + parameters.joined(separator: ", ") + "): " + function.result + whereClause
    }

    private func parameters(_ method: JVMForeignMethod, droppingReceiver: Bool = false) -> String {
        let suspend = method.kotlinSuspendFunction
        let types = method.sourceParameters.dropFirst(droppingReceiver ? 1 : 0)
        let receiverInParameters = suspend?.receiverIsNullable != nil && !droppingReceiver
        let names = suspend?.parameters.compactMap(\.name) ?? []
        let useNames = names.count == suspend?.parameters.count && names.allSatisfy(JVMProgramBuilder.isIdentifier)
            && Set(names).count == names.count
        return types.enumerated().map { index, parameter in
            let isVararg = method.isVarargs && index == types.count - 1
            let name: String
            let nullable: Bool
            let suspendSourceType: String?
            if receiverInParameters && index == 0 {
                name = "`$receiver`"
                nullable = suspend?.receiverIsNullable == true
                suspendSourceType = nil
            } else if let suspend {
                let metadataIndex = index - (receiverInParameters ? 1 : 0)
                name = useNames ? "`\(names[metadataIndex])`" : "p\(index)"
                nullable = suspend.parameters[metadataIndex].isNullable
                suspendSourceType = suspend.parameters[metadataIndex].sourceType
            } else {
                name = "p\(index)"
                nullable = false
                suspendSourceType = nil
            }
            let parameterType: String
            if let generic = method.genericResultParameter, generic.classParameterIndices.contains(index) {
                parameterType = "java.lang.Class<`\(generic.name)`>"
            } else if isVararg, let name = parameter.referenceName, name.hasPrefix("["),
               let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 {
                parameterType = kotlinType(element)
            } else {
                parameterType = kotlinType(parameter)
            }
            return (isVararg ? "vararg " : "") + name + ": "
                + (suspendSourceType ?? (parameterType + (nullable ? "?" : "")))
        }.joined(separator: ", ")
    }

    private func overridesParent(_ method: JVMForeignMethod, in info: JVMClassInfo, visited: Set<String>) -> Bool {
        guard !visited.contains(info.name) else { return false }
        if ["toString()Ljava/lang/String;", "hashCode()I", "equals(Ljava/lang/Object;)Z"].contains(method.name + method.descriptor) { return true }
        let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
        for parentName in ([info.superclass].compactMap { $0 } + info.interfaces) {
            // java.lang.Object maps to kotlin.Any, which only provides
            // toString/hashCode/equals (already handled above). Its other
            // members (clone, finalize, wait, ...) have no Kotlin
            // counterpart, so treating them as overridden parents would
            // emit `override` for declarations that resolve to nothing.
            // The same applies to covered parents that render as Kotlin
            // mapped types (kotlin.Number, kotlin.CharSequence,
            // kotlin.text.Appendable): their Kotlin member sets differ
            // from the erased classfile signatures, so memberDeclarations
            // bridges the differences explicitly instead.
            if parentName == "java/lang/Object" || resolvesToKotlinDecl(parentName)
                || info.kotlinReadOnlyCollectionSupertypes[parentName] != nil {
                // Only the Kotlin read-only list contract declares subList.
                if parentName == "java/util/List", method.name == "subList",
                   info.kotlinReadOnlyCollectionSupertypes[parentName] != nil { return true }
                continue
            }
            guard let parent = classes[parentName] else { continue }
            if parent.methods.contains(where: { !$0.isStatic && !$0.isConstructor && $0.name + $0.descriptor.prefix(through: $0.descriptor.firstIndex(of: ")")!) == key }) { return true }
            if overridesParent(method, in: parent, visited: visited.union([info.name])) { return true }
        }
        return false
    }
    /// Converts foreign reference signatures to Kotlin platform types after
    /// header collection and before any user body is checked.
    func bind(in ctx: CompilationContext, sema: SemaModule) throws {
        var facadeMethodsByRange: [SourceRange: JVMForeignMethod] = [:]
        if let ast = ctx.ast {
            for file in ast.files {
                if let getters = kotlinFacadeGetters[file.fileID] {
                    let properties = file.topLevelDecls.filter { declaration in
                        if case .propertyDecl = ast.arena.decl(declaration) { return true }
                        return false
                    }
                    if properties.count == getters.count {
                        for (declaration, getter) in zip(properties, getters) {
                            if let symbol = sema.bindings.declSymbol(for: declaration) {
                                importedTopLevelGetters[symbol] = getter
                            }
                        }
                    }
                }
                guard let methods = kotlinFacadeMethods[file.fileID] else { continue }
                let functions = file.topLevelDecls.compactMap { declaration -> FunDecl? in
                    guard case let .funDecl(function) = ast.arena.decl(declaration) else { return nil }
                    return function
                }
                guard functions.count == methods.count else { continue }
                // Top-level Kotlin facade stubs are emitted in classfile order.
                // Their logical signature can differ from the physical descriptor.
                for (function, method) in zip(functions, methods)
                    where method.kotlinFunction != nil || method.kotlinSuspendFunction != nil {
                    facadeMethodsByRange[function.range] = method
                }
            }
        }
        func platform(_ type: TypeID) -> TypeID {
            switch sema.types.kind(of: type) {
            case .classType, .stringStruct, .any, .typeParam: return sema.types.withNullability(.platformType, for: type)
            default: return type
            }
        }
        for symbol in sema.symbols.allSymbols() {
            guard let site = symbol.declSite, symbol.kind == .function || symbol.kind == .constructor,
                  let signature = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let name = symbol.kind == .constructor ? "<init>" : ctx.interner.resolve(symbol.name)
            if let contract = composeStaticContracts[site.start.file], symbol.kind == .function {
                methods[symbol.id] = contract.method
                importedComposeCalls[symbol.id] = contract.composable
                if contract.composable?.hasExtensionReceiver == true { extensionSymbols.insert(symbol.id) }
                continue
            }
            if name == "setContent", sourceClasses[site.start.file]?.name == Self.composeView,
               let method = composeContentMethod {
                methods[symbol.id] = method
                composeContentSymbols.insert(symbol.id)
                continue
            }
            let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol)
            let sourceClass = sourceClasses[site.start.file]
            let topLevel = sourceClass.flatMap { _ in topLevelFunction(at: site, in: ctx) }
            let isTopLevel = topLevel != nil || parent?.kind == .package
            let isStaticCompanion = parent.map { $0.kind == .object && ctx.interner.resolve($0.name) == "Companion" } ?? false
            // Nested stubs share the outer class's file, so sourceClasses
            // alone cannot identify the declaring classfile. Walk the
            // nominal parent chain to the nearest class that has one
            // (a synthesized Companion object resolves to its outer class).
            // Top-level extensions may have their receiver as semantic parent.
            var owner = isTopLevel ? nil : sema.symbols.parentSymbol(for: symbol.id)
            if isStaticCompanion, let companion = owner {
                owner = sema.symbols.parentSymbol(for: companion)
            }
            var info: JVMClassInfo?
            while let candidate = owner, let candidateSymbol = sema.symbols.symbol(candidate),
                  [.class, .interface, .object, .enumClass, .annotationClass].contains(candidateSymbol.kind) {
                if let found = classes[Self.binaryName(candidate, sema: sema, ctx: ctx)] { info = found; break }
                owner = sema.symbols.parentSymbol(for: candidate)
            }
            guard let info = info ?? sourceClass else { continue }
            let isExtension = topLevel?.receiverType != nil || symbol.flags.contains(.memberExtension)
            if isExtension { extensionSymbols.insert(symbol.id) }
            if let method = facadeMethodsByRange[site] {
                methods[symbol.id] = method.logicalSuspendMethod ?? method
                importedDefaultMethods[symbol.id] = defaultArgumentMethod(for: method, in: info)
                if hasComposableLambdaFactory, let function = method.kotlinFunction {
                    importedComposableParameters[symbol.id] = function.composableParameters
                }
                continue
            }
            let receiverTypes = isExtension ? signature.receiverType.map { [$0] } ?? [] : []
            let descriptorTypes = try (receiverTypes + signature.parameterTypes).enumerated().map { index, type -> JVMValueType in
                let mapped = try Self.type(type, sema: sema, ctx: ctx)
                let valueIndex = index - receiverTypes.count
                guard valueIndex >= 0,
                      signature.valueParameterIsVararg.indices.contains(valueIndex),
                      signature.valueParameterIsVararg[valueIndex]
                else { return mapped }
                let component: JVMValueType
                if case .typeParam = sema.types.kind(of: type) { component = Self.boxed(mapped) }
                else { component = mapped }
                return .reference("[" + component.descriptor, nullable: false)
            }
            let parameters = descriptorTypes.map(\.descriptor).joined()
            let continuation = signature.isSuspend ? "Lkotlin/coroutines/Continuation;" : ""
            let descriptor = "(" + parameters + continuation + ")"
            let staticMember = isTopLevel || isStaticCompanion
            if !staticMember, !signature.isSuspend, JVMKotlinFunction.valueOperators.contains(name) {
                let logicalParameters = descriptorTypes.map(\.descriptor)
                let valueOperators = info.methods.filter {
                    $0.sourceName == name && $0.kotlinFunction?.valueOperatorParameterDescriptors == logicalParameters
                }
                if valueOperators.count == 1 {
                    methods[symbol.id] = valueOperators[0]
                    continue
                }
            }
            let method = info.methods.first(where: {
                $0.sourceName == name && ($0.kotlinSuspendFunction != nil) == signature.isSuspend
                    && $0.descriptor.hasPrefix(descriptor) && $0.isStatic == staticMember
            }) ?? (isStaticCompanion ? kotlinCompanion(of: info)?.methods.first(where: {
                !$0.isStatic && $0.sourceName == name && ($0.kotlinSuspendFunction != nil) == signature.isSuspend
                    && $0.descriptor.hasPrefix(descriptor)
            }) : nil)
            guard let method else { continue }
            if let logical = method.logicalSuspendMethod {
                methods[symbol.id] = logical
                continue
            }
            methods[symbol.id] = method
            // Kotlin metadata already provides source nullability.
            if method.kotlinFunction != nil { continue }
            // Keep the authored Kotlin types on the declaration of this JVM
            // stdlib base so imported methods can satisfy Kotlin List members.
            if ctx.sourceManager.path(of: site.start.file) == "<kswiftk-jvm>/abstractList.kt" { continue }
            let returnType = method.isConstructor ? signature.returnType : platform(signature.returnType)
            sema.symbols.setFunctionSignature(FunctionSignature(
                receiverType: signature.receiverType.map(platform),
                contextReceiverTypes: signature.contextReceiverTypes, contextParameterSymbols: signature.contextParameterSymbols,
                contextParameterTypes: signature.contextParameterTypes, parameterTypes: signature.parameterTypes.map(platform),
                returnType: returnType, isSuspend: signature.isSuspend, canThrow: false,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                hasStableParameterNames: signature.hasStableParameterNames,
                typeParameterSymbols: signature.typeParameterSymbols, reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList, classTypeParameterCount: signature.classTypeParameterCount
            ), for: symbol.id)
        }
        for symbol in sema.symbols.allSymbols() where symbol.kind == .function {
            guard let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol),
                  parent.fqName.map(ctx.interner.resolve) == ["kotlin", "Any"],
                  let signature = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let name = ctx.interner.resolve(symbol.name)
            guard ["toString", "hashCode", "equals"].contains(name) else { continue }
            let parameters = try signature.parameterTypes.map { try Self.type($0, sema: sema, ctx: ctx) }
            let result = try Self.type(signature.returnType, sema: sema, ctx: ctx)
            let descriptor = "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor
            methods[symbol.id] = JVMForeignMethod(owner: "java/lang/Object", name: name, descriptor: descriptor, parameters: parameters, result: result, isStatic: false, isInterface: false, isAbstract: false)
        }
        bindJDKResourceMethods(in: ctx, sema: sema)
        bindJDKFileConstructors(in: ctx, sema: sema)
    }
    private func topLevelFunction(at site: SourceRange, in ctx: CompilationContext) -> FunDecl? {
        guard let ast = ctx.ast,
              let file = ast.files.first(where: { $0.fileID == site.start.file }) else { return nil }
        for declaration in file.topLevelDecls {
            guard case let .funDecl(function) = ast.arena.decl(declaration), function.range == site else { continue }
            return function
        }
        return nil
    }
    static func type(_ id: TypeID, sema: SemaModule, ctx: CompilationContext) throws -> JVMValueType {
        switch sema.types.kind(of: id) {
        case let .intersection(parts):
            let concrete = parts.first { part in
                switch sema.types.kind(of: part) { case .primitive, .stringStruct: return true; case let .classType(t): return sema.symbols.symbol(t.classSymbol)?.kind != .interface; default: return false }
            } ?? parts.first { part in
                switch sema.types.kind(of: part) { case .typeParam, .any: return false; default: return true }
            } ?? parts.first
            guard let concrete else { throw JVMFrontendError(message: "Empty JVM intersection type.") }
            return try Self.type(concrete, sema: sema, ctx: ctx)
        case let .kClassType(t): return .reference("kotlin/reflect/KClass", nullable: t.nullability != .nonNull)
        case .unit: return .unit
        case .nothing(.nonNull): return .reference("java/lang/Void", nullable: false)
        case .nullableUnit: return .reference("kotlin/Unit", nullable: true)
        case .nothing(.nullable): return .reference("java/lang/Object", nullable: true)
        case let .any(nullability): return .reference("java/lang/Object", nullable: nullability != .nonNull, platform: nullability == .platformType)
        case let .stringStruct(nullability): return nullability == .nonNull ? .string : .reference("java/lang/String", nullable: true, platform: nullability == .platformType)
        case let .functionType(function):
            let inputs = function.contextReceivers + function.params
            let arity = inputs.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0)
            guard !inputs.contains(where: { if case .unit = sema.types.kind(of: $0) { return true }; return false }),
                  arity <= 22 else { throw JVMFrontendError(message: "JVM M7 supports Function0 through Function22, including a suspend continuation, without Unit parameters.") }
            return .reference("kotlin/jvm/functions/Function" + String(arity), nullable: function.nullability != .nonNull)
        case let .typeParam(parameter):
            if let bound = sema.symbols.typeParameterUpperBound(for: parameter.symbol) {
                if case let .typeParam(other) = sema.types.kind(of: bound), other.symbol == parameter.symbol { return .reference("java/lang/Object", nullable: true) }
                let upper = try Self.type(bound, sema: sema, ctx: ctx)
                // Final primitive bounds use primitive JVM descriptors. A
                // nullable use or nullable bound still requires its wrapper.
                let erased = parameter.nullability == .nonNull && (upper.isNumeric || upper == .boolean)
                    ? upper : boxed(upper)
                if parameter.nullability == .nullable, let name = erased.referenceName { return .reference(name, nullable: true) }
                return erased
            }
            return .reference("java/lang/Object", nullable: true)
        case let .primitive(p, n) where n != .nonNull:
            if let name = JVMValueType.primitive(p).unsignedName { return .reference(name, nullable: true) }
            guard let wrapper = wrappers[p.kotlinName] else { throw JVMFrontendError(message: "Unsupported boxed JVM primitive.") }
            return .reference("java/lang/" + wrapper, nullable: true, platform: n == .platformType)
        case let .classType(type):
            guard let symbol = sema.symbols.symbol(type.classSymbol) else { throw JVMClassReader.Invalid() }
            let name = Self.binaryName(symbol.id, sema: sema, ctx: ctx)
            // Sema keeps `Any()` typed as the nominal kotlin.Any disguise
            // symbol rather than `.any`; it is still java.lang.Object here.
            if name == "kotlin/Any" { return .reference("java/lang/Object", nullable: type.nullability != .nonNull, platform: type.nullability == .platformType) }
            if symbol.kind == .object,
               let site = symbol.declSite, ctx.sourceManager.origin(of: site.start.file) == .residualStdlib,
               let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol), parent.kind == .class,
               name.hasSuffix("$Companion") {
                let outer = String(name.dropLast("$Companion".count))
                if ctx.jvmImports?.classes[outer] != nil {
                    let importedName = ctx.jvmImports?.hasClassFile(name) == true ? name : outer
                    return .reference(importedName, nullable: type.nullability != .nonNull)
                }
            }
            if name == "kotlin/Array" {
                guard let arg = type.args.first else { throw JVMFrontendError(message: "JVM Array needs an element type.") }
                let element = try argumentType(arg, sema: sema, ctx: ctx)
                let descriptor = "[" + element.descriptor
                guard descriptor.prefix(while: { $0 == "[" }).count <= 255 else { throw JVMFrontendError(message: "JVM arrays support at most 255 dimensions.") }
                return .reference(descriptor, nullable: type.nullability != .nonNull)
            }
            if ctx.jvmRuntimeClassAliases[symbol.fqName.map(ctx.interner.resolve).joined(separator: "/")] == nil, name.hasPrefix("kotlin/"), let p = [PrimitiveType.uint, .ulong, .ubyte, .ushort].first(where: { name == "kotlin/" + $0.kotlinName + "Array" }) { return .unsignedArray(p, nullable: type.nullability != .nonNull) }
            if let element = primitiveArrays[String(name.dropFirst(7))], name.hasPrefix("kotlin/") { return .reference("[" + element.descriptor, nullable: type.nullability != .nonNull) }
            // Result's non-null logical value may carry a successful null.
            if name == "kotlin/Result" { return ctx.options.stdlibOnly ? .reference(name, nullable: type.nullability != .nonNull) : .reference("java/lang/Object", nullable: true) }
            if let mapped = builtinName(name) { return .reference(mapped, nullable: type.nullability != .nonNull) }
            // `.user` and `.residualStdlib` files both carry real JVM class
            // contracts (declarations injected for consumer compiles describe
            // stdlib-jar ABI types), so either origin may produce a reference.
            guard ctx.jvmImports?.classes[name] != nil || symbol.declSite.map({ [.user, .residualStdlib].contains(ctx.sourceManager.origin(of: $0.start.file)) && (symbol.kind == .class || symbol.kind == .interface || symbol.kind == .object || symbol.kind == .enumClass || symbol.kind == .annotationClass) }) == true else {
                let owner = symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
                throw JVMFrontendError(message: "Unsupported JVM reference type: \(name) used by \(owner)")
            }
            return .reference(name, nullable: type.nullability != .nonNull, platform: type.nullability == .platformType)
        case let .primitive(p, .nonNull):
            return .primitive(p)
        default: break
        }
        throw JVMFrontendError(message: "Unsupported JVM value type: \(sema.types.kind(of: id))")
    }
}

private extension JVMForeignMethod {
    var sourceName: String { kotlinFunction?.name ?? kotlinSuspendFunction?.name ?? name }
    var sourceResult: JVMValueType { kotlinSuspendFunction?.result ?? result }
    var sourceParameters: [JVMValueType] {
        kotlinSuspendFunction == nil ? parameters : Array(parameters.dropLast())
    }

    var logicalSuspendMethod: JVMForeignMethod? {
        guard let suspend = kotlinSuspendFunction else { return nil }
        // Coroutine lowering supplies the continuation and restores the physical descriptor.
        return JVMForeignMethod(
            owner: owner, name: name,
            descriptor: "(" + sourceParameters.map(\.descriptor).joined() + ")" + suspend.result.descriptor,
            parameters: sourceParameters, result: suspend.result,
            isStatic: isStatic, isInterface: isInterface, isAbstract: isAbstract,
            isFinal: isFinal, isSuspend: true, isProtected: isProtected
        )
    }
}
