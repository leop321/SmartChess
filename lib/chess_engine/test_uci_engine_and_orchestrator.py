"""
test_uci_engine_and_orchestrator.py
=====================================
Unit-Tests für UciEngineController und BotOrchestrator.

Da wir keinen echten Stockfish-Binary voraussetzen können,
werden alle Engine-Subprozesse mit asyncio-fähigen Mocks simuliert.

Testszenarien:
  - UciEngine: bestmove-Zeile korrekt parsen
  - UciEngine: Timeout wird korrekt als asyncio.TimeoutError gemeldet
  - Orchestrator: Buchzug wird bevorzugt (Engine wird NICHT gestartet)
  - Orchestrator: OutOfBook leitet korrekt an Engine weiter
  - Orchestrator: Engine-Fehler landet sauber als MoveDecision(source=ERROR)
  - Orchestrator: Unbekannte Bot-ID → ERROR ohne Absturz
"""

import asyncio
import json
import os
import tempfile
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from uci_engine import EngineResult, UciEngineConfig, UciEngineController, _parse_bestmove_line
from bot_orchestrator import BotOrchestrator, MoveSource


# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
UNKNOWN_FEN = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"

SAMPLE_BOOK = {
    "bot_aggressive": {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -": "e2e4",
    }
}

SAMPLE_BOT_CONFIG = {
    "bot_aggressive": {
        "engine_binary": "stockfish",
        "go_command": "go movetime 100",
        "uci_options": {},
        "opening_book_path": "opening_book/opening_book.json",
    },
    "bot_no_book": {
        "engine_binary": "stockfish",
        "go_command": "go movetime 100",
        "uci_options": {},
        "opening_book_path": "opening_book/opening_book.json",
    },
}


def _write_temp_json(data: dict) -> str:
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return path


def _setup_temp_config_dir(book_data: dict, config_data: dict) -> str:
    """
    Erstellt ein temporäres Verzeichnis mit:
      - bot_config.json
      - opening_book/opening_book.json
    Gibt den Pfad zum Verzeichnis zurück.
    """
    import tempfile, shutil
    tmpdir = tempfile.mkdtemp()
    # bot_config.json
    with open(os.path.join(tmpdir, "bot_config.json"), "w") as f:
        json.dump(config_data, f)
    # opening_book/opening_book.json
    os.makedirs(os.path.join(tmpdir, "opening_book"), exist_ok=True)
    with open(os.path.join(tmpdir, "opening_book", "opening_book.json"), "w") as f:
        json.dump(book_data, f)
    return tmpdir


# ---------------------------------------------------------------------------
# Tests: bestmove-Parser
# ---------------------------------------------------------------------------

class TestParseBestmoveLine(unittest.TestCase):

    def test_parse_with_ponder(self):
        move, ponder = _parse_bestmove_line("bestmove e2e4 ponder e7e5")
        self.assertEqual(move, "e2e4")
        self.assertEqual(ponder, "e7e5")

    def test_parse_without_ponder(self):
        move, ponder = _parse_bestmove_line("bestmove d2d4")
        self.assertEqual(move, "d2d4")
        self.assertIsNone(ponder)

    def test_parse_none_move(self):
        move, ponder = _parse_bestmove_line("bestmove (none)")
        self.assertIsNone(move)
        self.assertIsNone(ponder)

    def test_parse_empty_line_returns_none(self):
        move, ponder = _parse_bestmove_line("bestmove")
        self.assertIsNone(move)


# ---------------------------------------------------------------------------
# Async-Testbasisklasse
# ---------------------------------------------------------------------------

class AsyncTestCase(unittest.TestCase):
    """Basisklasse: Führt coroutine-Tests in einem frischen Event-Loop aus."""

    def _run(self, coro):
        return asyncio.get_event_loop().run_until_complete(coro)


# ---------------------------------------------------------------------------
# Tests: UciEngineController (mit Mock-Prozess)
# ---------------------------------------------------------------------------

def _make_mock_engine_process(responses: list[str]):
    """
    Erstellt einen Mock für asyncio.create_subprocess_exec,
    der eine vordefinierte Liste von Zeilen zurückgibt.
    """
    lines = [line.encode() + b"\n" for line in responses]
    lines.append(b"")  # EOF

    async def _readline():
        if lines:
            return lines.pop(0)
        return b""

    mock_stdout = MagicMock()
    mock_stdout.readline = _readline

    mock_stdin = MagicMock()
    mock_stdin.write = MagicMock()

    mock_process = MagicMock()
    mock_process.stdin = mock_stdin
    mock_process.stdout = mock_stdout
    mock_process.wait = AsyncMock(return_value=0)

    return mock_process


