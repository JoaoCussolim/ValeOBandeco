import 'dart:convert'; // Necessário para a decodificação latin1 (windows-1252)
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;

/// Modelo para guardar o resultado da análise de um prato.
class PratoAnalise {
  final String emoji;
  final String opiniao;
  final String classe; // Usaremos para definir a cor no Flutter

  PratoAnalise({
    required this.emoji,
    required this.opiniao,
    required this.classe,
  });
}

/// Modelo para guardar todas as informações de uma refeição (Almoço ou Janta).
class PratoInfo {
  String principal;
  String vegano;
  List<String> acompanhamentos;
  String refresco;
  String sobremesa;

  PratoInfo({
    this.principal = 'Não disponível',
    this.vegano = 'Não disponível',
    this.acompanhamentos = const [],
    this.refresco = 'Não disponível',
    this.sobremesa = 'Não disponível',
  });
}

/// Modelo que representa o cardápio completo de um dia.
class CardapioDia {
  final PratoInfo almoco;
  final PratoInfo janta;

  CardapioDia({required this.almoco, required this.janta});
}

/// Serviço responsável por buscar, extrair e analisar os dados do cardápio.
class CardapioService {
  // --- REGRAS E CONSTANTES (Tradução direta do seu JavaScript) ---
  static const List<Map<String, String>> _regrasCustomizadas = [
    {
      'palavraChave': 'fricassé',
      'emoji': '🤩',
      'opiniao': 'É a perfeição!',
      'classe': 'muito-bom',
    },
    {
      'palavraChave': 'strogonoff',
      'emoji': '😍',
      'opiniao': 'Coma imediatamente!',
      'classe': 'muito-bom',
    },
    {
      'palavraChave': 'moqueca de peixe',
      'emoji': '🤮',
      'opiniao': 'PERIGO!',
      'classe': 'muito-ruim',
    },
    {
      'palavraChave': 'tilápia',
      'emoji': '🤢',
      'opiniao': 'FUJA!',
      'classe': 'muito-ruim',
    },
    {
      'palavraChave': 'pescada',
      'emoji': '🤢',
      'opiniao': 'FUJA!',
      'classe': 'muito-ruim',
    },
    {
      'palavraChave': 'peixe',
      'emoji': '😖',
      'opiniao': 'Passe longe...',
      'classe': 'nao-vale-a-pena',
    },
    {
      'palavraChave': 'moqueca',
      'emoji': '😒',
      'opiniao': 'Melhor evitar.',
      'classe': 'nao-vale-a-pena',
    },
    {
      'palavraChave': 'jiló',
      'emoji': '🤢',
      'opiniao': 'Melhor não...',
      'classe': 'nao-vale-a-pena',
    },
    {
      'palavraChave': 'dobradinha',
      'emoji': '🤢',
      'opiniao': 'Melhor não...',
      'classe': 'nao-vale-a-pena',
    },
    {
      'palavraChave': 'puchero',
      'emoji': '🤔',
      'opiniao': 'Sei nem oq é isso.',
      'classe': 'nao-vale-a-pena',
    },
    {
      'palavraChave': 'moela',
      'emoji': '🤢',
      'opiniao': 'Melhor não...',
      'classe': 'nao-vale-a-pena',
    },
  ];
  static const List<String> _palavrasBoas = [
    'carne',
    'bife',
    'sobrecoxa',
    'frango',
    'bovina',
    'bisteca',
    'parmegiana',
    'churrasco',
    'massa',
    'batata',
  ];

