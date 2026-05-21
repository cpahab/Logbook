import 'package:flutter/material.dart';

class TrackCard extends StatelessWidget {
  const TrackCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Track Card'),
      ),
    );
  }
}
