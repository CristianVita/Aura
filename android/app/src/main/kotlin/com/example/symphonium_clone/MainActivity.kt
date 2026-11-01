package com.example.symphonium_clone

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.util.AtomicFile
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.io.File
import org.json.JSONObject
import org.json.JSONArray

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.example.symphonium_clone/audio_library"
    private val permissionRequestCode = 4281
    private val queryExecutor = Executors.newSingleThreadExecutor()
    private val artworkExecutor = Executors.newFixedThreadPool(2)
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanAudio" -> requestAudioAccessAndScan(result)
                    "loadLibrary" -> loadLibrary(result)
                    "loadSavedMusic", "loadPlaybackMemory" -> {
                        val fileName = if (call.method == "loadSavedMusic") "saved_music.json" else "playback_memory.json"
                        queryExecutor.execute {
                            try {
                                val file = AtomicFile(File(filesDir, fileName))
                                val saved = try {
                                    file.openRead().bufferedReader().use { it.readText() }
                                } catch (_: java.io.FileNotFoundException) { null }
                                runOnUiThread { result.success(saved) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("saved_music_load_failed", error.localizedMessage, null) }
                            }
                        }
                    }
                    "saveSavedMusic", "savePlaybackMemory" -> {
                        val fileName = if (call.method == "saveSavedMusic") "saved_music.json" else "playback_memory.json"
                        val json = call.argument<String>("json")
                        if (json == null) {
                            result.error("invalid_data", "Missing saved music", null)
                        } else queryExecutor.execute {
                            try {
                                check(JSONObject(json).getInt("version") == 1)
                                val file = AtomicFile(File(filesDir, fileName))
                                val output = file.startWrite()
                                try {
                                    output.write(json.toByteArray(Charsets.UTF_8))
                                    file.finishWrite(output)
                                } catch (error: Exception) {
                                    file.failWrite(output)
                                    throw error
                                }
                                runOnUiThread { result.success(null) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("saved_music_save_failed", error.localizedMessage, null) }
                            }
                        }
                    }
                    "loadArtwork" -> {
                        val source = call.argument<String>("uri")
                        artworkExecutor.execute {
                            val bytes = source?.let { loadArtwork(it) }
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    "loadSourceFolders" -> {
                        try {
                            val saved = getSharedPreferences("library_sources", MODE_PRIVATE)
                                .getString("folders", null)
                            val folders = saved?.let {
                                val array = JSONArray(it)
                                (0 until array.length()).map { index -> array.getString(index) }
                            }
                            result.success(folders)
                        } catch (error: Exception) {
                            result.error("sources_load_failed", error.localizedMessage, null)
                        }
                    }
                    "saveSourceFolders" -> {
                        val folders = call.argument<List<String>>("folders")
                        queryExecutor.execute {
                            val editor = getSharedPreferences("library_sources", MODE_PRIVATE).edit()
                            if (folders == null) editor.remove("folders")
                            else editor.putString("folders", JSONArray(folders).toString())
                            val saved = editor.commit()
                            runOnUiThread {
                                if (saved) result.success(null)
                                else result.error("save_failed", "Could not save source folders", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun loadArtwork(source: String): ByteArray? {
        val uri = Uri.parse(source)
        if (!hasAudioAccess() || uri.scheme != "content" || uri.authority != "$packageName.artwork") {
            return null
        }
        return try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun hasAudioAccess(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun libraryFile() = AtomicFile(File(filesDir, "audio_library.json"))

    private fun saveLibrary(tracks: List<Map<String, Any>>) {
        val data = JSONObject()
            .put("version", 3)
            .put("tracks", JSONArray(tracks))
            .toString().toByteArray(Charsets.UTF_8)
        val file = libraryFile()
        val output = file.startWrite()
        try {
            output.write(data)
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    private fun loadLibrary(result: MethodChannel.Result) {
        queryExecutor.execute {
            try {
                if (!hasAudioAccess()) {
                    runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
                    return@execute
                }
                val cached = try {
                    val data = libraryFile().openRead().bufferedReader().use { it.readText() }
                    val root = JSONObject(data)
                    check(root.getInt("version") == 3)
                    val rows = root.getJSONArray("tracks")
                    (0 until rows.length()).map { index ->
                        val row = rows.getJSONObject(index)
                        mapOf<String, Any>(
                            "id" to row.getString("id"),
                            "title" to row.getString("title"),
                            "artist" to row.getString("artist"),
                            "album" to row.getString("album"),
                            "durationMs" to row.getLong("durationMs"),
                            "uri" to row.getString("uri"),
                            "folder" to row.getString("folder"),
                            "modifiedSeconds" to row.getLong("modifiedSeconds"),
                        )
                    }
                } catch (_: Exception) {
                    null
                }
                // Seed the cache on upgrade or recover a missing/damaged cache.
                val tracks = cached ?: readAudioTracks().also { saveLibrary(it) }
                runOnUiThread { result.success(tracks) }
            } catch (error: Exception) {
                runOnUiThread { result.error("load_failed", error.localizedMessage, null) }
            }
        }
    }

    private fun requestAudioAccessAndScan(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("scan_in_progress", "A music scan is already in progress.", null)
            return
        }

        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            scanAudio(result)
        } else {
            pendingPermissionResult = result
            requestPermissions(arrayOf(permission), permissionRequestCode)
        }
    }

    @Deprecated("Deprecated in Android, but required for this permission flow.")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return

        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            scanAudio(result)
        } else {
            result.error(
                "permission_denied",
                "Audio permission was not granted.",
                null,
            )
        }
    }

    private fun scanAudio(result: MethodChannel.Result) {
        queryExecutor.execute {
            try {
                val tracks = readAudioTracks()
                saveLibrary(tracks)
                runOnUiThread { result.success(tracks) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("scan_failed", error.localizedMessage, null)
                }
            }
        }
    }

    private fun readAudioTracks(): List<Map<String, Any>> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.MediaColumns.DATE_MODIFIED,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        val tracks = mutableListOf<Map<String, Any>>()

        contentResolver.query(collection, projection, selection, null, sortOrder)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val folderColumn = cursor.getColumnIndexOrThrow(projection.last())

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val title = cursor.getString(titleColumn).orEmpty()
                if (title.isBlank()) continue

                val artist = cursor.getString(artistColumn)
                    .orEmpty()
                    .takeUnless { it == "<unknown>" }
                    .orEmpty()
                val album = cursor.getString(albumColumn)
                    .orEmpty()
                    .takeUnless { it == "<unknown>" }
                    .orEmpty()
                val duration = cursor.getLong(durationColumn)
                val contentUri = ContentUris.withAppendedId(collection, id).toString()
                val path = cursor.getString(folderColumn).orEmpty()
                val folder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    path.trimEnd('/')
                } else {
                    File(path).parent.orEmpty()
                }

                tracks += mapOf(
                    "id" to id.toString(),
                    "title" to title,
                    "artist" to artist,
                    "album" to album,
                    "durationMs" to duration,
                    "uri" to contentUri,
                    "folder" to folder,
                    "modifiedSeconds" to cursor.getLong(modifiedColumn),
                )
            }
        }

        return tracks
    }

    override fun onDestroy() {
        queryExecutor.shutdown()
        artworkExecutor.shutdown()
        super.onDestroy()
    }
}
