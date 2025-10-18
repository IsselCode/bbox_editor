import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

bool get isDesktopLike {
  if (kIsWeb) return true;
  return {
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);
}

bool get isMobileLike {
  return {
    TargetPlatform.android,
    TargetPlatform.iOS,
  }.contains(defaultTargetPlatform);
}