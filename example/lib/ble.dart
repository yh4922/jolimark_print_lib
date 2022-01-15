import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_elves/flutter_blue_elves.dart';
export 'package:flutter_blue_elves/flutter_blue_elves.dart';
import '../promise.dart';

/// 字节转文本
String bytesToString (Uint8List bytes) {
  String string = String.fromCharCodes(bytes);
  print('数据：$bytes');
  print('转换数据：$string');
  return string;
}
/// 文本转字节
Uint8List stringToBytes (String string) {
  Uint8List bytes = Uint8List.fromList(string.codeUnits);
  print('数据：$bytes');
  return bytes;
}

/// 蓝牙监听事件类型
enum BleEventType {
  /// 蓝牙状态事件
  STATUS,
  /// 蓝牙服务信息事件
  SERVICE,
  /// 蓝牙信号事件
  SIGNAL,
}

class BleEvent {
  /// 事件类型
  BleEventType type;

  /// 事件数据
  dynamic data;

  BleEvent(this.type, [this.data]);
}

/// 全局蓝牙状态
/// 
/// true: 已打开
class GlobalBleStatus extends ValueNotifier<bool> {
  /// 蓝牙对象
  /// 
  /// 当`value`为true时 `ble`才有值可以操作
  late Ble ble;

  GlobalBleStatus(bool value):super(value);
}

/// 蓝牙操作类
/// 
/// 封装了蓝牙对象的操作方法，提供打开蓝牙、扫描设备的静态方法
class Ble {
  /// 蓝牙广播信息
  /// 
  /// 包含蓝牙的基本信息
  late dynamic bleInfo;

  /// 蓝牙连接对象
  /// 
  /// 管理蓝牙连接的对象
  late Device bleDevice;

  /// 设备连接状态
  late DeviceState connectStatus;

  /// 服务ID
  late String serviceUuid;

  /// 特征ID
  late String characteristicUuid;

  // 监听列表
  List<Function(BleEvent)> listeners = [];

  /// 创建蓝牙连接
  /// 
  /// 传入蓝牙广播信息，建立连接获取蓝牙服务
  Ble(this.bleInfo) {
    // 超时定时器定时器15s后
    Timer timer = Timer(Duration(seconds: 10), () {
      sendListener(BleEventType.STATUS, DeviceState.disconnected);
    });

    // 创建蓝牙连接
    bleDevice = bleInfo.connect();
    
    // 蓝牙连接状态监听
    bleDevice.stateStream.listen((status)  {
      if (status == DeviceState.connected) {
        bleDevice.discoveryService(); // 触发发现设备服务
      } else if (
        status == DeviceState.disconnected ||
        status == DeviceState.disConnecting ||
        status == DeviceState.connectTimeout ||
        status == DeviceState.initiativeDisConnected ||
        status == DeviceState.destroyed
      ) {
        timer.cancel(); // 取消定时器
      }
      connectStatus = status;
      sendListener(BleEventType.STATUS, status);
    });

    // 设备服务监听
    bleDevice.serviceDiscoveryStream.listen((event) {
      // 指定1000的服务ID
      print('::::::::: ${event.serviceUuid}');
      if (event.serviceUuid.substring(4, 8) == '1000') {
        serviceUuid = event.serviceUuid; // 记录服务ID
        print('serviceUuid: $serviceUuid');
        event.characteristics.forEach((element) {
          /// 指定 1002 读特征码
          print('>>>>>: ${element.uuid}');
          if (element.uuid.substring(4, 8) == '1002') {
            timer.cancel(); // 取消定时器
            characteristicUuid = element.uuid; // 特征ID
            print('characteristicUuid: $characteristicUuid');
          }
        });
        sendListener(BleEventType.SERVICE);
      }
    });

    // 设备信号监听
    bleDevice.deviceSignalResultStream.listen((result) {
      print('result.uuid: ${result.uuid}');
      print('result.isSuccess: ${result.isSuccess}');
      print('result.type: ${result.type}');
      print('result.data: ${result.data}');
      if (result.data == null) {
        sendListener(BleEventType.SIGNAL, '');
        return;
      }

      
      Uint8List none = Uint8List.fromList([]);
      List<String> list = bytesToString(result.data ?? none).split('\r\n');
      
      String data;
      try { data = list[list.length - 2]; } catch (e) { 
        data = '';
        BotToast.showText(text: '蓝牙数据: ${list.join(',')}，异常信息: ${e.toString()}');
       }
      sendListener(BleEventType.SIGNAL, data);
    });
  }

