class PuzzleRushConfig {
  final int? durationSeconds; // 180 (3m), 300 (5m), null (Survival)
  final int lives; // 3, 5, 1
  final bool includeAntiTactics;
  final int difficultyRampStep; // 15 (Slow), 30 (Medium), 50 (Fast)

  const PuzzleRushConfig({
    this.durationSeconds = 180,
    this.lives = 3,
    this.includeAntiTactics = true,
    this.difficultyRampStep = 30,
  });

  String get durationLabel {
    if (durationSeconds == 180) return '3 Min';
    if (durationSeconds == 300) return '5 Min';
    return 'Survival';
  }

  String get livesLabel {
    if (lives == 1) return '1 Life';
    return '$lives Lives';
  }

  String get rampLabel {
    if (difficultyRampStep == 15) return 'Slow (+15)';
    if (difficultyRampStep == 50) return 'Fast (+50)';
    return 'Medium (+30)';
  }

  Map<String, dynamic> toJson() {
    return {
      'durationSeconds': durationSeconds,
      'lives': lives,
      'includeAntiTactics': includeAntiTactics,
      'difficultyRampStep': difficultyRampStep,
    };
  }

  factory PuzzleRushConfig.fromJson(Map<String, dynamic> json) {
    return PuzzleRushConfig(
      durationSeconds: json['durationSeconds'] as int?,
      lives: json['lives'] as int? ?? 3,
      includeAntiTactics: json['includeAntiTactics'] as bool? ?? true,
      difficultyRampStep: json['difficultyRampStep'] as int? ?? 30,
    );
  }
}
