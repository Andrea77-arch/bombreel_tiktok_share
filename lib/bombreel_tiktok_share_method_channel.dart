import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bombreel_tiktok_share_platform_interface.dart';

class MethodChannelBombreelTiktokShare
    extends BombreelTiktokSharePlatform {
  @visibleForTesting
  final methodChannel =
      const MethodChannel('bombreel_tiktok_share');

  @override
  Future<String?> getPlatformVersion() async {
    return methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
  }

  @override
  Future<bool> shareVideo(String videoPath) async {
    final launched = await methodChannel.invokeMethod<bool>(
      'shareVideo',
      {
        'videoPath': videoPath,
      },
    );

    return launched ?? false;
  }
}
