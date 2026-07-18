"""
test_opening_book_lookup.py
============================
Unit-Tests für das Eröffnungsbuch-Lookup-Modul.

Getestet werden:
  - FEN-Normalisierung (valide und ungültige Eingaben)
  - Buchzug gefunden (InBook)
  - Stellung nicht im Buch (OutOfBook)
  - Unbekannte Bot-ID (OutOfBook)
  - Ungültige FEN (OutOfBook-Fallback, kein Absturz)
  - Reload-Mechanismus des Loaders
"""

import json
import os
import tempfile
import unittest

from opening_book_lookup import (
    BookResult,
    OpeningBookLoader,
    OpeningBookService,
    create_opening_book_service,
    normalize_fen,
)


# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

SAMPLE_BOOK = {
    "bot_aggressive": {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -": "e2e4",
        "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3": "e7e5",
    },
    "bot_solid": {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -": "d2d4",
    },
}


def _write_temp_book(data: dict) -> str:
    """Schreibt ein Test-Eröffnungsbuch in eine temporäre Datei."""
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return path


# ---------------------------------------------------------------------------
# Tests: FEN-Normalisierung
# ---------------------------------------------------------------------------

class TestNormalizeFen(unittest.TestCase):

    def test_strips_halfmove_and_fullmove_clocks(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        expected = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
        self.assertEqual(normalize_fen(fen), expected)

    def test_strips_extra_whitespace(self):
        fen = "  rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR   w  KQkq  -  5  10  "
        result = normalize_fen(fen)
        self.assertEqual(len(result.split()), 4)

    def test_already_four_fields_passes_through(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
        self.assertEqual(normalize_fen(fen), fen)

    def test_raises_on_too_few_fields(self):
        with self.assertRaises(ValueError):
            normalize_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w")


# ---------------------------------------------------------------------------
# Tests: Eröffnungsbuch-Lookup
# ---------------------------------------------------------------------------

class TestOpeningBookService(unittest.TestCase):

    def setUp(self):
        self.book_path = _write_temp_book(SAMPLE_BOOK)
        self.service = create_opening_book_service(self.book_path)

    def tearDown(self):
        os.unlink(self.book_path)

    # -----------------------------------------------------------------------
    # InBook-Fälle
    # -----------------------------------------------------------------------

    def test_returns_book_move_when_fen_in_book(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        result = self.service.lookup(fen=fen, bot_id="bot_aggressive")
        self.assertTrue(result.in_book)
        self.assertFalse(result.is_out_of_book)
        self.assertEqual(result.move, "e2e4")

    def test_different_bot_returns_different_move_for_same_fen(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        result = self.service.lookup(fen=fen, bot_id="bot_solid")
        self.assertTrue(result.in_book)
        self.assertEqual(result.move, "d2d4")

    def test_fen_with_different_clocks_still_matches(self):
        # FEN mit anderen Halb- und Vollzugsfeldern soll trotzdem treffen
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 99 50"
        result = self.service.lookup(fen=fen, bot_id="bot_aggressive")
        self.assertTrue(result.in_book)
        self.assertEqual(result.move, "e2e4")

    # -----------------------------------------------------------------------
    # OutOfBook-Fälle
    # -----------------------------------------------------------------------

    def test_unknown_position_returns_out_of_book(self):
        fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        result = self.service.lookup(fen=fen, bot_id="bot_aggressive")
        self.assertFalse(result.in_book)
        self.assertTrue(result.is_out_of_book)
        self.assertIsNone(result.move)

    def test_unknown_bot_id_returns_out_of_book(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        result = self.service.lookup(fen=fen, bot_id="bot_nonexistent")
        self.assertFalse(result.in_book)
        self.assertIsNone(result.move)

    def test_invalid_fen_returns_out_of_book_without_crash(self):
        result = self.service.lookup(fen="garbage input", bot_id="bot_aggressive")
        self.assertFalse(result.in_book)
        self.assertIsNone(result.move)

    # -----------------------------------------------------------------------
    # BookResult-Metadaten
    # -----------------------------------------------------------------------

    def test_result_carries_correct_bot_id(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        result = self.service.lookup(fen=fen, bot_id="bot_aggressive")
        self.assertEqual(result.bot_id, "bot_aggressive")

    def test_result_fen_is_normalized(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        result = self.service.lookup(fen=fen, bot_id="bot_aggressive")
        self.assertEqual(len(result.fen.split()), 4)

    # -----------------------------------------------------------------------
    # Fehlertoleranz
    # -----------------------------------------------------------------------

    def test_missing_book_file_raises_file_not_found(self):
        service = create_opening_book_service("/nonexistent/path/book.json")
        with self.assertRaises(FileNotFoundError):
            service.lookup(
                fen="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                bot_id="bot_aggressive",
            )

    def test_reload_reloads_data(self):
        loader = OpeningBookLoader(self.book_path)
        _ = loader.book  # Einmal laden und cachen

        # Loader sollte reload unterstützen (keine Exception)
        loader.reload()
        self.assertIsNotNone(loader.book)


if __name__ == "__main__":
    unittest.main()
