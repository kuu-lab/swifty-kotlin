package org.swiftykotlin.fieldnotes

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

data class Note(val title: String, val body: String)

class NoteStore(context: Context) : SQLiteOpenHelper(context, "field-notes.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE notes (_id INTEGER PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    fun query(text: String): Cursor {
        val pattern = "%${text}%"
        return getReadableDatabase().rawQuery(
            "SELECT _id, title, body FROM notes WHERE title LIKE ? OR body LIKE ? ORDER BY _id DESC",
            arrayOf(pattern, pattern)
        )
    }

    fun find(id: Long): Note? {
        val cursor = getReadableDatabase().rawQuery(
            "SELECT title, body FROM notes WHERE _id = ?",
            arrayOf(id.toString())
        )
        try {
            if (!cursor.moveToFirst()) return null
            return Note(cursor.getString(0), cursor.getString(1))
        } finally {
            cursor.close()
        }
    }

    fun save(id: Long, note: Note): Boolean {
        val values = ContentValues()
        values.put("title", note.title)
        values.put("body", note.body)
        val db = getWritableDatabase()
        if (id == -1L) return db.insert("notes", null, values) != -1L
        return db.update("notes", values, "_id = ?", arrayOf(id.toString())) == 1
    }

    fun remove(id: Long): Boolean {
        return getWritableDatabase().delete("notes", "_id = ?", arrayOf(id.toString())) == 1
    }
}
