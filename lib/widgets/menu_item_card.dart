import 'package:flutter/material.dart';
import '../models/menu_item.dart';
import '../screens/cashier/v2_styles.dart';

class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final bool isSelected;
  final int quantity;
  final bool isMobile;

  const MenuItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.isSelected = false,
    this.quantity = 0,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    const double borderRadius = 10.0;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: V2Colors.s2,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isSelected ? V2Colors.yellow : V2Colors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: V2Colors.yellow.withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 1,
            )
          ] : [],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background Image/Thumb
            Positioned.fill(
              child: MenuItemThumb(
                item: item,
                radius: BorderRadius.circular(borderRadius - 1),
                placeholderIconSize: 32,
              ),
            ),

            // Gradient Overlay for Text Readability
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.0),
                      Colors.black.withOpacity(0.4),
                      Colors.black.withOpacity(0.85),
                      Colors.black.withOpacity(1.0),
                    ],
                    stops: const [0.0, 0.3, 0.5, 0.8, 1.0],
                  ),
                ),
              ),
            ),

            // Text Content
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                        height: 1.1,
                        shadows: [
                          Shadow(
                            offset: const Offset(0, 1),
                            blurRadius: 6,
                            color: Colors.black.withOpacity(0.8),
                          ),
                          Shadow(
                            offset: const Offset(0, 2),
                            blurRadius: 10,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            "₹${item.price.toStringAsFixed(0)}",
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 14,
                              color: V2Colors.yellow,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  offset: const Offset(0, 1),
                                  blurRadius: 4,
                                  color: Colors.black.withOpacity(0.8),
                                ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.category.isNotEmpty)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white12, width: 0.5),
                                ),
                                child: Text(
                                  item.category.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 6,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Selection & Quantity Badge
            if (isSelected && quantity > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: V2Colors.yellow,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  child: Center(
                    child: Text(
                      "$quantity",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb() {
    return MenuItemThumb(item: item, radius: const BorderRadius.vertical(top: Radius.circular(6)));
  }
}

class MenuItemThumb extends StatelessWidget {
  final MenuItem item;
  final BorderRadius radius;
  final double placeholderIconSize;

  const MenuItemThumb({
    super.key,
    required this.item,
    this.radius = const BorderRadius.all(Radius.circular(4)),
    this.placeholderIconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item.imageUrl ?? '').trim();

    final placeholder = Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: V2Colors.s3,
        borderRadius: radius,
      ),
      child: Center(
        child: Opacity(
          opacity: 0.1,
          child: Icon(
            Icons.restaurant_menu_rounded,
            size: placeholderIconSize,
            color: Colors.white,
          ),
        ),
      ),
    );

    if (imageUrl.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder;
        },
      ),
    );
  }
}
