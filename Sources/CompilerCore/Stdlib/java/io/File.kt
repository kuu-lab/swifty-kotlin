package java.io

// KUU-4440: java.io.File's JDK static fields, exposed through the synthetic
// class's companion object (registered in
// HeaderHelpers+SyntheticJavaIOStreamStubs.swift). KSwiftK targets POSIX
// hosts, matching the kotlinx-io `SystemPathSeparator` convention.

public val File.Companion.separator: String
    get() = "/"

public val File.Companion.separatorChar: Char
    get() = '/'

public val File.Companion.pathSeparator: String
    get() = ":"

public val File.Companion.pathSeparatorChar: Char
    get() = ':'
