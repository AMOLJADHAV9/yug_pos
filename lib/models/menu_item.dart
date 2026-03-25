class MenuItem {
  final String id;
  final String name;
  final String category;
  final double price;
  final String? imageUrl;
  final bool isAvailable;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageUrl,
    this.isAvailable = true,
  });

  factory MenuItem.fromMap(String documentId, Map<String, dynamic> data) {
    return MenuItem(
      id: documentId,
      name: data['name'] ?? '',
      category: data['category'] ?? 'Uncategorized',
      price: (data['price'] ?? 0).toDouble(),
      imageUrl: data['imageUrl'],
      isAvailable: data['isAvailable'] ?? true,
    );
  }
}
