import 'package:flutter/material.dart';
import './cart_view_content.dart';

class CartBottomSheet extends StatelessWidget {
  const CartBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return const CartViewContent(isBottomSheet: true);
  }
}