  /// Analisa o nome do prato e retorna uma opinião com base nas regras.
  /// (Tradução direta da sua função `analisaPrato`)
  PratoAnalise analisaPrato(String nomeDoPrato) {
    final nomeLower = nomeDoPrato.toLowerCase();

    for (final regra in _regrasCustomizadas) {
      if (nomeLower.contains(regra['palavraChave']!)) {
        return PratoAnalise(
          emoji: regra['emoji']!,
          opiniao: regra['opiniao']!,
          classe: regra['classe']!,
        );
      }
    }

    for (final palavra in _palavrasBoas) {
      if (nomeLower.contains(palavra)) {
        return PratoAnalise(
          emoji: '😋',
          opiniao: 'Vale a pena!',
          classe: 'vale-a-pena',
        );
      }
    }

    return PratoAnalise(emoji: '🧐', opiniao: 'É uma aposta!', classe: '');
  }

  /// Função auxiliar para extrair dados de uma seção do HTML do cardápio.
  /// (Tradução direta da sua função `extrairDados`)
  PratoInfo _extrairDados(dom.Element? section) {
    if (section == null)
      return PratoInfo(); // Retorna dados vazios se a seção não existir

    final pratoInfo = PratoInfo();

    pratoInfo.principal =
        section.querySelector('.menu-item-name')?.text.trim() ??
        'Não disponível';

    // Pega a descrição e separa por linhas (<br>)
    final descHTML =
        section.querySelector('.menu-item-description')?.innerHtml ?? '';
    final allItens = descHTML
        .split('<br>')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    // Remove observações, se houver
    final obsIndex = allItens.indexWhere(
      (item) => item.toLowerCase().startsWith('observações'),
    );
    final descItens = (obsIndex != -1
        ? allItens.sublist(0, obsIndex)
        : allItens);

    final List<String> tempAcompanhamentos = [];
    for (var item in descItens) {
      if (item.toLowerCase().contains('refresco')) {
        // Remove "REFRESCO DE " para pegar só o sabor
        pratoInfo.refresco = item.replaceAll(
          RegExp(r'REFRESCO DE ', caseSensitive: false),
          '',
        );
      } else {
        tempAcompanhamentos.add(item);
      }
    }

    // Se achamos um refresco e ainda há itens, o último é a sobremesa
    if (pratoInfo.refresco != 'Não disponível' &&
        tempAcompanhamentos.isNotEmpty) {
      pratoInfo.sobremesa = tempAcompanhamentos.removeLast();
    }

    pratoInfo.acompanhamentos = tempAcompanhamentos;

    return pratoInfo;
  }

  /// Busca o cardápio para uma data específica, faz o parse e retorna os dados organizados.
  Future<CardapioDia> buscarCardapioDoDia(DateTime data) async {
    final dataFormatada =
        "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
    final url = Uri.parse(
      "https://sistemas.prefeitura.unicamp.br/apps/cardapio/index.php?d=$dataFormatada",
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        // O site usa a codificação 'windows-1252', que no Dart é a 'latin1'
        final body = latin1.decode(response.bodyBytes);
        final document = parser.parse(body);

        final sections = document.querySelectorAll('.menu-section');

        // Extrai os dados de cada seção (almoço, veg almoço, janta, veg janta)
        final dadosAlmoco = _extrairDados(
          sections.isNotEmpty ? sections[0] : null,
        );
        final dadosAlmocoVegano = _extrairDados(
          sections.length > 1 ? sections[1] : null,
        );
        final dadosJanta = _extrairDados(
          sections.length > 2 ? sections[2] : null,
        );
        final dadosJantaVegano = _extrairDados(
          sections.length > 3 ? sections[3] : null,
        );

        // Combina as informações veganas nos objetos principais
        dadosAlmoco.vegano = dadosAlmocoVegano.principal;
        dadosJanta.vegano = dadosJantaVegano.principal;

        return CardapioDia(almoco: dadosAlmoco, janta: dadosJanta);
      } else {
        throw Exception(
          'Falha ao carregar o cardápio: Status ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Erro em buscarCardapioDoDia: $e');
      // Em caso de erro, retorna um objeto com informações de erro
      return CardapioDia(
        almoco: PratoInfo(principal: 'Erro ao carregar'),
        janta: PratoInfo(principal: 'Erro ao carregar'),
      );
    }
  }
}
