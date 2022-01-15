package com.civicint.print.flutter_print;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import com.jolimark.printerlib.RemotePrinter;
import com.jolimark.printerlib.VAR.TransType;
import com.jolimark.printerlib.VAR.PrinterType;
import com.jolimark.printerlib.util.ByteArrayUtils;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;

import android.annotation.TargetApi;
import android.bluetooth.BluetoothAdapter;
import android.os.Build;
import android.os.Environment;

import java.util.EventListener;
import java.util.HashMap;
import java.util.List;
import java.io.*;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;

import android.content.Context;
import android.widget.Toast;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

public class FlutterPrintPlugin implements FlutterPlugin, MethodCallHandler {
  private MethodChannel channel;
  private RemotePrinter myPrinter = null; // 创建打印机对象

  private EventChannel.EventSink eventSink = null;
  private static final String NativeToFlutterChannel = "flutter_print_event";

  /// 设置打印格式
  private byte[] getPrintData (byte[] data) {
    byte[] all = null;

    // 初始化
    final byte[] init = { (byte) 0x1B, (byte) 0x40 };
    all = ByteArrayUtils.twoToOne(all, init);

    // 设置每行0.5英寸  
    final byte[] line = { (byte) 0x1B, (byte) 0x33, (byte) 0x5A };
    all = ByteArrayUtils.twoToOne(all, line);

    // 设置纸张大小 11行 5.5英寸
    final byte[] size = { (byte) 0x1B, (byte) 0x43, (byte) 0xB };
    all = ByteArrayUtils.twoToOne(all, size);
    // 填充内容
    all = ByteArrayUtils.twoToOne(all, data);
    return all;
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_print");
    channel.setMethodCallHandler(this);

    //注册监听通道
    new EventChannel(
      flutterPluginBinding.getBinaryMessenger(),
      NativeToFlutterChannel
    ).setStreamHandler(
      new EventChannel.StreamHandler() {      
        @Override
        public void onListen(Object o, EventChannel.EventSink sink) {
          eventSink = sink;
        }

        @Override
        public void onCancel(Object o) {
          eventSink = null;
        }
      }
    );
  }

  @TargetApi(Build.VERSION_CODES.O)
  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("connectBle")) {
      // 获取mac地址
      String macaddr = call.argument("macaddr");

      // 检查打印对象是否存在
      if (myPrinter == null) {
        // 第一步：创建打印机对象
        myPrinter = new RemotePrinter(TransType.TRANS_BT, macaddr);
        System.out.println("打印机对象创建完成" + myPrinter.isConnected());

        // 第二步：打开通讯通道
        new Thread(new Runnable(){
          @Override
          public void run() {
            if (myPrinter.open(false)) { // 成功久返回
              System.out.println("SUCCESS: 打印机连接成功" + myPrinter.isConnected());
              result.success(1); // 返回1表示连接成功
            } else { // 失败就查询错误码返回
              System.out.println("ERROR: 打印机连接失败");
              int code = myPrinter.getLastErrorCode(); // 获取错误码
              result.success(code);
              myPrinter = null; // 清空打印机对象
            }
          }
        }).start();
      } else {
        // 对象处于已连接状态
        if (myPrinter.isConnected()) {
          result.success(1);
        } else {
          result.success(0);  // 未连接清除打印机对象
          myPrinter = null; // 清空打印机对象
        }
      }
    }
    else if (call.method.equals("disConnect")) {
      if (myPrinter != null) {
        myPrinter.close();
        myPrinter = null;
      }
      result.success(1);
    }
    else if (call.method.equals("sendData")) {
      // 把打印内容转为字节 并按每段长度1024分割
      String printData = call.argument("printData");
      List<byte[]> list = ByteArrayUtils.fen(printData.getBytes(),1024);

      // 判断打印对象是否存在
      if (myPrinter == null) {
        result.success(0);
        return;
      }

      // 打印线程
      new Thread(new Runnable(){
        @Override
        public void run() {
          // 开启通讯
          myPrinter.open(false);
          
          // 循环发送每段数据
          for (int i=0; i< list.size(); i++) {
            myPrinter.sendData(list.get(i));
            // 添加延时
            try {
              Thread.sleep(200);
            } catch (InterruptedException e) {
              e.printStackTrace();
            }
          }
          
          // 打印完成后关闭通讯
          if (myPrinter.close()) {
            result.success(1);
          } else {
            int code = myPrinter.getLastErrorCode();
            result.success(code);
          }
        }
      }).start();
    }
    else if (call.method.equals("sendPngData")) {
      // 判断打印对象是否存在
      if (myPrinter == null) {
        result.success(0);
        return;
      }

      // 图片数据
      final byte[] imgData = call.argument("data");
      // 转换为打印机识别的格式
      Bitmap bmpPic = BitmapFactory.decodeByteArray(imgData, 0, imgData.length);
      byte[] tmpBUf = RemotePrinter.ConvertImage(PrinterType.PT_DOT24, bmpPic);

      if (tmpBUf != null) {
        // 换页符号
        byte[] pageNext = "\f".getBytes();
        tmpBUf = getPrintData(tmpBUf);
        List<byte[]> list = ByteArrayUtils.fen(tmpBUf, 1024);

        new Thread(new Runnable(){
          @Override
          public void run() {
            // 开启通讯
            myPrinter.open(false);
            // 循环发送每段数据
            for (int i=0; i< list.size(); i++) {
              myPrinter.sendData(list.get(i));
              try {
                // 添加延时
                Thread.sleep(200);
              } catch (InterruptedException e) {
                e.printStackTrace();
              }
            }
            // 发送结束符
            myPrinter.sendData(pageNext);

            // 打印完成后关闭通讯
            if (myPrinter.close()) {
              result.success(1);
            } else {
              int code = myPrinter.getLastErrorCode();
              result.success(code);
            }
          }
        }).start();

      } else {
        // 图像转换失败
        result.success(-1);
      }
    }
    else if (call.method.equals("demo_event")) {

      if (eventSink != null) {
        System.out.print("OK");
        Map<String, Object> params = new HashMap<String,Object>();
        params.put("event", "demo");
        params.put("value", "value va lu eva lue val uev al ue");
        eventSink.success(params);
      } else {
        System.out.print("ERR");
      }
    }
    else {
      result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }
}