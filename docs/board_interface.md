# Board-Interface & Spiellogik Dokumentation

Dieses Dokument dient als technische Referenz für die Wiederverwendung der bestehenden Schachbrett- und Spiellogik (`ChessGame`, `ChessBoard`, `GameController`) im Rahmen künftiger Taktik- und Puzzle-Integrationen.

---

## 1. Stellungsrepräsentation & Source of Truth

* **Laufzeit-Repräsentation:**
  * Die primäre Stellung wird in `ChessBoard` als 64-Elemente langes Array `List<ChessPiece?> tiles = List.filled(64, null);` gehalten ([lib/logic/chess_board.dart:70](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L70)).
  * Parallel existieren getrennte Figurenlisten pro Spieler (`player1Pieces`, `player2Pieces`, `player1Rooks`, `player2Rooks`, `player1Queens`, `player2Queens`, `player1King`, `player2King`, [lib/logic/chess_board.dart:73-80](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L73-L80)).
  * Der Zobrist-Hash wird zur Zustandserkennung in `int zobristHash` inkrementell gepflegt ([lib/logic/chess_board.dart:85](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L85)).
  * Historische Züge und Rücknahmen werden über `List<MoveStackObject> moveStack` und `redoStack` verwaltet ([lib/logic/chess_board.dart:71-72](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L71-L72)).

