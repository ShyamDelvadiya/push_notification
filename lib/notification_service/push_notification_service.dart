import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request notification permission
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('user granted Notification permission');
    } else {
      print('User declined or has not granted permission');
    }

    ///------- Listen for foreground messages -------------------\\\
    FirebaseMessaging.onMessage.listen(
      (RemoteMessage message) {
        print('Message received: ${message.notification?.title}');
        print('Message body: ${message.notification?.body}');
        _showNotification(message);
      },
    );

    /// ------------  Listen for background ---------------\\\
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    ///----------------  Handle notification tap when app is in the background or terminated ------------\\\
    FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) {
        print('Notification clicked: ${message.notification?.title}');
      },
    );

    // Retrieve FCM token
    String? token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');
  }

  static Future<void> _firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    print('Background message received: ${message.notification?.title}');
  }

  Future<void> _showNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? androidNotification = message.notification?.android;

    if (notification != null && androidNotification != null) {
      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        'default_channel',
        'Default',
        importance: Importance.high,
        priority: Priority.high,
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidNotificationDetails);

      await _flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformChannelSpecifics,
      );
    }
  }
}
