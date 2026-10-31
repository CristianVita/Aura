package com.example.symphonium_clone

import android.content.ContentProvider
import android.content.ContentUris
import android.content.ContentValues
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException

/** Private, read-only artwork access shared by the UI and media notification. */
class ArtworkProvider : ContentProvider() {
    private val extractionLock = Any()

    override fun onCreate() = true
    override fun getType(uri: Uri) = "image/jpeg"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Artwork is read-only")
        val parts = uri.pathSegments
        val id = parts.getOrNull(0)?.toLongOrNull()
        val revision = parts.getOrNull(1)?.toLongOrNull()
        if (parts.size != 2 || id == null || id < 0 || revision == null || revision < 0) {
            throw FileNotFoundException("Invalid artwork address")
        }
        val appContext = context ?: throw FileNotFoundException("No application context")
        synchronized(extractionLock) {
            val directory = File(appContext.cacheDir, "embedded_covers")
            if (!directory.exists() && !directory.mkdirs()) throw FileNotFoundException("No artwork cache")
            val cached = File(directory, "$id-$revision.jpg")
            if (!cached.exists()) {
                var bitmap: Bitmap? = null
                try {
                    val retriever = MediaMetadataRetriever()
                    val picture = try {
                        retriever.setDataSource(appContext, ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id))
                        retriever.embeddedPicture
                    } finally { retriever.release() } ?: throw FileNotFoundException("No embedded cover")
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(picture, 0, picture.size, bounds)
                    var sample = 1
                    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 512) sample *= 2
                    bitmap = BitmapFactory.decodeByteArray(picture, 0, picture.size,
                        BitmapFactory.Options().apply { inSampleSize = sample })
                    val image = bitmap ?: throw FileNotFoundException("Invalid cover image")
                    val atomic = AtomicFile(cached)
                    val output = atomic.startWrite()
                    try {
                        if (!image.compress(Bitmap.CompressFormat.JPEG, 85, output)) {
                            throw FileNotFoundException("Could not encode cover")
                        }
                        atomic.finishWrite(output)
                    } catch (error: Exception) {
                        atomic.failWrite(output)
                        throw error
                    }
                    // Bound this app-owned cache, preserving the cover being opened.
                    val files = directory.listFiles()?.filter { it.extension == "jpg" }
                        ?.sortedBy { it.lastModified() }.orEmpty()
                    var total = files.sumOf { it.length() }
                    for (file in files) {
                        if (total <= 32L * 1024 * 1024) break
                        if (file != cached) {
                            val length = file.length()
                            if (file.delete()) total -= length
                        }
                    }
                } catch (error: Exception) {
                    throw FileNotFoundException(error.message ?: "Cover unavailable")
                } finally { bitmap?.recycle() }
            }
            return ParcelFileDescriptor.open(cached, ParcelFileDescriptor.MODE_READ_ONLY)
        }
    }
}
