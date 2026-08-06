class MoveRequest {
  final String fen;
  final int elo;
  final String character;

  MoveRequest({
    required this.fen,
    required this.elo,
    required this.character,
  });

  /// Generates the bot ID expected by the backend.
  /// E.g. elo=800, character='solid' => 'bot_800_solid'
  String get botId => 'bot_${elo}_$character';

  /// Serializes the request to JSON, mapping our internal fields
  /// to the format expected by the FastAPI backend.
  Map<String, dynamic> toJson() {
    return {
      'fen': fen,
      'bot_id': botId,
    };
  }
}

class MoveResponse {
  final String move;
  final String source;
  final String botId;
  final String fen;

  MoveResponse({
    required this.move,
    required this.source,
    required this.botId,
    required this.fen,
  });

  /// Parses the JSON response from the backend into a MoveResponse object.
  factory MoveResponse.fromJson(Map<String, dynamic> json) {
    return MoveResponse(
      move: json['move'] as String,
      source: json['source'] as String,
      botId: json['bot_id'] as String,
      fen: json['fen'] as String,
    );
  }
}

class AnalysisResponse {
  final double bestEval;
  final bool isMate;
  final List<String> suggestions;
  final List<double> alternatives;

  AnalysisResponse({
    required this.bestEval,
    required this.isMate,
    required this.suggestions,
    required this.alternatives,
  });

  factory AnalysisResponse.fromJson(Map<String, dynamic> json) {
    return AnalysisResponse(
      bestEval: (json['best_eval'] as num).toDouble(),
      isMate: json['is_mate'] as bool,
      suggestions: List<String>.from(json['suggestions'] as List? ?? []),
      alternatives: List<double>.from((json['alternatives'] as List? ?? [])
          .map((e) => (e as num).toDouble())),
    );
  }
}
