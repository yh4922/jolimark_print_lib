import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'dart:typed_data';
import 'ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

enum ScanStatus {
  none,
  scan,
}

class _MyAppState extends State<MyApp> {
  bool bleOpen = false;
  ScanStatus scanStatus = ScanStatus.none;
  List<ScanResult> bleList = [];
  List<HideConnectedDevice> hideList = [];

  Ble? curBle;
  String readData = '';

  @override
  void initState() {
    super.initState();
    checkBleList();
  }

  void checkBleList () {
    if (mounted) { // 清空设备
      setState(() {
        readData = '';
        bleOpen = false;
        scanStatus = ScanStatus.none;
        bleList = [];
        hideList = [];
      });
    }
    Ble.checkBle().then((value) {
      if (mounted) setState(() {bleOpen = value;});
      if (bleOpen) {
        // 开始扫描设备
        if (mounted) setState(() {scanStatus = ScanStatus.scan;});
        Ble.scanBle().listen((ScanResult result) {
          if (result.name == null) return;
          if (mounted) setState(() {bleList.add(result); });
        }, onDone: () {
          if (mounted) setState(() {scanStatus = ScanStatus.none;});
          BotToast.showText(text: '扫描完成');
          /// 获取被隐藏的列表
          Ble.scanHideBle().then((value) {
            print('读取隐藏列表: $value');
            value.forEach((element) {
              if (element.name == null) return;
              if (mounted) setState(() {hideList.add(element); });
            });
          });
        }, onError: (e) {
          if (mounted) setState(() {scanStatus = ScanStatus.none;});
          BotToast.showText(text: 'Error: 扫描出错  ${e.toString()}');
        });

        // 
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: BotToastInit(), //1.调用BotToastInit
      navigatorObservers: [BotToastNavigatorObserver()], //2.注册路由观察者
      home: Scaffold(
        appBar: AppBar(
          title: const Text('蓝牙调试'),
          actions: curBle == null ? [] : [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(const Color(0xffEDFCF5)), 
                      foregroundColor: MaterialStateProperty.all(const Color(0xff31C27C))
                    ),
                    child: const Text('断开连接'),
                    onPressed: () {
                      curBle?.destroy();
                      setState(() {curBle = null;});
                      checkBleList();
                    },
                  ),
                )
              ],
            )
          ],
        ),
        body: 
        curBle == null ?
        ListView(
          children: [
            ...bleList.map((e) {
              return ListTile(
                title: Text(e.name ?? '未知设备'),
                subtitle: Text(e.macAddress.toString()),
                trailing: const Icon(Icons.bluetooth),
                onTap: () {
                  curBle?.destroy();
                  setState(() {curBle = null;});
                  var hideLoading =  BotToast.showLoading();
                  Ble ble = Ble(e);
                  void eventService (BleEvent event) {
                    if (event.type == BleEventType.SERVICE) {
                      hideLoading();
                      curBle?.removeListener(eventService);
                      setState(() {curBle = ble;});
                    } else if (event.type == BleEventType.STATUS) {
                      if (
                        event.data == DeviceState.disconnected || // 断开状态
                        event.data == DeviceState.disConnecting || // 正在断开
                        event.data == DeviceState.initiativeDisConnected || // 用户主动断开蓝牙
                        event.data == DeviceState.destroyed // 蓝牙对象销毁状态
                      ) {
                        hideLoading();
                        BotToast.showText(text: '蓝牙已断开');
                      } else if (event.data == DeviceState.connectTimeout) {
                        hideLoading();
                        BotToast.showText(text: '蓝牙连接超时');
                      }
                    }
                  }
                  ble.addListener(eventService);
                },
              );
            }).toList(),
            ...hideList.map((e) {
              return ListTile(
                title: Text(e.name ?? '未知设备'),
                subtitle: Text(e.macAddress.toString()),
                trailing: const Icon(Icons.bluetooth),
                onTap: () {
                  curBle?.destroy();
                  setState(() {curBle = null;});
                  var hideLoading =  BotToast.showLoading();
                  Ble ble = Ble(e);
                  void eventService (BleEvent event) {
                    if (event.type == BleEventType.SERVICE) {
                      hideLoading();
                      curBle?.removeListener(eventService);
                      setState(() {curBle = ble;});
                    } else if (event.type == BleEventType.STATUS) {
                      if (
                        event.data == DeviceState.disconnected || // 断开状态
                        event.data == DeviceState.disConnecting || // 正在断开
                        event.data == DeviceState.initiativeDisConnected || // 用户主动断开蓝牙
                        event.data == DeviceState.destroyed // 蓝牙对象销毁状态
                      ) {
                        hideLoading();
                        BotToast.showText(text: '蓝牙已断开');
                      } else if (event.data == DeviceState.connectTimeout) {
                        hideLoading();
                        BotToast.showText(text: '蓝牙连接超时');
                      }
                    }
                  }
                  ble.addListener(eventService);
                },
              );
            }).toList()
          ],
        ) : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              readData.isEmpty ? '暂无数据' : '蓝牙读数：$readData',
              style: const TextStyle(fontSize: 20),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  child: const Text('读取数据'),
                  onPressed: () {

                    // stringToBytes('wewewe');

                    // bytesToString(Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 76, 73, 0, 32, 100, 84, 0, 32, 228, 78, 0, 32, 132, 71, 0, 32, 156, 73, 0, 32, 72, 69, 0, 32, 43, 233, 3, 0, 44, 0, 9, 0, 56, 236, 3, 0, 48, 36, 4, 0, 28, 38, 4, 0, 16, 0, 44, 0, 1, 0, 0, 32, 4, 106, 45, 19, 125, 128, 127, 1, 36, 0, 36, 0, 0, 0, 244, 1, 0, 0, 0, 0, 185, 204, 0, 32, 17, 0, 0, 0, 216, 204, 0, 32, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 132, 114, 0, 32, 152, 8, 0, 32, 0, 0, 0, 0, 141, 46, 1, 0, 32, 0, 0, 0, 1, 0, 0, 0, 24, 9, 0, 32, 0, 0, 0, 0, 1, 0, 0, 0, 253, 255, 255, 255, 24, 9, 0, 32, 31, 42, 0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 21, 45, 1, 0, 1, 0, 0, 0, 241, 255, 255, 255, 24, 9, 0, 32, 31, 42, 0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 21, 45, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 206, 9, 0, 0, 100, 23, 0, 32, 100, 23, 0, 32, 2, 0, 0, 0, 197, 218, 0]));

                    // return;
                    setState(() {readData = '';});
                    curBle?.readData().then((value) {
                      if (value == null) {
                        readData = '';
                      } else {
                        readData = value.toString();
                      }
                      setState(() {});
                    });
                  },
                )
              ],
            )
          ],
        ),
        floatingActionButton: bleOpen && scanStatus == ScanStatus.none && curBle == null ? FloatingActionButton(
          child: const Icon(Icons.refresh),
          onPressed: checkBleList
        ) : bleOpen && curBle == null ? const CircularProgressIndicator() : null,
      ),
    );
  }
}


/// 字节转文本
// String bytesToString (Uint8List bytes) {
//   String string = String.fromCharCodes(bytes);
//   return string;
// }
// /// 文本转字节
// Uint8List stringToBytes (String string) {
//   Uint8List bytes = Uint8List.fromList(string.codeUnits);
//   print('数据：$bytes');
//   return bytes;
// }