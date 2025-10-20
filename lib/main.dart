import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:valeobandeco/services/notification_service.dart';
import 'services/cardapio_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart'; // Importar intl
import 'package:intl/date_symbol_data_local.dart'; // Para formatação em português

// --- LÓGICA DE BACKGROUND (WORKMANAGER) ---
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final cardapioService = CardapioService();
    final notificationService = NotificationService();
    await notificationService.init();

    // Workmanager pode rodar um pouco depois, então pegamos a data atual novamente
    final hoje = DateTime.now();
    CardapioDia cardapio;
    try {
      cardapio = await cardapioService.buscarCardapioDoDia(hoje);
    } catch (e) {
      // Se a busca falhar, criamos um CardapioDia com erro para evitar null checks
      print('Erro ao buscar cardápio no callbackDispatcher: $e');
      cardapio = CardapioDia(
        almoco: PratoInfo(principal: 'Não foi possível buscar o cardápio.'),
        janta: PratoInfo(principal: 'Não foi possível buscar o cardápio.'),
      );
    }

    String titulo = 'Confira o cardápio do bandeco!';
    String corpo = 'Toque para ver o cardápio completo.'; // Mensagem padrão

    // Verifica se o prato principal não é a mensagem de erro padrão
    bool almocoOk =
        cardapio.almoco.principal != 'Erro ao carregar' &&
        cardapio.almoco.principal != 'Não disponível' &&
        cardapio.almoco.principal != 'Não foi possível buscar o cardápio.';
    bool jantaOk =
        cardapio.janta.principal != 'Erro ao carregar' &&
        cardapio.janta.principal != 'Não disponível' &&
        cardapio.janta.principal != 'Não foi possível buscar o cardápio.';

    if (taskName == 'almocoTask') {
      titulo = '😋 Cardápio do Almoço liberado!';
      if (almocoOk) {
        corpo = cardapio.almoco.principal;
      }
    } else if (taskName == 'jantaTask') {
      titulo = '🌃 É hora da Janta!';
      if (jantaOk) {
        corpo = cardapio.janta.principal;
      }
    }

    // Só mostra notificação se o corpo não for a mensagem de erro
    if (corpo != 'Não foi possível buscar o cardápio.' &&
        corpo != 'Toque para ver o cardápio completo.') {
      await notificationService.showNotification(
        id: taskName == 'almocoTask' ? 0 : 1,
        title: titulo,
        body: corpo,
      );
    }

    return Future.value(true); // Indica sucesso mesmo se não enviou notificação
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null); // Inicializa formatação PT-BR

  await Workmanager().initialize(
    callbackDispatcher 
  );

  await Workmanager().cancelByUniqueName('almocoTaskId');
  await Workmanager().cancelByUniqueName('jantaTaskId');

  Workmanager().registerPeriodicTask(
    'almocoTaskId',
    'almocoTask',
    frequency: const Duration(days: 1),
    initialDelay: _calculateInitialDelay(8, 45),
    existingWorkPolicy:
        ExistingPeriodicWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    constraints: Constraints(networkType: NetworkType.connected),
  );

  Workmanager().registerPeriodicTask(
    'jantaTaskId',
    'jantaTask',
    frequency: const Duration(days: 1),
    initialDelay: _calculateInitialDelay(17, 45),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
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
  // Adiciona um pequeno atraso aleatório (até 5 min) para distribuir a carga
  // scheduledDate = scheduledDate.add(Duration(minutes: Random().nextInt(5)));
  print("Próxima execução agendada para: $scheduledDate");
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
        appBarTheme: AppBarTheme(
          titleTextStyle: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
          Theme.of(context).textTheme,
        ),
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
  // late Future<CardapioDia> _cardapioFuture; // Removemos o Future daqui
  CardapioDia? _cardapioAtual; // Guardamos o cardápio carregado
  bool _isLoading = true; // Estado de carregamento
  String? _errorMessage; // Mensagem de erro
  DateTime _currentDate = DateTime.now(); // Data atual sendo exibida
  final CardapioService _cardapioService = CardapioService();
  final PageController _pageController =
      PageController(); // Controlador para PageView

  @override
  void initState() {
    super.initState();
    _pedirPermissaoNotificacao();
    _fetchCardapioForDate(_currentDate); // Busca o cardápio para a data inicial
  }

  Future<void> _pedirPermissaoNotificacao() async {
    try {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();

      // Verifica a plataforma antes de pedir permissão
      if (Theme.of(context).platform == TargetPlatform.android) {
        final plugin = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (plugin != null) {
          await plugin.requestNotificationsPermission();
        }
      }
      // Adicionar lógica para iOS se necessário
      // else if (Theme.of(context).platform == TargetPlatform.iOS) { ... }
    } catch (e) {
      print("Erro ao pedir permissão de notificação: $e");
      // Opcional: Mostrar uma mensagem para o usuário
    }
  }

  // Busca o cardápio para uma data específica
  Future<void> _fetchCardapioForDate(DateTime date) async {
    setState(() {
      _isLoading = true; // Inicia o carregamento
      _errorMessage = null; // Limpa erros anteriores
    });
    try {
      final cardapio = await _cardapioService.buscarCardapioDoDia(date);
      // Verifica se o widget ainda está montado antes de atualizar o estado
      if (mounted) {
        setState(() {
          _cardapioAtual = cardapio;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao carregar o cardápio: $e';
          _isLoading = false;
          _cardapioAtual = null; // Limpa o cardápio em caso de erro
        });
      }
    }
  }

  // Navega para o dia anterior
  void _goToPreviousDay() {
    // Impede de ir para antes de segunda-feira (weekday == 1)
    if (_currentDate.weekday == DateTime.monday) return;
    final newDate = _currentDate.subtract(const Duration(days: 1));
    // Se for fim de semana, pula para sexta
    // if (newDate.weekday > DateTime.friday) {
    //   newDate = newDate.subtract(Duration(days: newDate.weekday - DateTime.friday));
    // }
    _updateDate(newDate);
  }

  // Navega para o próximo dia
  void _goToNextDay() {
    // Impede de ir para depois de domingo (weekday == 7)
    if (_currentDate.weekday == DateTime.sunday) return;
    final newDate = _currentDate.add(const Duration(days: 1));
    // Se for fim de semana, pula para segunda
    // if (newDate.weekday > DateTime.friday) {
    //   newDate = newDate.add(Duration(days: DateTime.monday + 7 - newDate.weekday));
    // }
    _updateDate(newDate);
  }

  // Atualiza a data e busca o novo cardápio
  void _updateDate(DateTime newDate) {
    setState(() {
      _currentDate = newDate;
    });
    _fetchCardapioForDate(_currentDate);
  }

  // Formata a data para exibição (Ex: "Segunda-feira, 20/10")
  String _formatDate(DateTime date) {
    // Capitaliza a primeira letra do dia da semana
    String weekday = DateFormat('EEEE', 'pt_BR').format(date);
    weekday = weekday[0].toUpperCase() + weekday.substring(1);
    return '$weekday, ${DateFormat('dd/MM', 'pt_BR').format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Adiciona botões de navegação e a data formatada
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: _currentDate.weekday == DateTime.monday
              ? null
              : _goToPreviousDay, // Desabilita se for segunda
          tooltip: 'Dia anterior',
        ),
        title: Text(_formatDate(_currentDate)), // Mostra a data formatada
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: _currentDate.weekday == DateTime.sunday
                ? null
                : _goToNextDay, // Desabilita se for domingo
            tooltip: 'Próximo dia',
          ),
        ],
      ),
      // Usamos GestureDetector para detectar swipes na área do corpo
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 100) {
            // Swipe para a esquerda (velocidade positiva)
            _goToPreviousDay();
          } else if (details.primaryVelocity! < -100) {
            // Swipe para a direita (velocidade negativa)
            _goToNextDay();
          }
        },
        child: RefreshIndicator(
          onRefresh: () =>
              _fetchCardapioForDate(_currentDate), // Atualiza o dia atual
          child: Center(
            // Centraliza o conteúdo
            child:
                _buildBodyContent(), // Função separada para construir o corpo
          ),
        ),
      ),
    );
  }

  // Constrói o conteúdo do corpo baseado no estado (loading, error, success)
  Widget _buildBodyContent() {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _fetchCardapioForDate(_currentDate),
              child: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }
    if (_cardapioAtual != null) {
      // Usamos ListView para permitir scroll caso o conteúdo seja grande
      // e SingleChildScrollView + Column para centralizar se for pequeno
      // Garante que o RefreshIndicator funcione corretamente com ListView
      return ListView(
        // physics: const AlwaysScrollableScrollPhysics(), // Garante scroll mesmo com pouco conteúdo
        padding: const EdgeInsets.all(16.0),
        children: [
          // Adiciona um Sized Box para dar espaço no topo e permitir puxar para atualizar mais facilmente
          // const SizedBox(height: 10),
          _buildRefeicaoCard(
            refeicao: 'Almoço',
            pratoInfo: _cardapioAtual!.almoco,
          ),
          const SizedBox(height: 20),
          _buildRefeicaoCard(
            refeicao: 'Janta',
            pratoInfo: _cardapioAtual!.janta,
          ),
          // Adiciona espaço no final
          const SizedBox(height: 20),
        ],
      );
    }
    // Caso inesperado (sem erro, sem loading, sem cardápio)
    return const Text("Nenhum cardápio disponível para esta data.");
  }

  /// Constrói o card para uma refeição (Almoço ou Janta)
  Widget _buildRefeicaoCard({
    required String refeicao,
    required PratoInfo pratoInfo,
  }) {
    // Verifica se o cardápio está realmente disponível
    bool isNaoDisponivel = pratoInfo.principal == 'Não disponível';
    bool isErro = pratoInfo.principal == 'Erro ao carregar';

    final PratoAnalise analise = (isNaoDisponivel || isErro)
        ? PratoAnalise(
            emoji: '🤷',
            opiniao: 'Cardápio não encontrado',
            classe: 'indisponivel',
          ) // Análise padrão para indisponível/erro
        : _cardapioService.analisaPrato(pratoInfo.principal);

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
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isNaoDisponivel || isErro
                    ? Colors.grey
                    : Colors.deepOrange, // Cor diferente se não disponível
              ),
            ),
            const Divider(height: 20),
            // Mostra o prato principal ou a mensagem de erro/indisponível
            Text(
              pratoInfo.principal,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isNaoDisponivel || isErro
                    ? Colors.grey[600]
                    : null, // Cor cinza se não disponível
              ),
            ),
            // Só mostra análise, vegano, acompanhamentos etc., se o cardápio estiver disponível
            if (!isNaoDisponivel && !isErro) ...[
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
              if (pratoInfo.vegano.isNotEmpty &&
                  pratoInfo.vegano != 'Não disponível')
                Text(
                  'Opção Vegana: ${pratoInfo.vegano}',
                  style: const TextStyle(color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              if (pratoInfo.vegano.isNotEmpty &&
                  pratoInfo.vegano != 'Não disponível')
                const SizedBox(height: 10), // Espaçamento só se houver vegano

              if (pratoInfo.acompanhamentos.isNotEmpty)
                Text(
                  'Acompanhamentos: ${pratoInfo.acompanhamentos.join(" • ")}',
                  textAlign: TextAlign.center,
                ),
              if (pratoInfo.acompanhamentos.isNotEmpty)
                const SizedBox(
                  height: 10,
                ), // Espaçamento só se houver acompanhamento

              if (pratoInfo.refresco.isNotEmpty &&
                  pratoInfo.refresco != 'Não disponível')
                Text('Refresco: ${pratoInfo.refresco}'),
              if (pratoInfo.refresco.isNotEmpty &&
                  pratoInfo.refresco != 'Não disponível')
                const SizedBox(height: 10), // Espaçamento só se houver refresco

              if (pratoInfo.sobremesa.isNotEmpty &&
                  pratoInfo.sobremesa != 'Não disponível')
                Text('Sobremesa: ${pratoInfo.sobremesa}'),
              // Não precisa de SizedBox no final
            ] else if (isNaoDisponivel) ...[
              const SizedBox(height: 16),
              const Text(
                "Cardápio não cadastrado para esta data.",
                style: TextStyle(color: Colors.grey),
              ),
            ] else if (isErro) ...[
              // Se for erro, mostra a mensagem de erro que veio do service
              const SizedBox(height: 16),
              const Text(
                "Não foi possível carregar esta parte do cardápio.",
                style: TextStyle(color: Colors.redAccent),
              ),
            ],
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
        return Colors.orange[800]!; // Laranja escuro para "não vale a pena"
      case 'muito-ruim':
        return Colors.red[900]!;
      case 'indisponivel': // Cor para quando o cardápio não está disponível
        return Colors.grey[500]!;
      default: // Classe vazia ou desconhecida (aposta)
        return Colors.blueGrey[700]!; // Um cinza azulado para "aposta"
    }
  }
}
