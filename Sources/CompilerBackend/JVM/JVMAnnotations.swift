import Foundation
import CompilerCore

/// JVMS 4.7 annotation attributes share the constant pool with ordinary code.
enum JVMAnnotations {
    static func value(_ value: JVMAnnotationValue, pool: JVMConstantPool) throws -> Data {
        var b = JVMBytes()
        switch value {
        case let .constant(c):
            switch c {
            case let .string(s): b.u1(115); b.u2(try pool.utf8(s, kotlinLiteral: true))
            case .int: b.u1(73); b.u2(try pool.constant(c))
            case .long: b.u1(74); b.u2(try pool.constant(c))
            case .float: b.u1(70); b.u2(try pool.constant(c))
            case .double: b.u1(68); b.u2(try pool.constant(c))
            case let .boolean(v): b.u1(90); b.u2(try pool.constant(.int(v ? 1 : 0)))
            case .null: throw JVMEmissionError.limit("Annotation values cannot be null.")
            }
        case let .integral(number, tag): b.u1(tag); b.u2(try pool.constant(.int(number)))
        case let .enumEntry(type, name): b.u1(101); b.u2(try pool.utf8(type)); b.u2(try pool.utf8(name))
        case let .classType(type): b.u1(99); b.u2(try pool.utf8(type))
        case let .annotation(a): b.u1(64); b.data.append(try annotation(a, pool: pool))
        case let .array(values):
            guard values.count <= 65_535 else { throw JVMEmissionError.limit("Annotation array exceeds JVM limits.") }
            b.u1(91); b.u2(UInt16(values.count))
            for element in values { b.data.append(try self.value(element, pool: pool)) }
        }
        return b.data
    }
    static func annotation(_ annotation: JVMAnnotation, pool: JVMConstantPool) throws -> Data {
        guard annotation.values.count <= 65_535 else { throw JVMEmissionError.limit("Annotation exceeds JVM limits.") }
        var b = JVMBytes(); b.u2(try pool.utf8(annotation.descriptor)); b.u2(UInt16(annotation.values.count))
        for (name, value) in annotation.values { b.u2(try pool.utf8(name)); b.data.append(try self.value(value, pool: pool)) }
        return b.data
    }
    static func attributes(_ annotations: [JVMAnnotation], metadata: Data? = nil, deprecated: Bool = false, pool: JVMConstantPool) throws -> [(UInt16, Data)] {
        var result: [(UInt16, Data)] = []
        if deprecated || annotations.contains(where: { $0.descriptor == "Lkotlin/Deprecated;" }) {
            result.append((try pool.utf8("Deprecated"), Data()))
        }
        for visible in [true, false] {
            let selected = annotations.filter { $0.visible == visible }
            let count = selected.count + (visible && metadata != nil ? 1 : 0)
            guard count <= 65_535 else { throw JVMEmissionError.limit("Annotation count exceeds JVM limits.") }
            if count == 0 { continue }
            var b = JVMBytes(); b.u2(UInt16(count))
            if visible, let metadata { b.data.append(metadata.dropFirst(2)) }
            for annotation in selected { b.data.append(try self.annotation(annotation, pool: pool)) }
            result.append((try pool.utf8(visible ? "RuntimeVisibleAnnotations" : "RuntimeInvisibleAnnotations"), b.data))
        }
        return result
    }
    static func methodAttributes(_ method: JVMMethodCode, pool: JVMConstantPool) throws -> [(UInt16, Data)] {
        var attributes = try self.attributes(method.annotations, deprecated: method.isDeprecated, pool: pool)
        if let value = method.annotationDefault { attributes.append((try pool.utf8("AnnotationDefault"), try self.value(value, pool: pool))) }
        if !method.parameterAnnotations.isEmpty {
            guard method.parameterAnnotations.count <= 255 else { throw JVMEmissionError.limit("Annotated parameter count exceeds JVM limits.") }
            for visible in [true, false] where method.parameterAnnotations.contains(where: { $0.contains { $0.visible == visible } }) {
                var b = JVMBytes(); b.u1(UInt8(method.parameterAnnotations.count))
                for annotations in method.parameterAnnotations {
                    let selected = annotations.filter { $0.visible == visible }
                    guard selected.count <= 65_535 else { throw JVMEmissionError.limit("Parameter annotation count exceeds JVM limits.") }
                    b.u2(UInt16(selected.count))
                    for annotation in selected { b.data.append(try self.annotation(annotation, pool: pool)) }
                }
                attributes.append((try pool.utf8(visible ? "RuntimeVisibleParameterAnnotations" : "RuntimeInvisibleParameterAnnotations"), b.data))
            }
        }
        return attributes
    }
}
