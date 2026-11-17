class VideoMetadata {
  final int? id;
  final String rootPath;
  final String? projectId;
  final String filePath;
  final String fileName;
  final String? relativePath;
  final String? duration;
  final String? resolution;
  final String? codec;
  final String? frameRate;
  final String? bitrate;
  final String? fileSize;
  final String? thumbnailPath;

  // 音频信息
  final String? audioCodec;
  final String? audioSampleRate;
  final String? audioChannels;
  final String? audioBitrate;

  // 色彩信息
  final String? colorSpace;
  final String? colorPrimaries;
  final String? colorTransfer;
  final String? colorRange;
  final String? chromaLocation;
  final String? pixelFormat;

  // 设备信息
  final String? cameraMake;
  final String? cameraModel;
  final String? lensModel;
  final String? iso;
  final String? whiteBalance;

  // 时间信息
  final String? recordStartTime;
  final String? recordEndTime;

  // ALE扩展字段 - 相机信息
  final String? cameraSn;
  final String? cameraId;
  final String? cameraIndex;

  // ALE扩展字段 - 镜头信息
  final String? lensSn;
  final String? lensType;
  final String? focusDistanceUnit;
  final String? ndFilterDensity;

  // ALE扩展字段 - 色彩信息
  final String? gamma;
  final String? ccShift;
  final String? exposureIndex;
  final String? lookName;
  final String? lookBurnedIn;
  final String? lookUserLut;
  final String? lutFileName;

  // ALE扩展字段 - 拍摄参数
  final String? shutterAngle;
  final String? sensorFps;
  final String? imageOrientation;
  final String? imageSharpness;
  final String? imageDetail;
  final String? imageDenoising;

  // ALE扩展字段 - 制作信息
  final String? production;
  final String? cinematographer;
  final String? operator;
  final String? director;
  final String? location;
  final String? company;
  final String? userInfo1;
  final String? userInfo2;

  // ALE扩展字段 - 场记信息
  final String? reelName;
  final String? scene;
  final String? take;
  final String? dateCamera;
  final String? timeCamera;

  // ALE扩展字段 - 其他
  final String? uuid;
  final String? supVersion;
  final String? storageSn;
  final String? projectFps;
  final String? ascSat;
  final String? ascSop;

  // ALE元数据（原始JSON字符串，保留用于兼容）
  final String? aleMetadata;

  final DateTime createdAt;

  VideoMetadata({
    this.id,
    required this.rootPath,
    this.projectId,
    required this.filePath,
    required this.fileName,
    this.relativePath,
    this.duration,
    this.resolution,
    this.codec,
    this.frameRate,
    this.bitrate,
    this.fileSize,
    this.thumbnailPath,
    this.audioCodec,
    this.audioSampleRate,
    this.audioChannels,
    this.audioBitrate,
    this.colorSpace,
    this.colorPrimaries,
    this.colorTransfer,
    this.colorRange,
    this.chromaLocation,
    this.pixelFormat,
    this.cameraMake,
    this.cameraModel,
    this.lensModel,
    this.iso,
    this.whiteBalance,
    this.recordStartTime,
    this.recordEndTime,
    this.cameraSn,
    this.cameraId,
    this.cameraIndex,
    this.lensSn,
    this.lensType,
    this.focusDistanceUnit,
    this.ndFilterDensity,
    this.gamma,
    this.ccShift,
    this.exposureIndex,
    this.lookName,
    this.lookBurnedIn,
    this.lookUserLut,
    this.lutFileName,
    this.shutterAngle,
    this.sensorFps,
    this.imageOrientation,
    this.imageSharpness,
    this.imageDetail,
    this.imageDenoising,
    this.production,
    this.cinematographer,
    this.operator,
    this.director,
    this.location,
    this.company,
    this.userInfo1,
    this.userInfo2,
    this.reelName,
    this.scene,
    this.take,
    this.dateCamera,
    this.timeCamera,
    this.uuid,
    this.supVersion,
    this.storageSn,
    this.projectFps,
    this.ascSat,
    this.ascSop,
    this.aleMetadata,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'root_path': rootPath,
      'project_id': projectId,
      'file_path': filePath,
      'file_name': fileName,
      'relative_path': relativePath,
      'duration': duration,
      'resolution': resolution,
      'codec': codec,
      'frame_rate': frameRate,
      'bitrate': bitrate,
      'file_size': fileSize,
      'thumbnail_path': thumbnailPath,
      'audio_codec': audioCodec,
      'audio_sample_rate': audioSampleRate,
      'audio_channels': audioChannels,
      'audio_bitrate': audioBitrate,
      'color_space': colorSpace,
      'color_primaries': colorPrimaries,
      'color_transfer': colorTransfer,
      'color_range': colorRange,
      'chroma_location': chromaLocation,
      'pixel_format': pixelFormat,
      'camera_make': cameraMake,
      'camera_model': cameraModel,
      'lens_model': lensModel,
      'iso': iso,
      'white_balance': whiteBalance,
      'record_start_time': recordStartTime,
      'record_end_time': recordEndTime,
      'camera_sn': cameraSn,
      'camera_id': cameraId,
      'camera_index': cameraIndex,
      'lens_sn': lensSn,
      'lens_type': lensType,
      'focus_distance_unit': focusDistanceUnit,
      'nd_filter_density': ndFilterDensity,
      'gamma': gamma,
      'cc_shift': ccShift,
      'exposure_index': exposureIndex,
      'look_name': lookName,
      'look_burned_in': lookBurnedIn,
      'look_user_lut': lookUserLut,
      'lut_file_name': lutFileName,
      'shutter_angle': shutterAngle,
      'sensor_fps': sensorFps,
      'image_orientation': imageOrientation,
      'image_sharpness': imageSharpness,
      'image_detail': imageDetail,
      'image_denoising': imageDenoising,
      'production': production,
      'cinematographer': cinematographer,
      'operator': operator,
      'director': director,
      'location': location,
      'company': company,
      'user_info1': userInfo1,
      'user_info2': userInfo2,
      'reel_name': reelName,
      'scene': scene,
      'take': take,
      'date_camera': dateCamera,
      'time_camera': timeCamera,
      'uuid': uuid,
      'sup_version': supVersion,
      'storage_sn': storageSn,
      'project_fps': projectFps,
      'asc_sat': ascSat,
      'asc_sop': ascSop,
      'ale_metadata': aleMetadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory VideoMetadata.fromMap(Map<String, dynamic> map) {
    return VideoMetadata(
      id: map['id'],
      rootPath: map['root_path'],
      projectId: map['project_id'],
      filePath: map['file_path'],
      fileName: map['file_name'],
      relativePath: map['relative_path'],
      duration: map['duration'],
      resolution: map['resolution'],
      codec: map['codec'],
      frameRate: map['frame_rate'],
      bitrate: map['bitrate'],
      fileSize: map['file_size'],
      thumbnailPath: map['thumbnail_path'],
      audioCodec: map['audio_codec'],
      audioSampleRate: map['audio_sample_rate'],
      audioChannels: map['audio_channels'],
      audioBitrate: map['audio_bitrate'],
      colorSpace: map['color_space'],
      colorPrimaries: map['color_primaries'],
      colorTransfer: map['color_transfer'],
      colorRange: map['color_range'],
      chromaLocation: map['chroma_location'],
      pixelFormat: map['pixel_format'],
      cameraMake: map['camera_make'],
      cameraModel: map['camera_model'],
      lensModel: map['lens_model'],
      iso: map['iso'],
      whiteBalance: map['white_balance'],
      recordStartTime: map['record_start_time'],
      recordEndTime: map['record_end_time'],
      cameraSn: map['camera_sn'],
      cameraId: map['camera_id'],
      cameraIndex: map['camera_index'],
      lensSn: map['lens_sn'],
      lensType: map['lens_type'],
      focusDistanceUnit: map['focus_distance_unit'],
      ndFilterDensity: map['nd_filter_density'],
      gamma: map['gamma'],
      ccShift: map['cc_shift'],
      exposureIndex: map['exposure_index'],
      lookName: map['look_name'],
      lookBurnedIn: map['look_burned_in'],
      lookUserLut: map['look_user_lut'],
      lutFileName: map['lut_file_name'],
      shutterAngle: map['shutter_angle'],
      sensorFps: map['sensor_fps'],
      imageOrientation: map['image_orientation'],
      imageSharpness: map['image_sharpness'],
      imageDetail: map['image_detail'],
      imageDenoising: map['image_denoising'],
      production: map['production'],
      cinematographer: map['cinematographer'],
      operator: map['operator'],
      director: map['director'],
      location: map['location'],
      company: map['company'],
      userInfo1: map['user_info1'],
      userInfo2: map['user_info2'],
      reelName: map['reel_name'],
      scene: map['scene'],
      take: map['take'],
      dateCamera: map['date_camera'],
      timeCamera: map['time_camera'],
      uuid: map['uuid'],
      supVersion: map['sup_version'],
      storageSn: map['storage_sn'],
      projectFps: map['project_fps'],
      ascSat: map['asc_sat'],
      ascSop: map['asc_sop'],
      aleMetadata: map['ale_metadata'],
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  VideoMetadata copyWith({
    int? id,
    String? rootPath,
    String? projectId,
    String? filePath,
    String? fileName,
    String? relativePath,
    String? duration,
    String? resolution,
    String? codec,
    String? frameRate,
    String? bitrate,
    String? fileSize,
    String? thumbnailPath,
    String? audioCodec,
    String? audioSampleRate,
    String? audioChannels,
    String? audioBitrate,
    String? colorSpace,
    String? colorPrimaries,
    String? colorTransfer,
    String? colorRange,
    String? chromaLocation,
    String? pixelFormat,
    String? cameraMake,
    String? cameraModel,
    String? lensModel,
    String? iso,
    String? whiteBalance,
    String? recordStartTime,
    String? recordEndTime,
    String? cameraSn,
    String? cameraId,
    String? cameraIndex,
    String? lensSn,
    String? lensType,
    String? focusDistanceUnit,
    String? ndFilterDensity,
    String? gamma,
    String? ccShift,
    String? exposureIndex,
    String? lookName,
    String? lookBurnedIn,
    String? lookUserLut,
    String? lutFileName,
    String? shutterAngle,
    String? sensorFps,
    String? imageOrientation,
    String? imageSharpness,
    String? imageDetail,
    String? imageDenoising,
    String? production,
    String? cinematographer,
    String? operator,
    String? director,
    String? location,
    String? company,
    String? userInfo1,
    String? userInfo2,
    String? reelName,
    String? scene,
    String? take,
    String? dateCamera,
    String? timeCamera,
    String? uuid,
    String? supVersion,
    String? storageSn,
    String? projectFps,
    String? ascSat,
    String? ascSop,
    String? aleMetadata,
    DateTime? createdAt,
  }) {
    return VideoMetadata(
      id: id ?? this.id,
      rootPath: rootPath ?? this.rootPath,
      projectId: projectId ?? this.projectId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      relativePath: relativePath ?? this.relativePath,
      duration: duration ?? this.duration,
      resolution: resolution ?? this.resolution,
      codec: codec ?? this.codec,
      frameRate: frameRate ?? this.frameRate,
      bitrate: bitrate ?? this.bitrate,
      fileSize: fileSize ?? this.fileSize,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      audioCodec: audioCodec ?? this.audioCodec,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      colorSpace: colorSpace ?? this.colorSpace,
      colorPrimaries: colorPrimaries ?? this.colorPrimaries,
      colorTransfer: colorTransfer ?? this.colorTransfer,
      colorRange: colorRange ?? this.colorRange,
      chromaLocation: chromaLocation ?? this.chromaLocation,
      pixelFormat: pixelFormat ?? this.pixelFormat,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      lensModel: lensModel ?? this.lensModel,
      iso: iso ?? this.iso,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      recordStartTime: recordStartTime ?? this.recordStartTime,
      recordEndTime: recordEndTime ?? this.recordEndTime,
      cameraSn: cameraSn ?? this.cameraSn,
      cameraId: cameraId ?? this.cameraId,
      cameraIndex: cameraIndex ?? this.cameraIndex,
      lensSn: lensSn ?? this.lensSn,
      lensType: lensType ?? this.lensType,
      focusDistanceUnit: focusDistanceUnit ?? this.focusDistanceUnit,
      ndFilterDensity: ndFilterDensity ?? this.ndFilterDensity,
      gamma: gamma ?? this.gamma,
      ccShift: ccShift ?? this.ccShift,
      exposureIndex: exposureIndex ?? this.exposureIndex,
      lookName: lookName ?? this.lookName,
      lookBurnedIn: lookBurnedIn ?? this.lookBurnedIn,
      lookUserLut: lookUserLut ?? this.lookUserLut,
      lutFileName: lutFileName ?? this.lutFileName,
      shutterAngle: shutterAngle ?? this.shutterAngle,
      sensorFps: sensorFps ?? this.sensorFps,
      imageOrientation: imageOrientation ?? this.imageOrientation,
      imageSharpness: imageSharpness ?? this.imageSharpness,
      imageDetail: imageDetail ?? this.imageDetail,
      imageDenoising: imageDenoising ?? this.imageDenoising,
      production: production ?? this.production,
      cinematographer: cinematographer ?? this.cinematographer,
      operator: operator ?? this.operator,
      director: director ?? this.director,
      location: location ?? this.location,
      company: company ?? this.company,
      userInfo1: userInfo1 ?? this.userInfo1,
      userInfo2: userInfo2 ?? this.userInfo2,
      reelName: reelName ?? this.reelName,
      scene: scene ?? this.scene,
      take: take ?? this.take,
      dateCamera: dateCamera ?? this.dateCamera,
      timeCamera: timeCamera ?? this.timeCamera,
      uuid: uuid ?? this.uuid,
      supVersion: supVersion ?? this.supVersion,
      storageSn: storageSn ?? this.storageSn,
      projectFps: projectFps ?? this.projectFps,
      ascSat: ascSat ?? this.ascSat,
      ascSop: ascSop ?? this.ascSop,
      aleMetadata: aleMetadata ?? this.aleMetadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
