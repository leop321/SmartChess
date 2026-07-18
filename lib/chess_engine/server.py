"""
server.py
=========
Asynchrone REST-API (FastAPI) für den Schach-Bot.

Stellt die Schnittstelle zwischen dem mobilen Frontend (oder anderen Clients)
und dem Backend (BotOrchestrator) dar.

Enthält keine UI-Logik. Reines JSON-In / JSON-Out.
"""

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

from bot_orchestrator import BotOrchestrator, MoveSource

# ---------------------------------------------------------------------------
# Logging Setup
# ---------------------------------------------------------------------------
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Globale Instanz des Orchestrators
orchestrator: BotOrchestrator | None = None

# ---------------------------------------------------------------------------
# Lifespan / Setup
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan-Event-Handler für FastAPI.
    Wird beim Starten des Servers ausgeführt. Initialisiert den BotOrchestrator.
    """
    global orchestrator
    # Konfigurationsverzeichnis ist das Verzeichnis dieses Skripts
    config_dir = os.path.dirname(os.path.abspath(__file__))
    orchestrator = BotOrchestrator(config_dir=config_dir)
    logger.info("BotOrchestrator initialisiert (config_dir: %s)", config_dir)
    yield
    # Cleanup beim Beenden (falls nötig)
    logger.info("Server wird beendet, Cleanup...")
    orchestrator = None


# ---------------------------------------------------------------------------
# FastAPI App Definition
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Chess Bot API",
    description="REST API für Schach-Bot-Engines und Eröffnungsbücher.",
    version="1.0.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Pydantic Modelle für Request / Response
# ---------------------------------------------------------------------------
class MoveRequest(BaseModel):
    fen: str = Field(..., min_length=5, description="Die aktuelle Schachstellung im FEN-Format")
    bot_id: str = Field(..., min_length=1, description="Die ID der Bot-Persönlichkeit (z. B. 'bot_aggressive')")


class MoveResponse(BaseModel):
    move: str = Field(..., description="Der berechnete UCI-Zug (z. B. 'e2e4')")
    source: str = Field(..., description="Die Quelle des Zuges ('OPENING_BOOK' oder 'ENGINE')")
    bot_id: str = Field(..., description="Die abgefragte Bot-ID")
    fen: str = Field(..., description="Die abgefragte FEN")
    ponder: str | None = Field(None, description="Der Ponder-Zug der Engine (falls vorhanden)")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/health")
async def health_check():
    """Lightweight endpoint to ping and warm up the server during cold start."""
    return {"status": "ok"}


@app.post("/api/v1/move", response_model=MoveResponse)
async def get_move(request: MoveRequest):
    """
    Berechnet den besten Zug für eine gegebene Stellung und Bot-Persönlichkeit.
    
    - Zieht zuerst das Eröffnungsbuch zu Rate.
    - Fällt auf die konfigurierte UCI-Engine zurück, falls kein Buchzug existiert.
    """
    if not request.fen.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail="Das FEN-Feld darf nicht leer sein."
        )
    
    if orchestrator is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
            detail="Der BotOrchestrator ist nicht initialisiert."
        )

    # Delegation an die Logikschicht
    decision = await orchestrator.get_move(fen=request.fen, bot_id=request.bot_id)

    # Fehlerbehandlung
    if decision.source == MoveSource.ERROR:
        # Unterscheide zwischen Client-Fehlern (z.B. falsche Bot-ID) und internen Fehlern (Engine crasht)
        error_msg = decision.error_message or "Unbekannter Engine-Fehler."
        
        status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
        if "Unbekannte Bot-ID" in error_msg:
            status_code = status.HTTP_400_BAD_REQUEST

        logger.error("Fehler bei Zugberechnung: %s", error_msg)
        raise HTTPException(
            status_code=status_code,
            detail={
                "error": "EngineError",
                "message": error_msg
            }
        )

    # Erfolgreiches Mapping
    ponder_move = None
    if decision.engine_result and decision.engine_result.ponder:
        ponder_move = decision.engine_result.ponder

    return MoveResponse(
        move=decision.move,
        source=decision.source.name,
        bot_id=decision.bot_id,
        fen=decision.fen,
        ponder=ponder_move
    )


# ---------------------------------------------------------------------------
# Einstiegspunkt für lokales Ausführen
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn
    # Startet den Uvicorn-Server auf Port 8000
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
