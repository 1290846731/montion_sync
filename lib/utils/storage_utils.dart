import 'dart:convert';

import 'package:mmkv/mmkv.dart';

class StorageUtils{
  static final MMKV _mmkv = MMKV.defaultMMKV();
  static void saveToken(String token){
    _mmkv.encodeString('token', token);
  }

  static String? getToken(){
    return _mmkv.decodeString('token');
  }
  
  
  static void saveSubscriptionStatus(String status){
    _mmkv.encodeString('status', status);
  }

  static bool isSubscription(){
    String status = _mmkv.decodeString('status') ?? '';
    if(status == 'ACTIVE'){
      return true;
    }
    return false;
  }

  static void saveLocalCredentials(String productId,String credentials){
    Map<String,String> map = {'productId':productId,'credentials':credentials};
    _mmkv.encodeString('local_credentials', jsonEncode(map));
  }

  static Map<String,String>? getLocalCredentials(){
    String str = _mmkv.decodeString('local_credentials')??'';
    if(str.isNotEmpty){
      return Map<String, String>.from(jsonDecode(str));
    }
    return null;
  }

  static void clearLocalCredentials(){
    _mmkv.removeValue('local_credentials');
  }

}
