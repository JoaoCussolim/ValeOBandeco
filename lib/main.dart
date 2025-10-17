import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:valeobandeco/services/notification_service.dart';
import 'services/cardapio_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';

// --- LÓGICA DE BACKGROUND (WORKMANAGER) ---
// Esta função PRECISA ser de alto nível (fora de qualquer classe)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final cardapioService = CardapioService();
    final notificationService = NotificationService();
    await notificationService.init();

    final hoje = DateTime.now();
    final cardapio = await cardapioService.buscarCardapioDoDia(hoje);

    String titulo = 'Confira o cardápio do bandeco!';
    String corpo = 'Não foi possível carregar o cardápio.';

    if (taskName == 'almocoTask') {
      titulo = '😋 Cardápio do Almoço liberado!';
      corpo = cardapio.almoco.principal;
    } else if (taskName == 'jantaTask') {
      titulo = '🌃 É hora da Janta!';
      corpo = cardapio.janta.principal;
    }

    await notificationService.showNotification(
      id: taskName == 'almocoTask' ? 0 : 1,
      title: titulo,
      body: corpo,
    );

    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

  Workmanager().registerPeriodicTask(
    'almocoTaskId',
    'almocoTask',
    frequency: const Duration(days: 1),
    initialDelay: _calculateInitialDelay(7, 0), // Roda às 7:00
    constraints: Constraints(networkType: NetworkType.connected),
  );

  Workmanager().registerPeriodicTask(
    'jantaTaskId',
    'jantaTask',
    frequency: const Duration(days: 1),
    initialDelay: _calculateInitialDelay(18, 0), // Roda às 18:00
    constraints: Constraints(networkType: NetworkType.connected),
  );

  runApp(const MyApp());
}

Duration _calculateInitialDelay(int hour, int minute) {
  final now = DateTime.now();
  var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }
  return scheduledDate.difference(now);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bandeco Vale a Pena?',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: GoogleFonts.nunito().fontFamily,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<CardapioDia> _cardapioFuture;
  final CardapioService _cardapioService = CardapioService();

  @override
  void initState() {
    super.initState();
    _pedirPermissaoNotificacao();
    _fetchCardapio();
  }

  Future<void> _pedirPermissaoNotificacao() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Theme.of(context).platform == TargetPlatform.android) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  void _fetchCardapio() {
    setState(() {
      _cardapioFuture = _cardapioService.buscarCardapioDoDia(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cardápio da Semana')),
      body: FutureBuilder<CardapioDia>(
        future: _cardapioFuture,
        builder: (context, snapshot) {
          // Estado de Carregamento
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Estado de Erro
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Erro ao carregar o cardápio.'),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _fetchCardapio,
                    child: const Text('Tentar Novamente'),
                  ),
                ],
              ),
            );
          }
          // Estado de Sucesso
          final cardapio = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _fetchCardapio(),
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildRefeicaoCard(
                  refeicao: 'Almoço',
                  pratoInfo: cardapio.almoco,
                ),
                const SizedBox(height: 20),
                _buildRefeicaoCard(
                  refeicao: 'Janta',
                  pratoInfo: cardapio.janta,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Constrói o card para uma refeição (Almoço ou Janta)
  Widget _buildRefeicaoCard({
    required String refeicao,
    required PratoInfo pratoInfo,
  }) {
    final analise = _cardapioService.analisaPrato(pratoInfo.principal);

    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              refeicao,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
            const Divider(height: 20),
            Text(
              pratoInfo.principal,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text(analise.emoji, style: const TextStyle(fontSize: 60)),
            const SizedBox(height: 8),
            Text(
              analise.opiniao,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _getColorFromClasse(analise.classe),
              ),
            ),
            const Divider(height: 30),
            Text(
              'Opção Vegana: ${pratoInfo.vegano}',
              style: const TextStyle(color: Colors.green),
            ),
            const SizedBox(height: 10),
            Text('Acompanhamentos: ${pratoInfo.acompanhamentos.join(" • ")}'),
            const SizedBox(height: 10),
            Text('Refresco: ${pratoInfo.refresco}'),
            const SizedBox(height: 10),
            Text('Sobremesa: ${pratoInfo.sobremesa}'),
          ],
        ),
      ),
    );
  }

  /// Retorna uma cor baseada na classe da análise (igual ao seu CSS)
  Color _getColorFromClasse(String classe) {
    switch (classe) {
      case 'muito-bom':
        return Colors.green[700]!;
      case 'vale-a-pena':
        return Colors.green;
      case 'nao-vale-a-pena':
        return Colors.red;
      case 'muito-ruim':
        return Colors.red[900]!;
      default:
        return Colors.grey[700]!;
    }
  }
}
