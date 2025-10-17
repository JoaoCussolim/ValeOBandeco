import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Configurações de inicialização para Android e iOS
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        ); // Ícone padrão do app

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    // Detalhes da notificação para Android
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'bandeco_channel_id', // ID do canal
          'Cardápio do Bandeco', // Nome do canal
          channelDescription: 'Notificações sobre o almoço e janta do bandeco.',
          importance: Importance.max,
          priority: Priority.high,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await _notificationsPlugin.show(id, title, body, notificationDetails);
  }
}
