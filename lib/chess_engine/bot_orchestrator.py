"""
bot_orchestrator.py
====================
Zusammenführender Controller für Bot-Persönlichkeiten.

Dieses Modul ist die zentrale Schaltstelle zwischen:
  - Dem Eröffnungsbuch-Lookup (OpeningBookService)
  - Der UCI-Engine-Anbindung (UciEngineController)
  - Der Bot-Konfiguration (bot_config.json)

Ablauf für eine Anfrage (FEN + bot_id):
  1. Konfiguration für bot_id aus bot_config.json laden.
  2. OpeningBookService fragen → Buchzug?
     a. Buchzug gefunden  → sofort zurückgeben (kein Engine-Start nötig)
     b. OutOfBook         → Engine starten, Zug berechnen, Engine schließen
  3. Ergebnis als MoveDecision-Datenklasse zurückgeben.

Kein UI-Code. Kein Netzwerk. Nur Datenstrom-Orchestrierung.
"""

import asyncio
import json
import logging
import os
from dataclasses import dataclass
from enum import Enum, auto
from typing import Optional

from opening_book.opening_book_lookup import create_opening_book_service
from uci_engine import EngineResult, UciEngineConfig, UciEngineController

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Ergebnis-Typen
# ---------------------------------------------------------------------------

class MoveSource(Enum):
    """Zeigt an, woher der empfohlene Zug stammt."""
    OPENING_BOOK = auto()   # Buchzug – Engine wurde nicht gestartet
    ENGINE       = auto()   # Engine-Berechnung
    ERROR        = auto()   # Fehlerfall – kein gültiger Zug verfügbar


@dataclass(frozen=True)
class MoveDecision:
    """
    Endresultat des Orchestrators für eine Bot-Anfrage.

    Felder:
        move:        UCI-Zug (z. B. "e2e4") oder None bei Fehler.
        source:      MoveSource-Enum (OPENING_BOOK / ENGINE / ERROR).
        bot_id:      Bot-ID der Anfrage.
        fen:         Angefragte FEN-Stellung.
        engine_result: Roh-Ergebnis der Engine (nur bei source=ENGINE gesetzt).
        error_message: Fehlerbeschreibung (nur bei source=ERROR gesetzt).
    """
    move:          Optional[str]
    source:        MoveSource
    bot_id:        str
    fen:           str
    engine_result: Optional[EngineResult] = None
    error_message: Optional[str]         = None

    @property
    def is_valid(self) -> bool:
        return self.move is not None


# ---------------------------------------------------------------------------
# Bot-Konfigurations-Loader
# ---------------------------------------------------------------------------

class BotConfigLoader:
    """
    Lädt und cached die Bot-Konfigurationen aus bot_config.json.

    Jede Bot-Konfiguration enthält:
      - engine_binary:     Pfad/Name der Engine-Binary
      - go_command:        Vollständiger UCI go-Befehl
      - uci_options:       Dict mit Engine-Optionen
      - opening_book_path: Relativer Pfad zur Eröffnungsbuch-JSON-Datei
    """

    def __init__(self, config_path: str):
        self._config_path = config_path
        self._configs: Optional[dict] = None

    def _load(self) -> dict:
        if not os.path.isfile(self._config_path):
            raise FileNotFoundError(
                f"Bot-Konfigurationsdatei nicht gefunden: '{self._config_path}'"
            )
        with open(self._config_path, encoding="utf-8") as f:
            return json.load(f)

    @property
    def configs(self) -> dict:
        if self._configs is None:
            self._configs = self._load()
        return self._configs

    def get(self, bot_id: str) -> dict:
        """
        Gibt die Konfiguration für eine Bot-ID zurück.

        Raises:
            KeyError: Wenn die bot_id nicht in der Konfigurationsdatei existiert.
        """
        if bot_id not in self.configs:
            raise KeyError(
                f"Unbekannte Bot-ID: '{bot_id}'. "
                f"Bekannte IDs: {list(self.configs.keys())}"
            )
        return self.configs[bot_id]


# ---------------------------------------------------------------------------
# Haupt-Orchestrator
# ---------------------------------------------------------------------------

