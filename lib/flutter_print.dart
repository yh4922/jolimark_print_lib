
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';


String intToHex (int interger) {
  String hex = interger.toRadixString(16).toUpperCase();
  return '0x' + hex;
}

class FlutterPrintCurrentAddr extends ValueNotifier<String> {
  FlutterPrintCurrentAddr(String value):super(value);
}

class FlutterPrint {
  /// 事件通道
  static const MethodChannel _channel = MethodChannel('flutter_print');
  /// 消息通道
  static StreamSubscription<dynamic>? _eventSubScript;
  /// 事件监听
  static StreamSubscription<dynamic> _eventChannelFor () {
    return const EventChannel('flutter_print_event')
      .receiveBroadcastStream()
      .listen(eventListener, onError: errorListener);
  }
  /// 初始化事件通道
  static void initEventChannel () {
    _eventSubScript = _eventChannelFor();
  }
  /// 事件监听回调函数
  static void eventListener (event) {
    final Map map = event as Map;
    switch (map['event']) {
      case 'demo': 
        String value = map['value'];
        print('收到::' + value);
        break;
      default:
        break;
    }
  }

  /// 错误监听回调函数
  static void errorListener (error) {
    final PlatformException e = error as PlatformException;
    throw e;
  }

  /// 获取插件版本
  static String pluginVersion () => 'v0.0.1';
    
  /// 打印机地址
  static FlutterPrintCurrentAddr printAddr = FlutterPrintCurrentAddr('');
  /// 打印机连接状态
  static bool printStatus = false;


  
  /// 链接Ble打印机
  /// 
  /// [mac] 打印机mac地址
  static Future<int> connectBle(String macaddr) async {
    final int code = await _channel.invokeMethod('connectBle', {
      'macaddr': macaddr,
    });
    if (code == 1) {
      printAddr.value = macaddr;
      printStatus = true;
    } else {
      printAddr.value = '';
      printStatus = false;
    }
    return code;
  }

  // 断开打印机连接
  static Future<int> disConnect() async {
    final int code = await _channel.invokeMethod('disConnect');
    if (code == 1) {
      printAddr.value = '';
      printStatus = false;
    }
    return code;
  }

  /// 打开打印通道
  static Future<bool> open() async {
    final bool result = await _channel.invokeMethod('open');
    return result;
  }

  /// 关闭打印通道
  static Future<bool> close() async {
    final bool result = await _channel.invokeMethod('close');
    return result;
  }

  /// 发送打印数据
  static Future<int> sendData(List<int> data) async {
    final int result = await _channel.invokeMethod('sendData', {
      'data': data,
    });
    return result;
  }

  /// 发送打印数据
  static Future<int> sendHtmlData(String htmlString) async {
    final int result = await _channel.invokeMethod('sendHtmlData', {
      'htmlString': htmlString,
    });
    return result;
  }

  /// 发送打印PNG图像
  static Future<int> sendPngData(Uint8List data) async {
    final int result = await _channel.invokeMethod('sendPngData', { 'data': data });
    return result;
  }

  /// 判断是否与打印机连接
  static void demoEvent() async {
    await _channel.invokeMethod('demo_event');
  }
}
