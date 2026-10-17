import 'package:background_downloader/background_downloader.dart';

/// Resume-data persistence helpers.
///
/// background_downloader stores resume bytes keyed by taskId but does not
/// expose read/write on [FileDownloader]. The database [PersistentStorage]
/// is the supported test surface; we use it to re-bind signed URLs without
/// losing partial files.
class DownloadResumeStore {
  DownloadResumeStore({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  // background_downloader exposes resume I/O only on PersistentStorage (test API).
  // ignore: invalid_use_of_visible_for_testing_member
  PersistentStorage get _storage => _downloader.database.storage;

  Future<ResumeData?> resumeDataFor(String taskId) =>
      _storage.retrieveResumeData(taskId);

  Future<void> saveResumeData(ResumeData data) =>
      _storage.storeResumeData(data);

  Future<void> deleteResumeData(String taskId) =>
      _storage.removeResumeData(taskId);

  Future<TaskRecord?> taskRecordFor(String taskId) =>
      _downloader.database.recordForId(taskId);

  Future<void> deleteTaskRecord(String taskId) =>
      _downloader.database.deleteRecordWithId(taskId);

  /// Copies resume metadata from [fromTaskId] to [toTaskId] and removes legacy.
  Future<void> migrateResumeData({
    required String fromTaskId,
    required String toTaskId,
    required DownloadTask updatedTask,
  }) async {
    final existing = await resumeDataFor(fromTaskId);
    if (existing == null) {
      return;
    }
    if (fromTaskId != toTaskId) {
      await deleteResumeData(fromTaskId);
    }
    await saveResumeData(
      ResumeData(
        updatedTask,
        existing.data,
        existing.requiredStartByte,
        existing.eTag,
      ),
    );
  }
}
