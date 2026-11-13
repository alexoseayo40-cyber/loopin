// Loopin — da a otras apps (compartir) los WAV exportados, sin permisos
// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.alexoseayo40_cyber.loopin

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

// Solo sirve los archivos de la carpeta de exportar (cache/exports), solo para
// leer y solo a quien se le dé permiso al compartir. Un FileProvider de
// AndroidX haría lo mismo, pero sería una dependencia más.
class ExportProvider : ContentProvider() {
    override fun onCreate() = true

    private fun fileFor(uri: Uri): File {
        val ctx = context ?: throw FileNotFoundException()
        val dir = File(ctx.cacheDir, EXPORTS).canonicalFile
        val name = uri.lastPathSegment ?: throw FileNotFoundException()
        val f = File(dir, name).canonicalFile
        // Nada fuera de la carpeta (ni «../»)
        if (f.parentFile != dir || !f.isFile) throw FileNotFoundException(name)
        return f
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("solo lectura")
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?,
    ): Cursor {
        val f = fileFor(uri)
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = cols.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> f.name
                OpenableColumns.SIZE -> f.length()
                else -> null
            }
        }
        return MatrixCursor(cols).apply { addRow(row) }
    }

    override fun getType(uri: Uri) = "audio/wav"
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(
        uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?,
    ) = 0

    companion object {
        const val EXPORTS = "exports"
        fun uriFor(packageName: String, f: File): Uri =
            Uri.parse("content://$packageName.exports/${Uri.encode(f.name)}")
    }
}