  /// 添加监听
  /// 
  /// [listener] 监听函数
  void addListener (Function(BleEvent) listener) {
    listeners.add(listener);
  }

  /// 删除监听
  /// 
  /// [listener] 监听函数
  void removeListener (Function(BleEvent) listener) {
    listeners.remove(listener);
  }
  
  /// 发送监听数据
  /// 
  /// [type] 事件类型
  /// [data] 事件数据
  void sendListener (BleEventType type, [dynamic data]) {
    BleEvent event = BleEvent(type, data);
    List<dynamic Function(BleEvent)> _listeners = [...listeners];
    _listeners.forEach((element) => element(event));
  }

  /// 读取设备数据
  /// 
  /// 创建监听后，调用该方法读取设备数据 监听收到事件触发异步回调返回数据
  Future<String?> readData () async {
    if (
      connectStatus == DeviceState.connected &&
      serviceUuid.isNotEmpty && characteristicUuid.isNotEmpty
    ) {
      String? data;
      try {
        data = await Promise((resolve, reject) {
          // 创建监听方法
          dynamic listenerFun (event) {
            if (event.type == BleEventType.SIGNAL) {
              // 移除监听并返回函数
              removeListener(listenerFun);
              resolve(event.data);
            }
          }
          
          // 设置监听
          addListener(listenerFun);
          // 读取数据
          bleDevice.readData(serviceUuid, characteristicUuid);
        }).future;
      } catch (e) {
        BotToast.showText(text: '读取蓝牙数据失败：${e.toString()}');
      }

      return data;
    } else {
      return null;
    }
  }

  /// 断开连接连接
  /// 
  /// 当蓝牙状态为已断开、正在连接和正在断开状态时不执行
  void disConnect () {
    if (
      connectStatus != DeviceState.disconnected &&
      connectStatus != DeviceState.connecting &&
      connectStatus != DeviceState.disConnecting
    ) {
      bleDevice.disConnect();
    }
  }

  /// 创建蓝牙连接
  /// 
  /// 当蓝牙状态为已连接、正在连接和正在断开状态时不执行
  void connect () {
    if (
      connectStatus != DeviceState.connected &&
      connectStatus != DeviceState.connecting &&
      connectStatus != DeviceState.disConnecting
    ) {
      bleDevice.connect();
    }
  }


  /// 销毁对象
  /// 
  /// 断开蓝牙连接，销毁蓝牙对象，释放监听列表
  void destroy () {
    bleDevice.destroy();
    listeners.clear();
  }




  //// 静态方法
  /// 方便调用
  /// 

  static bool statusIsError (DeviceState status) {
    if (
      status == DeviceState.disconnected ||
      status == DeviceState.disConnecting ||
      status == DeviceState.connectTimeout ||
      status == DeviceState.initiativeDisConnected ||
      status == DeviceState.destroyed
    ) {
      return true;
    } else {
      return false;
    }
  }

  /// 检测蓝牙状态是否打开
  /// 
  /// 安卓下先获取权限 再检查蓝牙打开状态
  static Future<bool> checkBle () async {
    // 检查是否有蓝牙权限
    if (Platform.isAndroid) {
      // 申请蓝牙和蓝牙扫描权限
      PermissionStatus bluetooth = await Permission.bluetooth.request();
      PermissionStatus bluetoothScan = await Permission.bluetoothScan.request();
      PermissionStatus location = await Permission.location.request();
      if (
        bluetooth != PermissionStatus.granted ||
        bluetoothScan != PermissionStatus.granted ||
        location != PermissionStatus.granted
      ) {
        return false;
      }

      // 蓝牙是否打开
      bool isOpen = await Promise((resolve, reject) {
        FlutterBlueElves.instance.androidOpenBluetoothService(resolve);
      }).future;
      return isOpen;
    } else {
      /// 暂时只支持安卓
      return false;
    }
  }
  
  /// 扫描未连接的设备  
  /// 
  /// 需要自行保存已连接的设备对象，已经创建连接的设备扫描不能再次扫描到
  static Stream<ScanResult> scanBle () {
    return FlutterBlueElves.instance.startScan(5000);
  }
  
  /// 获取被隐藏的蓝牙列表
  static Future<List<HideConnectedDevice>> scanHideBle () {
    return FlutterBlueElves.instance.getHideConnectedDevices();
  }

  /// 停止扫描设备
  static void stopScan () {
    FlutterBlueElves.instance.stopScan();
  }
}