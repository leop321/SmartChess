"""
uci_engine.py
=============
Asynchroner Controller für Schach-Engines über das UCI-Protokoll.

Dieses Modul startet eine Engine als Subprozess und kommuniziert
mit ihr ausschließlich über stdin/stdout nach UCI-Spezifikation.

Kein UI-Code. Kein Netzwerk-Code. Nur purer Datenstrom-Handler.

UCI-Ablauf (vereinfacht):
  Client → "uci"
  Engine → ... → "uciok"
  Client → "setoption name X value Y"
  Client → "isready"
  Engine → "readyok"
  Client → "position fen <FEN>"
  Client → "go movetime 1000"
  Engine → ... → "bestmove <ZUG>"

Schnittstelle nach außen:
  - UciEngineController.calculate_move(fen, go_command) → str (UCI-Zug)
  - Als Context Manager verwendbar (async with) für sicheres Cleanup
"""

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Konfiguration des Engine-Starts
# ---------------------------------------------------------------------------

@dataclass
class UciEngineConfig:
    """Alle Parameter, die für den Start und die Konfiguration einer UCI-Engine benötigt werden."""

    # Pfad zur Engine-Binary oder einfach der Name, wenn im PATH (z. B. "stockfish")
    engine_binary: str

    # UCI-Optionen als Dict: { "Skill Level": "15", "Threads": "2", ... }
    uci_options: dict[str, str] = field(default_factory=dict)

    # Timeout in Sekunden: Wie lange wir maximal auf "uciok" / "readyok" warten
    init_timeout_sec: float = 10.0

    # Timeout in Sekunden: Wie lange wir maximal auf "bestmove" warten
    # Sollte großzügiger als go_command-Zeit sein (Puffer für Prozess-Overhead)
    move_timeout_sec: float = 60.0


# ---------------------------------------------------------------------------
# Ergebnis-Datenklasse
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class EngineResult:
    """Kapselt das Ergebnis einer Engine-Berechnung."""

    move: Optional[str]       # UCI-Zug, z. B. "e2e4" oder None bei Fehler
    ponder: Optional[str]     # Ponder-Zug (optional, von Engine geliefert)
    raw_bestmove_line: str    # Rohzeile "bestmove e2e4 ponder e7e5" für Debugging

    @property
    def is_valid(self) -> bool:
        """True, wenn ein gültiger Zug zurückgegeben wurde."""
        return self.move is not None and self.move != "(none)"


# ---------------------------------------------------------------------------
# Hilfsfunktion: bestmove-Zeile parsen
# ---------------------------------------------------------------------------

def _parse_bestmove_line(line: str) -> tuple[Optional[str], Optional[str]]:
    """
    Parst eine UCI 'bestmove'-Zeile.

    Beispiele:
      "bestmove e2e4 ponder e7e5" → ("e2e4", "e7e5")
      "bestmove e2e4"             → ("e2e4", None)
      "bestmove (none)"           → (None, None)

    Args:
        line: Rohe Ausgabezeile der Engine.

    Returns:
        Tupel (best_move, ponder_move), beide Optional[str].
    """
    parts = line.strip().split()
    # parts[0] == "bestmove"
    if len(parts) < 2:
        return None, None

    best = parts[1] if parts[1] != "(none)" else None
    ponder = parts[3] if len(parts) >= 4 and parts[2] == "ponder" else None
    return best, ponder


# ---------------------------------------------------------------------------
# Haupt-Controller
# ---------------------------------------------------------------------------

