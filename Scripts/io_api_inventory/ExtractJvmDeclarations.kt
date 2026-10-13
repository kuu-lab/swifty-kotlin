import java.io.File
import java.net.URLClassLoader
import java.security.MessageDigest
import java.util.jar.JarFile
import kotlin.metadata.*
import kotlin.metadata.jvm.*

private fun typeName(type: KmType?, parameters: List<KmTypeParameter> = emptyList()): String {
    if (type == null) return ""
    val name = when (val classifier = type.classifier) {
        is KmClassifier.Class -> classifier.name.replace('/', '.')
        is KmClassifier.TypeAlias -> classifier.name.replace('/', '.')
        is KmClassifier.TypeParameter -> "0:" + parameters.indexOfFirst { it.id == classifier.id }.also { check(it >= 0) }
    }
    val arguments = if (type.arguments.isEmpty()) "" else type.arguments.joinToString(",", "<", ">") { argument ->
        if (argument.type == null) "*" else when (argument.variance) {
            KmVariance.IN -> "in|"
            KmVariance.OUT -> "out|"
            else -> ""
        } + typeName(argument.type, parameters)
    }
    return name + arguments + if (type.isNullable) "?" else ""
}

fun main(arguments: Array<String>) {
    require(arguments.size == 2) { "Usage: ExtractJvmDeclarationsKt <core-jar> <bytestring-jar>" }
    val jars = arguments.map { File(it).canonicalFile }
    val records = mutableListOf<Map<String, Any?>>()
    URLClassLoader(jars.map { it.toURI().toURL() }.toTypedArray(), KotlinClassMetadata::class.java.classLoader).use { loader ->
        for (jar in jars) {
            val module = if (jar.name.contains("bytestring")) "bytestring" else "core"
            JarFile(jar).use { archive ->
                for (entry in archive.entries().asSequence().filter { it.name.endsWith(".class") && !it.name.startsWith("META-INF/") }.sortedBy { it.name }) {
                    val owner = entry.name.removeSuffix(".class")
                    val loaded = Class.forName(owner.replace('/', '.'), false, loader)
                    val annotation = loaded.getAnnotation(Metadata::class.java) ?: continue
                    val metadata = KotlinClassMetadata.readStrict(annotation)
                    fun add(kind: String, fqName: String, receiver: String, parameters: List<String>, visibility: Visibility,
                            jvmName: String?, descriptor: String?, defaults: List<Boolean> = emptyList()) {
                        if (jvmName == null || descriptor == null) return
                        records.add(linkedMapOf(
                            "module" to module, "jvmOwner" to owner, "jvmName" to jvmName, "descriptor" to descriptor,
                            "kind" to kind, "fqName" to fqName, "receiver" to receiver, "parameters" to parameters,
                            "visibility" to visibility.toString().lowercase(), "defaults" to defaults
                        ))
                    }
                    val functions: List<KmFunction>
                    val properties: List<KmProperty>
                    val kotlinOwner: String
                    when (metadata) {
                        is KotlinClassMetadata.Class -> {
                            val klass = metadata.kmClass
                            kotlinOwner = klass.name.replace('/', '.')
                            functions = klass.functions
                            properties = klass.properties
                            val kind = when (klass.kind) {
                                ClassKind.INTERFACE -> "interface"
                                ClassKind.ANNOTATION_CLASS -> "annotation class"
                                ClassKind.OBJECT, ClassKind.COMPANION_OBJECT -> "object"
                                else -> "class"
                            }
                            add(kind, kotlinOwner, "", emptyList(), klass.visibility, "<class>", "")
                            for (constructor in klass.constructors) {
                                add("constructor", "$kotlinOwner.<init>", "", constructor.valueParameters.map {
                                    typeName(it.type, klass.typeParameters) + if (it.varargElementType != null) "..." else ""
                                }, constructor.visibility, constructor.signature?.name, constructor.signature?.descriptor,
                                    constructor.valueParameters.map { it.declaresDefaultValue })
                            }
                        }
                        is KotlinClassMetadata.FileFacade -> {
                            kotlinOwner = owner.substringBeforeLast('/').replace('/', '.')
                            functions = metadata.kmPackage.functions
                            properties = metadata.kmPackage.properties
                        }
                        is KotlinClassMetadata.MultiFileClassPart -> {
                            kotlinOwner = owner.substringBeforeLast('/').replace('/', '.')
                            functions = metadata.kmPackage.functions
                            properties = metadata.kmPackage.properties
                        }
                        else -> continue
                    }
                    for (function in functions) {
                        add("function", "$kotlinOwner.${function.name}", typeName(function.receiverParameterType, function.typeParameters),
                            function.valueParameters.map { typeName(it.type, function.typeParameters) + if (it.varargElementType != null) "..." else "" },
                            function.visibility, function.signature?.name, function.signature?.descriptor,
                            function.valueParameters.map { it.declaresDefaultValue })
                    }
                    for (property in properties) {
                        val fqName = "$kotlinOwner.${property.name}"
                        val receiver = typeName(property.receiverParameterType, property.typeParameters)
                        for (signature in listOfNotNull(property.getterSignature, property.setterSignature)) {
                            add("property", fqName, receiver, emptyList(), property.visibility, signature.name, signature.descriptor)
                        }
                        property.fieldSignature?.let { signature ->
                            add("property", fqName, receiver, emptyList(), property.visibility, signature.name, signature.descriptor)
                        }
                    }
                }
            }
        }
    }
    val inputs = jars.map { jar -> linkedMapOf(
        "file" to jar.name,
        "sha256" to MessageDigest.getInstance("SHA-256").digest(jar.readBytes()).joinToString("") { "%02x".format(it.toInt() and 255) }
    ) }
    println(json(linkedMapOf("schemaVersion" to 1, "jars" to inputs, "declarations" to records)))
}
