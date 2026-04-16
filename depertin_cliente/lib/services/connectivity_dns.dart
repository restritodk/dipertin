// Import condicional: `dart:io` não existe no Flutter Web.
export 'connectivity_dns_io.dart' if (dart.library.html) 'connectivity_dns_web.dart';

