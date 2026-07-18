"""
opening_book_lookup.py
======================
Backend-Modul zur Eröffnungsbuch-Suche für Bot-Persönlichkeiten.

Dieses Modul ist vollständig losgelöst von jeder UI-Logik.
Es übernimmt folgende Aufgaben:
  - Laden und Parsen der Eröffnungsbuch-Datendatei (JSON)
  - Normalisierung einer FEN-Stellung auf einen stabilen Lookup-Schlüssel
  - Suche nach einem vordefinierten Zug für einen bestimmten Bot
  - Rückgabe des Zuges oder eines sauberen OutOfBook-Signals

Schnittstelle für den nächsten Schritt:
  - Gibt `None` (OutOfBook) zurück → UCI-Engine-Anbindung übernimmt
  - Gibt einen Zug im UCI-Format zurück (z. B. "e2e4") → direkt verwendbar

Angenommene Datenstruktur des JSON-Eröffnungsbuches:
{
  "<bot_id>": {
    "<fen_normalized>": "<uci_move>",
    ...
  },
  ...
}
"""

import json
import os
from dataclasses import dataclass
from typing import Optional


# ---------------------------------------------------------------------------
# Datenklassen
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BookResult:
    """Kapselt das Ergebnis einer Eröffnungsbuch-Suche."""

    move: Optional[str]  # UCI-Zug, z. B. "e2e4", oder None bei OutOfBook
    in_book: bool         # True, wenn ein Zug im Buch gefunden wurde
    bot_id: str           # Bot-ID der Anfrage
    fen: str              # Normalisierte FEN der Anfrage

    @property
    def is_out_of_book(self) -> bool:
        """True, wenn kein Buchzug gefunden wurde."""
        return not self.in_book


# ---------------------------------------------------------------------------
# FEN-Normalisierung
# ---------------------------------------------------------------------------

def normalize_fen(fen: str) -> str:
    """
    Normalisiert eine FEN-Zeichenkette auf die ersten 4 Felder.

    Hintergrund: FEN besteht aus 6 Feldern, aber für den Positions-
    Vergleich sind nur die ersten 4 relevant:
      1. Figurenaufstellung
      2. Am Zug (w/b)
      3. Rochaderechte (KQkq)
      4. En-Passant-Zielfeld

    Halbzug- und Vollzugzähler (Felder 5 und 6) variieren je nach
    Spielverlauf, sind jedoch für die Eröffnungs-ID irrelevant.

    Args:
        fen: Vollständige FEN-Zeichenkette.

    Returns:
        Normalisierte FEN (4 Felder, durch Leerzeichen getrennt).

    Raises:
        ValueError: Wenn die FEN weniger als 4 Felder enthält.
    """
    fields = fen.strip().split()
    if len(fields) < 4:
        raise ValueError(f"Ungültige FEN (weniger als 4 Felder): '{fen}'")
    return " ".join(fields[:4])


# ---------------------------------------------------------------------------
# Eröffnungsbuch-Loader
# ---------------------------------------------------------------------------

