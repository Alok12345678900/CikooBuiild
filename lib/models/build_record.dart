class BuildRecord {
  const BuildRecord({
    required this.id,
    required this.type,
    required this.owner,
    required this.repo,
    required this.workflow,
    required this.startedAt,
    this.finishedAt,
    this.status = 'queued',
    this.percent = 0,
    this.step = '',
    this.runId,
    this.baselineRunId = 0,
    this.url,
    this.artifactsUrl,
    this.diagnostics = const [],
    this.isInstalled = false,
    this.runNumber,
    this.branch,
    this.sha,
    this.actor,
    this.mode = '',
    this.customWorkflow = false,
    this.jobs = const [],
    this.logTail = '',
    this.apkPath,
    this.downloadState = 'none',
    this.downloadPercent = 0,
    this.downloadError = '',
    this.chain = const {},
    this.analysis = const {},
    this.apkLabel = '',
    this.apkPackage = '',
    this.apkVersion = '',
    this.apkIconPath = '',
    this.apkSize = 0,
    this.logPath = '',
    this.uploadLog = '',
    this.uploadSteps = const [],
    this.publicPath = '',
    this.cloudLink = '',
  });

  final String id;
  final String type; // ANDROID | FLUTTER | WEBTOAPK
  final String owner;
  final String repo;
  final String workflow;
  final int startedAt;
  final int? finishedAt;
  final String status; // queued | running | success | failure | cancelled
  final int percent;
  final String step;
  final int? runId;
  final int baselineRunId;
  final String? url;
  final String? artifactsUrl;
  final List<String> diagnostics;
  final bool isInstalled;

  // Detail run GitHub
  final int? runNumber;
  final String? branch;
  final String? sha;
  final String? actor;
  final String mode; // release | debug
  final bool customWorkflow; // true = .yml dari pengguna, false = bawaan assets

  /// Detail job + step: [{id,name,status,conclusion,start,end,runner,url,steps:[{n,name,status,conclusion,start,end}]}]
  final List<Map<String, dynamic>> jobs;
  final String logTail;

  // Hasil download APK (artifact) di perangkat
  final String? apkPath;
  final String downloadState; // none | downloading | done | failed
  final int downloadPercent;
  final String downloadError;

  /// Analyzer: workflow build yang dijalankan otomatis bila tidak ada error.
  final Map<String, dynamic> chain;

  /// Analyzer: hasil analisis {kind, steps, findings (hanya error)}.
  final Map<String, dynamic> analysis;

  // Info APK hasil build (dibaca dari file APK)
  final String apkLabel;
  final String apkPackage;
  final String apkVersion;
  final String apkIconPath;
  final int apkSize;

  /// Log lengkap build yang gagal (file di penyimpanan aplikasi).
  final String logPath;

  /// Log & tahap upload sebelum build dimulai.
  final String uploadLog;
  final List<String> uploadSteps;

  /// Salinan APK di folder Download publik; '!' di awal = gagal.
  final String publicPath;

  /// Link Google Drive; '!' di awal = gagal.
  final String cloudLink;

  bool get isFinished =>
      status == 'success' || status == 'failure' || status == 'cancelled';
  bool get isSuccess => status == 'success';
  bool get isAnalyzer => type == 'ANALYZER';

  List<Map<String, dynamic>> get analysisErrors {
    final f = analysis['findings'];
    if (f is! List) return const [];
    return f.whereType<Map>().map((m) => m.map((k, v) => MapEntry(k.toString(), v))).toList();
  }

  bool get isDownloading => downloadState == 'downloading';
  bool get hasApk => apkPath != null && apkPath!.isNotEmpty && downloadState == 'done';

  int get elapsedMs {
    final end = finishedAt ?? DateTime.now().millisecondsSinceEpoch;
    final v = end - startedAt;
    return v < 0 ? 0 : v;
  }

  String get typeLabel {
    switch (type) {
      case 'FLUTTER':
        return 'Flutter';
      case 'WEBTOAPK':
        return 'WebToAPK';
      case 'ANALYZER':
        return 'Analyzer';
      case 'ANDROID':
      default:
        return 'Android Studio';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'queued':
        return 'Mengantre';
      case 'uploading':
        return 'Mengunggah';
      case 'running':
        return 'Berjalan';
      case 'success':
        return 'Berhasil';
      case 'cancelled':
        return 'Dibatalkan';
      case 'failure':
      default:
        return 'Gagal';
    }
  }

  BuildRecord copyWith({
    int? finishedAt,
    String? status,
    int? percent,
    String? step,
    int? runId,
    String? url,
    String? artifactsUrl,
    List<String>? diagnostics,
    bool? isInstalled,
    int? runNumber,
    String? branch,
    String? sha,
    String? actor,
    List<Map<String, dynamic>>? jobs,
    String? logTail,
    String? apkPath,
    String? downloadState,
    int? downloadPercent,
    String? downloadError,
    Map<String, dynamic>? chain,
    Map<String, dynamic>? analysis,
    String? apkLabel,
    String? apkPackage,
    String? apkVersion,
    String? apkIconPath,
    int? apkSize,
    String? logPath,
    String? uploadLog,
    List<String>? uploadSteps,
    String? publicPath,
    String? cloudLink,
  }) {
    return BuildRecord(
      id: id,
      type: type,
      owner: owner,
      repo: repo,
      workflow: workflow,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      status: status ?? this.status,
      percent: percent ?? this.percent,
      step: step ?? this.step,
      runId: runId ?? this.runId,
      baselineRunId: baselineRunId,
      url: url ?? this.url,
      artifactsUrl: artifactsUrl ?? this.artifactsUrl,
      diagnostics: diagnostics ?? this.diagnostics,
      isInstalled: isInstalled ?? this.isInstalled,
      runNumber: runNumber ?? this.runNumber,
      branch: branch ?? this.branch,
      sha: sha ?? this.sha,
      actor: actor ?? this.actor,
      mode: mode,
      customWorkflow: customWorkflow,
      jobs: jobs ?? this.jobs,
      logTail: logTail ?? this.logTail,
      apkPath: apkPath ?? this.apkPath,
      downloadState: downloadState ?? this.downloadState,
      downloadPercent: downloadPercent ?? this.downloadPercent,
      downloadError: downloadError ?? this.downloadError,
      chain: chain ?? this.chain,
      analysis: analysis ?? this.analysis,
      apkLabel: apkLabel ?? this.apkLabel,
      apkPackage: apkPackage ?? this.apkPackage,
      apkVersion: apkVersion ?? this.apkVersion,
      apkIconPath: apkIconPath ?? this.apkIconPath,
      apkSize: apkSize ?? this.apkSize,
      logPath: logPath ?? this.logPath,
      uploadLog: uploadLog ?? this.uploadLog,
      uploadSteps: uploadSteps ?? this.uploadSteps,
      publicPath: publicPath ?? this.publicPath,
      cloudLink: cloudLink ?? this.cloudLink,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'owner': owner,
        'repo': repo,
        'workflow': workflow,
        'startedAt': startedAt,
        'finishedAt': finishedAt,
        'status': status,
        'percent': percent,
        'step': step,
        'runId': runId,
        'baselineRunId': baselineRunId,
        'url': url,
        'artifactsUrl': artifactsUrl,
        'diagnostics': diagnostics,
        'isInstalled': isInstalled,
        'runNumber': runNumber,
        'branch': branch,
        'sha': sha,
        'actor': actor,
        'mode': mode,
        'customWorkflow': customWorkflow,
        'jobs': jobs,
        'logTail': logTail,
        'apkPath': apkPath,
        'downloadState': downloadState,
        'downloadPercent': downloadPercent,
        'downloadError': downloadError,
        'chain': chain,
        'analysis': analysis,
        'apkLabel': apkLabel,
        'apkPackage': apkPackage,
        'apkVersion': apkVersion,
        'apkIconPath': apkIconPath,
        'apkSize': apkSize,
        'logPath': logPath,
        'uploadLog': uploadLog,
        'uploadSteps': uploadSteps,
        'publicPath': publicPath,
        'cloudLink': cloudLink,
      };

  factory BuildRecord.fromJson(Map<String, dynamic> j) => BuildRecord(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'ANDROID',
        owner: j['owner'] as String? ?? '',
        repo: j['repo'] as String? ?? '',
        workflow: j['workflow'] as String? ?? '',
        startedAt: (j['startedAt'] as num).toInt(),
        finishedAt: (j['finishedAt'] as num?)?.toInt(),
        status: j['status'] as String? ?? 'queued',
        percent: (j['percent'] as num?)?.toInt() ?? 0,
        step: j['step'] as String? ?? '',
        runId: (j['runId'] as num?)?.toInt(),
        baselineRunId: (j['baselineRunId'] as num?)?.toInt() ?? 0,
        url: j['url'] as String?,
        artifactsUrl: j['artifactsUrl'] as String?,
        diagnostics:
            (j['diagnostics'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        isInstalled: j['isInstalled'] as bool? ?? false,
        runNumber: (j['runNumber'] as num?)?.toInt(),
        branch: j['branch'] as String?,
        sha: j['sha'] as String?,
        actor: j['actor'] as String?,
        mode: j['mode'] as String? ?? '',
        customWorkflow: j['customWorkflow'] as bool? ?? false,
        jobs: (j['jobs'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        logTail: j['logTail'] as String? ?? '',
        apkPath: j['apkPath'] as String?,
        downloadState: j['downloadState'] as String? ?? 'none',
        downloadPercent: (j['downloadPercent'] as num?)?.toInt() ?? 0,
        downloadError: j['downloadError'] as String? ?? '',
        chain: _asMap(j['chain']),
        analysis: _asMap(j['analysis']),
        apkLabel: j['apkLabel'] as String? ?? '',
        apkPackage: j['apkPackage'] as String? ?? '',
        apkVersion: j['apkVersion'] as String? ?? '',
        apkIconPath: j['apkIconPath'] as String? ?? '',
        apkSize: (j['apkSize'] as num?)?.toInt() ?? 0,
        logPath: j['logPath'] as String? ?? '',
        uploadLog: j['uploadLog'] as String? ?? '',
        uploadSteps: (j['uploadSteps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        publicPath: j['publicPath'] as String? ?? '',
        cloudLink: j['cloudLink'] as String? ?? '',
      );
}

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};
