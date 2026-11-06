/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/reflect/>.
 */

package kotlin.reflect

public interface KDeclarationContainer : KAnnotatedElement {
    public val members: Collection<KCallable<*>>
    public val nestedClasses: Collection<KClass<*>>
    public val typeParameters: List<KTypeParameter>
    public val supertypes: List<KType>
    public val visibility: KVisibility?

    public val isFinal: Boolean
    public val isOpen: Boolean
    public val isAbstract: Boolean
    public val isSealed: Boolean
    public val isData: Boolean
    public val isInner: Boolean
    public val isCompanion: Boolean
    public val isFun: Boolean
    public val isValue: Boolean
}
