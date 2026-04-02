import 'package:cloud_firestore/cloud_firestore.dart';

enum TableStatus { available, occupied, kotSent, billRequested }

class TableModel {
  final String id;
  final String name;
  final int capacity;
  final String section;
  final TableStatus status;
  final String? currentOrderId; // Useful to navigate directly to the open order

  TableModel({
    required this.id,
    required this.name,
    required this.capacity,
    required this.section,
    required this.status,
    this.currentOrderId,
  });

  factory TableModel.fromMap(String documentId, Map<String, dynamic> data) {
    TableStatus mapStatus(String statusStr) {
      switch (statusStr) {
        case 'occupied': return TableStatus.occupied;
        case 'kotSent': return TableStatus.kotSent;
        case 'billRequested': return TableStatus.billRequested;
        default: return TableStatus.available;
      }
    }

    return TableModel(
      id: documentId,
      name: data['name'] ?? '',
      capacity: data['capacity'] ?? 2,
      section: data['section'] ?? 'Main',
      status: mapStatus(data['status'] ?? 'available'),
      currentOrderId: data['currentOrderId'],
    );
  }

  static int compareByName(TableModel a, TableModel b) {
     final regExp = RegExp(r'(\d+)');
     final aName = a.name;
     final bName = b.name;
     
     final aParts = aName.split(regExp);
     final bParts = bName.split(regExp);
     final aMatches = regExp.allMatches(aName).toList();
     final bMatches = regExp.allMatches(bName).toList();

     for (int i = 0; i < aParts.length && i < bParts.length; i++) {
        int res = aParts[i].toLowerCase().compareTo(bParts[i].toLowerCase());
        if (res != 0) return res;

        if (i < aMatches.length && i < bMatches.length) {
           int aNum = int.tryParse(aMatches[i].group(1)!) ?? 0;
           int bNum = int.tryParse(bMatches[i].group(1)!) ?? 0;
           if (aNum != bNum) return aNum.compareTo(bNum);
        }
     }
     return aName.toLowerCase().compareTo(bName.toLowerCase());
  }
}
