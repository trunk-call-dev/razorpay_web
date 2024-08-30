import 'dart:async';
import 'package:js/js_util.dart';
import 'package:web/web.dart' as web;
import 'package:js/js.dart' as js;
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Flutter plugin for Razorpay SDK
class RazorpayFlutterPlugin {
  static const _CODE_PAYMENT_SUCCESS = 0;
  static const _CODE_PAYMENT_ERROR = 1;
  static const NETWORK_ERROR = 0;
  static const INVALID_OPTIONS = 1;
  static const PAYMENT_CANCELLED = 2;
  static const TLS_ERROR = 3;
  static const INCOMPATIBLE_PLUGIN = 4;
  static const UNKNOWN_ERROR = 100;
  static const BASE_REQUEST_ERROR = 5;

  static void registerWith(Registrar registrar) {
    final MethodChannel methodChannel = MethodChannel(
        'razorpay_flutter', const StandardMethodCodec(), registrar.messenger);
    final RazorpayFlutterPlugin instance = RazorpayFlutterPlugin();
    methodChannel.setMethodCallHandler(instance.handleMethodCall);
  }

  Future<Map<dynamic, dynamic>> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'open':
        return await startPayment(call.arguments);
      case 'resync':
      default:
        var defaultMap = {'status': 'Not implemented on web'};
        return defaultMap;
    }
  }

  Future<Map<dynamic, dynamic>> startPayment(
      Map<dynamic, dynamic> options) async {
    var completer = Completer<Map<dynamic, dynamic>>();
    var returnMap = <dynamic, dynamic>{};
    var dataMap = <dynamic, dynamic>{};

    options['handler'] = js.allowInterop((response) {
      returnMap['type'] = _CODE_PAYMENT_SUCCESS;
      dataMap['razorpay_payment_id'] = response['razorpay_payment_id'];
      dataMap['razorpay_order_id'] = response['razorpay_order_id'];
      dataMap['razorpay_signature'] = response['razorpay_signature'];
      returnMap['data'] = dataMap;
      completer.complete(returnMap);
    });

    options['modal.ondismiss'] = js.allowInterop(() {
      if (!completer.isCompleted) {
        returnMap['type'] = _CODE_PAYMENT_ERROR;
        dataMap['code'] = PAYMENT_CANCELLED;
        dataMap['message'] = 'Payment processing cancelled by user';
        returnMap['data'] = dataMap;
        completer.complete(returnMap);
      }
    });

    var jsObjOptions = jsify(options);

    // Ensuring jsObjOptions is a valid JavaScript object
    if (jsObjOptions is Map || jsObjOptions is js.JsObject) {
      var retryOptions = getProperty(jsObjOptions, 'retry');
      if (retryOptions != null && getProperty(retryOptions, 'enabled') == true) {
        options['retry'] = true;
      } else {
        options['retry'] = false;
      }
    } else {
      options['retry'] = false;
    }

    var rjs = web.document.getElementsByTagName('script').item(0);
    if (rjs != null) {
      var rzpjs = web.document.createElement('script') as web.HTMLScriptElement;
      rzpjs.id = 'rzp-jssdk';
      rzpjs.src = 'https://checkout.razorpay.com/v1/checkout.js';
      rjs.parentNode?.insertBefore(rzpjs, rjs);

      rzpjs.onLoad.listen((event) async {
        var razorpayConstructor = await getProperty(web.window, 'Razorpay');
        if (razorpayConstructor != null) {
          var razorpay = callConstructor(razorpayConstructor, [jsObjOptions]);

          razorpay.callMethod('on', [
            'payment.failed',
            js.allowInterop((response) {
              returnMap['type'] = _CODE_PAYMENT_ERROR;
              dataMap['code'] = BASE_REQUEST_ERROR;
              dataMap['message'] = response['error']['description'];
              var metadataMap = <dynamic, dynamic>{};
              metadataMap['payment_id'] =
                  response['error']['metadata']['payment_id'];
              dataMap['metadata'] = metadataMap;
              dataMap['source'] = response['error']['source'];
              dataMap['step'] = response['error']['step'];
              returnMap['data'] = dataMap;
              completer.complete(returnMap);
            })
          ]);
          razorpay.callMethod('open');
        }
      });
    }

    return completer.future;
  }
}