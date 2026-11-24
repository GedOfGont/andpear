package com.notifybridge.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/** Share-sheet target: "Mac'e gönder". Sends the shared text to the Mac's clipboard and closes immediately. */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (text.isNullOrBlank()) {
            Toast.makeText(this, getString(R.string.share_empty), Toast.LENGTH_SHORT).show()
        } else {
            Sender.sendClip(this, text)
            Toast.makeText(this, getString(R.string.share_sending), Toast.LENGTH_SHORT).show()
        }
        finish()
    }
}
