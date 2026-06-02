import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class ModelDownloadService {
  final Map<String, StreamSubscription?> _activeDownloads = {};
  final Map<String, bool> _cancelledDownloads = {};

  // Download a model file from a remote URL with real-time progress callbacks.
  // Supports chunked stream download and a simulated high-fidelity mode.
  Future<void> downloadModel({
    required String modelId,
    required String url,
    required String localPath,
    required Function(double progress) onProgress,
    required Function(String localPath) onComplete,
    required Function(dynamic error) onError,
  }) async {
    _cancelledDownloads[modelId] = false;

    // Determine if we should run a high-fidelity simulation (when using mock URLs, or for robust testing)
    final isMockUrl = url.contains('mock') || 
                      url.startsWith('http://mock') || 
                      url.contains('example.com') || 
                      !url.startsWith('http');

    if (isMockUrl) {
      await _downloadSimulated(modelId, localPath, onProgress, onComplete, onError);
    } else {
      await _downloadReal(modelId, url, localPath, onProgress, onComplete, onError);
    }
  }

  // Cancel an ongoing download
  void cancelDownload(String modelId) {
    _cancelledDownloads[modelId] = true;
    final subscription = _activeDownloads[modelId];
    if (subscription != null) {
      subscription.cancel();
      _activeDownloads.remove(modelId);
    }
  }

  Future<void> _downloadReal(
    String modelId,
    String url,
    String localPath,
    Function(double progress) onProgress,
    Function(String localPath) onComplete,
    Function(dynamic error) onError,
  ) async {
    try {
      final file = File(localPath);
      if (file.existsSync()) {
        await file.delete();
      }
      
      // Ensure directory exists
      await file.parent.create(recursive: true);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;
      final sink = file.openWrite();

      final streamSubscription = response.stream.listen(
        (chunk) {
          if (_cancelledDownloads[modelId] == true) {
            return;
          }
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (contentLength > 0) {
            final progress = downloadedBytes / contentLength;
            onProgress(progress);
          }
        },
        onError: (err) async {
          await sink.close();
          client.close();
          onError(err);
        },
        onDone: () async {
          await sink.close();
          client.close();
          _activeDownloads.remove(modelId);

          if (_cancelledDownloads[modelId] == true) {
            if (file.existsSync()) {
              await file.delete();
            }
            onError('Download cancelled');
          } else {
            // Verify file size is greater than 0
            if (file.existsSync() && file.lengthSync() > 0) {
              onComplete(localPath);
            } else {
              onError('Downloaded file is empty or corrupted');
            }
          }
        },
        cancelOnError: true,
      );

      _activeDownloads[modelId] = streamSubscription;
    } catch (e) {
      onError(e);
    }
  }

  Future<void> _downloadSimulated(
    String modelId,
    String localPath,
    Function(double progress) onProgress,
    Function(String localPath) onComplete,
    Function(dynamic error) onError,
  ) async {
    try {
      final file = File(localPath);
      if (file.existsSync()) {
        await file.delete();
      }
      await file.parent.create(recursive: true);

      double progress = 0.0;
      final sink = file.openWrite();

      Timer.periodic(const Duration(milliseconds: 150), (timer) async {
        if (_cancelledDownloads[modelId] == true) {
          timer.cancel();
          await sink.close();
          if (file.existsSync()) {
            await file.delete();
          }
          onError('Download cancelled');
          return;
        }

        progress += 0.05;
        if (progress >= 1.0) {
          progress = 1.0;
          timer.cancel();
          
          sink.write('Simulated Model Weights GGUF file content for ID: $modelId');
          await sink.close();
          
          onProgress(1.0);
          onComplete(localPath);
        } else {
          sink.write('chunk_');
          onProgress(progress);
        }
      });
    } catch (e) {
      onError(e);
    }
  }
}