class UciEngineController:
    """
    Asynchroner Controller für eine einzelne UCI-Engine-Instanz.

    Startet die Engine als Subprozess und kommuniziert über stdin/stdout.
    Sicheres Ressourcen-Management über __aenter__ / __aexit__ (async with).

    Verwendung:
        config = UciEngineConfig(engine_binary="stockfish", uci_options={"Skill Level": "10"})
        async with UciEngineController(config) as engine:
            move = await engine.calculate_move("rnbqkbnr/.../... w KQkq -", "go movetime 1000")
    """

    def __init__(self, config: UciEngineConfig):
        self._config = config
        self._process: Optional[asyncio.subprocess.Process] = None

    # -----------------------------------------------------------------------
    # Privat: Senden und Empfangen
    # -----------------------------------------------------------------------

    def _send(self, command: str) -> None:
        """
        Sendet einen UCI-Befehl an stdin der Engine.

        Args:
            command: UCI-Befehl ohne abschließendes Newline.
        """
        if self._process is None or self._process.stdin is None:
            raise RuntimeError("Engine-Prozess ist nicht gestartet.")

        raw = (command + "\n").encode()
        self._process.stdin.write(raw)
        logger.debug("→ Engine: %s", command)

    async def _read_until(self, sentinel: str, timeout: float) -> list[str]:
        """
        Liest Ausgabe-Zeilen der Engine, bis eine Zeile mit `sentinel` beginnt.

        Args:
            sentinel: Erwartetes Schlüsselwort (z. B. "uciok", "readyok", "bestmove").
            timeout:  Maximale Wartezeit in Sekunden.

        Returns:
            Alle gelesenen Zeilen (einschließlich der sentinel-Zeile).

        Raises:
            asyncio.TimeoutError: Wenn das Sentinel nicht innerhalb des Timeouts kommt.
            RuntimeError: Wenn der Engine-Prozess nicht gestartet ist.
        """
        if self._process is None or self._process.stdout is None:
            raise RuntimeError("Engine-Prozess ist nicht gestartet.")

        collected: list[str] = []

        async def _inner() -> list[str]:
            while True:
                raw_line = await self._process.stdout.readline()
                if not raw_line:
                    # EOF: Engine hat sich unerwartet beendet
                    raise RuntimeError("Engine-Prozess hat sich unerwartet beendet.")
                line = raw_line.decode(errors="replace").strip()
                logger.debug("← Engine: %s", line)
                collected.append(line)
                if line.startswith(sentinel):
                    return collected

        return await asyncio.wait_for(_inner(), timeout=timeout)

    # -----------------------------------------------------------------------
    # Privat: UCI-Initialisierung
    # -----------------------------------------------------------------------

    async def _initialize(self) -> None:
        """
        Führt den vollständigen UCI-Handshake durch:
          1. Sendet 'uci', wartet auf 'uciok'
          2. Setzt alle konfigurierten Optionen via 'setoption'
          3. Sendet 'isready', wartet auf 'readyok'
        """
        timeout = self._config.init_timeout_sec

        # Schritt 1: UCI-Handshake
        self._send("uci")
        await self._read_until("uciok", timeout=timeout)
        logger.info("UCI-Handshake erfolgreich für '%s'.", self._config.engine_binary)

        # Schritt 2: Optionen setzen
        for name, value in self._config.uci_options.items():
            self._send(f"setoption name {name} value {value}")
            logger.debug("Option gesetzt: %s = %s", name, value)

        # Schritt 3: Bereitschaft bestätigen
        self._send("isready")
        await self._read_until("readyok", timeout=timeout)
        logger.info("Engine '%s' ist bereit.", self._config.engine_binary)

    # -----------------------------------------------------------------------
    # Öffentliche Methoden
    # -----------------------------------------------------------------------

    async def start(self) -> None:
        """
        Startet den Engine-Subprozess und führt den UCI-Initialisierungsablauf durch.

        Raises:
            FileNotFoundError: Wenn die Engine-Binary nicht gefunden wird.
            asyncio.TimeoutError: Wenn die Initialisierung zu lange dauert.
        """
        logger.info("Starte Engine: '%s'", self._config.engine_binary)
        self._process = await asyncio.create_subprocess_exec(
            self._config.engine_binary,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,  # Engine-Fehler ignorieren wir hier
        )
        await self._initialize()

    async def calculate_move(self, fen: str, go_command: str) -> EngineResult:
        """
        Übergibt eine FEN-Stellung und berechnet den besten Zug.

        Ablauf:
          1. "ucinewgame" (setzt internen Engine-Zustand zurück)
          2. "position fen <FEN>"
          3. go_command (z. B. "go movetime 1000" oder "go nodes 1")
          4. Liest Output bis "bestmove <ZUG>"

        Args:
            fen:        Vollständige FEN-Zeichenkette der Stellung.
            go_command: UCI go-Befehl (vollständig, z. B. "go movetime 500").

        Returns:
            EngineResult mit dem berechneten Zug.

        Raises:
            asyncio.TimeoutError: Wenn die Engine zu lange rechnet.
            RuntimeError: Wenn die Engine nicht gestartet ist.
        """
        # Engine-Zustand zurücksetzen (verhindert Hash-Kollisionen bei neuer Partie)
        self._send("ucinewgame")
        self._send(f"position fen {fen}")
        self._send(go_command)

        lines = await self._read_until(
            sentinel="bestmove",
            timeout=self._config.move_timeout_sec,
        )

        # Die letzte Zeile ist garantiert die bestmove-Zeile
        bestmove_line = lines[-1]
        move, ponder = _parse_bestmove_line(bestmove_line)

        return EngineResult(
            move=move,
            ponder=ponder,
            raw_bestmove_line=bestmove_line,
        )

    async def close(self) -> None:
        """
        Beendet die Engine sauber über den UCI-Befehl 'quit'.

        Wartet bis zu 3 Sekunden auf einen sauberen Exit, bevor
        der Prozess hart terminiert wird.
        """
        if self._process is None:
            return

        try:
            self._send("quit")
            await asyncio.wait_for(self._process.wait(), timeout=3.0)
            logger.info("Engine '%s' sauber beendet.", self._config.engine_binary)
        except (asyncio.TimeoutError, BrokenPipeError):
            logger.warning(
                "Engine '%s' reagiert nicht auf 'quit' – terminiere hart.",
                self._config.engine_binary,
            )
            self._process.terminate()
            await self._process.wait()
        finally:
            self._process = None

    # -----------------------------------------------------------------------
    # Context Manager (async with UciEngineController(...) as engine)
    # -----------------------------------------------------------------------

    async def __aenter__(self) -> "UciEngineController":
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        await self.close()
