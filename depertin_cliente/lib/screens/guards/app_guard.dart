import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import 'no_internet_screen.dart';
import 'no_gps_screen.dart';

class AppGuard extends StatelessWidget {
  final Widget child;

  const AppGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final location = context.watch<LocationService>();

    if (!connectivity.initialized) {
      return child;
    }

    if (!connectivity.isOnline) {
      return Stack(
        children: [
          child,
          const Positioned.fill(child: NoInternetScreen()),
        ],
      );
    }

    if (!location.initialized) {
      return child;
    }

    if (location.status != LocationStatus.pronto) {
      return Stack(
        children: [
          child,
          const Positioned.fill(child: NoGpsScreen()),
        ],
      );
    }

    return child;
  }
}
