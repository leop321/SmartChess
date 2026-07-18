"""
test_server.py
==============
Unit-Tests für die FastAPI-Schnittstelle.

Verwendet TestClient, um HTTP-Anfragen gegen die API zu simulieren.
Der BotOrchestrator wird gemockt, um saubere Isolation zu garantieren.
"""

import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

# Server-Modul importieren
import server
from server import app
from bot_orchestrator import MoveDecision, MoveSource
from uci_engine import EngineResult


# ---------------------------------------------------------------------------
# Test-Daten
# ---------------------------------------------------------------------------
START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
BOT_ID = "bot_test"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
class TestServerAPI(unittest.TestCase):

    def setUp(self):
        # Den globalen Orchestrator im server-Modul mit einem Mock ersetzen
        self.mock_orchestrator = AsyncMock()
        server.orchestrator = self.mock_orchestrator
        self.client = TestClient(app)

    def tearDown(self):
        server.orchestrator = None

    def test_successful_move_from_opening_book(self):
        # Mock-Verhalten: Buchzug gefunden
        self.mock_orchestrator.get_move.return_value = MoveDecision(
            move="e2e4",
            source=MoveSource.OPENING_BOOK,
            bot_id=BOT_ID,
            fen=START_FEN
        )

        response = self.client.post("/api/v1/move", json={
            "fen": START_FEN,
            "bot_id": BOT_ID
        })

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["move"], "e2e4")
        self.assertEqual(data["source"], "OPENING_BOOK")
        self.assertEqual(data["bot_id"], BOT_ID)
        self.assertIsNone(data["ponder"])

    def test_successful_move_from_engine_with_ponder(self):
        # Mock-Verhalten: Engine-Zug gefunden
        self.mock_orchestrator.get_move.return_value = MoveDecision(
            move="g1f3",
            source=MoveSource.ENGINE,
            bot_id=BOT_ID,
            fen=START_FEN,
            engine_result=EngineResult(
                move="g1f3",
                ponder="d7d5",
                raw_bestmove_line="bestmove g1f3 ponder d7d5"
            )
        )

        response = self.client.post("/api/v1/move", json={
            "fen": START_FEN,
            "bot_id": BOT_ID
        })

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["move"], "g1f3")
        self.assertEqual(data["source"], "ENGINE")
        self.assertEqual(data["ponder"], "d7d5")

    def test_empty_fen_returns_422(self):
        # Sollte von FastAPI / Pydantic oder unserer eigenen Prüfung abgefangen werden
        response = self.client.post("/api/v1/move", json={
            "fen": "   ",
            "bot_id": BOT_ID
        })
        self.assertEqual(response.status_code, 422)

    def test_missing_bot_id_returns_422(self):
        # FastAPI's Pydantic validation (Unprocessable Entity)
        response = self.client.post("/api/v1/move", json={
            "fen": START_FEN
            # bot_id fehlt
        })
        self.assertEqual(response.status_code, 422)

    def test_unknown_bot_returns_400(self):
        # Mock-Verhalten: Bot-ID unbekannt
        self.mock_orchestrator.get_move.return_value = MoveDecision(
            move=None,
            source=MoveSource.ERROR,
            bot_id="unknown_bot",
            fen=START_FEN,
            error_message="Unbekannte Bot-ID: 'unknown_bot'"
        )

        response = self.client.post("/api/v1/move", json={
            "fen": START_FEN,
            "bot_id": "unknown_bot"
        })

        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertEqual(data["detail"]["error"], "EngineError")
        self.assertTrue("Unbekannte Bot-ID" in data["detail"]["message"])

    def test_engine_error_returns_500(self):
        # Mock-Verhalten: Engine Timeout / Crash
        self.mock_orchestrator.get_move.return_value = MoveDecision(
            move=None,
            source=MoveSource.ERROR,
            bot_id=BOT_ID,
            fen=START_FEN,
            error_message="Engine-Timeout: stockfish"
        )

        response = self.client.post("/api/v1/move", json={
            "fen": START_FEN,
            "bot_id": BOT_ID
        })

        self.assertEqual(response.status_code, 500)
        data = response.json()
        self.assertEqual(data["detail"]["error"], "EngineError")
        self.assertTrue("Timeout" in data["detail"]["message"])

    def test_orchestrator_not_initialized_returns_500(self):
        # Orchestrator auf None setzen (als wäre lifespan fehlgeschlagen)
        server.orchestrator = None
        
        response = self.client.post("/api/v1/move", json={
            "fen": START_FEN,
            "bot_id": BOT_ID
        })
        self.assertEqual(response.status_code, 500)
        data = response.json()
        self.assertEqual(data["detail"], "Der BotOrchestrator ist nicht initialisiert.")

if __name__ == "__main__":
    unittest.main()
