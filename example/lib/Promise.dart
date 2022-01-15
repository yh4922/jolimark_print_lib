// ignore_for_file: use_function_type_syntax_for_parameters, unnecessary_new

import 'dart:async';

class Promise {
  late Future future;
  Promise(Function excutor) {
    final Completer completer = Completer();
    try {
      excutor(completer.complete, completer.completeError);
    } catch (e) {
      completer.completeError(e);
    }
    future = completer.future;
  }

  /// Promise链式回调，对应Dart [.then]
  Future? then(Future Function(dynamic) onValue, {required Function onError}) {
    return future.then(onValue, onError: onError);
  }

  /// Promise链式回调，对应Dart [.catchError]
  Future catch_(Function onError, {required bool Function(Object) test}) {
    return future.catchError(onError, test: test);
  }

  /// Promise链式回调，对应Dart [.whenComplete]
  Future finally_(Future<dynamic> Function() action) {
    return future.whenComplete(action);
  }

}