import 'package:flutter_test/flutter_test.dart';
import 'package:bombreel_tiktok_share/bombreel_tiktok_share.dart';
import 'package:bombreel_tiktok_share/bombreel_tiktok_share_platform_interface.dart';
import 'package:bombreel_tiktok_share/bombreel_tiktok_share_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBombreelTiktokSharePlatform
    with MockPlatformInterfaceMixin
    implements BombreelTiktokSharePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final BombreelTiktokSharePlatform initialPlatform = BombreelTiktokSharePlatform.instance;

  test('$MethodChannelBombreelTiktokShare is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBombreelTiktokShare>());
  });

  test('getPlatformVersion', () async {
    BombreelTiktokShare bombreelTiktokSharePlugin = BombreelTiktokShare();
    MockBombreelTiktokSharePlatform fakePlatform = MockBombreelTiktokSharePlatform();
    BombreelTiktokSharePlatform.instance = fakePlatform;

    expect(await bombreelTiktokSharePlugin.getPlatformVersion(), '42');
  });
}
