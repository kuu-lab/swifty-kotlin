class ConstructorFields {
    val immutable: Int
    var mutable: Int

    constructor(flag: Boolean) {
        if (flag) {
            immutable = 10
            mutable = 20
            return
        }
        immutable = 30
        mutable = 40
    }

    constructor() : this(true) {}
}

class InitializedBeforeConstructor {
    val immutable: Int
    var mutable: Int

    init { immutable = 50 }
    init { mutable = 60 }
    constructor() {}
}

class FinallyFields {
    val immutable: Int
    var mutable: Int

    constructor() {
        try {} finally {
            immutable = 70
            mutable = 80
        }
    }
}

class LaterDeclaredFields {
    constructor() {
        immutable = 110
        mutable = 120
    }

    val immutable: Int
    var mutable: Int
}

@Target(AnnotationTarget.FIELD)
annotation class FieldMark

class AnnotatedInitializedFields {
    @FieldMark val immutable: Int = 90
    @field:FieldMark var mutable: Int = 100
    constructor() {}
}

fun main() {
    val first = ConstructorFields()
    val second = ConstructorFields(false)
    val initialized = InitializedBeforeConstructor()
    val final = FinallyFields()
    val annotated = AnnotatedInitializedFields()
    val later = LaterDeclaredFields()
    println(first.immutable)
    println(first.mutable)
    println(second.immutable)
    println(second.mutable)
    println(initialized.immutable)
    println(initialized.mutable)
    println(final.immutable)
    println(final.mutable)
    println(annotated.immutable)
    println(annotated.mutable)
    println(later.immutable)
    println(later.mutable)
}
