import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'bombreel_tiktok_share_method_channel.dart';

abstract class BombreelTiktokSharePlatform extends PlatformInterface {
  BombreelTiktokSharePlatform() : super(token: _token);

  static final Object _token = Object();

  static BombreelTiktokSharePlatform _instance =
      MethodChannelBombreelTiktokShare();

  static BombreelTiktokSharePlatform get instance => _instance;

  static set instance(BombreelTiktokSharePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError(
      'getPlatformVersion() has not been implemented.',
    );
  }

  Future<bool> shareVideo(String videoPath) {
    throw UnimplementedError(
      'shareVideo() has not been implemented.',
    );
  }
}
