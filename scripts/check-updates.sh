#!/bin/bash
# Script para verificar atualizações (usado pelo serviço systemd)

LOG_FILE="/var/log/pacs-block-updates.log"
GIT_REPO="https://raw.githubusercontent.com/celionorajr/pacs-block-system/main"  # ← ALTERE AQUI

echo "[$(date)] Verificando atualizações..." >> "$LOG_FILE"

# Obter versão atual
CURRENT_VERSION=$(grep "^VERSION" /usr/local/bin/manage-block.sh | cut -d'"' -f2)

# Obter versão remota
REMOTE_VERSION=$(curl -sSL "$GIT_REPO/version.txt" 2>/dev/null)

if [ -z "$REMOTE_VERSION" ]; then
    echo "[$(date)] ERRO: Não foi possível verificar versão remota" >> "$LOG_FILE"
    exit 1
fi

if [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
    echo "[$(date)] NOVA VERSÃO: $REMOTE_VERSION (atual: $CURRENT_VERSION)" >> "$LOG_FILE"
    
    # Se configurado para auto-update, executar
    if [ -f "/etc/pacs-block-auto-update.conf" ]; then
        echo "[$(date)] Executando atualização automática..." >> "$LOG_FILE"
        /usr/local/bin/manage-block.sh update >> "$LOG_FILE" 2>&1
    fi
else
    echo "[$(date)] Sistema atualizado (versão $CURRENT_VERSION)" >> "$LOG_FILE"
fi