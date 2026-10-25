/*
 * Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the license/LICENSE.txt file.
 */

package kotlin

public open class KotlinNullPointerException : NullPointerException {
    public constructor()

    public constructor(message: String?) : super(message)
}
