package com.civicint.print.flutter_print;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
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
import android.os.Build;
import android.os.Environment;
import java.util.List;
import java.io.*;
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

  /// 打印机纸张大小设置
  ///
  /// 1CM == 70.8px  1710px  991
  private static double paperWidth = 24.16; // 纸张宽度单位CM 包括两边的打孔区域
  private static double paperHeight = 14;   // 纸张高度单位CM

  /// 设置打印格式
  private byte[] getPrintData (byte[] data) {
    byte[] all = null;

    // 初始化
    all = ByteArrayUtils.twoToOne(all, Command.a17);

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
            // 停止线程
            Thread.currentThread().stop();
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
    else if (call.method.equals("sendHtmlData")) {
      // 获取html数据
      final String htmlString = call.argument("htmlString");
      new Thread(new Runnable(){
        @Override
        public void run() {
          // 解析HTML字符串 编码 替换 &
          String temp = null;
          try {
            temp = new String(htmlString.getBytes(), "UTF-8");
            temp = temp.replace("&","&amp;");
          } catch (UnsupportedEncodingException e) {
            temp = null;
            e.printStackTrace();
            result.success(0);
            Thread.currentThread().stop();
          }
          if (temp == null) return;
          final String _htmlStr = temp;

          // 把html字符串按照协议传为打印数据
          Callable<byte[]> callable = new Callable<byte[]>() {
            @Override
            public byte[] call() throws Exception {
              byte[] data = RemotePrinter.html2PrintData(_htmlStr);
              return data;
            }
          };
          FutureTask<byte[]> futureTask = new FutureTask<>(callable);
          Thread thread = new Thread(futureTask);
          thread.start();
          
          try {
            // 获取打印数据
            byte[] printData = futureTask.get();
            byte[] pageNext = "\f".getBytes();
            // 分割数据大小
            List<byte[]> list = ByteArrayUtils.fen(printData,1024);

            // 判断打印对象是否存在
            if (myPrinter == null) {
              result.success(0);
              return;
            }

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
          } catch (ExecutionException e) {
            e.printStackTrace();
            result.success(0);
            System.out.print("ExecutionException错误");
          } catch (InterruptedException e) {
            e.printStackTrace();
            result.success(0);
            System.out.print("InterruptedException错误");
          }
        }
      }).start();
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
    else if (call.method.equals("sendPng")) {
      // 图片数据
      // final String pngPath = call.argument("pngPath");
      final byte[] imgData = call.argument("data");
      Bitmap bmpPic = BitmapFactory.decodeByteArray(imgData, 0, imgData.length);
      // 打印图片数据
      byte[] tmpBUf = RemotePrinter.ConvertImage(PrinterType.PT_DOT24, bmpPic);
      if (tmpBUf != null) {
        byte[] pageNext = "\f".getBytes();
        tmpBUf = getPrintData(tmpBUf);
        List<byte[]> list = ByteArrayUtils.fen(tmpBUf, 1024);

        // 判断打印对象是否存在
        if (myPrinter == null) {
          result.success(0);
          return;
        }

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
        result.success(-1);
      }

    //  try {
        // 读取图片
      //  File file = new File(pngPath);//要写入的图片
       
       // 读取文件转byte[]
        // byte[] img_content = Files.readAllBytes(file.toPath());
        // System.out.println("图片长度" + imgData.length);
       
//       FileInputStream fis = new FileInputStream(file);
//       int length = fis.available();
//       System.out.println("图片长度" + length);
//        byte[] img_content = Files.readAllBytes(file.toPath());
//
//       System.out.println("图片长度" + img_content.length);
//        fis.read(img_content);
//        fis.close();
//        System.out.print("读取图片" + img_content.length);
//
//        Bitmap bmpPic = null;
//        bmpPic = BitmapFactory.decodeByteArray(img_content, 0, length);
      
      // 图片路径
      // byte[] tmpBUf = RemotePrinter.ConvertImage(PrinterType.PT_DOT24, pngPath);
      
      // if (tmpBUf != null) {
      //   List<byte[]> list = ByteArrayUtils.fen(tmpBUf, 1024);
      // } else {
      //   result.success(-1);
      // }

    //  } catch (FileNotFoundException e) {
    //    System.out.print("读取图片失败111");
    //    e.printStackTrace();
    //  } catch (IOException e) {
    //    System.out.print("读取图片失败");
    //    e.printStackTrace();
    //  }



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


class Command {
  // -------------EPSON打印机指令--------------------
  // 回车换行
  public static final byte a12[] = { (byte) 0x0D, (byte) 0x0A };
  // 汉字打印命令
  public static final byte a14[] = { (byte) 0x1C, (byte) 0x26 };
  // 取消汉字打印命令
  public static final byte a15[] = { (byte) 0x1c, (byte) 0x2e };
  // 打印机初始化
  public static final byte a17[] = { (byte) 0x1B, (byte) 0x40 };
  // 斜体
  public static final byte a18[] = { (byte) 0x1B, (byte) 0x34 };
  // 解除斜体
  public static final byte a19[] = { (byte) 0x1B, (byte) 0x35 };
  // 粗体
  public static final byte a20[] = { (byte) 0x1B, (byte) 0x45 };
  // 解除粗体
  public static final byte a21[] = { (byte) 0x1B, (byte) 0x46 };
  // 重叠打印
  public static final byte a22[] = { (byte) 0x1B, (byte) 0x47 };
  // 解除重叠打印
  public static final byte a23[] = { (byte) 0x1B, (byte) 0x48 };
  // 下划线 一条实线
  public static final byte a24[] = { (byte) 0x1B, (byte) 0x28, (byte) 0x2D, (byte) 0x3, (byte) 0x0, (byte) 0x1,
          (byte) 0x1, (byte) 0x1 };
  // 下划线 一条虚线
  public static final byte a25[] = { (byte) 0x1B, (byte) 0x28, (byte) 0x2D, (byte) 0x3, (byte) 0x0, (byte) 0x1,
          (byte) 0x1, (byte) 0x5 };
  // 解除下划线
  public static final byte a26[] = { (byte) 0x1B, (byte) 0x28, (byte) 0x2D, (byte) 0x3, (byte) 0x0, (byte) 0x1,
          (byte) 0x1, (byte) 0x0 };
  // 倍宽打印
  public static final byte a27[] = { (byte) 0x1B, (byte) 0x57, (byte) 0x1 };
  // 解除倍宽打印
  public static final byte a28[] = { (byte) 0x1B, (byte) 0x57, (byte) 0x0 };
  // 倍高倍宽打印
  public static final byte a29[] = { (byte) 0x1C, (byte) 0x57, (byte) 0x1 };
  // 解除倍高倍宽打印
  public static final byte a30[] = { (byte) 0x1C, (byte) 0x57, (byte) 0x0 };
  // 倍高打印
  public static final byte a31[] = { (byte) 0x1C, (byte) 0x21, (byte) 0x8 };
  // 解除倍高打印
  public static final byte a32[] = { (byte) 0x1C, (byte) 0x21, (byte) 0x0 };
  // 推出
  public static final byte a33[] = { (byte) 0xC };
  // 间距
  public static final byte a35[] = { (byte) 0x1C, (byte) 0x76, (byte) 0x1 };
  // 解除间距
  public static final byte a36[] = { (byte) 0x1C, (byte) 0x76, (byte) 0x0 };
  // -------------EPSON打印机指令--------------------

  // -------------爱普生pos指令--------------------
  // 中文倍宽
  public static final byte b1[] = { (byte) 0x1C, (byte) 0x21, (byte) 0x4 };
  // 中文倍高
  public static final byte b2[] = { (byte) 0x1C, (byte) 0x21, (byte) 0x8 };
  // 中文倍宽、倍高字体
  public static final byte b3[] = { (byte) 0x1C, (byte) 0x21, (byte) 0xC };
  // 关闭中文倍宽倍高
  public static final byte b11[] = { (byte) 0x1C, (byte) 0x21, (byte) 0x0 };

  // 英文倍宽
  public static final byte b4[] = { (byte) 0x1B, (byte) 0x21, (byte) 0x20 };
  // 英文倍高
  public static final byte b5[] = { (byte) 0x1B, (byte) 0x21, (byte) 0x10 };
  // 英文倍宽、倍高字体
  public static final byte b6[] = { (byte) 0x1B, (byte) 0x21, (byte) 0x30 };
  // 关闭英文倍宽倍高
  public static final byte b12[] = { (byte) 0x1B, (byte) 0x21, (byte) 0x0 };
  // -------------爱普生pos指令--------------------
}