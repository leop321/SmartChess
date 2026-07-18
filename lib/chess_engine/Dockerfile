# Schlankes Python-Basisimage
FROM python:3.11-slim

# System-Abhängigkeiten aktualisieren und Stockfish installieren
RUN apt-get update && apt-get install -y \
    stockfish \
    && rm -rf /var/lib/apt/lists/*

# Sicherstellen, dass /usr/games (wo Debian Stockfish standardmäßig ablegt) im PATH ist
ENV PATH="/usr/games:${PATH}"

# Arbeitsverzeichnis im Container
WORKDIR /app

# Requirements kopieren und installieren
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Den gesamten Backend-Code kopieren
COPY . .

# Port 8000 freigeben (Standardport für FastAPI)
EXPOSE 8000

# Server starten mit Uvicorn
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