class OpeningBookLoader:
    """
    Lädt und cached das Eröffnungsbuch aus einer JSON-Datei.

    Das Buch wird beim ersten Zugriff einmalig geladen und dann im
    Speicher gehalten. Alle FEN-Schlüssel werden beim Laden
    normalisiert, um spätere Lookups schnell und konsistent zu machen.
    """

    def __init__(self, book_path: str):
        """
        Args:
            book_path: Absoluter oder relativer Pfad zur JSON-Datei.
        """
        self._book_path = book_path
        self._book: Optional[dict] = None  # Lazy-loaded

    def _load(self) -> dict:
        """
        Lädt die JSON-Datei von der Festplatte und normalisiert alle FEN-Schlüssel.

        Returns:
            Eröffnungsbuch als verschachteltes Dict:
            { bot_id -> { normalized_fen -> uci_move } }

        Raises:
            FileNotFoundError: Wenn die Datei nicht existiert.
            json.JSONDecodeError: Wenn die JSON-Datei fehlerhaft ist.
        """
        if not os.path.isfile(self._book_path):
            raise FileNotFoundError(
                f"Eröffnungsbuch-Datei nicht gefunden: '{self._book_path}'"
            )

        with open(self._book_path, encoding="utf-8") as f:
            raw: dict = json.load(f)

        # Normalisiere alle FEN-Schlüssel für jeden Bot
        normalized_book: dict = {}
        for bot_id, positions in raw.items():
            normalized_book[bot_id] = {
                normalize_fen(fen): move
                for fen, move in positions.items()
            }

        return normalized_book

    @property
    def book(self) -> dict:
        """Gibt das gecachte Buch zurück; lädt es bei Bedarf."""
        if self._book is None:
            self._book = self._load()
        return self._book

    def reload(self) -> None:
        """Erzwingt ein erneutes Laden der Datei vom Datenträger."""
        self._book = None


# ---------------------------------------------------------------------------
# Eröffnungsbuch-Lookup-Service
# ---------------------------------------------------------------------------

class OpeningBookService:
    """
    Kernlogik des Eröffnungsbuch-Lookups.

    Nimmt eine FEN-Stellung und eine Bot-ID entgegen und prüft,
    ob für diese Stellung ein Buchzug für den angegebenen Bot
    hinterlegt ist.

    Verwendung:
        loader  = OpeningBookLoader("path/to/opening_book.json")
        service = OpeningBookService(loader)

        result = service.lookup(
            fen    = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            bot_id = "bot_aggressive",
        )

        if result.is_out_of_book:
            # → Weiter zur UCI-Engine-Anbindung
            pass
        else:
            print(f"Buchzug gefunden: {result.move}")
    """

    def __init__(self, loader: OpeningBookLoader):
        """
        Args:
            loader: Ein OpeningBookLoader, der die Buchdaten bereitstellt.
        """
        self._loader = loader

    def lookup(self, fen: str, bot_id: str) -> BookResult:
        """
        Prüft, ob für die gegebene FEN-Stellung und Bot-ID ein Buchzug existiert.

        Args:
            fen:    Aktuelle Stellung im FEN-Format (beliebige Felder-Anzahl).
            bot_id: Bezeichner der Bot-Persönlichkeit.

        Returns:
            BookResult mit dem Buchzug (in_book=True) oder
            OutOfBook-Signal (in_book=False, move=None).
        """
        try:
            normalized = normalize_fen(fen)
        except ValueError:
            # Ungültige FEN → sicheres Fallback zu OutOfBook
            return BookResult(move=None, in_book=False, bot_id=bot_id, fen=fen)

        book = self._loader.book

        # Prüfe, ob der Bot überhaupt im Buch vorhanden ist
        if bot_id not in book:
            return BookResult(move=None, in_book=False, bot_id=bot_id, fen=normalized)

        # Suche nach der Stellung im Eröffnungsbuch des Bots
        move = book[bot_id].get(normalized)

        if move is None:
            # Stellung nicht im Buch → OutOfBook → Engine übernimmt
            return BookResult(move=None, in_book=False, bot_id=bot_id, fen=normalized)

        # Buchzug gefunden
        return BookResult(move=move, in_book=True, bot_id=bot_id, fen=normalized)


# ---------------------------------------------------------------------------
# Fabrikfunktion (öffentliche API)
# ---------------------------------------------------------------------------

def create_opening_book_service(book_path: str) -> OpeningBookService:
    """
    Erstellt einen vollständig konfigurierten OpeningBookService.

    Dies ist der empfohlene Einstiegspunkt für externe Module (z. B.
    die UCI-Engine-Anbindung), um den Service zu instanziieren.

    Args:
        book_path: Pfad zur JSON-Eröffnungsbuchdatei.

    Returns:
        Fertig konfigurierter OpeningBookService.
    """
    loader = OpeningBookLoader(book_path)
    return OpeningBookService(loader)
