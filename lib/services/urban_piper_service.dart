import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class UrbanPiperService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // These should be moved to a configuration document in Firestore
  static const String _apiBaseUrl = "https://api.urbanpiper.com/external/api/v1";
  
  /// Fetches the local menu and converts it to UrbanPiper Atlas JSON format.
  Future<Map<String, dynamic>> generateAtlasJson(String restaurantId) async {
    // 1. Fetch Categories
    final categoriesSnap = await _firestore
        .collection('menu_categories')
        .where('restaurantId', isEqualTo: restaurantId)
        .get();

    // 2. Fetch Items
    final itemsSnap = await _firestore
        .collection('menu_items')
        .where('restaurantId', isEqualTo: restaurantId)
        .get();

    List<Map<String, dynamic>> categories = [];
    for (var doc in categoriesSnap.docs) {
      final data = doc.data();
      categories.add({
        "ref_id": doc.id,
        "name": data['name'],
        "description": "",
        "sort_order": data['order'] ?? 0,
        "active": data['isVisible'] ?? true,
      });
    }

    List<Map<String, dynamic>> items = [];
    for (var doc in itemsSnap.docs) {
      final data = doc.data();
      // Skip items not marked for online sale
      if (!(data['availableOnline'] ?? true)) continue;

      items.add({
        "ref_id": doc.id,
        "title": data['name'],
        "description": data['description'] ?? "",
        "price": data['price'] ?? 0.0,
        "category_ref_ids": [categoriesSnap.docs.firstWhere((c) => c.data()['name'] == data['category'], orElse: () => categoriesSnap.docs.first).id],
        "active": data['isAvailable'] ?? true,
        "sold_at_store": true,
        "available_online": true,
        "img_url": data['imageUrl'] ?? "",
      });
    }

    return {
      "categories": categories,
      "items": items,
      "flush_items": false,
      "flush_categories": false,
    };
  }

  /// Pushes the menu to UrbanPiper Atlas.
  Future<bool> syncMenu(String restaurantId, String apiKey, String username) async {
    try {
      final atlasData = await generateAtlasJson(restaurantId);
      
      final response = await http.post(
        Uri.parse("$_apiBaseUrl/inventory/locations/"), // Example endpoint, varies by config
        headers: {
          "Authorization": "apikey $username:$apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(atlasData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
         debugPrint("UrbanPiper Sync Successful: ${response.body}");
         return true;
      } else {
         debugPrint("UrbanPiper Sync Failed: ${response.statusCode} - ${response.body}");
         return false;
      }
    } catch (e) {
      debugPrint("UrbanPiper Sync Error: $e");
      return false;
    }
  }
  
  /// Formats a single item for real-time stock update.
  Future<void> updateStock(String itemId, bool isAvailable, String apiKey, String username) async {
    // In a real implementation, this would call UrbanPiper's stock update API
    debugPrint("Syncing stock for $itemId: $isAvailable");
  }
}