class BotOrchestrator:
    """
    Orchestriert den gesamten Zug-Entscheidungsprozess für einen Bot.

    Kombiniert Eröffnungsbuch-Lookup und UCI-Engine-Anbindung basierend
    auf der Bot-Konfiguration.

    Verwendung (einmaliger Aufruf):
        orchestrator = BotOrchestrator(
            config_dir="path/to/chess_engine/"
        )
        decision = await orchestrator.get_move(
            fen    = "rnbqkbnr/.../... w KQkq - 0 1",
            bot_id = "bot_1200_maia",
        )
        if decision.is_valid:
            print(f"Zug: {decision.move} (Quelle: {decision.source.name})")

    Verwendung (wiederholte Aufrufe mit persistenter Engine):
        Für Szenarien, wo dieselbe Engine-Instanz mehrfach genutzt werden soll,
        kann UciEngineController direkt als Context Manager verwendet werden.
        Siehe get_move_with_persistent_engine() unten.
    """

    def __init__(self, config_dir: str):
        """
        Args:
            config_dir: Verzeichnis, in dem bot_config.json liegt.
                        Eröffnungsbuch-Pfade in der Konfiguration werden
                        relativ zu diesem Verzeichnis aufgelöst.
        """
        self._config_dir = config_dir
        self._bot_config_loader = BotConfigLoader(
            os.path.join(config_dir, "bot_config.json")
        )

    def _resolve_path(self, relative_path: str) -> str:
        """Löst einen in der Konfiguration angegebenen relativen Pfad auf."""
        return os.path.join(self._config_dir, relative_path)

    def _build_uci_config(self, bot_cfg: dict) -> UciEngineConfig:
        """Erstellt einen UciEngineConfig aus dem Bot-Konfigurations-Dict."""
        return UciEngineConfig(
            engine_binary=bot_cfg["engine_binary"],
            uci_options=bot_cfg.get("uci_options", {}),
        )

    async def get_move(self, fen: str, bot_id: str) -> MoveDecision:
        """
        Hauptmethode: Gibt den empfohlenen Zug für eine Stellung und Bot-ID zurück.

        Ablauf:
          1. Bot-Konfiguration laden.
          2. OpeningBookService fragen.
          3a. Buchzug → sofort als MoveDecision(source=OPENING_BOOK) zurückgeben.
          3b. OutOfBook → Engine starten, berechnen, Engine schließen.

        Die Engine wird pro Aufruf neu gestartet und nach dem Zug sofort
        geschlossen. Für persistente Engine-Sitzungen: get_move_with_engine().

        Args:
            fen:    Vollständige FEN-Zeichenkette.
            bot_id: Bezeichner der Bot-Persönlichkeit.

        Returns:
            MoveDecision mit Zug, Quelle und Metadaten.
        """
        # Schritt 1: Bot-Konfiguration laden
        try:
            bot_cfg = self._bot_config_loader.get(bot_id)
        except KeyError as exc:
            logger.error("Unbekannte Bot-ID: %s", bot_id)
            return MoveDecision(
                move=None, source=MoveSource.ERROR,
                bot_id=bot_id, fen=fen,
                error_message=str(exc),
            )

        # Schritt 2: Eröffnungsbuch-Lookup
        book_path = self._resolve_path(bot_cfg["opening_book_path"])
        try:
            book_service = create_opening_book_service(book_path)
            book_result = book_service.lookup(fen=fen, bot_id=bot_id)
        except Exception as exc:
            logger.warning(
                "Eröffnungsbuch-Fehler für Bot '%s': %s – fahre mit Engine fort.",
                bot_id, exc,
            )
            book_result = None  # Sicheres Fallback: Engine übernimmt

        # Schritt 3a: Buchzug direkt zurückgeben
        if book_result is not None and book_result.in_book:
            logger.info(
                "Bot '%s' spielt Buchzug '%s' für FEN '%s'.",
                bot_id, book_result.move, fen,
            )
            return MoveDecision(
                move=book_result.move,
                source=MoveSource.OPENING_BOOK,
                bot_id=bot_id,
                fen=fen,
            )

        # Schritt 3b: OutOfBook → Engine fragen
        logger.info(
            "Bot '%s' ist OutOfBook für FEN '%s' – starte Engine '%s'.",
            bot_id, fen, bot_cfg["engine_binary"],
        )
        uci_config = self._build_uci_config(bot_cfg)
        go_command = bot_cfg["go_command"]

        return await self._run_engine(
            fen=fen, bot_id=bot_id,
            uci_config=uci_config, go_command=go_command,
        )

    async def _run_engine(
        self,
        fen: str,
        bot_id: str,
        uci_config: UciEngineConfig,
        go_command: str,
    ) -> MoveDecision:
        """
        Startet die Engine, berechnet den Zug und schließt die Engine wieder.

        Internes Hilfsmethode. Ressourcen werden über 'async with' garantiert
        freigegeben, auch bei Exceptions.

        Returns:
            MoveDecision mit source=ENGINE oder source=ERROR.
        """
        try:
            async with UciEngineController(uci_config) as engine:
                result = await engine.calculate_move(fen=fen, go_command=go_command)

            if result.is_valid:
                logger.info(
                    "Engine liefert Zug '%s' für Bot '%s'.",
                    result.move, bot_id,
                )
                return MoveDecision(
                    move=result.move,
                    source=MoveSource.ENGINE,
                    bot_id=bot_id,
                    fen=fen,
                    engine_result=result,
                )
            else:
                logger.warning("Engine lieferte keinen gültigen Zug für Bot '%s'.", bot_id)
                return MoveDecision(
                    move=None, source=MoveSource.ERROR,
                    bot_id=bot_id, fen=fen,
                    engine_result=result,
                    error_message="Engine lieferte '(none)' – möglicherweise Mattstellung.",
                )

        except FileNotFoundError:
            msg = f"Engine-Binary '{uci_config.engine_binary}' nicht gefunden."
            logger.error(msg)
            return MoveDecision(
                move=None, source=MoveSource.ERROR,
                bot_id=bot_id, fen=fen, error_message=msg,
            )
        except asyncio.TimeoutError:
            msg = f"Engine-Timeout: '{uci_config.engine_binary}' hat nicht rechtzeitig geantwortet."
            logger.error(msg)
            return MoveDecision(
                move=None, source=MoveSource.ERROR,
                bot_id=bot_id, fen=fen, error_message=msg,
            )
        except Exception as exc:
            msg = f"Unerwarteter Engine-Fehler: {exc}"
            logger.exception(msg)
            return MoveDecision(
                move=None, source=MoveSource.ERROR,
                bot_id=bot_id, fen=fen, error_message=msg,
            )

    async def get_move_with_engine(
        self,
        fen: str,
        bot_id: str,
        engine: UciEngineController,
    ) -> MoveDecision:
        """
        Variante für persistente Engine-Sitzungen.

        Wenn die Engine bereits läuft (z. B. für eine ganze Partie),
        kann sie hier direkt übergeben werden. Die Engine wird NICHT
        geschlossen – das obliegt dem Aufrufer.

        Nützlich für:
          - Analyse-Modus (viele Stellungen in einer Session)
          - Mehrere Züge in einer Partie mit derselben Engine-Instanz

        Args:
            fen:    Vollständige FEN-Zeichenkette.
            bot_id: Bezeichner der Bot-Persönlichkeit.
            engine: Bereits gestartete UciEngineController-Instanz.

        Returns:
            MoveDecision.
        """
        try:
            bot_cfg = self._bot_config_loader.get(bot_id)
        except KeyError as exc:
            return MoveDecision(
                move=None, source=MoveSource.ERROR,
                bot_id=bot_id, fen=fen, error_message=str(exc),
            )

        # Eröffnungsbuch immer zuerst fragen
        book_path = self._resolve_path(bot_cfg["opening_book_path"])
        try:
            book_service = create_opening_book_service(book_path)
            book_result = book_service.lookup(fen=fen, bot_id=bot_id)
            if book_result.in_book:
                return MoveDecision(
                    move=book_result.move,
                    source=MoveSource.OPENING_BOOK,
                    bot_id=bot_id, fen=fen,
                )
        except Exception as exc:
            logger.warning("Buch-Fehler: %s – fahre mit Engine fort.", exc)

        # Engine-Berechnung mit persistenter Instanz
        go_command = bot_cfg["go_command"]
        result = await engine.calculate_move(fen=fen, go_command=go_command)
        return MoveDecision(
            move=result.move if result.is_valid else None,
            source=MoveSource.ENGINE if result.is_valid else MoveSource.ERROR,
            bot_id=bot_id, fen=fen, engine_result=result,
        )
