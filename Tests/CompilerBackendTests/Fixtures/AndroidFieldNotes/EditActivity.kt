package org.swiftykotlin.fieldnotes

import android.app.Activity
import android.os.Bundle
import android.view.View
import android.widget.EditText

class EditActivity : Activity() {
    private lateinit var store: NoteStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.edit_note)
        store = NoteStore(this)
        val id = getIntent().getLongExtra("note_id", -1L)
        val title = findViewById<EditText>(R.id.note_title)
        val body = findViewById<EditText>(R.id.note_body)
        val delete = findViewById<View>(R.id.delete_note)
        if (id == -1L) {
            delete.setVisibility(View.GONE)
        } else {
            val note = store.find(id)
            if (note != null) {
                title.setText(note.title)
                body.setText(note.body)
            }
            delete.setOnClickListener {
                if (store.remove(id)) finish()
            }
        }
        findViewById<View>(R.id.save_note).setOnClickListener {
            val enteredTitle = title.getText().toString().trim()
            if (enteredTitle.isEmpty()) {
                title.setError(getString(R.string.required_title))
            } else {
                val note = Note(enteredTitle, body.getText().toString())
                if (store.save(id, note)) finish()
            }
        }
    }

    override fun onDestroy() {
        store.close()
        super.onDestroy()
    }
}
