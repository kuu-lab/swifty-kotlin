/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

/**
 * Signals that the annotated annotation class is a marker of an API that requires an explicit opt-in.
 *
 * @property message message to be reported on usages of API without an explicit opt-in, or an empty string for the default message.
 * @property level specifies how usages of API without an explicit opt-in are reported in code.
 */
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class RequiresOptIn(
    val message: String = "",
    val level: Level = Level.ERROR
) {
    /**
     * Severity of the diagnostic that should be reported on usages which did not explicitly opt into
     * the API either by using [OptIn] or by being annotated with the corresponding marker annotation.
     */
    public enum class Level {
        /** Specifies that a warning should be reported on incorrect usages of this API. */
        WARNING,

        /** Specifies that a compilation error should be reported on incorrect usages of this API. */
        ERROR
    }
}