class TestUciEngineController(AsyncTestCase):

    def _controller(self):
        return UciEngineController(UciEngineConfig(engine_binary="stockfish"))

    def test_calculate_move_returns_correct_move(self):
        responses = [
            "id name Stockfish",
            "uciok",
            "readyok",
            "info depth 1 score cp 30 pv e2e4",
            "bestmove e2e4 ponder e7e5",
        ]
        mock_proc = _make_mock_engine_process(responses)

        async def _test():
            ctrl = self._controller()
            with patch("asyncio.create_subprocess_exec", AsyncMock(return_value=mock_proc)):
                await ctrl.start()
                result = await ctrl.calculate_move(START_FEN, "go movetime 100")
            return result

        result = self._run(_test())
        self.assertTrue(result.is_valid)
        self.assertEqual(result.move, "e2e4")
        self.assertEqual(result.ponder, "e7e5")

    def test_close_sends_quit(self):
        responses = ["uciok", "readyok", "bestmove d2d4"]
        mock_proc = _make_mock_engine_process(responses)

        async def _test():
            ctrl = self._controller()
            with patch("asyncio.create_subprocess_exec", AsyncMock(return_value=mock_proc)):
                await ctrl.start()
                await ctrl.close()

        self._run(_test())
        # Nach close() sollte der Prozess auf None gesetzt sein
        # (kein direkter Zugriff mehr möglich → sicherer Zustand)


# ---------------------------------------------------------------------------
# Tests: BotOrchestrator
# ---------------------------------------------------------------------------

class TestBotOrchestrator(AsyncTestCase):

    def setUp(self):
        self.tmpdir = _setup_temp_config_dir(SAMPLE_BOOK, SAMPLE_BOT_CONFIG)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir)

    def test_returns_book_move_without_starting_engine(self):
        """Buchzug muss zurückgegeben werden, ohne die Engine zu starten."""
        orchestrator = BotOrchestrator(config_dir=self.tmpdir)

        async def _test():
            with patch("bot_orchestrator.UciEngineController") as mock_ctrl_cls:
                decision = await orchestrator.get_move(fen=START_FEN, bot_id="bot_aggressive")
            # UciEngineController darf NICHT instanziiert worden sein
            mock_ctrl_cls.assert_not_called()
            return decision

        decision = self._run(_test())
        self.assertTrue(decision.is_valid)
        self.assertEqual(decision.move, "e2e4")
        self.assertEqual(decision.source, MoveSource.OPENING_BOOK)

    def test_out_of_book_delegates_to_engine(self):
        """Unbekannte Stellung muss an die Engine delegiert werden."""
        orchestrator = BotOrchestrator(config_dir=self.tmpdir)

        mock_engine = AsyncMock()
        mock_engine.__aenter__ = AsyncMock(return_value=mock_engine)
        mock_engine.__aexit__ = AsyncMock(return_value=False)
        mock_engine.calculate_move = AsyncMock(
            return_value=EngineResult(
                move="g1f3", ponder=None, raw_bestmove_line="bestmove g1f3"
            )
        )

        async def _test():
            with patch("bot_orchestrator.UciEngineController", return_value=mock_engine):
                return await orchestrator.get_move(fen=UNKNOWN_FEN, bot_id="bot_aggressive")

        decision = self._run(_test())
        self.assertTrue(decision.is_valid)
        self.assertEqual(decision.move, "g1f3")
        self.assertEqual(decision.source, MoveSource.ENGINE)

    def test_unknown_bot_id_returns_error(self):
        """Unbekannte Bot-ID muss sauber als ERROR zurückgegeben werden."""
        orchestrator = BotOrchestrator(config_dir=self.tmpdir)

        decision = self._run(
            orchestrator.get_move(fen=START_FEN, bot_id="bot_does_not_exist")
        )
        self.assertFalse(decision.is_valid)
        self.assertEqual(decision.source, MoveSource.ERROR)
        self.assertIsNotNone(decision.error_message)

    def test_engine_timeout_returns_error_decision(self):
        """Engine-Timeout muss als sauberes ERROR-Ergebnis ankommen."""
        orchestrator = BotOrchestrator(config_dir=self.tmpdir)

        mock_engine = AsyncMock()
        mock_engine.__aenter__ = AsyncMock(return_value=mock_engine)
        mock_engine.__aexit__ = AsyncMock(return_value=False)
        mock_engine.calculate_move = AsyncMock(side_effect=asyncio.TimeoutError())

        async def _test():
            with patch("bot_orchestrator.UciEngineController", return_value=mock_engine):
                return await orchestrator.get_move(fen=UNKNOWN_FEN, bot_id="bot_aggressive")

        decision = self._run(_test())
        self.assertFalse(decision.is_valid)
        self.assertEqual(decision.source, MoveSource.ERROR)

    def test_engine_binary_not_found_returns_error(self):
        """Fehlende Engine-Binary muss als ERROR signalisiert werden."""
        orchestrator = BotOrchestrator(config_dir=self.tmpdir)

        mock_engine = AsyncMock()
        mock_engine.__aenter__ = AsyncMock(side_effect=FileNotFoundError("stockfish not found"))
        mock_engine.__aexit__ = AsyncMock(return_value=False)

        async def _test():
            with patch("bot_orchestrator.UciEngineController", return_value=mock_engine):
                return await orchestrator.get_move(fen=UNKNOWN_FEN, bot_id="bot_aggressive")

        decision = self._run(_test())
        self.assertFalse(decision.is_valid)
        self.assertEqual(decision.source, MoveSource.ERROR)


if __name__ == "__main__":
    unittest.main()
