/// A host feature a mini app can declare and use. [id] is the name used
/// in `litestore.yaml` and by the host.
enum Feature {
  location('location', asksUser: true),
  camera('camera', asksUser: true),
  microphone('microphone', asksUser: true),
  bluetooth('bluetooth', asksUser: true),
  wifi('wifi', asksUser: true),
  wifiSignal('wifi.signal'),
  wifiEnable('wifi.enable'),
  torch('torch'),
  nfc('nfc'),
  sensors('sensors'),
  gestures('gestures'),
  clipboardRead('clipboard.read', asksUser: true),
  profileName('profile.name', asksUser: true),
  profilePhone('profile.phone', asksUser: true),
  profileEmail('profile.email', asksUser: true),
  notifications('notifications', asksUser: true),
  authToken('auth.token', asksUser: true),
  authBrowser('auth.browser'),
  scanner('scanner'),
  imagePick('image.pick'),
  share('share'),
  openUrl('open.url'),
  clipboardWrite('clipboard.write'),
  links('links'),
  biometric('biometric'),
  contactsPick('contacts.pick'),
  haptics('haptics'),
  keepScreenOn('screen.keepOn'),
  storage('storage'),
  deviceInfo('device.info');

  const Feature(this.id, {this.asksUser = false});

  final String id;

  /// The user is asked (once per app) before the app can use it.
  final bool asksUser;

  static Feature? fromId(String id) {
    for (final f in values) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// Bridge method -> the feature it needs (null: always available).
const Map<String, Feature?> bridgeMethods = {
  'host.capabilities': null,
  'location.get': Feature.location,
  'camera.request': Feature.camera,
  'microphone.request': Feature.microphone,
  'bluetooth.scan': Feature.bluetooth,
  'bluetooth.stopScan': Feature.bluetooth,
  'bluetooth.connect': Feature.bluetooth,
  'bluetooth.disconnect': Feature.bluetooth,
  'bluetooth.services': Feature.bluetooth,
  'bluetooth.read': Feature.bluetooth,
  'bluetooth.write': Feature.bluetooth,
  'bluetooth.subscribe': Feature.bluetooth,
  'bluetooth.unsubscribe': Feature.bluetooth,
  'wifi.get': Feature.wifi,
  'wifi.signal': Feature.wifiSignal,
  'wifi.enable': Feature.wifiEnable,
  'bluetooth.enable': Feature.bluetooth,
  'torch.set': Feature.torch,
  'torch.get': Feature.torch,
  'nfc.read': Feature.nfc,
  'sensors.list': Feature.sensors,
  'sensors.watch': Feature.sensors,
  'sensors.stop': Feature.sensors,
  'gestures.watch': Feature.gestures,
  'gestures.stop': Feature.gestures,
  'device.battery': Feature.deviceInfo,
  'clipboard.read': Feature.clipboardRead,
  'clipboard.write': Feature.clipboardWrite,
  'profile.get': null,
  'auth.token': Feature.authToken,
  'auth.browser': Feature.authBrowser,
  'scanner.scan': Feature.scanner,
  'image.pick': Feature.imagePick,
  'share': Feature.share,
  'open.url': Feature.openUrl,
  'haptics': Feature.haptics,
  'screen.keepOn': Feature.keepScreenOn,
  'storage.get': Feature.storage,
  'storage.set': Feature.storage,
  'storage.remove': Feature.storage,
  'storage.keys': Feature.storage,
  'storage.clear': Feature.storage,
  'device.info': Feature.deviceInfo,
  'link.create': Feature.links,
  'notifications.show': Feature.notifications,
  'notifications.schedule': Feature.notifications,
  'notifications.cancel': Feature.notifications,
  'biometric.confirm': Feature.biometric,
  'contacts.pick': Feature.contactsPick,
};
