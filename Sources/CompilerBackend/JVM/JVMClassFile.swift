import Foundation
import CompilerCore

/// JVM classfile output with verifier frames for the typed JVM CFG.
enum JVMClassFile {
    static func emit(_ program: JVMProgram, target: JVMTarget = .java8, javaParameters: Bool = false, classIndex: ClassIndex) throws -> Data {
        let pool = JVMConstantPool()
        guard program.functions.count < 65_535 else { throw JVMEmissionError.limit("JVM class exceeds the method-count limit.") }
        var methods = try program.functions.map { try emitMethod($0, owner: program.internalClassName, javaParameters: javaParameters, pool: pool) }
        let launcherDescriptor = JVMProgram.launcherDescriptor
        // A declared main(String[]) already occupies the launcher signature.
        let hasArrayMain = program.functions.contains {
            $0.reference.name == "main" && $0.reference.descriptor == launcherDescriptor
        }
        if program.hasMain && !hasArrayMain {
            var launcher = JVMBytes()
            launcher.u1(0xB8)
            launcher.u2(try pool.member(10, owner: program.internalClassName, name: "main", descriptor: "()V"))
            launcher.u1(0xB1)
            methods.append(JVMMethodCode(name: try pool.utf8("main"), descriptor: try pool.utf8(launcherDescriptor), access: 0x0009, code: launcher.data, stack: 0, locals: 1, frames: nil))
        }
        let metadata = try JVMMetadata.annotation(program, pool: pool)
        return try write(name: program.internalClassName, superclass: "java/lang/Object", interfaces: [], access: 0x0031, fields: program.properties.compactMap(\.field) + program.extraFields, fieldSignatures: Dictionary(uniqueKeysWithValues: program.properties.compactMap { property in property.field.flatMap { field in (property.fieldGenericSignature ?? property.genericSignature).flatMap { $0 == field.type.descriptor ? nil : (field.name, $0) } } }), methods: methods, sourceFile: program.sourceFileName, metadata: metadata, annotations: program.annotations, signature: nil, classIndex: classIndex, rootClassName: program.internalClassName, majorVersion: target.classFileMajorVersion, pool: pool)
    }
    static func emit(_ type: JVMClass, program: JVMProgram, target: JVMTarget = .java8, javaParameters: Bool = false, classIndex: ClassIndex) throws -> Data {
        if type.isFileFacade {
            var facade = JVMProgram(internalClassName: type.name, sourceFileName: type.sourceFileName ?? program.sourceFileName, functions: type.functions, hasMain: false, moduleName: program.moduleName)
            facade.properties = type.properties; facade.extraFields = type.extraFields; facade.typeAliases = type.typeAliases
            facade.classes = program.classes
            return try emit(facade, target: target, javaParameters: javaParameters, classIndex: classIndex)
        }
        let pool = JVMConstantPool()
        let methods = try type.functions.map { try emitMethod($0, owner: type.name, javaParameters: javaParameters, pool: pool) }
        return try write(name: type.name, superclass: type.superclass, interfaces: type.interfaces, access: type.access, fields: type.properties.compactMap(\.field) + type.extraFields, fieldSignatures: Dictionary(uniqueKeysWithValues: type.properties.compactMap { property in property.field.flatMap { field in (property.fieldGenericSignature ?? property.genericSignature).flatMap { $0 == field.type.descriptor ? nil : (field.name, $0) } } }), methods: methods, sourceFile: type.sourceFileName ?? program.sourceFileName, metadata: type.emitMetadata ? try JVMMetadata.annotation(program, type: type, pool: pool) : nil, annotations: type.annotations, signature: type.genericSignature, typeParameters: type.typeParameters, recordComponents: type.recordComponents, classIndex: classIndex, rootClassName: program.internalClassName, enclosingMethod: type.enclosingMethod, majorVersion: target.classFileMajorVersion, pool: pool)
    }
    private static func emitMethod(_ function: JVMFunction, owner: String, javaParameters: Bool, pool: JVMConstantPool) throws -> JVMMethodCode {
        var method = try JVMMethodEmitter(function: function, owner: owner, pool: pool).emit()
        method.annotations = function.annotations; method.parameterAnnotations = function.parameterAnnotations
        method.typeParameters = function.typeParameters
        method.isDeprecated = function.isDeprecated
        method.annotationDefault = function.annotationDefault
        // Each descriptor parameter gets one entry, regardless of its local slot width.
        if javaParameters, method.access & 0x1000 == 0,
           function.javaParameters.count == function.reference.parameters.count {
            method.javaParameters = function.javaParameters
        }
        return method
    }
    private static func methodAttributes(_ method: JVMMethodCode, pool: JVMConstantPool) throws -> [(UInt16, Data)] {
        var attributes = try JVMAnnotations.methodAttributes(method, pool: pool)
        guard !method.javaParameters.isEmpty else { return attributes }
        guard let count = UInt8(exactly: method.javaParameters.count) else {
            throw JVMEmissionError.limit("JVM MethodParameters count exceeds the classfile limit.")
        }
        let forbiddenNameCharacters = CharacterSet(charactersIn: ".;[/")
        var data = JVMBytes()
        data.u1(count)
        for parameter in method.javaParameters {
            // Zero denotes an unnamed entry when the source name is invalid in a classfile.
            let validName = !parameter.name.isEmpty && parameter.name.rangeOfCharacter(from: forbiddenNameCharacters) == nil
            data.u2(validName ? try pool.utf8(parameter.name) : 0)
            data.u2(parameter.access)
        }
        attributes.append((try pool.utf8("MethodParameters"), data.data))
        return attributes
    }
    struct ClassIndex {
        typealias Entry = (name: String, outer: String?, inner: String?, access: UInt16)

