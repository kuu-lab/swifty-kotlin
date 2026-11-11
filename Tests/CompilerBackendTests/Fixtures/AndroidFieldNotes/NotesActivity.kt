package org.swiftykotlin.fieldnotes

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ListView
import android.widget.SearchView
import android.widget.SimpleCursorAdapter

class NotesActivity : Activity() {
    private lateinit var store: NoteStore
    private lateinit var notes: SimpleCursorAdapter
    private var filter = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.notes)
        store = NoteStore(this)
        notes = SimpleCursorAdapter(
            this, android.R.layout.simple_list_item_2, null,
            arrayOf("title", "body"), intArrayOf(android.R.id.text1, android.R.id.text2), 0
        )
        val list = findViewById<ListView>(R.id.notes_list)
        list.setEmptyView(findViewById<View>(R.id.empty_notes))
        list.setAdapter(notes)
        list.setOnItemClickListener { _, _, _, id -> openEditor(id) }
        findViewById<View>(R.id.add_note).setOnClickListener { openEditor(-1L) }
        findViewById<SearchView>(R.id.search_notes).setOnQueryTextListener(object : SearchView.OnQueryTextListener {
            override fun onQueryTextSubmit(query: String): Boolean = true

            override fun onQueryTextChange(newText: String): Boolean {
                filter = newText
                refreshNotes()
                return true
            }
        })
    }

    override fun onResume() {
        super.onResume()
        refreshNotes()
    }

    override fun onDestroy() {
        notes.changeCursor(null)
        store.close()
        super.onDestroy()
    }

    private fun refreshNotes() {
        notes.changeCursor(store.query(filter))
    }

    private fun openEditor(id: Long) {
        val intent = Intent(this, EditActivity::class.java)
        intent.putExtra("note_id", id)
        startActivity(intent)
    }
}
