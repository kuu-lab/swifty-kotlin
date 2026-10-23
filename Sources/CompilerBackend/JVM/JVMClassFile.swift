import Foundation
import CompilerCore

/// Java 8 classfile output with verifier frames for the typed JVM CFG.
enum JVMClassFile {
    static func emit(_ program: JVMProgram) throws -> Data {
        let pool = JVMConstantPool()
        guard program.functions.count < 65_535 else { throw JVMEmissionError.limit("JVM class exceeds the method-count limit.") }
        var methods = try program.functions.map { try emitMethod($0, owner: program.internalClassName, pool: pool) }
        if program.hasMain {
            var launcher = JVMBytes()
            launcher.u1(0xB8)
            launcher.u2(try pool.member(10, owner: program.internalClassName, name: "main", descriptor: "()V"))
            launcher.u1(0xB1)
            methods.append(JVMMethodCode(name: try pool.utf8("main"), descriptor: try pool.utf8("([Ljava/lang/String;)V"), access: 0x0009, code: launcher.data, stack: 0, locals: 1, frames: nil))
        }
        let metadata = try JVMMetadata.annotation(program, pool: pool)
        return try write(name: program.internalClassName, superclass: "java/lang/Object", interfaces: [], access: 0x0031, fields: program.properties.compactMap(\.field) + program.extraFields, fieldSignatures: Dictionary(uniqueKeysWithValues: program.properties.compactMap { property in property.field.flatMap { field in property.genericSignature.flatMap { $0 == field.type.descriptor ? nil : (field.name, $0) } } }), methods: methods, sourceFile: program.sourceFileName, metadata: metadata, annotations: program.annotations, signature: nil, innerClasses: innerClasses(program), pool: pool)
    }
    static func emit(_ type: JVMClass, program: JVMProgram) throws -> Data {
        if type.isFileFacade {
            var facade = JVMProgram(internalClassName: type.name, sourceFileName: type.sourceFileName ?? program.sourceFileName, functions: type.functions, hasMain: false, moduleName: program.moduleName)
            facade.properties = type.properties; facade.extraFields = type.extraFields; facade.typeAliases = type.typeAliases
            return try emit(facade)
        }
        let pool = JVMConstantPool()
        let methods = try type.functions.map { try emitMethod($0, owner: type.name, pool: pool) }
        return try write(name: type.name, superclass: type.superclass, interfaces: type.interfaces, access: type.access, fields: type.properties.compactMap(\.field) + type.extraFields, fieldSignatures: Dictionary(uniqueKeysWithValues: type.properties.compactMap { property in property.field.flatMap { field in property.genericSignature.flatMap { $0 == field.type.descriptor ? nil : (field.name, $0) } } }), methods: methods, sourceFile: type.sourceFileName ?? program.sourceFileName, metadata: type.emitMetadata ? try JVMMetadata.annotation(program, type: type, pool: pool) : nil, annotations: type.annotations, signature: type.genericSignature, innerClasses: innerClasses(program), pool: pool)
    }
    private static func emitMethod(_ function: JVMFunction, owner: String, pool: JVMConstantPool) throws -> JVMMethodCode {
        var method = try JVMMethodEmitter(function: function, owner: owner, pool: pool).emit()
        method.annotations = function.annotations; method.parameterAnnotations = function.parameterAnnotations
        method.isDeprecated = function.isDeprecated
        method.annotationDefault = function.annotationDefault
        return method
    }
    private static func innerClasses(_ program: JVMProgram) -> [(String, String, String?, UInt16)] {
        program.classes.compactMap { type in
            guard let outer = type.outerName else { return nil }
            if type.innerName == nil {
                return (type.name, outer, nil, 0)
            }
            let visibility: UInt16 = type.modifiers.contains(.private) ? 2 : (type.modifiers.contains(.protected) ? 4 : 1)
            return (type.name, outer, type.innerName, (type.access & 0x7610) | visibility | (type.isInner ? 0 : 8))
        }
    }
    private static func write(name: String, superclass: String, interfaces: [String], access: UInt16, fields: [JVMField], fieldSignatures: [String: String] = [:], methods: [JVMMethodCode], sourceFile: String, metadata: Data?, annotations: [JVMAnnotation] = [], signature: String?, innerClasses: [(String, String, String?, UInt16)] = [], pool: JVMConstantPool) throws -> Data {
        guard methods.count <= 65_535, fields.count <= 65_535, interfaces.count <= 65_535 else { throw JVMEmissionError.limit("JVM member/interface count exceeds the classfile limit.") }
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
        let constantName = try pool.utf8("ConstantValue")
        let fieldConstants = try fields.map { field -> UInt16? in
            guard let constant = field.constantValue else { return nil }
            if case let .boolean(value) = constant { return try pool.constant(.int(value ? 1 : 0)) }
            return try pool.constant(constant)
        }
        let fieldAnnotations = try fields.map { try JVMAnnotations.attributes($0.annotations, deprecated: $0.isDeprecated, pool: pool) }
        let methodAnnotations = try methods.map { try JVMAnnotations.methodAttributes($0, pool: pool) }
        let innerName = try innerClasses.isEmpty ? nil : pool.utf8("InnerClasses")
        let innerIndices = try innerClasses.map { entry in
            (
                try pool.classInfo(entry.0),
                try pool.classInfo(entry.1),
                try entry.2.map { try pool.utf8($0) } ?? 0,
                entry.3
            )
        }
        let bootstrapAttribute = try pool.bootstrapMethodsAttribute()
        var bytes = JVMBytes()
        bytes.u4(0xCAFEBABE); bytes.u2(0); bytes.u2(52)
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
            let attributes = methodAnnotations[i]
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
        bytes.u2(UInt16(1 + classAnnotations.count + (classSignature == nil ? 0 : 1) + (innerClasses.isEmpty ? 0 : 1) + (bootstrapAttribute == nil ? 0 : 1))); bytes.u2(sourceName); bytes.u4(2); bytes.u2(sourceIndex)
        for (name, data) in classAnnotations { bytes.u2(name); bytes.u4(UInt32(data.count)); bytes.data.append(data) }
        if let classSignature { bytes.u2(signatureName); bytes.u4(2); bytes.u2(classSignature) }
        if !innerClasses.isEmpty {
            bytes.u2(innerName!); bytes.u4(UInt32(2 + 8 * innerIndices.count)); bytes.u2(UInt16(innerIndices.count))
            for entry in innerIndices { bytes.u2(entry.0); bytes.u2(entry.1); bytes.u2(entry.2); bytes.u2(entry.3) }
        }
        if let bootstrapAttribute {
            guard let size = UInt32(exactly: bootstrapAttribute.data.count) else { throw JVMEmissionError.limit("JVM BootstrapMethods attribute exceeds the classfile size limit.") }
            bytes.u2(bootstrapAttribute.nameIndex); bytes.u4(size); bytes.data.append(bootstrapAttribute.data)
        }
        return bytes.data
    }
}