        private let entries: [Entry]
        private let emittedNames: Set<String>
        private var byName: [String: [Int]] = [:]
        private var children: [String: [String]] = [:]

        init(_ program: JVMProgram) {
            emittedNames = Set(program.classes.map(\.name))
            entries = program.classes.compactMap { type in
                if let outer = type.outerName {
                    guard let inner = type.innerName else { return (type.name, nil, nil, 0) }
                    let visibility: UInt16 = type.modifiers.contains(.private) ? 2 : (type.modifiers.contains(.protected) ? 4 : 1)
                    return (type.name, outer, inner, (type.access & 0x7610) | visibility | (type.isInner ? 0 : 8))
                }
                guard type.enclosingMethod != nil else { return nil }
                return (type.name, nil, type.innerName, 0x0019)
            }
            for (index, entry) in entries.enumerated() {
                byName[entry.name, default: []].append(index)
                if let outer = entry.outer, entry.inner != nil {
                    children[outer, default: []].append(entry.name)
                }
            }
        }

        func relevant(owner: String, root: String, references: Set<String>) -> [Entry] {
            func isAvailable(_ name: String) -> Bool {
                name == root || emittedNames.contains(name)
            }

            var pending = Array(references)
            pending.append(owner)
            if isAvailable(owner), let nestedNames = children[owner] {
                pending.append(contentsOf: nestedNames)
            }
            var visited: Set<String> = []
            var selected: [Int] = []
            while let name = pending.popLast() {
                guard visited.insert(name).inserted, let indices = byName[name] else { continue }
                for index in indices {
                    if let outer = entries[index].outer {
                        guard isAvailable(outer) else { continue }
                        pending.append(outer)
                    }
                    selected.append(index)
                }
            }
            // Keep InnerClasses attribute order identical to program class order.
            return selected.sorted().map { entries[$0] }
        }
    }
    private static func write(name: String, superclass: String, interfaces: [String], access: UInt16, fields: [JVMField], fieldSignatures: [String: String] = [:], methods: [JVMMethodCode], sourceFile: String, metadata: Data?, annotations: [JVMAnnotation] = [], signature: String?, typeParameters: [JVMTypeParameter] = [], recordComponents: [JVMRecordComponent] = [], classIndex: ClassIndex, rootClassName: String, enclosingMethod: JVMEnclosingMethod? = nil, majorVersion: UInt16 = 52, pool: JVMConstantPool) throws -> Data {
        guard methods.count <= 65_535, fields.count <= 65_535, interfaces.count <= 65_535 else { throw JVMEmissionError.limit("JVM member/interface count exceeds the classfile limit.") }
        guard recordComponents.count <= 65_535 else { throw JVMEmissionError.limit("JVM record component count exceeds the classfile limit.") }
        guard recordComponents.isEmpty || majorVersion >= 60 else { throw JVMEmissionError.limit("JVM Record attributes require classfile version 60 or later.") }
        let thisClass = try pool.classInfo(name), superClass = try pool.classInfo(superclass)
        let interfaceIndices = try interfaces.map(pool.classInfo)
        let fieldIndices = try fields.map { (try pool.utf8($0.name), try pool.utf8($0.type.descriptor)) }
        let codeName = try pool.utf8("Code"), stackMapName = try pool.utf8("StackMapTable")
        let sourceName = try pool.utf8("SourceFile"), sourceIndex = try pool.utf8(sourceFile)
        let signatureName = try pool.utf8("Signature")
        let fieldGenerics = try fields.map { try fieldSignatures[$0.name].map { try pool.utf8($0) } }
        let classSignature = try signature.map { try pool.utf8($0) }
        let methodSignatures = try methods.map { try $0.signature.map { try pool.utf8($0) } }
        let classAnnotations = try JVMAnnotations.attributes(annotations, metadata: metadata, pool: pool)
        let typeParameterAttributes = try JVMAnnotations.typeParameterAttributes(typeParameters, targetType: 0x00, pool: pool)
        let constantName = try pool.utf8("ConstantValue")
        let fieldConstants = try fields.map { field -> UInt16? in
            guard let constant = field.constantValue else { return nil }
            if case let .boolean(value) = constant { return try pool.constant(.int(value ? 1 : 0)) }
            return try pool.constant(constant)
        }
        let fieldAnnotations = try fields.map { try JVMAnnotations.attributes($0.annotations, deprecated: $0.isDeprecated, pool: pool) }
        let methodAttributes = try methods.map { try self.methodAttributes($0, pool: pool) }
        let recordAttributeName: UInt16? = recordComponents.isEmpty ? nil : try pool.utf8("Record")
        let recordComponentIndices = try recordComponents.map { component in
            (try pool.utf8(component.name), try pool.utf8(component.type.descriptor), try component.genericSignature.map { try pool.utf8($0) })
        }
        let relevantInnerClasses = classIndex.relevant(owner: name, root: rootClassName, references: pool.referencedClassNames)
        let innerName = try relevantInnerClasses.isEmpty ? nil : pool.utf8("InnerClasses")
        let innerIndices = try relevantInnerClasses.map { entry in
            (
                try pool.classInfo(entry.0),
                try entry.1.map { try pool.classInfo($0) } ?? 0,
                try entry.2.map { try pool.utf8($0) } ?? 0,
                entry.3
            )
        }
        let enclosingMethodName = try enclosingMethod == nil ? nil : pool.utf8("EnclosingMethod")
        let enclosingMethodIndices = try enclosingMethod.map { method in
            let methodIndex = try method.name == "<clinit>"
                ? 0
                : pool.pair(12, pool.utf8(method.name), pool.utf8(method.descriptor))
            return (
                try pool.classInfo(method.owner),
                methodIndex
            )
        }
        let bootstrapAttribute = try pool.bootstrapMethodsAttribute()
        var bytes = JVMBytes()
        bytes.u4(0xCAFEBABE); bytes.u2(0); bytes.u2(majorVersion)
        pool.write(to: &bytes)
        bytes.u2(access); bytes.u2(thisClass); bytes.u2(superClass)
        bytes.u2(UInt16(interfaceIndices.count))
        for interface in interfaceIndices { bytes.u2(interface) }
        bytes.u2(UInt16(fields.count))
        for (i, pair) in zip(fields, fieldIndices).enumerated() {
            let (field, indices) = pair
            bytes.u2(field.access); bytes.u2(indices.0); bytes.u2(indices.1); bytes.u2(UInt16((fieldGenerics[i] == nil ? 0 : 1) + (fieldConstants[i] == nil ? 0 : 1) + fieldAnnotations[i].count))
            for (name, data) in fieldAnnotations[i] { bytes.u2(name); bytes.u4(UInt32(data.count)); bytes.data.append(data) }
            if let constant = fieldConstants[i] { bytes.u2(constantName); bytes.u4(2); bytes.u2(constant) }
            if let generic = fieldGenerics[i] { bytes.u2(signatureName); bytes.u4(2); bytes.u2(generic) }
        }
        bytes.u2(UInt16(methods.count))
        for (i, pair) in zip(methods, methodSignatures).enumerated() {
            let (method, generic) = pair
            let attributes = methodAttributes[i]
            guard method.exceptions.count <= 65_535 else { throw JVMEmissionError.limit("JVM exception table exceeds the classfile limit.") }
            if method.access & 0x0400 != 0 {
                bytes.u2(method.access); bytes.u2(method.name); bytes.u2(method.descriptor); bytes.u2(UInt16((generic == nil ? 0 : 1) + attributes.count))
                for (name, data) in attributes { bytes.u2(name); bytes.u4(UInt32(data.count)); bytes.data.append(data) }
                if let generic { bytes.u2(signatureName); bytes.u4(2); bytes.u2(generic) }; continue
            }
            let nestedSize = method.frames.map { 6 + $0.count } ?? 0
            let attributeSize = 12 + method.code.count + nestedSize + 8 * method.exceptions.count
            guard let size = UInt32(exactly: attributeSize) else { throw JVMEmissionError.limit("JVM Code attribute exceeds the classfile size limit.") }
            bytes.u2(method.access); bytes.u2(method.name); bytes.u2(method.descriptor); bytes.u2(UInt16((generic == nil ? 1 : 2) + attributes.count))
            for (name, data) in attributes { bytes.u2(name); bytes.u4(UInt32(data.count)); bytes.data.append(data) }
            bytes.u2(codeName); bytes.u4(size)
            bytes.u2(method.stack); bytes.u2(method.locals); bytes.u4(UInt32(method.code.count))
            bytes.data.append(method.code); bytes.u2(UInt16(method.exceptions.count))
            for entry in method.exceptions { bytes.u2(entry.0); bytes.u2(entry.1); bytes.u2(entry.2); bytes.u2(entry.3) }
            if let frames = method.frames {
                bytes.u2(1); bytes.u2(stackMapName); bytes.u4(UInt32(frames.count)); bytes.data.append(frames)
            } else { bytes.u2(0) }
            if let generic { bytes.u2(signatureName); bytes.u4(2); bytes.u2(generic) }
        }
        let classAttributeCount = 1 + classAnnotations.count + typeParameterAttributes.count + (classSignature == nil ? 0 : 1) + (relevantInnerClasses.isEmpty ? 0 : 1) + (enclosingMethod == nil ? 0 : 1) + (bootstrapAttribute == nil ? 0 : 1) + (recordAttributeName == nil ? 0 : 1)
        guard classAttributeCount <= 65_535 else { throw JVMEmissionError.limit("JVM class attribute count exceeds the classfile limit.") }
        bytes.u2(UInt16(classAttributeCount)); bytes.u2(sourceName); bytes.u4(2); bytes.u2(sourceIndex)
        for (name, data) in classAnnotations { bytes.u2(name); bytes.u4(UInt32(data.count)); bytes.data.append(data) }
        for (name, data) in typeParameterAttributes { bytes.u2(name); bytes.u4(UInt32(data.count)); bytes.data.append(data) }
        if let classSignature { bytes.u2(signatureName); bytes.u4(2); bytes.u2(classSignature) }
        if !relevantInnerClasses.isEmpty {
            bytes.u2(innerName!); bytes.u4(UInt32(2 + 8 * innerIndices.count)); bytes.u2(UInt16(innerIndices.count))
            for entry in innerIndices { bytes.u2(entry.0); bytes.u2(entry.1); bytes.u2(entry.2); bytes.u2(entry.3) }
        }
        if let enclosingMethodIndices {
            bytes.u2(enclosingMethodName!); bytes.u4(4); bytes.u2(enclosingMethodIndices.0); bytes.u2(enclosingMethodIndices.1)
        }
        if let bootstrapAttribute {
            guard let size = UInt32(exactly: bootstrapAttribute.data.count) else { throw JVMEmissionError.limit("JVM BootstrapMethods attribute exceeds the classfile size limit.") }
            bytes.u2(bootstrapAttribute.nameIndex); bytes.u4(size); bytes.data.append(bootstrapAttribute.data)
        }
        if let recordAttributeName {
            var attribute = JVMBytes()
            attribute.u2(UInt16(recordComponents.count))
            for indices in recordComponentIndices {
                attribute.u2(indices.0); attribute.u2(indices.1)
                attribute.u2(indices.2 == nil ? 0 : 1)
                if let generic = indices.2 {
                    attribute.u2(signatureName); attribute.u4(2); attribute.u2(generic)
                }
            }
            guard let size = UInt32(exactly: attribute.data.count) else { throw JVMEmissionError.limit("JVM Record attribute exceeds the classfile size limit.") }
            bytes.u2(recordAttributeName); bytes.u4(size); bytes.data.append(attribute.data)
        }
        return bytes.data
    }
}