* **Source of Truth:**
  * Das interne `tiles`-Array zusammen mit den `ChessPiece`-Listen ist die **alleinige Source of Truth** während des Spielbetriebs.
  * FEN (Forsyth-Edwards Notation) dient ausschließlich als externes Serialisierungs- und Ladeformat ([lib/logic/chess_board.dart:123](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L123) in `loadFEN`). Das `tiles`-Array wird beim Aufruf von `loadFEN` aus dem FEN-String neu aufgebaut.
  * *Hinweis:* Es gibt im Core-Board keine kontinuierliche `getFEN()`-Methode; FEN-Generierung für den Analyse-Modus erfolgt separat über das `chess`-Paket in `GameAnalysisPage` ([lib/views/components/analyze_view/game_analysis_page.dart:152](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/views/components/analyze_view/game_analysis_page.dart#L152)).

---

## 2. Setzen einer Stellung von außen

* **Modell- / Board-Ebene:**
  * **Methode:** `Player loadFEN(String fen)` ([lib/logic/chess_board.dart:123](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L123))
  * **Parameter:** `String fen`
  * **Rückgabewert:** `Player` (der am Zug befindliche Spieler: `Player.player1` für Weiß, `Player.player2` für Schwarz).
  * **Wirkung:** Leert alle Figurenlisten und Stacks, initialisiert die 64 Felder, parst Rochaderechte, En-Passant-Feld sowie Halbzug-/Vollzugzähler und ermittelt den Schach-Status der Könige.

* **Controller-Ebene:**
  * **Methode:** `void loadFEN(String fen)` ([lib/logic/game_controller.dart:73](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L73))
  * **Parameter:** `String fen`
  * **Wirkung:**
    ```dart
    void loadFEN(String fen) {
      appModel.turn = board.loadFEN(fen);
      validMoves = [];
      selectedPiece = null;
      latestMove = null;
      checkHintTile = null;
      warningTile = null;
      snapSprites(snap: true);
    }
    ```
  * Aktualisiert den Zugstatus im `AppModel`, setzt Auswahlen zurück und triggert `snapSprites()` im Flame-Layer zur Neupositionierung der Figurensprites.

---

## 3. Steuerung der Brettorientierung

* **Zentraler Getter:**
  * `bool get isBoardInverted` in `AppModel` ([lib/model/app_model.dart:346-361](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/model/app_model.dart#L346-L361)):
    * Liefert `true`, wenn Schwarz unten dargestellt werden soll (um 180° gedreht), sonst `false`.
    * Nach der Bereinigung in Schritt 1 orientiert sich `isBoardInverted` im Einzelspieler-/KI-Modus an `playerSide == Player.player2` und im 2-Spieler-Modus an `enableRotation && turn == Player.player2`.
* **Interaktion mit der UI / Engine:**
  1. **Flutter-Widget-Ebene:** `ChessBoardWidget` wrappt das Flame-Spielfeld in ein `AnimatedRotation(turns: appModel.isBoardInverted ? 0.5 : 0)` ([lib/views/components/chess_view/chess_board_widget.dart:18-24](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/views/components/chess_view/chess_board_widget.dart#L18-L24)).
  2. **Koordinaten-Overlay:** `_NotationOverlay` spiegelt die Beschriftung (a–h bzw. h–a / 1–8 bzw. 8–1) synchron anhand von `appModel.isBoardInverted` ([lib/views/components/chess_view/chess_board_widget.dart:47](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/views/components/chess_view/chess_board_widget.dart#L47)).
  3. **Flame-Canvas:** `ChessGame` setzt `targetRotation = appModel.isBoardInverted ? math.pi : 0` ([lib/logic/chess_game.dart:196-206](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_game.dart#L196-L206)) und richtet die Figuren-Sprites über `_getPieceRotation()` aus ([lib/logic/chess_game.dart:306-312](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_game.dart#L306-L312)).

---

## 4. Meldung ausgeführter Nutzerzüge

* **Input-Pipeline (Flame -> Controller):**
  * `ChessGame.onTapDown(TapDownEvent event)` ([lib/logic/chess_game.dart:130-133](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_game.dart#L130-L133)) rechnet die Touch-Koordinaten in einen Feldindex (0–63) um und ruft `controller.handleTap(int tile)` auf ([lib/logic/game_controller.dart:95](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L95)).
* **User-Move-Callback / Interceptor:**
  * **Feld:** `bool Function(Move move)? onUserMoveCompleted;` ([lib/logic/game_controller.dart:58](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L58))
  * **Exakte Signatur:** `bool Function(Move move)`
  * **Aufrufstelle:** Wird in `GameController.movePiece(int tile)` synchron vor der Ausführung (`board.push`) aufgerufen ([lib/logic/game_controller.dart:156-165](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L156-L165)).
  * **Rückgabewert:** Wenn `onUserMoveCompleted!(attemptedMove)` den Wert `false` liefert, wird der Zug sofort abgebrochen, die Auswahl verworfen und ein Warn-Haptic-Signal ausgelöst.
* **Abschlussmeldung:**
  * Nach erfolgreicher Ausführung benachrichtigt `_moveCompletion` das `AppModel` über `appModel.pushMoveMeta(meta)` und `appModel.update()` (`notifyListeners()`) ([lib/logic/game_controller.dart:513-524](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L513-L524)).

---

## 5. Zugformat & Datenklassen

* **Primäres Zug-Objekt: `Move`** ([lib/logic/move_calculation/move_classes/move.dart:3-8](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/move_calculation/move_classes/move.dart#L3-L8))
  * `int from;` — Ausgangsfeld (0..63, 0 = a8, 63 = h1).
  * `int to;` — Zielfeld (0..63).
  * `ChessPieceType promotionType;` — Ziel-Figurentyp bei Umwandlung (Default: `ChessPieceType.promotion`).
* **Zusätzliche Metadaten: `MoveMeta`** ([lib/logic/move_calculation/move_classes/move_meta.dart:5-19](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/move_calculation/move_classes/move_meta.dart#L5-L19))
  * `Move? move;`
  * `Player? player;`
  * `ChessPieceType? type;`
  * `bool took;`
  * `bool kingCastle;`
  * `bool queenCastle;`
  * `bool promotion;`
  * `ChessPieceType? promotionType;`
  * `bool isCheck;`
  * `bool isCheckmate;`
  * `bool isStalemate;`
  * `bool rowIsAmbiguous;`
  * `bool colIsAmbiguous;`
* **Stack-Objekt für Undo/Redo: `MoveStackObject`** ([lib/logic/move_calculation/move_classes/move_stack_object.dart:4-16](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/move_calculation/move_classes/move_stack_object.dart#L4-L16))
  * Hält Referenzen auf `movedPiece`, `takenPiece`, `enPassantPiece`, Flags (`castled`, `promotion`, `enPassant`) sowie den vorigen `zobristHash` und `incrementalValue`.
* **UCI-Konvertierung:**
  * Koordinaten-Strings (z. B. `e2e4`, `e7e8q`) werden über `GameController._uciToMove(String uci)` ([lib/logic/game_controller.dart:369](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L369)) bzw. `StockfishService.msoToUCI` ([lib/logic/stockfish_service.dart:181](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/stockfish_service.dart#L181)) übersetzt.

---

## 6. Programmatische Zugausführung

* **Methode für automatische Züge (z. B. Gegnerantwort im Puzzle):**
  * **Name:** `executeOpponentMove` ([lib/logic/game_controller.dart:228](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L228))
  * **Exakte Signatur:** `void executeOpponentMove(Move move)`
  * **Funktionsweise:** Führt den Zug direkt über `board.push(move, getMeta: true)` aus, spielt den Zug-Sound (`appModel.audio.playMovedSound()`), ruft `_moveCompletion(meta, changeTurn: !meta.promotion)` auf und synchronisiert eventuelle Umwandlungen.
* **Methode für direkte Züge mit Legalitätsprüfung:**
  * **Name:** `submitDirectMove` ([lib/logic/game_controller.dart:212](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L212))
  * **Exakte Signatur:** `bool submitDirectMove(Move move)`

---

## 7. Sonderzug-Unterstützung & historische Fixes

* **Rochade (Castling):**
  * **Logik:** Liegt in `ChessBoard.push` ([lib/logic/chess_board.dart:347-358](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L347-L358)), `_castle` ([lib/logic/chess_board.dart:579-610](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L579-L610)), `_undoCastle` ([lib/logic/chess_board.dart:612-626](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L612-L626)) und `_canCastle` ([lib/logic/chess_board.dart:797-812](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L797-L812)).
  * **Interne Besonderheit:** Die Engine modelliert die Rochade intern als Königsschlag auf den eigenen Turm (`Move(60, 63)` für Weiß O-O; `Move(60, 56)` für Weiß O-O-O). `push()` korrigiert das Zielfeld automatisch auf die korrekten Zielfelder für König und Turm.
  * **Robustheit & FEN-Fixes:** In den Commits `18e274c` und `a36a0a5` wurde `loadFEN` so gehärtet, dass `K`/`Q`/`k`/`q` die `moveCount`-Flags der beteiligten Türme und Könige auf 0 setzt, während alle anderen Figuren `moveCount = 1` erhalten ([lib/logic/chess_board.dart:183-185, 207-249](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L183-L185)). Dies ist für reguläre FENs vollständig und robust.
* **En-Passant:**
  * **Logik:** `_checkEnPassant` ([lib/logic/chess_board.dart:680-691](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L680-L691)), `_canTakeEnPassantAt` ([lib/logic/chess_board.dart:735-741](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L735-L741)) und FEN-Restoration ([lib/logic/chess_board.dart:251-262](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L251-L262)).
  * Funktioniert inklusive Undo/Redo fehlerfrei.
* **Bauernumwandlung (Pawn Promotion):**
  * **Logik:** `_promote` ([lib/logic/chess_board.dart:628-640](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L628-L640)), `_undoPromote` ([lib/logic/chess_board.dart:669-678](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L669-L678)).
  * **Human vs. Programmatic Flow:** Bei manuellen Zügen verzögert `movePiece` den Zugwechsel (`changeTurn: false`), bis der `PromotionDialog` gewählt wurde ([lib/logic/game_controller.dart:170-174](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L170-L174)). Programmatische Züge (`executeOpponentMove` / `_aiMove`) übergeben den Typ direkt in `Move.promotionType`.

---

## 8. Erkennung des Spielendes (Schachmatt / Patt vs. Puzzle-Lösung)

* **Schachmatt- & Patt-Erkennung:**
  * **Board-Methode:** `bool kingInCheckmate(Player player)` ([lib/logic/chess_board.dart:532-539](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_board.dart#L532-L539)) prüft, ob für den Spieler keine legalen Züge mehr existieren.
  * **Asynchrone Auslagerung:** `GameController._moveCompletion` ([lib/logic/game_controller.dart:526-534](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L526-L534)) serialisiert das Board und prüft Matt im persistenten Hintergrund-Isolate via `CheckmateWorker.check()`.
  * **Ergebnis:** Setzt `meta.isCheckmate = true`, `meta.isStalemate = true` oder beendet die Partie via `appModel.endGame(winner: moverTurn)`.
* **Eignung für Taktikaufgaben:**
  * **REICHT NICHT AUS.** Schach-Puzzles enden in der Regel nicht im Matt, sondern nach einer konkreten Zugfolge mit Material- oder Positionsgewinn (z. B. nach 2–4 Halbzügen).
  * Eine Validierung gegen eine Liste erwarteter Lösungszüge (z. B. `List<String> expectedUciMoves`) existiert im Standard-Board nicht und muss durch die übergeordnete Puzzle-Logik abgebildet werden.

---

## 9. Widget-Einbettung & Instanziierung

* **Einbettung in Flutter:**
  * `ChessGame` erweitert `FlameGame` mit `TapCallbacks` ([lib/logic/chess_game.dart:18](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_game.dart#L18)).
  * In der UI wird `ChessGame` innerhalb von `ChessBoardWidget` über das Flame-Widget `GameWidget(game: chessGame)` gerendert ([lib/views/components/chess_view/chess_board_widget.dart:34](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/views/components/chess_view/chess_board_widget.dart#L34)).
* **Mehrfachinstanziierung:**
  * `ChessGame`, `GameController` und `ChessBoard` sind **keine Singletons**. Eine zweite Instanz kann prinzipiell erstellt werden.
  * **Einschränkung:** `GameController` und `ChessGame` verlangen im Konstruktor zwingend ein `AppModel` ([lib/logic/game_controller.dart:60](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L60), [lib/logic/chess_game.dart:51](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_game.dart#L51)).
  * Wird das globale `AppModel` (aus dem Provider) an eine Puzzle-Instanz übergeben, manipulieren Puzzle-Züge globale Variablen (`appModel.turn`, `appModel.moveMetaList`, `appModel.gameOver`), was die Hauptpartie beschädigen würde. Für den Puzzle-Modus ist eine Kapselung oder ein dediziertes Puzzle-Model erforderlich.

---

## 10. Erforderliche Mindestparameter & Konfiguration

Um ein funktionierendes, isoliertes Brett im Puzzle-Modus ohne Seiteneffekte zu betreiben, sind folgende Komponenten und Konfigurationen mindestens nötig:

1. **Eigene Instanzen:**
   * Eine separate `ChessBoard`-Instanz.
   * Ein dedizierter Controller (oder eine angepasste `GameController`-Instanz).
   * Eine separate `ChessGame`-Instanz für das Rendering.
2. **Deaktivierung von KI-Automatismen:**
   * `appModel.playingWithAI = false` oder Vermeidung des automatischen Aufrufs von `_aiMove()` in `_moveCompletion` ([lib/logic/game_controller.dart:587](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L587)).
3. **Deaktivierung der Autosave-Logik:**
   * Kein Aufruf von `GameStateStorage.saveGameState()` während des Lösens von Puzzles.
4. **Isolierte Zeitsteuerung:**
   * Deaktivierung von `appModel.timerService` bzw. Nutzung eines puzzle-eigenen Timers.

---

## 11. Globale Kopplungen bei Animationen & Effekten

* **Figuren-Sprites & Drag-Animationen:**
  * `ChessPieceSprite` ([lib/logic/chess_piece_sprite.dart](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/chess_piece_sprite.dart)) ist an die Instanz von `ChessGame.spriteMap` gebunden und bricht bei separaten Instanzen **nicht**.
* **Highlights & Hints:**
  * `latestMove`, `validMoves`, `checkHintTile`, `warningTile` liegen im jeweiligen `GameController` und sind vollkommen instanzlokal.
* **Audio & Haptik:**
  * `appModel.audio.playMovedSound()` ([lib/logic/game_controller.dart:169](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L169)) und `appModel.haptic.*` rufen globale Singletons (`AudioService`, `HapticService`) auf. Diese können ohne Nebeneffekte von mehreren Instanzen genutzt werden.
* **Speech (TTS):**
  * `appModel.speak(...)` ([lib/logic/game_controller.dart:603](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L603)) liest bei jedem Zug den Zug vor, was im Puzzle-Kontext unerwünscht sein kann.

---

## Integrationsrisiken

Bei der Wiederverwendung der bestehenden Komponenten für ein neues Taktik-Feature müssen folgende Risiken zwingend berücksichtigt werden:

1. **State-Verschmutzung im `AppModel`:**
   * `GameController._moveCompletion` pusht jeden Zug direkt in `appModel.moveMetaList` ([lib/logic/game_controller.dart:513](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L513)) und schaltet `appModel.turn` um. Wird dieselbe `AppModel`-Instanz verwendet, überschreiben Puzzles die Zugliste des normalen Spiels.
2. **Ungewollter Stockfish-Start (`_aiMove`):**
   * Wenn `appModel.playingWithAI == true` aktiv ist, triggert `_moveCompletion` nach einem Zug automatisch die Stockfish-Engine ([lib/logic/game_controller.dart:587](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L587)). Puzzles benötigen stattdessen eine deterministische Ausführung des vorgegebenen Antwortzugs via `executeOpponentMove`.
3. **Isolate-Ressourcenleaks:**
   * Jeder `GameController` öffnet im Hintergrund einen `CheckmateWorker` (Isolate) ([lib/logic/game_controller.dart:68](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L68)). Wenn bei jedem Puzzle ein neuer Controller instanziiert wird, ohne den alten via `dispose()` zu schließen, führt dies zu Speicher- und Isolate-Leaks.
4. **Pawn Promotion Interaction Block:**
   * Wenn ein Puzzle eine Unterverwandlung (z. B. Umwandlung in Springer) fordert, hält die Standard-Logik den Zug an und öffnet den modalen `PromotionDialog` ([lib/logic/game_controller.dart:170](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/logic/game_controller.dart#L170)). Die Puzzle-Logik muss Umwandlungszüge entweder vorab prüfen oder den Dialog in die Lösungsvalidierung einbinden.
5. **Autosave-Interferenz:**
   * App-Lifecycle-Events (App pausiert / wechselt in den Hintergrund) rufen `appModel.saveGameStateImmediate()` auf ([lib/views/chess_view.dart:100](file:///c:/Users/Leo/Desktop/Antigravity/Flutter%20Proj/Schach2.0/lib/views/chess_view.dart#L100)). Befindet sich der Nutzer im Puzzle-Modus und teilt den State mit `AppModel`, könnte eine unvollständige Taktikaufgabe als aktive Partie persistiert werden.
