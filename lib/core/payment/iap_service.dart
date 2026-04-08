import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../utils/storage_utils.dart';

class IapService {
  static final IapService _instance = IapService._internal();
  factory IapService() => _instance;

  IapService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  
  // 订阅商品ID列表，用于检查订阅状态
  List<String> _subscriptionProductIds = [];

  // 用于通知外部购买状态的回调
  Function(String message)? onMessage;
  // 购买状态回调
  Function(BuyState state)? onBuyState;
  // 订阅状态回调
  Function(SubscriptionState state)? onSubscriptionState;

  // 购买状态流
  final StreamController<BuyState> _purchaseStreamController = StreamController<BuyState>.broadcast();
  Stream<BuyState> get purchaseStream => _purchaseStreamController.stream;

  // 订阅状态流
  final StreamController<SubscriptionState> _subscriptionStreamController = StreamController<SubscriptionState>.broadcast();
  Stream<SubscriptionState> get subscriptionStream => _subscriptionStreamController.stream;

  // 当前是否订阅
  bool _isSubscribed = false;
  bool get isSubscribed => _isSubscribed;

  void init({List<String> subscriptionProductIds = const ['com.mj.telescope.s1']}) {
    _subscriptionProductIds = subscriptionProductIds;
    _isSubscribed = StorageUtils.isSubscription();
    _subscription?.cancel(); // 防止重复监听
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      onMessage?.call("Purchase Stream Error: $error");
      final state = BuyErrorState("", "Stream Error: $error");
      _purchaseStreamController.add(state);
      onBuyState?.call(state);
    });
  }

  // 通常不需要调用 dispose，除非确认不再需要监听内购（如退出登录）
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _purchaseStreamController.close();
    _subscriptionStreamController.close();
  }

  /// 获取商品详情
  Future<ProductDetails?> _getProduct(String productId) async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      onMessage?.call("Store not available");
      final state = BuyErrorState(productId,'Store not available');
      _purchaseStreamController.add(state);
      onBuyState?.call(state);
      return null;
    }

    // 查询商品
    Set<String> ids = {productId};
    if (kDebugMode && Platform.isAndroid) {
      ids.add('android.test.purchased');
    }
    
    final ProductDetailsResponse response = await _iap.queryProductDetails(ids);
    if (response.notFoundIDs.isNotEmpty) {
      onMessage?.call("Product not found: ${response.notFoundIDs}");
      final state = BuyErrorState(productId,'Product not found: ${response.notFoundIDs}');
      _purchaseStreamController.add(state);
      onBuyState?.call(state);
    }
    
    if (response.productDetails.isEmpty) {
      onMessage?.call("No product details found for $productId");
      final state = BuyErrorState(productId,'No product details found for $productId');
      _purchaseStreamController.add(state);
      onBuyState?.call(state);
      return null;
    }

    // 找到匹配的商品
    for (var element in response.productDetails) {
      if (element.id == productId) {
        return element;
      }
    }
    return response.productDetails.first; // Fallback for test
  }

  /// 购买消耗型商品 (如金币)
  Future<void> buyConsumable(String productId) async {
    final ProductDetails? productDetails = await _getProduct(productId);
    if (productDetails == null) return;

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  /// 购买非消耗型商品或订阅 (如会员)
  Future<void> buySubscription(String productId) async {
    final ProductDetails? productDetails = await _getProduct(productId);
    if (productDetails == null) return;

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// 检查订阅状态
  /// 如果有多个订阅商品，有一个还在订阅中则认为是订阅态
  Future<void> checkSubscriptionStatus() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      onMessage?.call("Store not available");
      final state = SubscriptionNormalState("Store not available");
      _subscriptionStreamController.add(state);
      onSubscriptionState?.call(state);
      return;
    }
    // 恢复购买会触发 purchaseUpdated 流，逻辑在 _listenToPurchaseUpdated 中处理
    await _iap.restorePurchases();
    
    // 注意：restorePurchases 没有返回值，也无法直接知道是否"没有恢复任何商品"
    // 实际业务中通常需要结合后端验证，或者设定一个超时，如果超时未收到 restored 事件则认为未订阅
    // 这里简单处理：默认认为是 Normal，只有收到 Restored 事件才转为 Subscribed
    // 由于是流式更新，这里不主动 emit Normal，除非有明确的业务逻辑
  }

  @Deprecated('Use buyConsumable instead')
  Future<void> buyProduct(String productId) async {
    await buyConsumable(productId);
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    if (purchaseDetailsList.isEmpty) {
      onMessage?.call("Received empty purchase list");
      return;
    }

    bool hasActiveSubscription = false;

    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      // Debug log
      if (kDebugMode) {
        print("IAP Update: ${purchaseDetails.productID}, status: ${purchaseDetails.status}");
      }

      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        onMessage?.call("Purchase Pending...");
        final state = BuyPendingState(purchaseDetails.productID, "Pending...");
        _purchaseStreamController.add(state);
        onBuyState?.call(state);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          onMessage?.call("Purchase Error: ${purchaseDetails.error?.message ?? 'Unknown error'}");
          final state = BuyErrorState(purchaseDetails.productID, purchaseDetails.error?.message ?? 'Unknown error');
          _purchaseStreamController.add(state);
          onBuyState?.call(state);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          
          // 验证购买凭证 (服务端验证)
          // deliverProduct(purchaseDetails);
          
          onMessage?.call("Purchase Success/Restored: ${purchaseDetails.productID}");

          // 区分购买成功和恢复成功
          if (purchaseDetails.status == PurchaseStatus.purchased) {
             final state = BuySuccessState(purchaseDetails.productID, "Success",purchaseDetails.purchaseID,purchaseDetails.verificationData);
             StorageUtils.saveLocalCredentials(purchaseDetails.productID, purchaseDetails.verificationData.serverVerificationData);
             _purchaseStreamController.add(state);
             onBuyState?.call(state);
          }
          
          // 检查是否为订阅商品
          if (_subscriptionProductIds.contains(purchaseDetails.productID)) {
            hasActiveSubscription = true;
          }
        }else if(purchaseDetails.status == PurchaseStatus.canceled){
          final state = BuyErrorState(purchaseDetails.productID, 'Purchase canceled');
          _purchaseStreamController.add(state);
          onBuyState?.call(state);
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }
      }
    }

    // 如果发现有激活的订阅商品，更新订阅状态
    if (hasActiveSubscription) {
      _isSubscribed = true;
      StorageUtils.saveSubscriptionStatus('ACTIVE');
      final state = SubscriptionActiveState("Active subscription found");
      _subscriptionStreamController.add(state);
      onSubscriptionState?.call(state);
    } else {
      _isSubscribed = false;
      // 注意：这里不能轻易置为 Normal，因为 purchaseDetailsList 可能只包含部分更新
      // 只有在明确知道"所有恢复已结束且无订阅"时才能置为 Normal，但这在纯客户端很难判断
      // 这里的逻辑主要保证：只要有 active 的，就由 Normal -> Active
    }
  }
}

abstract class BuyState{
  final String productId;
  final String tips;


  const BuyState(this.productId, this.tips);
}

class BuySuccessState extends BuyState{
  final String? purchaseID;
  final PurchaseVerificationData verificationData;


  BuySuccessState(super.productId, super.tips,this.purchaseID,this.verificationData);
}

class BuyErrorState extends BuyState{
  BuyErrorState(super.productId, super.tips);
}

class BuyPendingState extends BuyState{
  BuyPendingState(super.productId, super.tips);
}

// 订阅状态
abstract class SubscriptionState {
  final String message;
  const SubscriptionState(this.message);
}

class SubscriptionActiveState extends SubscriptionState {
  SubscriptionActiveState(super.message);
}

class SubscriptionNormalState extends SubscriptionState {
  SubscriptionNormalState(super.message);
}


