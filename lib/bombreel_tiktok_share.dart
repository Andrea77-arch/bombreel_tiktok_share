import 'bombreel_tiktok_share_platform_interface.dart';

class BombreelTiktokShare {
  Future<String?> getPlatformVersion() {
    return BombreelTiktokSharePlatform.instance.getPlatformVersion();
  }

  Future<bool> shareVideo(String videoPath) {
    return BombreelTiktokSharePlatform.instance.shareVideo(videoPath);
  }
}
