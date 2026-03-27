import 'package:cloud_firestore/cloud_firestore.dart';

class RestaurantModel {
  final String id;
  final String name;
  final String address;
  final String? gstin;
  final String? phone;
  final String? logoUrl;
  final DateTime createdAt;

  RestaurantModel({
    required this.id,
    required this.name,
    required this.address,
    this.gstin,
    this.phone,
    this.logoUrl,
    required this.createdAt,
  });

  factory RestaurantModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return RestaurantModel(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      gstin: data['gstin'],
      phone: data['phone'],
      logoUrl: data['logoUrl'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'address': address,
      'gstin': gstin,
      'phone': phone,
      'logoUrl': logoUrl,
      'createdAt': createdAt,
    };
  }
}
