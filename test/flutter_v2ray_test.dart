import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:flutter_v2ray/flutter_v2ray_platform_interface.dart';
import 'package:flutter_v2ray/flutter_v2ray_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterV2rayPlatform
    with MockPlatformInterfaceMixin
    implements FlutterV2rayPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterV2rayPlatform initialPlatform = FlutterV2rayPlatform.instance;

  test('$MethodChannelFlutterV2ray is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterV2ray>());
  });

  test('getPlatformVersion', () async {
    FlutterV2ray flutterV2rayPlugin = FlutterV2ray();
    MockFlutterV2rayPlatform fakePlatform = MockFlutterV2rayPlatform();
    FlutterV2rayPlatform.instance = fakePlatform;

    expect(await flutterV2rayPlugin.getPlatformVersion(), '42');
  });
}
